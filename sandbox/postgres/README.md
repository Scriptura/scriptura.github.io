# Marius — ECS/DOD Database Engine

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791?style=for-the-badge&logo=postgresql&logoColor=white)]()
[![PostGIS](https://img.shields.io/badge/PostGIS-3.x-008BB9?style=for-the-badge&logo=postgresql&logoColor=white)]()
[![Architecture](https://img.shields.io/badge/Architecture-ECS%2FDOD-E85D04?style=for-the-badge)]()
[![Design](https://img.shields.io/badge/Design-Data--Oriented-2D6A4F?style=for-the-badge)]()
[![Semantics](https://img.shields.io/badge/Sémantique-schema.org-1565C0?style=for-the-badge)]()
[![Hierarchy](https://img.shields.io/badge/Hiérarchies-ltree-5C6BC0?style=for-the-badge)]()
[![ADR](https://img.shields.io/badge/ADR-30%20décisions-455A64?style=for-the-badge)]()
[![Status](https://img.shields.io/badge/Statut-R%26D-7B1FA2?style=for-the-badge)]()

Architecture de base de données orientée données (DOD) pour PostgreSQL 18, appliquant les principes de l'Entity-Component-System (ECS) à la modélisation relationnelle. Conçu pour une cible de **500 000 utilisateurs actifs**.

---

## Philosophie

Ce projet applique le paradigme **SoA** (_Structure of Arrays_), inspiré de l'ECS des moteurs de jeu et du DOD bas niveau :

- **Entity** — un identifiant entier pur, sans donnée métier.
- **Component** — une table physique par axe d'accès (noms, contact, biographie, contenu long), dimensionnée selon sa fréquence de lecture réelle.
- **System** — une procédure stockée par mutation, seul point d'écriture autorisé sur les composants physiques.

La couche applicative ne voit que des **vues sémantiques** reconstituant l'interface [schema.org](https://schema.org) par-dessus les composants fragmentés.

La fragmentation des données augmente mécaniquement la densité des composants hot path. Le composant le plus dense du schéma (`content.tag_hierarchy`, 40B/tuple) atteint ~185 tuples/page ; les composants purement fixes (`commerce.transaction_item`, 48B) ~157 tuples/page. À titre de comparaison, une table monolithique équivalente portant les mêmes champs se situerait généralement autour de 20 à 30 tuples/page.

---

## Prérequis

| Composant  | Version minimale                   |
| ---------- | ---------------------------------- |
| PostgreSQL | **18** (async I/O, EXPLAIN MEMORY) |
| PostGIS    | 3.x                                |
| pgTAP      | Compatible PG 18 (tests uniquement)|

### Extensions PostgreSQL requises

| Extension  | Usage                                                                          |
| ---------- | ------------------------------------------------------------------------------ |
| `unaccent` | Normalisation des accents pour les index de recherche texte                    |
| `ltree`    | Chemins matérialisés pour la taxonomie des tags et les threads de commentaires |
| `pg_trgm`  | Index trigrammes pour la recherche partielle sur les noms et titres            |
| `postgis`  | Type `geometry(Point, 4326)`, index GiST géospatiaux, opérateur KNN `<->`      |

Vérification de disponibilité sur le serveur cible :

```sql
SELECT name, default_version FROM pg_available_extensions
WHERE  name IN ('unaccent', 'ltree', 'pg_trgm', 'postgis')
ORDER  BY name;
-- Les quatre extensions doivent apparaître dans la liste.
```

---

## Installation

### 1. Déploiement du schéma (DDL)

```bash
psql -U postgres -f master_schema_ddl.pgsql
```

Le script commence par `DROP DATABASE IF EXISTS marius` — il repart d'une ardoise vierge. Sur une installation déjà existante, vérifier que la base peut être supprimée avant d'exécuter.

Ce que le script fait dans l'ordre : crée l'utilisateur `marius_user` et la base, installe les quatre extensions, crée les cinq schémas (`identity`, `geo`, `org`, `commerce`, `content`), puis les spines, composants, fonctions, triggers, procédures, vues, permissions et politiques RLS. Aucune dépendance externe : le fichier est entièrement autonome.

### 2. Données de test (optionnel)

```bash
psql -U postgres -d marius -f master_schema_dml.pgsql
```

À des fins de développement et de benchmarking uniquement. **Ne pas exécuter en production.** Les insertions traversent les mêmes procédures stockées que la production — la seed ne bypasse pas l'interface de mutation.

### 3. Vérification post-installation

```sql
\c marius

-- Les cinq schémas métier doivent être présents
SELECT schema_name FROM information_schema.schemata
WHERE  schema_name IN ('identity','geo','org','commerce','content')
ORDER  BY schema_name;

-- Compte de tables par schéma (valeurs indicatives)
SELECT table_schema, COUNT(*) AS tables
FROM   information_schema.tables
WHERE  table_schema IN ('identity','geo','org','commerce','content')
GROUP  BY table_schema ORDER BY table_schema;

-- Tester une vue sémantique
SELECT identifier, headline, published_at
FROM   content.v_article_list
LIMIT  5;

-- Vérifier l'intégrité des chemins ltree des commentaires
SELECT id, path, nlevel(path) AS depth
FROM   content.comment
ORDER  BY path;

-- Vérifier que marius_user ne peut pas écrire directement (ADR-001)
SET ROLE marius_user;
INSERT INTO identity.entity DEFAULT VALUES; -- doit échouer avec ERROR 42501
RESET ROLE;

-- Vérifier que SECURITY DEFINER est actif sur toutes les procédures de mutation
SELECT n.nspname, p.proname, p.prosecdef
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname IN ('identity','content','org','commerce','geo')
  AND  p.prokind = 'p'
ORDER  BY n.nspname, p.proname;
-- prosecdef = true attendu sur toutes les lignes
```

### 4. Installation du Meta-Registry (optionnel, recommandé)

Le Meta-Registry détecte les dérives entre l'intention architecturale et la réalité physique du catalogue. Il s'installe sur la même base :

```bash
psql -U postgres -d marius -f meta_registry.sql

# ANALYZE est requis pour que la densité des colonnes varlena soit calculée
# à partir des données réelles (pg_stats.avg_width). Sans ANALYZE, la matrice
# utilise un fallback de 4B par colonne TEXT/VARCHAR.
psql -U postgres -d marius -c "ANALYZE;"
```

Interroger la matrice :

```sql
SELECT component_name,
       component_not_found_alert AS "∄",
       density_drift_alert        AS "DOD",
       missing_mutation_interface AS "ECS",
       security_breach_alert      AS "SEC",
       intent_density_bytes       AS "intent",
       actual_density_bytes       AS "actual"
FROM   meta.v_extended_containment_security_matrix
ORDER  BY component_name;
-- Zéro TRUE dans les colonnes d'alerte = schéma conforme aux ADR.
```

Voir `documentation/extended-containment-security-matrix.md` pour le guide complet.

### 5. Installation des outils `meta` (optionnel, recommandé)

Le répertoire `tools/` contient quatre outils d'ingénierie et d'audit qui s'appuient sur le Meta-Registry. Ils doivent être installés après l'étape 4 :

```bash
# Générateur DDL aligné CPU
psql -U postgres -d marius -f tools/f_generate_dod_template.sql

# Compilateur AOT de la vue de profil ECS
psql -U postgres -d marius -f tools/f_compile_entity_profile.sql

# Vue d'audit de performance (HOT / BRIN / bloat)
psql -U postgres -d marius -f tools/v_performance_sentinel.sql

# Vue de santé globale (agrège ECSM + sentinel)
psql -U postgres -d marius -f tools/v_master_health_audit.sql
```

Premier lancement après installation :

```sql
-- Compiler la vue de profil ECS (à relancer après tout ajout de composant)
SELECT meta.f_compile_entity_profile();

-- Vérifier le sentinel (requiert ANALYZE au préalable)
SELECT component_id, hot_blocker_alert, brin_drift_alert, bloat_alert
FROM   meta.v_performance_sentinel;
-- Zéro TRUE = schéma conforme aux invariants de performance.
```

Voir `documentation/meta_tooling_guide.md` pour le guide complet des trois outils.

### 5. Séquence complète (environnement CI/CD)

```bash
# Déploiement
psql -U postgres -f master_schema_ddl.pgsql
psql -U postgres -d marius -f master_schema_dml.pgsql

# Meta-Registry
psql -U postgres -d marius -f meta_registry.sql
psql -U postgres -d marius -c "ANALYZE;"

# Suite de tests (requiert pgTAP)
psql -U postgres -d marius -c "CREATE EXTENSION IF NOT EXISTS pgtap;"
for f in tests/0*.sql; do
  psql -U postgres -d marius -f "$f"
done
```

---

## Rôles PostgreSQL

| Rôle           | Droits                                        | Usage                            |
| -------------- | --------------------------------------------- | -------------------------------- |
| `marius_user`  | `SELECT` + `EXECUTE`                          | Runtime applicatif               |
| `marius_admin` | `SELECT` + `EXECUTE` + `INSERT/UPDATE/DELETE` | Maintenance, migrations, CI seed |
| `postgres`     | Superutilisateur                              | Déploiement DDL, installation    |

`marius_admin` hérite de `marius_user` via `GRANT ... WITH INHERIT TRUE` et possède `BYPASSRLS` pour les opérations de maintenance. En environnement hautement sécurisé, désactiver le `LOGIN` direct sur `marius_admin` et passer par `SET ROLE marius_admin` depuis une session `postgres`. Surveiller les sessions actives de ce rôle via `identity.v_admin_sessions` — toute connexion hors fenêtre de maintenance est une anomalie.

---

## Concepts clés — Quick Reference

### Alignement mémoire et padding (ADR-006)

Toutes les tables respectent un ordre de déclaration **décroissant par taille d'alignement** pour éliminer le padding invisible entre colonnes :

```
8 bytes  →  TIMESTAMPTZ, FLOAT8, INT8
4 bytes  →  INT4, DATE, FLOAT4
2 bytes  →  SMALLINT
1 byte   →  BOOLEAN
variable →  VARCHAR, TEXT, ltree, geometry
```

`NUMERIC` est varlena dans PostgreSQL indépendamment de sa précision déclarée — il se place toujours après les types fixes. Aucune colonne `CHAR(n)` dans le schéma : `bpchar` est varlena avec padding CPU, remplacé par `VARCHAR` + contrainte `CHECK` pour les longueurs fixes (ADR-026). Les codes ISO numériques (`country_code`, `currency_code`, `nationality`) sont stockés en `SMALLINT` (2B pass-by-value) plutôt qu'en `CHAR(2)`/`CHAR(3)` (ADR-028).

### Tailles de tuples padded — valeurs de référence

| Composant                    | Tuple padded | ff   | tpp approx. | Hot path                          |
| ---------------------------- | ------------ | ---- | ----------- | --------------------------------- |
| `content.tag_hierarchy`      | 40B          | 100% | ~185        | INSERT-only (Closure Table)       |
| `commerce.transaction_item`  | 48B          | 100% | ~157        | INSERT-only (trigger immuabilité) |
| `commerce.product_core`      | 48B          | 80%  | ~125        | HOT update sur `stock`            |
| `content.core`               | 72B          | 100% | ~107        | Aucun HOT (toutes colonnes indexées) |
| `identity.auth`              | 160B         | 70%  | ~34         | HOT update sur `last_login_at`    |

Le tuple `identity.auth` (160B) inclut `password_hash` inline (~101B) en `STORAGE MAIN` : argon2id est pseudo-aléatoire, la compression PGLZ n'apporte rien. `content.core` n'a pas de fillfactor : tous ses chemins d'UPDATE touchent des colonnes indexées (`published_at`, `modified_at`), le HOT n'est jamais possible.

### Convention centimes (ADR-026)

Les montants monétaires sont stockés en **centimes entiers** (`INT8`), pas en décimaux. Le suffixe `_cents` est visible dans les colonnes physiques et les alias de vues :

```sql
-- Prix d'un produit
SELECT identifier, price_cents FROM commerce.v_product WHERE identifier = 1;
-- price_cents = 1999 → 19,99 € (conversion déléguée à la couche applicative)

-- Total d'une commande
SELECT total_cents FROM commerce.v_transaction WHERE identifier = 42;
```

`INT8` est pass-by-value sur toutes les architectures 64 bits : arithmétique ALU native, zéro overhead varlena.

### Bitmask des permissions de rôle (ADR-015)

Les permissions sont encodées dans un `INT4` par OR binaire des puissances de 2 (bits 0 à 20). Vérification en une opération `&` sans jointure :

```sql
-- Vérifier si un utilisateur peut publier (bit 4 = valeur 16)
SELECT identity.has_permission(entity_id, 16);

-- Décomposer le bitmask en colonnes booléennes nommées
SELECT * FROM identity.v_role WHERE id = 1;
```

La fonction `has_permission` est `LANGUAGE sql STABLE PARALLEL SAFE` : inlinable par le planner, elle disparaît du plan d'exécution et devient une simple opération `&` sur la ligne.

### Vues de listing vs page complète (ADR-009)

| Vue                      | Usage                      | Charge TOAST        |
| ------------------------ | -------------------------- | ------------------- |
| `content.v_article_list` | Listings, flux, navigation | Zéro                |
| `content.v_article`      | Page article complète      | Oui (`articleBody`) |

Toujours utiliser `v_article_list` pour les listings. Ne projeter `articleBody` que sur les lectures de page complète. `toast_tuple_target = 128` sur les composants basse fréquence (`content.body`, `content.revision`, `identity.person_content`, etc.) garantit que les données textuelles longues ne chargent jamais les pages des composants hot path.

### Écriture via procédures uniquement (ADR-001)

`marius_user` ne possède aucun droit `INSERT`, `UPDATE`, `DELETE` direct. Toute mutation passe par les procédures `SECURITY DEFINER`, qui s'exécutent avec les droits du propriétaire (`postgres`) indépendamment des droits de l'appelant.

Procédures principales :

| Procédure                                        | Composants créés                                  |
| ------------------------------------------------ | ------------------------------------------------- |
| `identity.create_account(...)`                   | `entity` + `auth` + `account_core`                |
| `identity.create_person(...)`                    | `entity` + `person_identity`                      |
| `identity.anonymize_person(entity_id)`           | Purge RGPD des 10 composants nominatifs (ADR-017) |
| `identity.create_group(name)`                    | `group`                                           |
| `identity.add_account_to_group(...)`             | `group_to_account`                                |
| `geo.create_place(...)`                          | `place_core` + `postal_address` optionnel         |
| `content.create_document(...)`                   | `document` + `core` + `identity` + `revision`     |
| `content.publish_document(document_id)`          | UPDATE `core.status`                              |
| `content.save_revision(document_id, author_id)`  | Snapshot éditorial complet (ADR-024)              |
| `content.create_comment(...)`                    | `comment` avec chemin ltree atomique (ADR-007)    |
| `content.create_tag(...)`                        | `tag` + entrées `tag_hierarchy` (Closure Table)   |
| `content.create_media(...)`                      | `media_core` + `media_content` optionnel          |
| `content.add_media_to_document(...)`             | `content_to_media`                                |
| `commerce.create_product(...)`                   | `product_core` + `product_identity`               |
| `commerce.create_transaction(...)`               | `transaction_core` + 3 composants ECS             |
| `commerce.create_transaction_item(...)`          | `transaction_item` + décrémentation `stock`       |

---

## Tests pgTAP

La suite de tests est découplée en fichiers thématiques. Chaque fichier s'exécute dans `BEGIN / ROLLBACK` — aucune donnée ne persiste. Prérequis : `CREATE EXTENSION pgtap` sur la base `marius`.

```bash
psql -U postgres -d marius -f tests/01_schema_and_security.sql
psql -U postgres -d marius -f tests/02_identity_logic.sql
# ... etc
```

| Fichier                       | Périmètre                                                              |
| ----------------------------- | ---------------------------------------------------------------------- |
| `01_schema_and_security.sql`  | Types physiques, BRIN, RBAC, SECURITY DEFINER, triggers immuabilité    |
| `02_identity_logic.sql`       | `create_account`, slugs, bitmask, connexions, garde escalade de rôle   |
| `03_content_logic.sql`        | Documents, snapshot complet (ADR-024), ltree, commentaires             |
| `04_commerce_logic.sql`       | Stock, snapshot de prix, sur-vente, agrégats, gardes ADR-030           |
| `05_tag_hierarchy.sql`        | Closure Table, profondeur max, sous-arbre, breadcrumb                  |
| `06_security_audit.sql`       | Shadow write detection, qualification des objets, bypass admin         |
| `07_hot_audit.sql`            | Immuabilité `created_at`, matrice HOT, corrélation BRIN                |
| `08_rgpd_audit.sql`           | Gardes bitwise, anonymisation complète, jointure orpheline, finance     |
| `09_dod_hot_collision.sql`    | Collision layout/HOT, fillfactor, index `core_author`                  |
| `10_mutation_interface.sql`   | Nouvelles procédures, trigger `entity_id` immuable, gardes bitwise     |
| `11_meta_audit.sql`           | ECSM fail-safe : zéro dérive DOD/sécurité/interface                    |

---

## Maintenance

### Surveiller les dérives structurelles

Après toute modification du DDL ou chargement de données significatif :

```bash
psql -U postgres -d marius -c "ANALYZE;"
psql -U postgres -d marius -c "SELECT * FROM meta.v_extended_containment_security_matrix;"
```

Zéro alerte `TRUE` = schéma conforme.

### Surveiller les régressions de performance

```sql
-- HOT-blockers, BRIN-drift et bloat en un seul appel
SELECT component_id,
       hot_blocker_alert, hot_blocker_cols,
       brin_drift_alert,  brin_worst_col, brin_correlation,
       bloat_alert,       observed_bytes_per_tuple, bloat_threshold_bytes
FROM   meta.v_performance_sentinel
WHERE  hot_blocker_alert OR brin_drift_alert OR bloat_alert = TRUE;
-- Zéro ligne = invariants de performance respectés.
```

Requiert `ANALYZE` préalable pour que `pg_stats.correlation` et `n_live_tup` soient fiables.

### Surveillance des dead tuples

```sql
SELECT schemaname, relname, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
       last_autovacuum, last_analyze
FROM   pg_stat_user_tables
WHERE  schemaname IN ('identity','content','commerce')
ORDER  BY n_dead_tup DESC
LIMIT  20;
```

| Table                   | Source de dead tuples                     | fillfactor |
| ----------------------- | ----------------------------------------- | ---------- |
| `identity.auth`         | `last_login_at` à chaque connexion        | 70         |
| `commerce.product_core` | `stock` à chaque vente                    | 80         |
| `content.comment`       | Suppressions de modération (`status = 9`) | défaut     |

`content.core` n'a pas de fillfactor : aucun de ses chemins d'UPDATE n'est HOT-eligible (toutes les colonnes mutées sont indexées). Le vacuum par défaut (ff=100%) est correct.

### Détecter les shadow writes (bypass ADR-001)

```sql
-- Toute ligne ici est une violation : DML direct sans passer par une procédure
SELECT logged_at, schema_name, table_name, operation, row_pk
FROM   identity.v_shadow_writes
ORDER  BY logged_at DESC;

-- Sessions marius_admin actives hors maintenance planifiée
SELECT * FROM identity.v_admin_sessions;
-- Doit retourner zéro ligne en production normale.
```

### Vérification de l'isolation TOAST

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT "identifier", headline, slug FROM content.v_article_list LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT "identifier", headline, "articleBody" FROM content.v_article
WHERE  identifier = 1;
```

`shared_blks_hit` doit être significativement plus élevé pour la seconde requête.

### Vérification du predicate pushdown sur `commerce.v_transaction`

```sql
-- Attendu : Index Scan sur commerce.transaction_core (PK), pas de Seq Scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM commerce.v_transaction WHERE "identifier" = 1;
```

---

## Cas d'usage

### Micro-hébergement — le "Blog Frugal"

**Cible** : VPS 1 Go RAM, Raspberry Pi 4, instance mutualisée.

L'enjeu est la **résidence en RAM** du hot path. Pour un site de 5 000 articles avec 500 tags et 2 000 utilisateurs actifs, les composants hot path (`content.core`, `content.identity`, `identity.auth`, `identity.account_core`) représentent environ 5 000 × (72 + 240) + 2 000 × (160 + 48) ≈ **2 Mo de données utiles**. Un `shared_buffers` de 128 Mo couvre ce volume avec une marge ×60. Le système est silencieux : zéro I/O heap sur les lectures de listing une fois le cache chaud.

### Plateformes à fort trafic — le "Scale-up Industriel"

**Cible** : 500 000+ utilisateurs, flux de commentaires massifs, catalogues produits dynamiques.

À ce volume, le coût dominant n'est plus le I/O disque mais la **fragmentation progressive du stockage** (_bloat_) et la pression sur l'autovacuum.

**Zéro dead tuple structurel** (ADR-007) : `content.create_comment()` effectue une seule écriture heap par commentaire (construction du chemin ltree en mémoire PL/pgSQL avant l'INSERT, sans UPDATE post-insertion).

**HOT updates** (ADR-008) : `fillfactor=70` sur `identity.auth` et `fillfactor=80` sur `commerce.product_core` permettent les mises à jour `last_login_at` et `stock` sans nouvelle entrée d'index. Sur 500 000 connexions/jour, l'économie en index maintenance est significative.

**BRIN sur les colonnes temporelles** (ADR-010) : sur `identity.auth` à 500 000 lignes, le BRIN occupe ~50 Ko de `shared_buffers` contre ~11 Mo pour un B-tree équivalent. Les colonnes `created_at` sont protégées par un trigger d'immuabilité — toute modification invaliderait la corrélation physique/logique de l'index.

### Architecture Headless & API-first — le "Content Hub"

**Cible** : Systèmes où le contenu est consommé par plusieurs clients (web, mobile, IoT, services tiers) via une API.

**Zéro N+1 par agrégation SQL** (ADR-023) : un `SELECT` sur `content.v_article` retourne l'article, ses tags et ses médias en un seul aller-retour réseau.

**Interface schema.org stable** (ADR-012) : les vues exposent un contrat nommé (`"givenName"`, `"datePublished"`, `"gtin13"`) découplé du modèle physique. Un remaniement interne ne casse pas l'interface API.

---

## Références

- [Architecture Decision Records](./architecture_decision_records.md)
- [Extended Containment Security Matrix — Guide](./documentation/extended-containment-security-matrix.md)
- [Outils Meta — Mode d'emploi](./documentation/meta_tooling_guide.md)
- [PostgreSQL 18 — Async I/O](https://www.postgresql.org/docs/18/runtime-config-resource.html)
- [PostGIS — ST_DWithin / opérateur KNN](https://postgis.net/docs/ST_DWithin.html)
- [schema.org — Person](https://schema.org/Person) · [Article](https://schema.org/Article) · [Organization](https://schema.org/Organization) · [Order](https://schema.org/Order)
- [ltree — PostgreSQL](https://www.postgresql.org/docs/current/ltree.html)
- [BRIN Indexes](https://www.postgresql.org/docs/current/brin-intro.html)
- [SECURITY DEFINER — PostgreSQL](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY)

---

_Architecture ECS/DOD · PostgreSQL 18 · Projet Marius_
