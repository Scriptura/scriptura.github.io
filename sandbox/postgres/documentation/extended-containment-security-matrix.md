# Protocole d'Audit des Invariants et de la Dérive Structurelle (AOT)

## Guide d’exploitation de l’Extended Containment Security Matrix (ECSM)

---

Ce guide décrit l'utilisation du **Meta-Registry**, l'outil de contrôle **AOT** (Ahead-Of-Time) conçu pour maintenir l'intégrité de votre architecture **ECS/DOD**.

---

## 1. Concept : L'Intention vs La Réalité

Le fichier `meta_registry.sql` crée un moteur d'audit. Pour fonctionner, il a besoin de deux sources :

1.  **La Réalité** : Extraite automatiquement du catalogue système PostgreSQL (taille réelle des tables, sécurité des procédures).
2.  **L'Intention** : Ce que vous avez décidé dans vos **ADR** (taille cible, bits de sécurité).

**L'outil ne sert à rien tant que vous ne lui avez pas déclaré votre "Intention".**

---

## 2. Étape 1 : Installation de l'Infrastructure

Exécutez le script pour créer le schéma `meta` et les vues d'introspection.

```bash
psql -U postgres -d marius -f meta_registry.sql
```

---

## 3. Étape 2 : Déclarer le Manifeste (L'Intention)

C'est la phase la plus importante. Vous devez remplir la table `meta.containment_intent` avec vos invariants théoriques. Créez un fichier `meta_data.sql` :

### Exemple de déclaration d'un composant :

```sql
INSERT INTO meta.containment_intent (
    component_id,           -- Nom de la table (casté en ::regclass)
    intent_density_bytes,   -- Taille MAX autorisée en octets (selon ADR)
    rls_guard_bitmask,      -- Bit de sécurité requis (ex: 1 pour auth)
    mutation_procedure      -- La seule procédure autorisée à écrire ici
) VALUES (
    'identity.auth'::regclass,
    155,
    1,
    'identity.record_login(integer)'::regprocedure
);
```

> **Note technique** : L'utilisation de `::regclass` et `::regprocedure` permet à PostgreSQL de lier l'ID interne (OID) de l'objet. Si vous renommez la table, le registre suit automatiquement.

---

## 4. Étape 3 : Lecture de la Matrice (L'Audit)

Une fois le manifeste chargé, la matrice devient votre tableau de bord. Interrogez la vue pour détecter les anomalies.

```sql
SELECT * FROM meta.v_extended_containment_security_matrix;
```

### Comprendre les alertes :

| Colonne                          | Signification                                                                        | Action requise                                |
| :------------------------------- | :----------------------------------------------------------------------------------- | :-------------------------------------------- |
| **`density_drift_alert`**        | `TRUE` : La table est plus grosse que prévu (Padding CPU détecté).                   | Réorganiser l'ordre des colonnes dans le DDL. |
| **`security_breach_alert`**      | `TRUE` : La procédure n'est plus `SECURITY DEFINER` ou son `search_path` est ouvert. | Corriger la signature de la procédure.        |
| **`missing_mutation_interface`** | `TRUE` : Le composant n'a pas de procédure d'écriture associée dans le registre.     | Sceller l'interface (ADR-001).                |

---

## 5. Étape 4 : Automatisation (Le "Fail-Safe")

Pour garantir qu'aucune mise à jour du DDL ne casse vos invariants DOD/Security en production, intégrez la matrice à vos tests **pgTAP**.

### Exemple de test d'intégrité :

```sql
-- Dans un fichier tests/11_meta_audit.sql
SELECT is_empty(
    'SELECT 1 FROM meta.v_extended_containment_security_matrix WHERE density_drift_alert OR security_breach_alert',
    'La structure physique doit être 100% conforme aux ADR (Zéro Drift).'
);
```

---
