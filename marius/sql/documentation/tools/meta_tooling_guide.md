# Outillage `meta` — Mode d'emploi
**Projet Marius · Architecture ECS/DOD · PostgreSQL 18**

---

## Contexte

Le schéma `meta` héberge trois outils d'ingénierie complémentaires. Ils s'appuient sur `meta.containment_intent` (registre AOT des composants) et sur `pg_catalog`. Aucun n'est destiné au runtime applicatif — accès réservé à `marius_admin` et `postgres`.

---

## 1. `meta.f_generate_dod_template` — Générateur de DDL aligné CPU

### Raison d'être

Dans une architecture DOD, l'ordre des colonnes dans une table n'est pas cosmétique : il détermine le padding d'alignement CPU entre chaque champ. Un ordre naïf (tel que dicté par la logique métier) peut insérer plusieurs octets de padding par tuple, ce qui réduit la densité et augmente la pression cache.

Cette fonction prend une liste de colonnes brutes et produit trois livrables en un seul appel :

- le `CREATE TABLE` avec les colonnes triées dans l'ordre optimal (8 B → 4 B → 2 B → 1 B → varlena),
- un bloc de commentaires SQL détaillant le layout mémoire colonne par colonne (offset, taille, padding),
- l'`INSERT INTO meta.containment_intent` pré-calculé pour armer le registre d'audit.

### Utilisation

```sql
SELECT meta.f_generate_dod_template(
    'commerce.my_table',
    ARRAY[
        'id            int8 GENERATED ALWAYS AS IDENTITY',
        'created_at    timestamptz NOT NULL',
        'status        smallint NOT NULL DEFAULT 0',
        'is_active     boolean NOT NULL DEFAULT true',
        'label         varchar(64)'
    ]
);
```

La fonction retourne un bloc TEXT à copier-coller directement dans le DDL de migration. Exemple de sortie :

```sql
-- ============================================================
-- DOD TEMPLATE : commerce.my_table
-- ------------------------------------------------------------
-- Fixed-Length Header  : 24 B
--   (23 B base + 1 B null bitmap [ceil(5 cols / 8)] -> MAXALIGN 8)
-- ------------------------------------------------------------
-- Layout memoire (Ordre DOD) :
--   id                       (int8                  ) : offset  24 B, size  8 B, padding_before 0 B
--   created_at               (timestamptz           ) : offset  32 B, size  8 B, padding_before 0 B
--   status                   (smallint              ) : offset  40 B, size  2 B, padding_before 0 B
--   is_active                (boolean               ) : offset  42 B, size  1 B, padding_before 0 B
--   label                    (varchar(64)           ) : offset  44 B, size  4 B, padding_before 1 B  [varlena -- 4 B pre-ANALYZE]
-- ------------------------------------------------------------
-- Ordre naif (input)   : 56 B / tuple
-- Ordre DOD optimise   : 48 B / tuple
-- Padding economise    : 8 B / tuple
-- ============================================================
CREATE TABLE commerce.my_table (
    id                          int8 GENERATED ALWAYS AS IDENTITY,
    created_at                  timestamptz NOT NULL,
    status                      smallint NOT NULL DEFAULT 0,
    is_active                   boolean NOT NULL DEFAULT true,
    label                       varchar(64)
);

-- Armement du registre AOT
INSERT INTO meta.containment_intent
    (component_id, intent_density_bytes)
VALUES
    ('commerce.my_table', 48)
ON CONFLICT (component_id)
    DO UPDATE SET intent_density_bytes = EXCLUDED.intent_density_bytes;
```

### Points d'attention

- Les types custom (PostGIS `geometry`, `ltree`, etc.) sont supportés à condition que l'extension soit installée.
- Les colonnes varlena (`text`, `varchar`, `jsonb`...) sont toujours reléguées en fin de table (Fixed-Length Prefixing) et leur taille est fixée à 4 B dans la simulation. La valeur `intent_density_bytes` doit être réévaluée après `ANALYZE` via `meta.v_extended_containment_security_matrix`.
- Le format `p_table_name` doit respecter `schema.table` en snake_case, lettre initiale obligatoire — conforme au `CHECK` constraint de `meta.containment_intent`.

---

## 2. `meta.f_compile_entity_profile` — Compilateur AOT de la vue de profil ECS

### Raison d'être

Dans une architecture ECS, une entité est un identifiant entier pur. Ses données sont fragmentées dans des tables de composants indépendantes (`identity.auth`, `content.core`, etc.). Il n'existe aucune table centrale listant quels composants sont actifs pour un identifiant donné.

Cette fonction génère et exécute dynamiquement la vue `meta.v_entity_profile`, qui permet de répondre à la question de debugging : *"Quels composants sont peuplés pour l'entité #N ?"*

Le principe AOT (Ahead-Of-Time) est central : l'introspection du catalogue (`pg_catalog`, `meta.containment_intent`) n'a lieu qu'une seule fois — à la compilation. La vue résultante est un `UNION ALL` pur, sans aucun accès catalogue au runtime.

### Utilisation

