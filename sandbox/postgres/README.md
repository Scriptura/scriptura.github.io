# Marius — ECS/DOD Database Engine

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791?style=for-the-badge&logo=postgresql&logoColor=white)]()
[![PostGIS](https://img.shields.io/badge/PostGIS-3.x-008BB9?style=for-the-badge&logo=postgresql&logoColor=white)]()
[![Architecture](https://img.shields.io/badge/Architecture-ECS%2FDOD-E85D04?style=for-the-badge)]()
[![Design](https://img.shields.io/badge/Design-Data--Oriented-2D6A4F?style=for-the-badge)]()
[![Semantics](https://img.shields.io/badge/Sémantique-schema.org-1565C0?style=for-the-badge)]()
[![Hierarchy](https://img.shields.io/badge/Hiérarchies-ltree-5C6BC0?style=for-the-badge)]()
[![ADR](https://img.shields.io/badge/ADR-21%20décisions-455A64?style=for-the-badge)]()
[![Status](https://img.shields.io/badge/Statut-R%26D-7B1FA2?style=for-the-badge)]()

Architecture de base de données orientée données (DOD) pour PostgreSQL 18,
appliquant les principes de l'Entity-Component-System (ECS) à la modélisation
relationnelle. Conçu pour une cible de **500 000 utilisateurs actifs**.

---

## Philosophie

Ce projet applique le paradigme **SoA** (*Structure of Arrays*), inspiré de l'ECS
des moteurs de jeu et du DOD bas niveau :

- **Entity** — un identifiant entier pur, sans donnée métier.
- **Component** — une table physique par axe d'accès (noms, contact, biographie,
  contenu long), dimensionnée selon sa fréquence de lecture réelle.
- **System** — une procédure stockée par mutation, seul point d'écriture autorisé
  sur les composants physiques.

La couche applicative ne voit que des **vues sémantiques** reconstituant
l'interface [schema.org](https://schema.org) par-dessus les composants fragmentés.

**Résultat mesurable** : la densité de certains composants hot path atteint
×8,5 celle d'un modèle monolithique équivalent (`identity.person_identity` :
~110 tuples/page).

---

## Structure du dépôt

```
.
├── master_schema_ddl.pgsql          # Blueprint immuable — DDL pur
├── master_schema_dml.pgsql          # Seed data — dev / CI uniquement
├── architecture_decision_records.md # 20 arbitrages architecturaux
└── README.md
```

### `master_schema_ddl.pgsql`

Le schéma complet en un fichier autonome. Contient dans l'ordre d'exécution :

| Section | Contenu |
|---|---|
| 0 — Initialisation | Création de l'utilisateur, de la base, connexion |
| 1 — Extensions | `unaccent`, `ltree`, `pg_trgm`, `postgis` |
| 2 — Schémas | `identity`, `geo`, `org`, `commerce`, `content` |
| 3 — Spines | `identity.entity`, `org.entity`, `content.document` |
| 4 — Fondation | `geo.place_core/content`, `identity.permission_bit`, `identity.role` |
| 5–8 — Composants | Toutes les tables physiques par domaine |
| 9 — Fonctions | `fn_update_modified_at`, `fn_slug_deduplicate`, `fn_revision_num`, `has_permission` |
| 10 — Triggers | Triggers `modified_at`, déduplication de slug, numérotation des révisions |
| 11 — Procédures | `create_account`, `create_document`, `create_comment`, `create_transaction_item`, etc. |
| 12 — Vues | Toutes les vues sémantiques schema.org |
| 13 — Permissions | `GRANT SELECT + EXECUTE` sur `marius_user` · calibrage autovacuum |
| 14 — Verrouillage ECS | `marius_admin` · révocation DML globale · `SECURITY DEFINER` (ADR-020) |

### `master_schema_dml.pgsql`

Données de remplissage à des fins de développement et de benchmarking.
**Ne pas exécuter en production.**

Exécuté en tant que `postgres` (superutilisateur) : la révocation DML sur
`marius_user` (ADR-020) ne l'affecte pas. Les commentaires sont insérés via
`CALL content.create_comment()` — le seed traverse exactement le même chemin
d'écriture que la production.

### `architecture_decision_records.md`

21 arbitrages architecturaux, ordonnés par importance décroissante. Chaque
entrée documente ce qui **n'est pas déductible de la lecture du code** : le
raisonnement derrière la décision, les alternatives écartées et leurs coûts.

---

## Prérequis

| Composant | Version minimale |
|---|---|
| PostgreSQL | **18** (async I/O, EXPLAIN MEMORY) |
| PostGIS | 3.x |

### Extensions PostgreSQL requises

| Extension | Usage |
|---|---|
| `unaccent` | Normalisation des accents pour les index de recherche texte |
| `ltree` | Chemins matérialisés pour la taxonomie des tags et les threads de commentaires |
| `pg_trgm` | Index trigrammes pour la recherche partielle sur les noms et titres |
| `postgis` | Type `geometry(Point, 4326)`, index GiST géospatiaux, opérateur KNN `<->` |

Vérification de disponibilité sur le serveur cible :

```sql
SELECT name, default_version FROM pg_available_extensions
WHERE  name IN ('unaccent', 'ltree', 'pg_trgm', 'postgis')
ORDER  BY name;
```

---

## Installation

### 1. Déploiement du schéma (DDL)

```bash
psql -U postgres -f master_schema_ddl.pgsql
```

Script **idempotent sur une installation vierge** (`DROP DATABASE IF EXISTS`
en tête). Sur une base existante, supprimer manuellement la base avant exécution.

### 2. Injection des données de test (optionnel)

```bash
psql -U postgres -d marius -f master_schema_dml.pgsql
```

### 3. Vérification post-installation

```sql
\c marius

-- Vérifier les schémas
SELECT schema_name FROM information_schema.schemata
WHERE  schema_name IN ('identity','geo','org','commerce','content')
ORDER  BY schema_name;

-- Vérifier le compte de tables par schéma
SELECT table_schema, COUNT(*) AS tables
FROM   information_schema.tables
WHERE  table_schema IN ('identity','geo','org','commerce','content')
GROUP  BY table_schema ORDER BY table_schema;

-- Tester une vue sémantique
SELECT "identifier", "headline", "datePublished"
FROM   content.v_article_list
LIMIT  5;

-- Vérifier l'intégrité des chemins ltree des commentaires
SELECT id, path, nlevel(path) AS depth
FROM   content.comment
ORDER  BY path;

-- Vérifier que marius_user ne peut pas écrire directement (ADR-020)
SET ROLE marius_user;
INSERT INTO identity.entity DEFAULT VALUES; -- doit échouer avec ERROR 42501
RESET ROLE;

-- Vérifier que SECURITY DEFINER est actif sur toutes les procédures de mutation
SELECT n.nspname, p.proname, p.prosecdef
FROM   pg_proc p
JOIN   pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname IN ('identity','content','org','commerce')
  AND  p.prokind = 'p'
ORDER  BY n.nspname, p.proname;
-- prosecdef = true attendu sur toutes les lignes
```

### Séquence complète (environnement CI/CD)

```bash
psql -U postgres -f master_schema_ddl.pgsql \
  && psql -U postgres -d marius -f master_schema_dml.pgsql
```

---

## Concepts clés — Quick Reference

### Alignement mémoire et padding

Toutes les tables respectent un ordre de déclaration **décroissant par taille
d'alignement** pour éliminer le padding invisible entre colonnes (ADR-004) :

```
8 bytes  →  TIMESTAMPTZ, FLOAT8, INT8
4 bytes  →  INT4, DATE, FLOAT4
2 bytes  →  SMALLINT
1 byte   →  BOOLEAN
variable →  VARCHAR, TEXT, CHAR, NUMERIC, ltree, geometry
```

`NUMERIC` est varlena dans PostgreSQL indépendamment de sa précision déclarée —
il va toujours après les types fixes.

### Bitmask des permissions de rôle

Les permissions sont encodées dans un `INT4` par OR binaire des puissances de 2
(ADR-003). Vérification en une opération `&` sans jointure :

```sql
-- Vérifier si un utilisateur peut publier (bit 4 = valeur 16)
SELECT identity.has_permission(entity_id, 16);

-- Décomposer le bitmask en colonnes booléennes nommées
SELECT * FROM identity.v_role WHERE id = 1;
```

### Vues de listing vs page complète (isolation TOAST, ADR-016)

| Vue | Usage | Charge TOAST |
|---|---|---|
| `content.v_article_list` | Listings, flux, navigation | Zéro |
| `content.v_article` | Page article complète | Oui (`articleBody`) |

Toujours utiliser `v_article_list` pour les listings. Ne projeter `articleBody`
que sur les lectures de page complète.

### Écriture via procédures uniquement (ADR-020)

`marius_user` ne possède aucun droit `INSERT`, `UPDATE`, `DELETE` direct sur les
tables physiques. Toute mutation passe par les procédures stockées, déclarées
`SECURITY DEFINER` : elles s'exécutent avec les droits du propriétaire (`postgres`)
indépendamment des droits de l'appelant.

| Procédure | Usage |
|---|---|
| `identity.create_account(...)` | Créer un compte (entity + auth + account_core) |
| `identity.create_person(...)` | Créer un profil public |
| `identity.record_login(entity_id)` | Enregistrer une connexion (hot path) |
| `content.create_document(...)` | Créer un article/page |
| `content.publish_document(document_id)` | Publier un brouillon |
| `content.save_revision(document_id, author_id)` | Snapshot éditorial complet (name, slug, alt_headline, description, body) |
| `content.create_comment(...)` | Insérer un commentaire (zéro dead tuple, ADR-012) |
| `commerce.create_transaction_item(...)` | Ligne de commande avec snapshot de prix |

### Rôles PostgreSQL

| Rôle           | Droits | Usage |
|---|---|---|
| `marius_user`  | `SELECT` + `EXECUTE` | Runtime applicatif |
| `marius_admin` | `SELECT` + `EXECUTE` + `INSERT/UPDATE/DELETE` | Maintenance, migrations, CI seed |
| `postgres`     | Superutilisateur | Déploiement DDL, installation |

`marius_admin` hérite de `marius_user` via `GRANT ... WITH INHERIT TRUE`.
En environnement hautement sécurisé, désactiver le `LOGIN` direct sur
`marius_admin` et passer par `SET ROLE marius_admin` depuis une session `postgres`.

---

## Cas d'usage : de la frugalité à l'extreme scale

L'architecture Marius n'est pas dimensionnée *pour* 500 000 utilisateurs —
elle est dimensionnée *par* les contraintes physiques de PostgreSQL. Cette
rigueur mécanique la rend pertinente à n'importe quelle échelle.

---

### Micro-hébergement & auto-hébergement — le "Blog Frugal"

**Cible** : VPS 1 Go RAM, Raspberry Pi 4, instance mutualisée.

L'enjeu n'est pas le débit mais la **résidence en RAM** du hot path. Si les
pages les plus accédées tiennent dans `shared_buffers`, chaque requête est
servie sans I/O disque.

**Estimation concrète** : pour un site de 5 000 articles avec 500 tags et
2 000 utilisateurs actifs, les composants hot path (`content.core`,
`content.identity`, `identity.auth`, `identity.account_core`) représentent
environ 5 000 × (64 + 240) + 2 000 × (155 + 77) ≈ **2 Mo de données utiles**.
Un `shared_buffers` de 128 Mo couvre ce volume avec une marge ×60. Le système
est silencieux : zéro I/O heap sur les lectures de listing une fois le cache chaud.

`toast_tuple_target = 128` (ADR-016) garantit que les corps d'articles ne
gonfleront jamais les tables hot path, quelle que soit leur longueur.

---

### Plateformes à fort trafic — le "Scale-up Industriel"

**Cible** : Applications web avec 500 000+ utilisateurs, flux de commentaires
massifs, catalogues produits dynamiques.

À ce volume, le coût dominant n'est plus le I/O disque mais la **fragmentation
progressive du stockage** (*bloat*) et la pression sur l'autovacuum.

**Zéro dead tuple structurel** (ADR-012) : `content.create_comment()` effectue
une seule écriture heap par commentaire. Sur 10 000 commentaires/jour, l'absence
de dead tuples structurels réduit significativement la charge autovacuum.

**HOT updates** (ADR-015) : les `fillfactor` réduits (70 sur `identity.auth`,
80 sur `commerce.product_core`) permettent les mises à jour `last_login_at` et
`stock` sans nouvelle entrée d'index. Sur 500 000 connexions/jour, l'économie
en index maintenance est significative.

**BRIN sur les colonnes temporelles** (ADR-017) : sur `identity.auth` à 500 000
lignes, le BRIN occupe ~50 Ko de `shared_buffers` contre ~11 Mo pour un B-tree
équivalent.

---

### Architecture Headless & API-first — le "Content Hub"

**Cible** : Systèmes où le contenu est consommé par plusieurs clients (web,
mobile, IoT, services tiers) via une API.

**Zéro N+1 par agrégation SQL** (ADR-018) : un `SELECT` sur `content.v_article`
retourne l'article, ses tags et ses médias en un seul aller-retour réseau.

**Interface schema.org stable** (ADR-006) : les vues exposent un contrat nommé
(`"givenName"`, `"datePublished"`, `"gtin13"`) découplé du modèle physique. Un
remaniement interne ne casse pas l'interface API.

**Cloisonnement des permissions par domaine** (ADR-007 + ADR-020) :

```sql
-- Exemple : rôle éditorial, lecture identity + écriture content
CREATE ROLE editorial_service;
GRANT USAGE ON SCHEMA content  TO editorial_service;
GRANT USAGE ON SCHEMA identity TO editorial_service;
GRANT SELECT ON identity.v_account     TO editorial_service;
GRANT SELECT ON content.v_article_list TO editorial_service;
GRANT EXECUTE ON PROCEDURE content.create_document  TO editorial_service;
GRANT EXECUTE ON PROCEDURE content.publish_document TO editorial_service;
```

---

## Maintenance

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

| Table | Source de dead tuples | fillfactor |
|---|---|---|
| `identity.auth` | `last_login_at` à chaque connexion | 70 |
| `commerce.product_core` | `stock` à chaque vente | 80 |
| `content.core` | `status` à chaque changement de cycle | 75 |
| `content.comment` | Suppressions de modération (`status = 9`) | défaut |

### Vérification de l'isolation TOAST

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT "identifier", headline, slug FROM content.v_article_list LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT "identifier", headline, "articleBody" FROM content.v_article
WHERE  "identifier" = 1;
```

`shared_blks_hit` doit être significativement plus élevé pour la seconde requête.

### Calibrage autovacuum sur `content.comment`

```sql
SELECT reloptions FROM pg_class
WHERE  relname = 'comment'
  AND  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'content');
-- Attendu : autovacuum_vacuum_scale_factor=0.05, autovacuum_analyze_scale_factor=0.02
```

### Audit des connexions par rôle

```sql
SELECT usename, application_name, client_addr, state
FROM   pg_stat_activity
WHERE  usename IN ('marius_user', 'marius_admin')
ORDER  BY usename, state;
-- marius_admin ne doit apparaître que lors d'opérations de maintenance explicites.
```

---

## Références

- [Architecture Decision Records](./architecture_decision_records.md)
- [PostgreSQL 18 — Async I/O](https://www.postgresql.org/docs/18/runtime-config-resource.html)
- [PostGIS — ST_DWithin / opérateur KNN](https://postgis.net/docs/ST_DWithin.html)
- [schema.org — Person](https://schema.org/Person) · [Article](https://schema.org/Article) · [Organization](https://schema.org/Organization) · [Order](https://schema.org/Order)
- [ltree — PostgreSQL](https://www.postgresql.org/docs/current/ltree.html)
- [BRIN Indexes](https://www.postgresql.org/docs/current/brin-intro.html)
- [SECURITY DEFINER — PostgreSQL](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY)

---

*Architecture ECS/DOD · PostgreSQL 18 · Projet Marius*
