# Matrice d'Intégrité ECS — Guide d'Exploitation de l'ECSM

## Extended Containment Security Matrix · Projet Marius · PostgreSQL 18

---

Ce guide décrit l'utilisation du **Meta-Registry**, le moteur d'audit **AOT** (Ahead-Of-Time) du projet Marius. Il détecte en continu toute dérive entre l'intention architecturale consignée dans les ADR et la réalité physique du dictionnaire de données PostgreSQL.

---

## 1. Concept : L'Intention vs La Réalité

Le schéma `meta` maintient deux sources de vérité en regard permanent :

**L'Intention** (`meta.containment_intent`) — ce que l'architecture a décidé : taille maximale acceptable d'un tuple, bit de permission requis, procédures autorisées à écrire, colonnes immuables après INSERT.

**La Réalité** (`pg_catalog` + `pg_stats`) — ce que le moteur observe physiquement : taille réelle des tuples calculée par simulation d'alignement CPU, statut SECURITY DEFINER des procédures, search_path effectivement fixé.

La **matrice** (`meta.v_extended_containment_security_matrix`) croise ces deux sources et expose une ligne d'alertes booléennes par composant enregistré. Une ligne sans alerte signifie que le composant est conforme à son ADR. Toute alerte à `TRUE` est une dérive à traiter.

**Précondition critique :** `ANALYZE` doit avoir été exécuté sur les tables auditées pour que la densité des colonnes `TEXT`/`VARCHAR` soit calculée à partir des données réelles (via `pg_stats.avg_width`). Sans `ANALYZE`, la matrice utilise un fallback de 4B par colonne varlena — la densité est alors sous-estimée et `density_drift_alert` peut produire des faux négatifs.

---

## 2. Installation

```bash
# Créer le schéma meta, les vues et le seed initial
psql -U postgres -d marius -f meta_registry_v2.sql

# Mettre à jour les statistiques pour une densité varlena précise
psql -U postgres -d marius -c "ANALYZE;"
```

---

## 3. Déclarer le Manifeste (L'Intention)

Remplissez `meta.containment_intent` avec les invariants de vos composants. C'est l'étape la plus importante : **la matrice ne peut détecter une dérive que si l'intention a été déclarée.**

### Structure d'une déclaration

```sql
INSERT INTO meta.containment_intent (
    component_id,           -- Nom qualifié 'schema.table' (TEXT)
    intent_density_bytes,   -- Taille maximale tolérée du tuple padded (en octets)
    rls_guard_bitmask,      -- Bit de permission requis pour lire (NULL = pas de RLS)
    mutation_procedures,    -- Tableau des procédures autorisées à écrire
    immutable_keys          -- Colonnes scellées post-INSERT
) VALUES (
    'identity.auth',
    160,           -- Tuple réel : 24B header + colonnes fixes + password_hash inline ~101B
    NULL,          -- auth n'est pas exposé via RLS (REVOKE SELECT sur la table physique)
    ARRAY[
        'identity.create_account(character varying,character varying,character varying,smallint,character varying)',
        'identity.record_login(integer)',
        'identity.anonymize_person(integer)'
    ],
    ARRAY['entity_id'::name, 'created_at'::name]
);
```

### Notes sur `component_id` (TEXT, pas regclass)

`component_id` est stocké en `TEXT` (pas en `regclass`). Cela permet de **pré-déclarer un composant avant sa création physique** : l'alerte `component_not_found_alert` sera `TRUE` jusqu'à ce que le DDL soit appliqué, puis passera automatiquement à `FALSE`. En contrepartie, un renommage de table ne met pas à jour le registre automatiquement — une mise à jour manuelle est requise (`UPDATE meta.containment_intent SET component_id = 'nouveau.nom' WHERE component_id = 'ancien.nom'`).

### Notes sur `mutation_procedures` (tableau)

Un composant ECS est souvent écrit par plusieurs procédures. `identity.auth` est modifié par `create_account` (INSERT), `record_login` (UPDATE last_login_at) et `anonymize_person` (UPDATE password_hash, is_banned). Le champ accepte un tableau. Les signatures doivent utiliser les **types canoniques PostgreSQL** tels qu'ils apparaissent dans `pg_proc` : `character varying` (pas `varchar`), `integer` (pas `int`), `bigint` (pas `int8`).

### Calculer `intent_density_bytes`

`intent_density_bytes` est la taille du **tuple padded complet** : header + null bitmap + colonnes + MAXALIGN final. Ce n'est pas la taille des données brutes.

Formule du header :
```
header_bytes = MAXALIGN(23 + ceil(n_cols / 8))
             = ((23 + ceil(n_cols / 8) + 7) / 8) * 8
```

Exemples tirés du schéma Marius (post-Audit DOD) :

| Composant | Cols | Header | Données | Padded |
|---|---|---|---|---|
| `commerce.transaction_item` | 4 (aucune nullable) | 24B | 8+4+4+4=20B | **48B** |
| `identity.auth` | 7 (2 nullable) | 24B | 24+4+2+1+1+101=133B | **160B** |
| `content.core` | 9 (3 nullable) | 32B | 8+8+8+4+4+2+1+1+1=37B | **72B** |
| `content.tag_hierarchy` | 3 (aucune nullable) | 24B | 4+4+2=10B | **40B** |

**Erreur fréquente :** déclarer la taille des données brutes (ex: 20B pour `transaction_item`) plutôt que le tuple padded (48B). La matrice lèverait alors systématiquement `density_drift_alert = TRUE` — faux positif.

---

## 4. Lecture de la Matrice

```sql
SELECT * FROM meta.v_extended_containment_security_matrix;
```

### Colonnes d'alerte