**Compiler (ou recompiler après ajout d'un composant) :**

```sql
SELECT meta.f_compile_entity_profile();
```

La fonction retourne le DDL compilé pour inspection, puis l'exécute. Exemple de sortie :

```sql
CREATE OR REPLACE VIEW meta.v_entity_profile AS
SELECT
    spine_id,
    spine_type,
    array_agg(component_name ORDER BY component_name) AS active_components
FROM (
    SELECT entity_id AS spine_id, 'entity_id' AS spine_type, 'identity.auth' AS component_name FROM identity.auth
    UNION ALL
    SELECT document_id AS spine_id, 'document_id' AS spine_type, 'content.core' AS component_name FROM content.core
) AS raw_components
GROUP BY spine_id, spine_type
```

**Interroger la vue une fois compilée :**

```sql
-- Tous les composants actifs pour l'entité #42
SELECT spine_id, spine_type, active_components
FROM meta.v_entity_profile
WHERE spine_id = 42;
```

```
 spine_id | spine_type |       active_components
----------+------------+--------------------------------
       42 | entity_id  | {identity.auth}
       42 | document_id| {content.core}
```

### Points d'attention

- **Recompiler après chaque ajout de composant** dans `meta.containment_intent`. La vue n'est pas auto-rafraîchie.
- La colonne `spine_type` est obligatoire pour lever l'ambiguïté : `identity.entity` et `content.document` ont des séquences d'identifiants indépendantes. Un `spine_id = 7` peut désigner simultanément une entité et un document — le `spine_type` les distingue.
- Seuls les composants possédant une colonne de liaison directe vers une spine (`entity_id`, `document_id`, ou `id` avec FK vérifiée via `pg_constraint`) sont inclus. Les composants sans liaison spine directe (`commerce.transaction_item`, `content.tag_hierarchy`, etc.) sont silencieusement exclus — ils ne portent pas d'identifiant d'entité au sens ECS.

---

## 3. `meta.v_performance_sentinel` — Sentinel de performance DOD

### Raison d'être

Les invariants de performance du projet (densité DOD, HOT-eligibility, corrélation BRIN) peuvent être dégradés silencieusement par une modification de schéma : ajout d'un index sur une colonne fréquemment mise à jour, réorganisation physique des lignes, ou dérive de densité après une vague d'insertions imprévues.

Cette vue croise les statistiques runtime (`pg_stat_user_tables`, `pg_stats`) avec le registre d'intention (`meta.containment_intent`) pour lever trois types d'alertes booléennes par composant enregistré.

### Les trois alertes

| Alerte | Condition | Cause typique |
|---|---|---|
| `hot_blocker_alert` | `n_tup_upd > 0` ET colonne indexée non-immutable | Ajout d'un index sur une colonne mise à jour fréquemment |
| `brin_drift_alert` | `abs(brin_correlation) < 0.90` | Insertions non séquentielles sur une table avec index BRIN |
| `bloat_alert` | `pg_relation_size / n_live_tup > (intent_density / fillfactor) * 1.20` | Padding structurel, varlena plus large que prévu, dead tuples |

### Utilisation

```sql
-- Vue d'ensemble : tous les composants avec au moins une alerte active
SELECT component_id,
       hot_blocker_alert, hot_blocker_cols,
       brin_drift_alert,  brin_worst_col, brin_correlation,
       bloat_alert,       observed_bytes_per_tuple, bloat_threshold_bytes,
       fillfactor_pct,    n_live_tup
FROM meta.v_performance_sentinel
WHERE hot_blocker_alert
   OR brin_drift_alert
   OR bloat_alert = TRUE;

-- Détail d'un composant spécifique
SELECT * FROM meta.v_performance_sentinel
WHERE component_id = 'content.core';
```

### Colonnes de diagnostic

| Colonne | Usage |
|---|---|
| `hot_blocker_cols` | Noms des colonnes qui bloquent HOT (à dé-indexer ou déclarer immutable) |
| `brin_worst_col` | Colonne BRIN la plus dégradée (candidat à un `CLUSTER` ou `VACUUM FULL`) |
| `brin_correlation` | Valeur abs de corrélation (1.0 = parfait, < 0.9 = drift) |
| `observed_bytes_per_tuple` | Densité observée brute (pg_relation_size / n_live_tup) |
| `bloat_threshold_bytes` | Seuil effectif après correction fillfactor (pour comprendre le calcul) |
| `fillfactor_pct` | Fillfactor lu depuis `pg_class.reloptions` (100 si absent) |
| `n_live_tup` | Tuples vivants selon `pg_stat_user_tables` — NULL ou 0 = ANALYZE requis |

### Points d'attention

- **Prérequis : `ANALYZE`** sur les tables auditées. Sans statistiques, `brin_correlation` est NULL (pas d'alerte BRIN) et `n_live_tup` peut être sous-estimé (alertes bloat silencieuses ou erronées).
- `bloat_alert = NULL` (et non FALSE) indique une table vide ou sans statistiques — à distinguer d'une absence de dérive.
- La correction fillfactor est automatique : les tables `identity.auth` (ff=70) et `commerce.product_core` (ff=80) n'afficheront pas de faux positif bloat sur un layout sain.
- La vue est en lecture seule, sans effet de bord. Elle peut être interrogée à tout moment en session `marius_admin`.

---

## Workflow recommandé

```
Nouveau composant
      │
      ▼
1. meta.f_generate_dod_template(...)
   └─ Obtenir le DDL trié + intent_density_bytes
      │
      ▼
2. Appliquer le DDL (CREATE TABLE) + INSERT meta.containment_intent
      │
      ▼
3. meta.f_compile_entity_profile()
   └─ Recompiler meta.v_entity_profile si le composant porte entity_id / document_id
      │
      ▼
4. ANALYZE <schema>.<table>
      │
      ▼
5. SELECT * FROM meta.v_performance_sentinel WHERE component_id = '<schema>.<table>'
   └─ Vérifier : hot_blocker_alert, brin_drift_alert, bloat_alert tous à FALSE
```
