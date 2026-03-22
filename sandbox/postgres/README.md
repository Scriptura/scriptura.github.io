# Marius — ECS/DOD Database Engine

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-336791?style=for-the-badge&logo=postgresql&logoColor=white)]()
[![PostGIS](https://img.shields.io/badge/PostGIS-3.x-008BB9?style=for-the-badge&logo=postgresql&logoColor=white)]()
[![Architecture](https://img.shields.io/badge/Architecture-ECS%2FDOD-E85D04?style=for-the-badge)]()
[![Design](https://img.shields.io/badge/Design-Data--Oriented-2D6A4F?style=for-the-badge)]()
[![Semantics](https://img.shields.io/badge/Sémantique-schema.org-1565C0?style=for-the-badge)]()
[![Hierarchy](https://img.shields.io/badge/Hiérarchies-ltree-5C6BC0?style=for-the-badge)]()
[![ADR](https://img.shields.io/badge/ADR-19%20décisions-455A64?style=for-the-badge)]()
[![Status](https://img.shields.io/badge/Statut-R%26D-7B1FA2?style=for-the-badge)]()

Architecture de base de données orientée données (DOD) pour PostgreSQL 18,
appliquant les principes de l'Entity-Component-System (ECS) à la modélisation
relationnelle. Conçu pour une cible de **500 000 utilisateurs actifs**.

---

## Philosophie

Les modèles relationnels traditionnels organisent les données en **AoS** (*Array
of Structures*) : chaque entité — utilisateur, article, organisation — est
stockée dans un tuple large regroupant tous ses attributs, qu'ils soient accédés
à chaque requête ou une fois par an.

Ce projet applique le paradigme inverse, **SoA** (*Structure of Arrays*), inspiré
de l'ECS des moteurs de jeu et du DOD bas niveau :

- **Entity** — un identifiant entier pur, sans donnée métier.
- **Component** — une table physique par axe d'accès (noms, contact, biographie,
  contenu long), dimensionnée selon sa fréquence de lecture réelle.
- **System** — une procédure stockée par mutation, seul point d'écriture autorisé
  sur les composants physiques.

La couche applicative ne voit que des **vues sémantiques** reconstituant
l'interface [schema.org](https://schema.org) par-dessus les composants fragmentés.

**Résultat mesurable** : la densité de certains composants hot path atteint
×8,5 celle du modèle monolithique original (`identity.person_identity` :
~110 tuples/page vs ~13 pour `__person`).

---

## Structure du dépôt

```
.
├── master_schema_ddl.pgsql          # Blueprint immuable — DDL pur
├── master_schema_dml.pgsql          # Seed data — dev / CI uniquement
├── architecture_decision_records.md # Journal des 18 décisions architecturales
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
| 9 — Fonctions | Fonctions partagées (`fn_update_modified_at`, `fn_slug_deduplicate`, etc.) |
| 10 — Triggers | Triggers `modified_at`, déduplication de slug, révisions |
| 11 — Procédures | `create_account`, `create_document`, `create_comment`, `create_transaction_item`, etc. |
| 12 — Vues | Toutes les vues sémantiques schema.org |
| 13 — Permissions | `GRANT` / `REVOKE` par rôle applicatif + calibrage autovacuum |

### `master_schema_dml.pgsql`

Données de remplissage à des fins de développement et de benchmarking.
**Ne pas exécuter en production.**

Contenu : 8 entités identity · 12 lieux · 4 profils historiques · 16 articles ·
232 tags · 9 médias · 5 commentaires (via `CALL content.create_comment()`) · liaisons N:N.

Les commentaires sont insérés via la procédure stockée, non par `INSERT` direct :
le DML traverse le même chemin d'écriture que la production, validant l'absence
de dead tuples structurels sur `content.comment`.

Prérequis : `master_schema_ddl.pgsql` exécuté préalablement.

### `architecture_decision_records.md`

Journal des 18 décisions architecturales de la session R&D. Pour chaque décision :
contexte, options évaluées, décision retenue, justification avec chiffres.
Document de référence pour toute évolution future du schéma.

---

## Prérequis

| Composant | Version minimale |
|---|---|
| PostgreSQL | **18** (async I/O, EXPLAIN MEMORY) |
| PostGIS | 3.x |

### Extensions PostgreSQL requises

Les extensions sont déclarées dans le DDL et créées automatiquement à l'exécution.
Elles doivent être disponibles sur le serveur PostgreSQL cible.

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

Le fichier DDL crée lui-même l'utilisateur, la base et se connecte. Exécuter
en tant que superutilisateur PostgreSQL :

```bash
psql -U postgres -f master_schema_ddl.pgsql
```

Ce script est **idempotent sur une installation vierge** (`DROP DATABASE IF EXISTS`
en tête). Sur une base existante, supprimer manuellement la base avant exécution.

### 2. Injection des données de test (optionnel)

```bash
psql -U postgres -d marius -f master_schema_dml.pgsql
```

Le DML utilise `CALL content.create_comment()` pour les commentaires : les
données de test traversent exactement le même chemin d'écriture qu'en production,
validant l'absence de dead tuples structurels et la construction des chemins ltree.

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
d'alignement** pour éliminer le padding invisible entre colonnes :

```
8 bytes  →  TIMESTAMPTZ, FLOAT8, INT8
4 bytes  →  INT4, DATE, FLOAT4
2 bytes  →  SMALLINT
1 byte   →  BOOLEAN
variable →  VARCHAR, TEXT, CHAR, NUMERIC, ltree, geometry
```

NUMERIC est varlena dans PostgreSQL indépendamment de sa précision déclarée —
il va toujours après les types fixes.

### Bitmask des permissions de rôle

Les 15 permissions de `identity.role` sont stockées dans un seul `INT4`
(`permissions`). Chaque bit correspond à une permission (voir `identity.permission_bit`).

```sql
-- Vérifier si une entité peut publier des contenus
SELECT identity.has_permission(42, 16);  -- 16 = publish_contents

-- Lire les permissions d'un compte comme colonnes nommées
SELECT access_admin, create_contents, can_read
FROM   identity.v_role
WHERE  name = 'editor';

-- Accorder une permission à un rôle
CALL identity.grant_permission(3, 256);   -- manage_users au rôle id=3
CALL identity.revoke_permission(3, 256);  -- révoquer
```

Gain : lecture d'un rôle = 1 appel `slot_getattr()` + 30 instructions CPU
en registre, contre 45 appels dans le modèle booléen original.

### TOAST agressif (`toast_tuple_target = 128`)

Les tables cold path (`content.body`, `geo.place_content`,
`commerce.product_content`, `identity.person_content`) sont configurées avec
`toast_tuple_target = 128`. Ce seuil force l'externalisation de tout texte
long, quelle que soit sa taille, laissant un pointeur TOAST de 18 bytes dans
le tuple principal.

Conséquence directe : un `SELECT headline, slug FROM content.v_article_list`
ne déclenche **zéro accès TOAST**, même si la vue inclut `content.body` via
jointure. PostgreSQL ne résout le pointeur TOAST que si la colonne est dans
la liste de projection.

> Ne pas supprimer ce paramètre. Sa valeur non-standard est intentionnelle
> (voir ADR-016).

### Vues de listing vs vues complètes

| Vue | Usage | Charge TOAST |
|---|---|---|
| `content.v_article_list` | Listings, flux, navigation | Zéro |
| `content.v_article` | Page article complète | Oui (`articleBody`) |

Toujours utiliser `v_article_list` pour les listings. Ne projeter `articleBody`
que sur les lectures de page complète.

### Écriture via procédures uniquement

Les `INSERT`/`UPDATE` directs sur les tables physiques sont révoqués pour les
rôles applicatifs. Toute mutation passe par les procédures stockées :

| Procédure | Usage |
|---|---|
| `identity.create_account(...)` | Créer un compte (entity + auth + account_core) |
| `identity.create_person(...)` | Créer un profil public |
| `identity.record_login(entity_id)` | Enregistrer une connexion (hot path) |
| `content.create_document(...)` | Créer un article/page |
| `content.publish_document(document_id)` | Publier un brouillon |
| `content.save_revision(document_id, author_id)` | Snapshot éditorial |
| `content.create_comment(...)` | Insérer un commentaire (zéro dead tuple) |
| `commerce.create_transaction_item(...)` | Ajouter une ligne de commande avec snapshot de prix |

---

## Cas d'usage : de la frugalité à l'extreme scale

L'architecture Marius n'est pas dimensionnée *pour* 500 000 utilisateurs —
elle est dimensionnée *par* les contraintes physiques de PostgreSQL. Cette
rigueur mécanique la rend pertinente à n'importe quelle échelle.

---

### Micro-hébergement & auto-hébergement — le "Blog Frugal"

**Cible** : VPS 1 Go RAM, Raspberry Pi 4, instance mutualisée.

L'enjeu sur ces environnements n'est pas le débit mais la **résidence en RAM**
du hot path. Si les pages les plus accédées tiennent dans `shared_buffers`,
chaque requête est servie sans I/O disque.

**Estimation concrète** : pour un site de 5 000 articles avec 500 tags et
2 000 utilisateurs actifs, les composants hot path (`content.core`,
`content.identity`, `identity.auth`, `identity.account_core`) représentent
environ 5 000 × (64 + 240) + 2 000 × (155 + 77) ≈ **2 Mo de données utiles**.
Un `shared_buffers` de 128 Mo — valeur raisonnable sur un VPS 1 Go — couvre
ce volume avec une marge ×60. Le système est silencieux : zéro I/O heap sur
les lectures de listing une fois le cache chaud.

Le paramètre `toast_tuple_target = 128` (ADR-016) garantit que les corps
d'articles, quelle que soit leur longueur, ne gonfleront jamais ces tables
hot path. La base grossit, les composants core restent denses.

---

### Plateformes à fort trafic — le "Scale-up Industriel"

**Cible** : Applications web avec 500 000+ utilisateurs, flux de commentaires
massifs, catalogues produits dynamiques.

À ce volume, le coût dominant n'est plus le I/O disque mais la **fragmentation
progressive du stockage** (*bloat*) et la pression sur l'autovacuum. Trois
décisions techniques adressent directement ce problème.

**Élimination des dead tuples structurels** (ADR-012) : la procédure
`content.create_comment()` utilise `nextval()` en amont de l'INSERT pour
construire le chemin ltree en mémoire et n'effectuer qu'une seule écriture
heap. Le double trigger `BEFORE`/`AFTER` précédent généraient un dead tuple
garanti par commentaire — sur 10 000 commentaires/jour, l'autovacuum traitait
un bloat auto-infligé continu.

**HOT updates sur les tables à mutations fréquentes** (ADR-015) : les `fillfactor`
réduits (70 sur `identity.auth`, 80 sur `commerce.product_core`) réservent de
l'espace libre dans chaque page pour les mises à jour de `last_login_at` et
`stock`. Un HOT update ne crée pas de nouvelle entrée d'index — sur
500 000 connexions/jour, l'économie en index maintenance est significative.

**Index BRIN sur les colonnes temporelles** (ADR-017) : les colonnes `created_at`
utilisent des index BRIN dont l'empreinte est ~200 fois inférieure à un B-tree
équivalent. Sur `identity.auth` à 500 000 lignes, le BRIN occupe ~50 Ko de
`shared_buffers` contre ~11 Mo pour un B-tree — autant de cache disponible
pour les pages heap à haute densité.

---

### Architecture Headless & API-first — le "Content Hub"

**Cible** : Systèmes où le contenu est consommé par plusieurs clients (web,
mobile, IoT, services tiers) via une API, sans couplage à un front-end unique.

L'isolation stricte des domaines en schémas PostgreSQL (`identity`, `content`,
`commerce`, `geo`, `org`) permet d'utiliser Marius comme un **moteur de données
pur**, indépendant de toute couche de présentation.

**Zéro N+1 par agrégation SQL** (ADR-018) : les vues sémantiques
(`content.v_article`, `commerce.v_transaction`) embarquent les relations N:N
(tags, médias, lignes de commande) directement dans le moteur via `json_agg`.
Un `SELECT` sur `content.v_article WHERE "identifier" = :id` retourne l'article,
ses tags et ses médias en un seul aller-retour réseau, quel que soit le client
consommateur.

**Interface schema.org stable** (ADR-006) : les vues exposent un contrat
nommé (`"givenName"`, `"datePublished"`, `"gtin13"`) découplé du modèle
physique sous-jacent. Un remaniement interne des composants ne casse pas
l'interface API tant que la vue est maintenue.

**Cloisonnement des permissions par domaine** (ADR-007) : chaque service
applicatif peut se voir accorder l'accès à un sous-ensemble de schémas.
Un service éditorial n'a accès qu'à `content` et aux vues en lecture de
`identity` ; un service de facturation accède à `commerce` sans voir les
données personnelles de `identity`.

```sql
-- Exemple : rôle éditorial, lecture identity + écriture content
CREATE ROLE editorial_service;
GRANT USAGE ON SCHEMA content  TO editorial_service;
GRANT USAGE ON SCHEMA identity TO editorial_service;
GRANT SELECT ON identity.v_account    TO editorial_service;
GRANT SELECT ON content.v_article_list TO editorial_service;
GRANT EXECUTE ON PROCEDURE content.create_document  TO editorial_service;
GRANT EXECUTE ON PROCEDURE content.publish_document TO editorial_service;
```

---

## Maintenance

### Surveillance des dead tuples

```sql
-- État global par table (trier par n_dead_tup DESC)
SELECT schemaname, relname, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
       last_autovacuum, last_analyze
FROM   pg_stat_user_tables
WHERE  schemaname IN ('identity','content','commerce')
ORDER  BY n_dead_tup DESC
LIMIT  20;
```

Les tables à surveiller en priorité :

| Table | Source de dead tuples | fillfactor |
|---|---|---|
| `identity.auth` | `last_login_at` mis à jour à chaque connexion | 70 |
| `commerce.product_core` | `stock` décrémenté à chaque vente | 80 |
| `content.core` | `status` à chaque changement de cycle de vie | 75 |
| `content.comment` | Suppressions de modération (`status = 9`) | défaut |

La procédure `content.create_comment()` (intégrée nativement dans le DDL) élimine les dead tuples
**structurels** liés à la construction du chemin ltree. Les dead tuples
résiduels proviennent uniquement des suppressions légitimes (modération).

### Vérification de l'isolation TOAST post-insertion

```sql
-- Comparer les shared_blks_hit entre listing et lecture complète
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT "identifier", headline, slug FROM content.v_article_list LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT "identifier", headline, "articleBody" FROM content.v_article
WHERE  "identifier" = 1;
```

`shared_blks_hit` doit être significativement plus élevé pour la seconde requête
(accès TOAST). Si les deux sont identiques, vérifier que `toast_tuple_target = 128`
est bien en place sur `content.body`.

### Calibrage autovacuum sur `content.comment`

Les paramètres autovacuum de la table sont calibrés dans le DDL (SECTION 13).

```sql
SELECT reloptions FROM pg_class
WHERE  relname = 'comment'
  AND  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'content');
```

Attendu : `autovacuum_vacuum_scale_factor=0.05, autovacuum_analyze_scale_factor=0.02`.

---

## Références

- [Architecture Decision Records](./architecture_decision_records.md) — journal
  des 18 décisions structurantes de la session R&D.
- [PostgreSQL 18 — Async I/O](https://www.postgresql.org/docs/18/runtime-config-resource.html)
- [PostGIS — ST_DWithin / opérateur KNN](https://postgis.net/docs/ST_DWithin.html)
- [schema.org — Person](https://schema.org/Person) ·
  [Article](https://schema.org/Article) ·
  [Organization](https://schema.org/Organization) ·
  [Order](https://schema.org/Order)
- [ltree — PostgreSQL](https://www.postgresql.org/docs/current/ltree.html)
- [BRIN Indexes](https://www.postgresql.org/docs/current/brin-intro.html)

---

*Architecture ECS/DOD · PostgreSQL 18 · Session R&D Marius*