| Colonne | `TRUE` signifie | Action |
|---|---|---|
| `component_not_found_alert` | La table n'existe pas encore physiquement (pré-déclaration en attente de DDL) | Appliquer le DDL de création |
| `density_drift_alert` | Le tuple réel dépasse l'intention déclarée (padding structurel ou croissance des varlena) | Réorganiser les colonnes dans le DDL, ou réévaluer l'intention |
| `missing_mutation_interface` | Aucune procédure déclarée, ou toutes ont une signature obsolète (procédure renommée ou supprimée) | Mettre à jour `mutation_procedures` dans le manifeste |
| `security_breach_alert` | Au moins une procédure déclarée n'est plus `SECURITY DEFINER` ou expose un `search_path` dangereux (`public`, `$user`, vide) | Corriger l'`ALTER PROCEDURE` correspondant |

### Colonnes de diagnostic

| Colonne | Utilisation |
|---|---|
| `intent_density_bytes` | Valeur cible déclarée dans le manifeste |
| `actual_density_bytes` | Taille réelle simulée (dépend d'`ANALYZE` pour les varlena) |
| `header_bytes_used` | Header calculé avec null bitmap — utile pour vérifier la formule |

### Requêtes d'audit ciblées

```sql
-- Dérives de densité uniquement
SELECT component_name, intent_density_bytes, actual_density_bytes
FROM meta.v_extended_containment_security_matrix
WHERE density_drift_alert;

-- Violations de sécurité uniquement
SELECT component_name, mutation_procedures
FROM meta.v_extended_containment_security_matrix
WHERE security_breach_alert;

-- Composants pré-déclarés en attente de création
SELECT component_name
FROM meta.v_extended_containment_security_matrix
WHERE component_not_found_alert;

-- Vue complète diagnostic, zéro alerte = système conforme
SELECT
    component_name,
    component_not_found_alert AS "∄",
    density_drift_alert        AS "DOD",
    missing_mutation_interface AS "ECS",
    security_breach_alert      AS "SEC",
    intent_density_bytes       AS "intent",
    actual_density_bytes       AS "actual"
FROM meta.v_extended_containment_security_matrix
ORDER BY component_name;
```

---

## 5. Intégration pgTAP (Fail-Safe CI/CD)

Ajoutez le fichier suivant à votre suite de tests pour bloquer tout déploiement qui introduit une dérive :

```sql
-- tests/11_meta_audit.sql
\set ON_ERROR_STOP 1
BEGIN;
SELECT plan(3);

-- Aucune table enregistrée ne doit être manquante
SELECT is_empty(
    $$SELECT component_name FROM meta.v_extended_containment_security_matrix
      WHERE component_not_found_alert$$,
    'ECSM : tous les composants enregistrés existent physiquement'
);

-- Aucune dérive de densité DOD
SELECT is_empty(
    $$SELECT component_name, intent_density_bytes, actual_density_bytes
      FROM meta.v_extended_containment_security_matrix
      WHERE density_drift_alert$$,
    'ECSM : zéro dérive de layout mémoire (Zéro Padding Drift)'
);

-- Aucune violation de sécurité procédurale
SELECT is_empty(
    $$SELECT component_name
      FROM meta.v_extended_containment_security_matrix
      WHERE security_breach_alert OR missing_mutation_interface$$,
    'ECSM : interface de mutation scellée, zéro brèche SECURITY DEFINER (ADR-001)'
);

SELECT * FROM finish();
ROLLBACK;
```

**Important :** ce test doit être précédé d'un `ANALYZE` dans le pipeline CI pour que `density_drift_alert` repose sur des statistiques fraîches :

```bash
psql -U postgres -d marius -c "ANALYZE;"
psql -U postgres -d marius -f tests/11_meta_audit.sql
```

---

## 6. Maintenance du Manifeste

### Après un renommage de table ou de procédure

```sql
-- Renommage de table
UPDATE meta.containment_intent
SET component_id = 'nouveau_schema.nouvelle_table'
WHERE component_id = 'ancien_schema.ancienne_table';

-- Renommage ou changement de signature d'une procédure
UPDATE meta.containment_intent
SET mutation_procedures = array_replace(
    mutation_procedures,
    'ancien.nom(integer)',
    'nouveau.nom(integer)'
)
WHERE mutation_procedures @> ARRAY['ancien.nom(integer)'];
```

### Après un ALTER TABLE (ajout de colonne, changement de type)

Recalculer `intent_density_bytes` si la modification impacte le layout physique, puis mettre à jour le manifeste. Lancer `ANALYZE` pour rafraîchir `pg_stats`, puis vérifier `density_drift_alert`.

### Cycle de mise à jour recommandé

```
ADR modifié
    → Mettre à jour containment_intent (intention)
    → Appliquer le DDL (réalité)
    → ANALYZE
    → SELECT * FROM meta.v_extended_containment_security_matrix
    → Zéro alerte = déploiement validé
```

---

## Annexe — Limites connues

**Densité sans ANALYZE** : sans statistiques `pg_stats`, les colonnes `TEXT`/`VARCHAR` contribuent seulement 4B à `actual_density_bytes` (header varlena seul). La densité réelle est sous-estimée. `density_drift_alert` peut être `FALSE` alors que le tuple réel dépasse l'intention. Exécuter `ANALYZE` régulièrement (au moins après chaque chargement de données significatif).

**Varlena avec STORAGE EXTERNAL** : `pg_stats.avg_width` inclut la référence TOAST (18B) pour les colonnes systématiquement TOASTées, pas la donnée inline. La matrice détecte correctement ces colonnes comme légères (ce qu'elles sont dans le heap).

**Overloading de procédures** : si deux procédures partagent le même nom mais des signatures différentes, `to_regprocedure()` résout l'overload correct via la signature complète. La signature doit être exacte — y compris l'ordre et le type canonique de chaque paramètre.
