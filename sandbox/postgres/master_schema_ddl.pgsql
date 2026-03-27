-- ==============================================================================
-- MASTER SCHEMA DDL — Source of Truth (Blueprint immuable)
-- Architecture ECS/DOD · PostgreSQL 18
-- Consolidation : identity_blueprint (+ role_bitmask_update)
--                 extension_blueprint (geo · org · commerce)
--                 content_blueprint
-- ==============================================================================
-- Fichier     : master_schema_ddl.pgsql
-- Exécution   : psql -U postgres -f master_schema_ddl.pgsql
-- Topologie   : Initialisation → Extensions → Schémas → Spines → Composants
--               → Fonctions → Triggers → Procédures → Vues → Permissions
-- Dépendances : aucune (fichier autonome)
-- Associé à   : master_schema_dml.pgsql (seed data, dev/CI uniquement)
-- ==============================================================================


-- ==============================================================================
-- SECTION 0 : INITIALISATION
-- ==============================================================================

DROP DATABASE IF EXISTS marius;
REASSIGN OWNED BY marius_user TO postgres;
DROP OWNED BY marius_user;
DROP USER IF EXISTS marius_user;
CREATE USER marius_user WITH ENCRYPTED PASSWORD 'root';
CREATE DATABASE marius OWNER marius_user;

\c marius


-- ==============================================================================
-- SECTION 1 : EXTENSIONS
-- ==============================================================================

CREATE EXTENSION unaccent;    -- normalisation des accents (recherche texte)
CREATE EXTENSION ltree;       -- chemins matérialisés (tags, commentaires)
CREATE EXTENSION pg_trgm;     -- index trigrammes (recherche partielle sur noms)
CREATE EXTENSION postgis;     -- types et index géospatiaux (geo.place_core)


-- ==============================================================================
-- SECTION 2 : SCHÉMAS
-- ==============================================================================

CREATE SCHEMA identity;
CREATE SCHEMA geo;
CREATE SCHEMA org;
CREATE SCHEMA commerce;
CREATE SCHEMA content;


-- ==============================================================================
-- SECTION 3 : SPINES (ENTITÉS RACINES)
-- Tous les composants référencent ces tables via FK.
-- Aucune donnée métier stockée ici — identifiants purs.
-- ==============================================================================

-- Acteurs du système (utilisateurs, profils publics, contacts)
-- anonymized_at : timestamp de la dernière anonymisation RGPD (irréversible).
-- NULL = entité active. Non-NULL = données nominatives effacées (ADR-024).
-- L'entité physique est conservée pour maintenir l'intégrité des FK commerce.
CREATE TABLE identity.entity (
  anonymized_at  TIMESTAMPTZ  NULL,
  id             INT          GENERATED ALWAYS AS IDENTITY,
  PRIMARY KEY (id)
);

-- Organisations (entreprises, associations, organismes)
CREATE TABLE org.entity (
  id  INT  GENERATED ALWAYS AS IDENTITY,
  PRIMARY KEY (id)
);

-- Documents éditoriaux (articles, pages, newsletters)
-- doc_type : 0=article · 1=page · 2=billet · 3=newsletter
CREATE TABLE content.document (
  id        INT       GENERATED ALWAYS AS IDENTITY,
  doc_type  SMALLINT  NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  CONSTRAINT doc_type_range CHECK (doc_type IN (0, 1, 2, 3))
);


-- ==============================================================================
-- SECTION 4 : TABLES DE FONDATION
-- (aucune FK vers les composants — dépendances minimales)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 4a — GEO : PLACE CORE & PLACE CONTENT
-- ------------------------------------------------------------------------------

-- Spine spatial pur — ADR-024 : données postales extraites vers geo.postal_address.
-- Layout (ADR-004) :
--   id INT4 (offset 0) · elevation SMALLINT (4) · type_id SMALLINT (6) | varlena
-- Tuple avec GPS+nom : ~46 B → ~179 tuples/page (vs ~211 B avant fragmentation)
-- Tuple GPS seul, sans nom : ~26 B → ~317 tuples/page
-- Les requêtes KNN/ST_DWithin ne chargent plus aucune donnée postale.
CREATE TABLE geo.place_core (
  id            INT                   GENERATED ALWAYS AS IDENTITY,
  elevation     SMALLINT              NULL,
  type_id       SMALLINT              NULL,
  name          VARCHAR(60)           NULL,
  coordinates   geometry(Point,4326)  NULL,
  PRIMARY KEY (id),
  CONSTRAINT coordinates_valid CHECK (coordinates IS NULL OR ST_IsValid(coordinates))
);

CREATE INDEX place_core_gist ON geo.place_core USING gist (coordinates)
  WHERE coordinates IS NOT NULL;

-- POSTAL ADDRESS — adresse postale (ADR-024 · sémantique schema.org/PostalAddress)
-- Composant logistique 1:1 sur place_id. Accès lors de l'affichage d'une adresse,
-- de la génération d'une facture ou d'un bordereau d'expédition.
-- Layout (ADR-004) :
--   place_id INT4 (offset 0) · country_code SMALLINT (4) · 2B pad (6) | varlena
-- country_code : ISO 3166-1 numérique — 2 B pass-by-value (ADR-024).
-- Nom conservé (vs address_country) : country_code signale explicitement que la
-- valeur est un code entier (250), pas une chaîne textuelle ("France") — ADR-025.
--   Exemples : 250 = France · 276 = Allemagne · 840 = États-Unis · 826 = Royaume-Uni.
--   Le mapping vers le code alphabétique (FR, DE, US) est délégué à l'applicatif.
CREATE TABLE geo.postal_address (
  place_id      INT          NOT NULL,
  country_code  SMALLINT     NULL,
  address_locality  VARCHAR(64)  NULL,
  address_region    VARCHAR(64)  NULL,
  street_address    VARCHAR(60)  NULL,
  postal_code   VARCHAR(16)  NULL,
  PRIMARY KEY (place_id),
  FOREIGN KEY (place_id) REFERENCES geo.place_core(id) ON DELETE CASCADE,
  CONSTRAINT country_code_range CHECK (country_code IS NULL OR country_code BETWEEN 1 AND 999)
);

CREATE INDEX postal_address_country_locality ON geo.postal_address (country_code, address_locality)
  WHERE country_code IS NOT NULL;

-- Corps textuel isolé : TOAST systématique (toast_tuple_target = 128)
CREATE TABLE geo.place_content (
  place_id     INT   NOT NULL,
  description  TEXT  NULL,
  PRIMARY KEY (place_id),
  FOREIGN KEY (place_id) REFERENCES geo.place_core(id) ON DELETE CASCADE
) WITH (toast_tuple_target = 128);


-- ------------------------------------------------------------------------------
-- 4b — IDENTITY : PERMISSIONS & RÔLES (bitmask INT4)
-- ------------------------------------------------------------------------------

-- Registre des bits — source of truth des permissions
-- Layout : bit_value INT4 · bit_index INT4 | puis varlena
CREATE TABLE identity.permission_bit (
  bit_value    INT          NOT NULL,
  bit_index    INT          NOT NULL,
  name         VARCHAR(30)  NOT NULL UNIQUE,
  description  VARCHAR(120) NULL,
  PRIMARY KEY (bit_value),
  UNIQUE (bit_index),
  CONSTRAINT power_of_2  CHECK (bit_value > 0 AND (bit_value & (bit_value - 1)) = 0),
  CONSTRAINT index_range CHECK (bit_index BETWEEN 0 AND 30)
);
-- Données de configuration structurelle — immuables en production
-- Protégées ici au plus tôt, avant le GRANT global de SECTION 13.
REVOKE INSERT, UPDATE, DELETE ON identity.permission_bit FROM PUBLIC;

INSERT INTO identity.permission_bit (bit_value, bit_index, name, description) VALUES
  (    1,  0, 'access_admin',     'Accès au panneau d''administration'),
  (    2,  1, 'create_contents',  'Créer des contenus éditoriaux'),
  (    4,  2, 'edit_contents',    'Modifier des contenus existants'),
  (    8,  3, 'delete_contents',  'Supprimer des contenus'),
  (   16,  4, 'publish_contents', 'Publier et dépublier des contenus'),
  (   32,  5, 'create_comments',  'Poster des commentaires'),
  (   64,  6, 'edit_comments',    'Modifier des commentaires'),
  (  128,  7, 'delete_comments',  'Supprimer des commentaires'),
  (  256,  8, 'manage_users',     'Gérer les comptes utilisateurs'),
  (  512,  9, 'manage_groups',    'Gérer les groupes'),
  ( 1024, 10, 'manage_contents',  'Administrer l''ensemble des contenus'),
  ( 2048, 11, 'manage_tags',      'Gérer la taxonomie (tags)'),
  ( 4096, 12, 'manage_menus',     'Gérer la navigation (menus)'),
  ( 8192, 13, 'upload_files',     'Uploader des fichiers médias'),
  (16384, 14, 'can_read',             'Lire les contenus protégés (rôle minimal)'),
  (32768,    15, 'edit_others_contents', 'Modifier les contenus rédigés par d''autres auteurs'),
  (65536,    16, 'moderate_comments',    'Changer le statut des commentaires (spam, approbation)'),
  (131072,   17, 'view_transactions',    'Lire les données financières du schéma commerce'),
  (262144,   18, 'manage_commerce',      'Gérer produits, stocks et remboursements'),
  (524288,   19, 'manage_system',        'Modifier les invariants structurels (org, geo, config)'),
  (1048576,  20, 'export_data',          'Extraction massive de données (RGPD, sauvegarde)');

-- Layout : permissions INT4 (offset 0) · id SMALLINT (offset 4) · 2B pad · name varlena
-- Tuple 'administrator' (13 chars) : 24+4+2+2+17 = 49 B  (vs 61 B ancien modèle booléen)
CREATE TABLE identity.role (
  permissions  INT          NOT NULL DEFAULT 16384,
  id           SMALLINT     GENERATED ALWAYS AS IDENTITY,
  name         VARCHAR(13)  NOT NULL UNIQUE,
  PRIMARY KEY (id),
  CONSTRAINT permissions_range CHECK (permissions BETWEEN 0 AND 2097151)
);
-- Données de configuration structurelle — immuables en production
REVOKE INSERT, UPDATE, DELETE ON identity.role FROM PUBLIC;

-- Valeurs calculées : somme des puissances de 2 des permissions actives (voir role_bitmask_update.pgsql)
-- Valeurs recalculées avec les bits 15-20 (ADR-027) ; delete_contents(8) ajouté à base_author (ADR-029).
-- administrator   : tous les bits 0–20 = 2^21−1
-- moderator       : base_author + publish_contents(16) + manage_tags(2048) + edit_others_contents(32768) + moderate_comments(65536)
-- editor          : base_author + edit_others_contents(32768) + manage_tags(2048)
-- author (base)   : can_read(16384)+create_contents(2)+edit_contents(4)+delete_contents(8)+upload_files(8192)+create_comments(32)
-- contributor     : can_read(16384)+create_contents(2)+create_comments(32)
-- commentator     : can_read(16384)+create_comments(32)+edit_comments(64)+delete_comments(128)
-- subscriber      : can_read uniquement (bit 14) · id=7, DEFAULT dans identity.auth
INSERT INTO identity.role (permissions, name) VALUES
  (2097151, 'administrator'),
  ( 124990, 'moderator'),
  (  59438, 'editor'),
  (  24622, 'author'),
  (  16418, 'contributor'),
  (  16608, 'commentator'),
  (  16384, 'subscriber');


-- ==============================================================================
-- SECTION 5 : COMPOSANTS IDENTITY
-- Ordre FK : entity → auth → account_core → person_* → group*
-- ==============================================================================

-- AUTH — hot path (chaque requête authentifiée) · fillfactor=70 pour HOT updates
-- Layout (ADR-004) :
--   3×TIMESTAMPTZ (8B, offsets 0–23) · entity_id INT4 (24) · role_id SMALLINT (28)
--   · is_banned BOOL (30, 1B) · [1B libre offset 31 — slot réservé pour un prochain
--   BOOLEAN sans coût marginal, ex : is_email_verified] · password_hash varlena (32+)
-- Tuple ~155 B → ~51 tuples/page
CREATE TABLE identity.auth (
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
  last_login_at  TIMESTAMPTZ   NULL,
  modified_at    TIMESTAMPTZ   NULL,
  entity_id      INT           NOT NULL,
  role_id        SMALLINT      NOT NULL DEFAULT 7,
  is_banned      BOOLEAN       NOT NULL DEFAULT false,
  -- Slot 1B libre à l'offset 31 (padding avant varlena) — voir commentaire de table.
  password_hash  VARCHAR(255)  NOT NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (role_id)   REFERENCES identity.role(id)
) WITH (fillfactor = 70);

CREATE INDEX auth_created_at_brin ON identity.auth USING brin (created_at)
  WITH (pages_per_range = 128);

-- ACCOUNT CORE — données publiques du compte (ADR-024 : +tos_accepted_at)
-- Layout (ADR-004) : tos_accepted_at TIMESTAMPTZ (offset 0, 8B)
--   · 4×INT4 (8-23) · 2×SMALLINT (24-27) · 2×BOOL (28-29) · 2B pad (30-31) | varlena
-- Tuple ~85 B → ~99 tuples/page
-- tos_accepted_at : timestamp d'acceptation des CGU. NULL = non encore accepté.
CREATE TABLE identity.account_core (
  tos_accepted_at     TIMESTAMPTZ  NULL,
  entity_id           INT          NOT NULL,
  person_entity_id    INT          NULL,
  media_id            INT          NULL,
  site_style          SMALLINT     NULL,
  display_mode        SMALLINT     NOT NULL DEFAULT 0,
  is_visible          BOOLEAN      NOT NULL DEFAULT true,
  is_private_message  BOOLEAN      NOT NULL DEFAULT false,
  username            VARCHAR(32)  NOT NULL,
  slug                VARCHAR(32)  NOT NULL,
  language            CHAR(5)      NOT NULL DEFAULT 'fr_FR',
  time_zone           TEXT         NULL,
  PRIMARY KEY (entity_id),
  UNIQUE (username),
  UNIQUE (slug),
  FOREIGN KEY (entity_id)        REFERENCES identity.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (person_entity_id) REFERENCES identity.entity(id) ON DELETE SET NULL,
  FOREIGN KEY (media_id)         REFERENCES content.media_core(id) ON DELETE SET NULL,
  CONSTRAINT display_mode_range  CHECK (display_mode BETWEEN 0 AND 3),
  CONSTRAINT slug_format         CHECK (slug ~ '^[a-z0-9-]+$')
);

-- PERSON IDENTITY — noms (HAUTE fréquence) · ~74 B → ~110 tuples/page
CREATE TABLE identity.person_identity (
  entity_id        INT          NOT NULL,
  gender           SMALLINT     NULL,
  given_name       VARCHAR(32)  NULL,
  family_name      VARCHAR(32)  NULL,
  usual_name       VARCHAR(32)  NULL,
  nickname         VARCHAR(32)  NULL,
  prefix           VARCHAR(32)  NULL,
  suffix           VARCHAR(32)  NULL,
  additional_name  VARCHAR(32)  NULL,
  nationality      CHAR(2)      NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE
);

CREATE INDEX person_identity_name ON identity.person_identity (family_name, given_name)
  WHERE family_name IS NOT NULL;

-- PERSON CONTACT — (MOYENNE fréquence)
CREATE TABLE identity.person_contact (
  entity_id  INT           NOT NULL,
  place_id   INT           NULL,
  email      VARCHAR(128)  NULL,
  phone      VARCHAR(32)   NULL,
  phone2     VARCHAR(32)   NULL,
  fax        VARCHAR(32)   NULL,
  url        VARCHAR(255)  NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (place_id)  REFERENCES geo.place_core(id)  ON DELETE SET NULL
);

-- PERSON BIOGRAPHY — dates/lieux · layout 100% INT4/DATE, zéro padding · 44 B → ~185 tuples/page
CREATE TABLE identity.person_biography (
  entity_id       INT   NOT NULL,
  birth_place_id  INT   NULL,
  death_place_id  INT   NULL,
  birth_date      DATE  NULL,
  death_date      DATE  NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id)      REFERENCES identity.entity(id)   ON DELETE CASCADE,
  FOREIGN KEY (birth_place_id) REFERENCES geo.place_core(id)    ON DELETE SET NULL,
  FOREIGN KEY (death_place_id) REFERENCES geo.place_core(id)    ON DELETE SET NULL
);

-- PERSON CONTENT — textes longs (TRÈS BASSE fréquence) · TOAST systématique
CREATE TABLE identity.person_content (
  entity_id   INT           NOT NULL,
  media_id    INT           NULL,
  occupation  VARCHAR(30)   NULL,
  bias        VARCHAR(30)   NULL,
  hobby       VARCHAR(64)   NULL,
  award       VARCHAR(128)  NULL,
  devise      VARCHAR(100)  NULL,
  description TEXT          NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (media_id)  REFERENCES content.media_core(id) ON DELETE SET NULL
) WITH (toast_tuple_target = 128);

-- GROUP — communautés / groupes d'utilisateurs
-- Layout : created_at TIMESTAMPTZ (8B) · id INT4 | puis varlena
CREATE TABLE identity.group (
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
  id           INT           GENERATED ALWAYS AS IDENTITY,
  name         VARCHAR(32)   NOT NULL UNIQUE,
  description  TEXT          NULL,
  PRIMARY KEY (id)
);

-- Liaison Group ↔ Account (N:N) · 32 B → ~255 tuples/page
CREATE TABLE identity.group_to_account (
  group_id          INT  NOT NULL,
  account_entity_id INT  NOT NULL,
  PRIMARY KEY (group_id, account_entity_id),
  FOREIGN KEY (group_id)          REFERENCES identity.group(id)  ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (account_entity_id) REFERENCES identity.entity(id) ON UPDATE CASCADE ON DELETE CASCADE
);


-- ==============================================================================
-- SECTION 6 : COMPOSANTS ORG
-- ==============================================================================

-- ORG CORE — lookup standard · ~84 B → ~97 tuples/page
-- Corrections : contact_entity_id INT FK identity.entity (ex VARCHAR(255))
--               parent_entity_id  INT FK org.entity      (self-référence)
CREATE TABLE org.org_core (
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  entity_id           INT           NOT NULL,
  place_id            INT           NULL,
  contact_entity_id   INT           NULL,
  media_id            INT           NULL,
  parent_entity_id    INT           NULL,
  type                VARCHAR(30)   NULL,
  purpose             VARCHAR(30)   NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id)         REFERENCES org.entity(id)       ON DELETE CASCADE,
  FOREIGN KEY (parent_entity_id)  REFERENCES org.entity(id)       ON DELETE SET NULL,
  FOREIGN KEY (place_id)          REFERENCES geo.place_core(id)   ON DELETE SET NULL,
  FOREIGN KEY (contact_entity_id) REFERENCES identity.entity(id)  ON DELETE SET NULL,
  FOREIGN KEY (media_id)          REFERENCES content.media_core(id) ON DELETE SET NULL
);

CREATE INDEX org_core_created_brin ON org.org_core USING brin (created_at)
  WITH (pages_per_range = 64);

-- Index B-tree sur parent_entity_id : navigation parent→enfants directs (O(log n)).
-- Sans cet index, WHERE parent_entity_id = X est un seq scan sur org_core.
CREATE INDEX org_core_parent ON org.org_core (parent_entity_id)
  WHERE parent_entity_id IS NOT NULL;

-- ORG IDENTITY — noms et marques (HAUTE fréquence)
CREATE TABLE org.org_identity (
  entity_id  INT           NOT NULL,
  name       VARCHAR(64)   NOT NULL,
  brand      VARCHAR(255)  NULL,
  slug       VARCHAR(64)   NOT NULL,
  PRIMARY KEY (entity_id),
  UNIQUE (slug),
  FOREIGN KEY (entity_id) REFERENCES org.entity(id) ON DELETE CASCADE,
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE INDEX org_identity_name_trgm ON org.org_identity
  USING gin (unaccent(name) gin_trgm_ops);

-- ORG CONTACT
CREATE TABLE org.org_contact (
  entity_id  INT           NOT NULL,
  email      VARCHAR(128)  NULL,
  phone      VARCHAR(30)   NULL,
  phone2     VARCHAR(30)   NULL,
  fax        VARCHAR(30)   NULL,
  url        VARCHAR(255)  NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES org.entity(id) ON DELETE CASCADE
);

-- ORG LEGAL — DUNS/SIRET en VARCHAR (ADR-022) : CHAR(n) dans PostgreSQL est varlena
-- comme VARCHAR(n) — aucun stockage fixe, mais surcoût de padding/stripping CPU.
-- L'invariant de longueur est garanti exclusivement par les contraintes CHECK.
CREATE TABLE org.org_legal (
  entity_id   INT           NOT NULL,
  duns        VARCHAR(9)    NULL,
  siret       VARCHAR(14)   NULL,
  vat_id      VARCHAR(32)   NULL,   -- VARCHAR(32) : TVA internationale + IDs fiscaux hors UE (ADR-024)
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES org.entity(id) ON DELETE CASCADE,
  CONSTRAINT duns_format  CHECK (duns  IS NULL OR duns  ~ '^[0-9]{9}$'),
  CONSTRAINT siret_format CHECK (siret IS NULL OR siret ~ '^[0-9]{14}$')
);

-- ORG HIERARCHY — nested set · 40 B → ~204 tuples/page
CREATE TABLE org.org_hierarchy (
  entity_id  INT       NOT NULL,
  lft        INT       NOT NULL DEFAULT 1,
  rgt        INT       NOT NULL DEFAULT 2,
  depth      SMALLINT  NOT NULL DEFAULT 0,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES org.entity(id) ON DELETE CASCADE,
  CONSTRAINT lft_rgt_order  CHECK (lft < rgt),
  CONSTRAINT depth_positive CHECK (depth >= 0)
);

CREATE INDEX org_hierarchy_interval ON org.org_hierarchy (lft, rgt);


-- ==============================================================================
-- SECTION 7 : COMPOSANTS COMMERCE
-- ==============================================================================

-- PRODUCT CORE — prix et stock (HAUTE fréquence) · fillfactor=80 pour HOT updates
-- Layout (ADR-004 + ADR-022) :
--   price_cents INT8 (offset 0, 8B) · id INT4 (8) · stock INT4 (12) · media_id INT4 (16)
--   · is_available BOOL (20, 1B) · 3B pad (21-23)
-- Tuple 24 B → ~341 tuples/page (vs ~170 avec NUMERIC — densité ×2)
-- price_cents : montant en centimes de la devise de référence (ADR-022).
--   Exemples : 1999 = 19,99 € · 0 = gratuit · NULL = prix non défini.
--   La conversion décimale est déléguée à la couche applicative.
CREATE TABLE commerce.product_core (
  price_cents   INT8     NULL                  CHECK (price_cents >= 0),
  id            INT      GENERATED ALWAYS AS IDENTITY,
  stock         INT      NOT NULL DEFAULT 0    CHECK (stock >= 0),
  media_id      INT      NULL,
  is_available  BOOLEAN  NOT NULL DEFAULT true,
  PRIMARY KEY (id),
  FOREIGN KEY (media_id) REFERENCES content.media_core(id) ON DELETE SET NULL
) WITH (fillfactor = 80);

-- PRODUCT IDENTITY — catalogue
-- isbn_ean en VARCHAR(13) : même raisonnement que duns/siret (ADR-022).
CREATE TABLE commerce.product_identity (
  product_id  INT           NOT NULL,
  name        VARCHAR(64)   NOT NULL,
  slug        VARCHAR(64)   NOT NULL,
  isbn_ean    VARCHAR(13)   NULL,
  PRIMARY KEY (product_id),
  UNIQUE (slug),
  UNIQUE (isbn_ean),
  FOREIGN KEY (product_id) REFERENCES commerce.product_core(id) ON DELETE CASCADE,
  CONSTRAINT isbn_ean_format CHECK (isbn_ean IS NULL OR isbn_ean ~ '^[0-9]{13}$'),
  CONSTRAINT slug_format     CHECK (slug ~ '^[a-z0-9-]+$')
);

-- PRODUCT CONTENT — TOAST systématique
CREATE TABLE commerce.product_content (
  product_id   INT           NOT NULL,
  description  TEXT          NULL,
  tags         VARCHAR(255)  NULL,
  PRIMARY KEY (product_id),
  FOREIGN KEY (product_id) REFERENCES commerce.product_core(id) ON DELETE CASCADE
) WITH (toast_tuple_target = 128);

-- TRANSACTION CORE — spine de commande (ADR-023)
-- Composant hot path : statut, dates, FK entités — zero champs froids.
-- Layout (ADR-004) :
--   2×TIMESTAMPTZ (offset 0, 16B) · id INT4 (16) · client_entity_id INT4 (20)
--   · seller_entity_id INT4 (24) · status SMALLINT (28) · 2B pad (30)
-- Tuple 32 B (sans description) → ~258 tuples/page
-- seller_entity_id : entité org vendeur (était org_entity_id — renommé pour
--   cohérence avec la sémantique schema.org/Order.seller).
CREATE TABLE commerce.transaction_core (
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at         TIMESTAMPTZ   NULL,
  id                  INT           GENERATED ALWAYS AS IDENTITY,
  client_entity_id    INT           NOT NULL,
  seller_entity_id    INT           NOT NULL,
  status              SMALLINT      NOT NULL DEFAULT 0,
  description         TEXT          NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (client_entity_id)  REFERENCES identity.entity(id),
  FOREIGN KEY (seller_entity_id)  REFERENCES org.entity(id),
  CONSTRAINT status_range CHECK (status IN (0, 1, 2, 3, 9))
);

CREATE INDEX transaction_core_pending ON commerce.transaction_core (client_entity_id, created_at DESC)
  WHERE status = 0;
CREATE INDEX transaction_created_brin ON commerce.transaction_core USING brin (created_at)
  WITH (pages_per_range = 128);

-- TRANSACTION PRICE — PriceSpecification (ADR-023)
-- Composant financier : montants, devise, taxe. Accès à la validation/affichage.
-- Layout (ADR-004 + ADR-022) :
--   3×INT8 (offset 0, 24B) · transaction_id INT4 (24) · tax_rate_bp INT4 (28)
--   · currency_code SMALLINT (32) · is_tax_included BOOL (34) · 1B pad (35)
-- Tuple 36 B → ~229 tuples/page
-- currency_code : code ISO 4217 numérique (ex: 978 = EUR, 840 = USD).
--   SMALLINT 2 B pass-by-value (ADR-023) vs CHAR(3) varlena avec padding.
-- tax_rate_bp : taux de taxe en basis points (ex: 2000 = 20,00%).
--   INT4 pass-by-value (ADR-023) vs NUMERIC varlena + arithmétique logicielle.
CREATE TABLE commerce.transaction_price (
  shipping_cents   INT8      NOT NULL DEFAULT 0  CHECK (shipping_cents  >= 0),
  discount_cents   INT8      NOT NULL DEFAULT 0  CHECK (discount_cents  >= 0),
  tax_cents        INT8      NOT NULL DEFAULT 0  CHECK (tax_cents       >= 0),
  transaction_id   INT       NOT NULL,
  tax_rate_bp      INT4      NOT NULL DEFAULT 0  CHECK (tax_rate_bp     >= 0),
  currency_code    SMALLINT  NOT NULL DEFAULT 978,
  is_tax_included  BOOLEAN   NOT NULL DEFAULT false,
  PRIMARY KEY (transaction_id),
  FOREIGN KEY (transaction_id) REFERENCES commerce.transaction_core(id) ON DELETE CASCADE,
  CONSTRAINT currency_code_range CHECK (currency_code BETWEEN 1 AND 999)
);

-- TRANSACTION PAYMENT — PaymentChargeSpecification (ADR-023)
-- Composant paiement : statut, méthode, référence PSP, numéro de facture.
-- Accès contextuel (confirmation de commande, facture, tableau de bord admin).
-- Layout (ADR-004) :
--   paid_at TIMESTAMPTZ (offset 0, 8B) · transaction_id INT4 (8)
--   · billing_place_id INT4 (12) · payment_status SMALLINT (16) · 2B pad (18)
--   · invoice_number varlena · payment_method varlena · provider_reference varlena
CREATE TABLE commerce.transaction_payment (
  paid_at             TIMESTAMPTZ   NULL,
  transaction_id      INT           NOT NULL,
  billing_place_id    INT           NULL,
  payment_status      SMALLINT      NOT NULL DEFAULT 0,
  invoice_number      VARCHAR(64)   NULL,
  payment_method      VARCHAR(32)   NULL,
  provider_reference  VARCHAR(255)  NULL,
  PRIMARY KEY (transaction_id),
  UNIQUE (invoice_number),
  FOREIGN KEY (transaction_id)  REFERENCES commerce.transaction_core(id) ON DELETE CASCADE,
  FOREIGN KEY (billing_place_id) REFERENCES geo.place_core(id)           ON DELETE SET NULL,
  CONSTRAINT payment_status_range CHECK (payment_status IN (0, 1, 2, 3, 9))
);

-- TRANSACTION DELIVERY — ParcelDelivery (ADR-023)
-- Composant logistique : adresse, transporteur, suivi. Données froides —
-- consultées après expédition uniquement. Isolées pour ne pas polluer
-- transaction_core qui est accédé à chaque affichage de statut de commande.
-- Layout (ADR-004) :
--   3×TIMESTAMPTZ (offset 0, 24B) · transaction_id INT4 (24)
--   · shipping_place_id INT4 (28) · delivery_status SMALLINT (32) · 2B pad (34)
--   · carrier varlena · tracking_number varlena
CREATE TABLE commerce.transaction_delivery (
  shipped_at          TIMESTAMPTZ   NULL,
  estimated_at        TIMESTAMPTZ   NULL,
  delivered_at        TIMESTAMPTZ   NULL,
  transaction_id      INT           NOT NULL,
  shipping_place_id   INT           NULL,
  delivery_status     SMALLINT      NOT NULL DEFAULT 0,
  carrier             VARCHAR(64)   NULL,
  tracking_number     VARCHAR(255)  NULL,
  PRIMARY KEY (transaction_id),
  FOREIGN KEY (transaction_id)    REFERENCES commerce.transaction_core(id) ON DELETE CASCADE,
  FOREIGN KEY (shipping_place_id) REFERENCES geo.place_core(id)            ON DELETE SET NULL,
  CONSTRAINT delivery_status_range CHECK (delivery_status IN (0, 1, 2, 3, 4, 9))
);

-- TRANSACTION ITEM — résolution 1NF
-- Layout (ADR-004 + ADR-022) :
--   unit_price_snapshot_cents INT8 (offset 0, 8B) · transaction_id INT4 (8)
--   · product_id INT4 (12) · quantity INT4 (16)
-- Tuple 20 B → ~409 tuples/page (vs ~186 avec NUMERIC — densité ×2,2)
-- unit_price_snapshot_cents : snapshot du prix en centimes au moment de l'INSERT.
--   Immuable après création — garantit l'intégrité de l'historique des commandes.
CREATE TABLE commerce.transaction_item (
  unit_price_snapshot_cents  INT8  NOT NULL  CHECK (unit_price_snapshot_cents >= 0),
  transaction_id             INT   NOT NULL,
  product_id                 INT   NOT NULL,
  quantity                   INT   NOT NULL DEFAULT 1  CHECK (quantity > 0),
  PRIMARY KEY (transaction_id, product_id),
  FOREIGN KEY (transaction_id) REFERENCES commerce.transaction_core(id) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (product_id)     REFERENCES commerce.product_core(id)
);

CREATE INDEX transaction_item_product ON commerce.transaction_item (product_id);

-- Immutabilité de transaction_item (ADR-030) :
-- unit_price_snapshot_cents est un enregistrement d'audit financier — il ne doit
-- jamais être modifié après l'INSERT, même par marius_admin.
-- La seule opération légitime sur une ligne existante est la suppression (annulation).
-- EXCEPTION : quantity peut être corrigée avant confirmation (status=0) — non implémenté
-- ici car hors périmètre du blueprint ; le trigger bloque tout UPDATE sans distinction.
CREATE FUNCTION commerce.fn_deny_transaction_item_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'transaction_item is immutable after INSERT: modify quantity by deleting and re-inserting the line'
    USING ERRCODE = '55000';  -- object_not_in_prerequisite_state
END;
$$;

CREATE TRIGGER transaction_item_immutable
BEFORE UPDATE ON commerce.transaction_item
FOR EACH ROW EXECUTE FUNCTION commerce.fn_deny_transaction_item_update();


-- ==============================================================================
-- SECTION 8 : COMPOSANTS CONTENT
-- ==============================================================================

-- CONTENT CORE — status / dates / auteur (TRÈS HAUTE fréquence) · fillfactor=75
-- Layout : 3×TIMESTAMPTZ · document_id INT4 · author_entity_id INT4 · status SMALLINT
--          · 3×BOOL · 3B pad
-- Tuple 64 B → ~127 tuples/page
CREATE TABLE content.core (
  published_at        TIMESTAMPTZ   NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at         TIMESTAMPTZ   NULL,
  document_id         INT           NOT NULL,
  author_entity_id    INT           NOT NULL,
  status              SMALLINT      NOT NULL DEFAULT 0,
  is_readable         BOOLEAN       NOT NULL DEFAULT true,
  is_commentable      BOOLEAN       NOT NULL DEFAULT false,
  is_visible_comments BOOLEAN       NOT NULL DEFAULT true,
  PRIMARY KEY (document_id),
  FOREIGN KEY (document_id)      REFERENCES content.document(id)  ON DELETE CASCADE,
  FOREIGN KEY (author_entity_id) REFERENCES identity.entity(id),
  CONSTRAINT status_range CHECK (status IN (0, 1, 2, 9))
) WITH (fillfactor = 75);

CREATE INDEX core_published ON content.core (published_at DESC) WHERE status = 1;
CREATE INDEX core_author    ON content.core (author_entity_id, published_at DESC) WHERE status = 1;
CREATE INDEX core_created_brin ON content.core USING brin (created_at)
  WITH (pages_per_range = 128);

-- CONTENT IDENTITY — titres / slug / description SEO (HAUTE fréquence)
CREATE TABLE content.identity (
  document_id           INT            NOT NULL,
  slug                  VARCHAR(255)   NOT NULL,
  headline              VARCHAR(255)   NOT NULL,
  alternative_headline  VARCHAR(255)   NULL,
  description           VARCHAR(1000)  NULL,
  PRIMARY KEY (document_id),
  UNIQUE (slug),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE,
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE INDEX content_identity_headline_trgm ON content.identity
  USING gin (unaccent(headline) gin_trgm_ops);

-- CONTENT BODY — corps HTML (BASSE fréquence) · TOAST EXTENDED systématique
CREATE TABLE content.body (
  document_id  INT   NOT NULL,
  content      TEXT  NULL,
  PRIMARY KEY (document_id),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE
) WITH (toast_tuple_target = 128);

ALTER TABLE content.body ALTER COLUMN content SET STORAGE EXTENDED;

-- CONTENT REVISION — cold storage des snapshots éditoriaux
-- Layout : saved_at TIMESTAMPTZ · document_id INT4 · author_entity_id INT4
--          · revision_num SMALLINT · 2B pad | varlena × 5 (snapshot_headline remplace snapshot_name)
-- snapshot_alternative_headline et snapshot_description inclus (ADR-021) :
-- un snapshot incomplet crée un historique silencieusement faux.
CREATE TABLE content.revision (
  saved_at                      TIMESTAMPTZ    NOT NULL DEFAULT now(),
  document_id                   INT            NOT NULL,
  author_entity_id              INT            NOT NULL,
  revision_num                  SMALLINT       NOT NULL DEFAULT 0,
  snapshot_headline             VARCHAR(255)   NOT NULL,
  snapshot_slug                 VARCHAR(255)   NOT NULL,
  snapshot_alternative_headline VARCHAR(255)   NULL,
  snapshot_description          VARCHAR(1000)  NULL,
  snapshot_body                 TEXT           NULL,
  PRIMARY KEY (document_id, revision_num),
  FOREIGN KEY (document_id)       REFERENCES content.document(id)  ON DELETE CASCADE,
  FOREIGN KEY (author_entity_id)  REFERENCES identity.entity(id),
  CONSTRAINT revision_num_positive CHECK (revision_num > 0)
) WITH (toast_tuple_target = 128);

CREATE INDEX revision_recent ON content.revision (document_id, revision_num DESC);

-- CONTENT TAG — spine taxonomique (Closure Table, ADR-026)
-- parent_id et path ltree supprimés : la hiérarchie est portée par tag_hierarchy.
-- Le spine tag reste immuable : seuls name et slug le définissent.
-- Layout (ADR-004) : id INT4 | slug varlena · name varlena
-- Tuple ~50 B (nom+slug 20 chars chacun) → ~164 tuples/page
CREATE TABLE content.tag (
  id    INT          GENERATED ALWAYS AS IDENTITY,
  slug  VARCHAR(64)  NOT NULL,
  name  VARCHAR(64)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE (slug),
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

-- TAG HIERARCHY — Closure Table (ADR-026)
-- Stocke toutes les paires (ancêtre, descendant) avec leur distance.
-- Un tag est son propre ancêtre à depth=0 (self-reference obligatoire).
-- Profondeur maximale : 4 niveaux (depth BETWEEN 0 AND 4).
-- Layout (ADR-004) :
--   ancestor_id INT4 (offset 0) · descendant_id INT4 (4) · depth SMALLINT (8) · 2B pad
-- Tuple 12 B → ~682 tuples/page
-- Cardinalité maximale théorique : N*(N+1)/2 ≈ 500 000 / 2 = 250 000 pour 1 000 tags
-- profonds. En pratique, taxonomie de ~200-500 tags avec depth ≤ 4 : ~1 000-2 000 lignes.
CREATE TABLE content.tag_hierarchy (
  ancestor_id    INT       NOT NULL,
  descendant_id  INT       NOT NULL,
  depth          SMALLINT  NOT NULL,
  PRIMARY KEY (ancestor_id, descendant_id),
  FOREIGN KEY (ancestor_id)   REFERENCES content.tag(id) ON DELETE CASCADE,
  FOREIGN KEY (descendant_id) REFERENCES content.tag(id) ON DELETE CASCADE,
  CONSTRAINT depth_range CHECK (depth BETWEEN 0 AND 4)
);

-- Index inverse : chercher tous les ancêtres d'un tag (breadcrumb, move)
CREATE INDEX tag_hierarchy_descendant ON content.tag_hierarchy (descendant_id, depth);

-- MEDIA CORE — métadonnées fichiers (MOYENNE fréquence)
-- Layout : 2×TIMESTAMPTZ · id INT4 · author_id INT4 · 2×INT4 (w/h) | varlena × 3
-- Tuple ~148 B → ~55 tuples/page
CREATE TABLE content.media_core (
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at  TIMESTAMPTZ   NULL,
  id           INT           GENERATED ALWAYS AS IDENTITY,
  author_id    INT           NOT NULL,
  width        INT           NULL,
  height       INT           NULL,
  mime_type    VARCHAR(255)  NULL,
  folder_url   VARCHAR(255)  NULL,
  file_name    VARCHAR(255)  NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (author_id) REFERENCES identity.entity(id)
);

-- MEDIA CONTENT — titre, texte alternatif, mention de droits (BASSE fréquence)
-- copyright_notice : mention légale du titulaire des droits (ADR-024).
--   Placé dans media_content (cold path) et non dans media_core (hot path)
--   pour ne pas diluer la densité du composant de métadonnées techniques.
CREATE TABLE content.media_content (
  media_id          INT           NOT NULL,
  name              VARCHAR(255)  NULL,
  description       VARCHAR(255)  NULL,
  copyright_notice  VARCHAR(255)  NULL,
  PRIMARY KEY (media_id),
  FOREIGN KEY (media_id) REFERENCES content.media_core(id) ON DELETE CASCADE
);

-- LIAISON Document ↔ Tag (N:N) · 32 B → ~255 tuples/page
CREATE TABLE content.content_to_tag (
  content_id  INT  NOT NULL,
  tag_id      INT  NOT NULL,
  PRIMARY KEY (content_id, tag_id),
  FOREIGN KEY (content_id) REFERENCES content.document(id) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (tag_id)     REFERENCES content.tag(id)      ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX content_to_tag_inv ON content.content_to_tag (tag_id, content_id);

-- LIAISON Document ↔ Média (N:N) — position SMALLINT pour l'ordre de galerie
-- Layout : content_id INT4 · media_id INT4 · position SMALLINT · 2B pad → 36 B → ~227 tuples/page
CREATE TABLE content.content_to_media (
  content_id  INT       NOT NULL,
  media_id    INT       NOT NULL,
  position    SMALLINT  NOT NULL DEFAULT 0,
  PRIMARY KEY (content_id, media_id),
  FOREIGN KEY (content_id) REFERENCES content.document(id)    ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (media_id)   REFERENCES content.media_core(id)  ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT position_range CHECK (position >= 0)
);

CREATE INDEX content_to_media_inv ON content.content_to_media (media_id, content_id);
CREATE INDEX content_to_media_pos ON content.content_to_media (content_id, position);

-- COMMENT — arborescence ltree
-- Layout : 2×TIMESTAMPTZ · document_id INT4 · account_entity_id INT4 · parent_id INT4
--          · id INT4 · status SMALLINT · 2B pad | path ltree · content TEXT
-- Tuple ~294 B → ~27 tuples/page (commentaire 200 chars)
--
-- path est déclaré NULL DEFAULT NULL pour permettre l'INSERT via OVERRIDING SYSTEM VALUE
-- dans content.create_comment(). La contrainte NOT NULL effective est portée par le CHECK
-- comment_path_not_null. Un INSERT direct sans path sera rejeté par la contrainte,
-- mais la procédure peut fournir la valeur après calcul du nextval() préalable.
CREATE TABLE content.comment (
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at         TIMESTAMPTZ   NULL,
  document_id         INT           NOT NULL,
  account_entity_id   INT           NOT NULL,
  parent_id           INT           NULL,
  id                  INT           GENERATED ALWAYS AS IDENTITY,
  status              SMALLINT      NOT NULL DEFAULT 1,
  path                ltree         NULL     DEFAULT NULL,
  content             TEXT          NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (document_id)       REFERENCES content.document(id)   ON DELETE CASCADE,
  FOREIGN KEY (account_entity_id) REFERENCES identity.entity(id),
  FOREIGN KEY (parent_id)         REFERENCES content.comment(id)    ON DELETE SET NULL,
  CONSTRAINT status_range         CHECK (status IN (0, 1, 9)),
  CONSTRAINT content_notempty     CHECK (char_length(trim(content)) > 0),
  CONSTRAINT comment_path_not_null CHECK (path IS NOT NULL)
  -- Le CHECK remplace NOT NULL pour laisser la procédure insérer avec OVERRIDING SYSTEM VALUE.
  -- Un INSERT direct sans fournir path sera rejeté. Seule content.create_comment() est
  -- autorisée (droits applicatifs révoqués en SECTION 14 — ADR-020).
);

CREATE INDEX comment_path_gist  ON content.comment USING gist (path);
CREATE INDEX comment_doc_path   ON content.comment (document_id, path);
CREATE INDEX comment_approved   ON content.comment (document_id, created_at)
  WHERE status = 1;


-- ==============================================================================
-- SECTION 9 : FONCTIONS
-- Toutes définies avant les triggers qui les référencent.
-- ==============================================================================

-- Fonction partagée : mise à jour du champ modified_at
-- Utilisée cross-schéma par auth, core, transaction, media_core
CREATE FUNCTION identity.fn_update_modified_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.modified_at = now();
  RETURN NEW;
END;
$$;

-- Fonction partagée : déduplication des slugs
-- Fonctionne sur n'importe quelle table via TG_TABLE_SCHEMA / TG_TABLE_NAME
-- Ignore la ligne courante (PK <> valeur courante) pour les UPDATE.
--
-- COMPORTEMENT SOUS CONCURRENCE
-- La boucle SELECT EXISTS + incrément fonctionne correctement en session unique.
-- Sous forte concurrence (deux transactions qui génèrent le même slug simultanément),
-- la contrainte UNIQUE est le vrai garde-fou : elle rejettera l'une des deux
-- insertions avec une erreur 23505 (unique_violation). Ce n'est pas un état
-- corrompu — l'erreur est propre et attrapable côté applicatif.
-- Le pattern "déduplication optimiste + UNIQUE comme filet" est acceptable pour
-- les slugs (générés depuis un titre, collisions rares). Pour un système à très
-- haute concurrence sur les titres (ex: importation de masse), préférer une
-- séquence applicationnelle avec retry explicite.
CREATE FUNCTION public.fn_slug_deduplicate()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_slug    TEXT    := NEW.slug;
  v_exists  BOOLEAN;
  v_counter INT     := 0;
  v_pk_col  TEXT;
  v_pk_val  INT;
BEGIN
  -- Détection de la colonne PK par convention de nommage
  v_pk_col := CASE TG_TABLE_NAME
    WHEN 'account_core' THEN 'entity_id'
    WHEN 'identity'     THEN 'document_id'
    ELSE 'id'
  END;

  EXECUTE format('SELECT ($1).%I', v_pk_col) INTO v_pk_val USING NEW;

  LOOP
    EXECUTE format(
      'SELECT EXISTS(SELECT 1 FROM %I.%I WHERE slug = $1 AND %I <> $2)',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_col
    ) INTO v_exists USING v_slug, COALESCE(v_pk_val, -1);
    EXIT WHEN NOT v_exists;
    v_counter := v_counter + 1;
    v_slug    := NEW.slug || '-' || v_counter;
  END LOOP;

  NEW.slug := v_slug;
  RETURN NEW;
END;
$$;

-- Numérotation automatique des révisions (BEFORE INSERT)
-- Calcule COALESCE(MAX(revision_num), 0) + 1 pour le document courant.
-- La colonne revision_num DEFAULT 0 est écrasée par ce trigger avant que
-- le CHECK revision_num > 0 ne soit évalué (les CHECK s'appliquent après
-- les triggers BEFORE dans PostgreSQL). Le 0 ne touche jamais le disque.
-- Le sentinel DEFAULT 0 n'est donc pas un bug : c'est une valeur placeholder
-- déléguée au moteur, documentée pour prévenir toute confusion future.
CREATE FUNCTION content.fn_revision_num()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  SELECT COALESCE(MAX(revision_num), 0) + 1
  INTO   NEW.revision_num
  FROM   content.revision
  WHERE  document_id = NEW.document_id;
  RETURN NEW;
END;
$$;

-- Vérification d'une permission sur un entity_id (hot path)
-- LANGUAGE sql : inlinable par le planner · PARALLEL SAFE
CREATE FUNCTION identity.has_permission(p_entity_id INT, p_permission INT)
RETURNS BOOLEAN LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT (r.permissions & p_permission) <> 0
  FROM   identity.auth  a
  JOIN   identity.role  r ON r.id = a.role_id
  WHERE  a.entity_id = p_entity_id
  LIMIT  1;
$$;


-- ==============================================================================
-- SECTION 10 : TRIGGERS
-- ==============================================================================

-- IDENTITY : auth — modified_at sur changement de rôle/statut/password uniquement
-- WHEN clause : évite de déclencher à chaque record_login (hot path)
CREATE TRIGGER auth_modified_at
BEFORE UPDATE ON identity.auth
FOR EACH ROW WHEN (
  OLD.password_hash IS DISTINCT FROM NEW.password_hash OR
  OLD.role_id       IS DISTINCT FROM NEW.role_id       OR
  OLD.is_banned     IS DISTINCT FROM NEW.is_banned
) EXECUTE FUNCTION identity.fn_update_modified_at();

-- IDENTITY : account_core — déduplication de slug
CREATE TRIGGER account_slug_dedup
BEFORE INSERT OR UPDATE OF slug ON identity.account_core
FOR EACH ROW EXECUTE FUNCTION public.fn_slug_deduplicate();

-- CONTENT : core — modified_at
CREATE TRIGGER content_core_modified_at
BEFORE UPDATE ON content.core
FOR EACH ROW WHEN (
  OLD.status      IS DISTINCT FROM NEW.status      OR
  OLD.is_readable IS DISTINCT FROM NEW.is_readable OR
  OLD.is_commentable IS DISTINCT FROM NEW.is_commentable
) EXECUTE FUNCTION identity.fn_update_modified_at();

-- CONTENT : identity — déduplication de slug
CREATE TRIGGER content_identity_slug_dedup
BEFORE INSERT OR UPDATE OF slug ON content.identity
FOR EACH ROW EXECUTE FUNCTION public.fn_slug_deduplicate();

-- CONTENT : revision — numérotation automatique
CREATE TRIGGER content_revision_num
BEFORE INSERT ON content.revision
FOR EACH ROW EXECUTE FUNCTION content.fn_revision_num();

-- COMMERCE : transaction_core — modified_at (sur changement de statut)
CREATE TRIGGER transaction_modified_at
BEFORE UPDATE ON commerce.transaction_core
FOR EACH ROW WHEN (
  OLD.status IS DISTINCT FROM NEW.status
) EXECUTE FUNCTION identity.fn_update_modified_at();

-- CONTENT : media_core — modified_at (ADR-021)
-- Déclenché uniquement sur les colonnes descriptives, pas sur created_at.
CREATE TRIGGER media_core_modified_at
BEFORE UPDATE ON content.media_core
FOR EACH ROW WHEN (
  OLD.mime_type   IS DISTINCT FROM NEW.mime_type   OR
  OLD.folder_url  IS DISTINCT FROM NEW.folder_url  OR
  OLD.file_name   IS DISTINCT FROM NEW.file_name   OR
  OLD.width       IS DISTINCT FROM NEW.width       OR
  OLD.height      IS DISTINCT FROM NEW.height
) EXECUTE FUNCTION identity.fn_update_modified_at();


-- ==============================================================================
-- SECTION 11 : PROCÉDURES D'ÉCRITURE (SYSTEM / AOT LAYER)
-- Les attributs SECURITY DEFINER et SET search_path sont appliqués en SECTION 14.
-- ==============================================================================

-- Création d'un compte (entity + auth + account_core)
CREATE PROCEDURE identity.create_account(
  p_username      VARCHAR(32),
  p_password_hash VARCHAR(255),
  p_slug          VARCHAR(32),
  p_role_id       SMALLINT DEFAULT 7,
  p_language      CHAR(5)  DEFAULT 'fr_FR',
  OUT p_entity_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO identity.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO identity.auth   (created_at, entity_id, role_id, is_banned, password_hash)
  VALUES (now(), p_entity_id, p_role_id, false, p_password_hash);
  INSERT INTO identity.account_core (entity_id, is_visible, is_private_message, display_mode, username, slug, language)
  VALUES (p_entity_id, true, false, 0, p_username, p_slug, p_language);
END;
$$;

-- Création d'une personne (entity + person_identity)
CREATE PROCEDURE identity.create_person(
  p_given_name  VARCHAR(32) DEFAULT NULL,
  p_family_name VARCHAR(32) DEFAULT NULL,
  p_gender      SMALLINT    DEFAULT NULL,
  p_nationality CHAR(2)     DEFAULT NULL,
  OUT p_entity_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO identity.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO identity.person_identity (entity_id, given_name, family_name, gender, nationality)
  VALUES (p_entity_id, p_given_name, p_family_name, p_gender, p_nationality);
END;
$$;

-- Anonymisation RGPD d'une personne physique (ADR-024)
-- Opération irréversible. Préserve l'entité (spine) pour l'intégrité des FK
-- commerce.transaction_core. Efface toutes les données nominatives dans les
-- composants person_*, invalide les credentials, purge les appartenances aux groupes.
-- Le champ anonymized_at dans identity.entity sert de marqueur de statut et
-- de preuve d'exécution pour les audits de conformité RGPD.
-- Garde d'autorisation (ADR-020 rev.) :
--   manage_users (bit 8, valeur 256) requis pour anonymiser autrui.
--   L'auto-anonymisation (p_entity_id = rls_user_id()) est toujours autorisée.
CREATE PROCEDURE identity.anonymize_person(p_entity_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND p_entity_id <> identity.rls_user_id()
     AND (identity.rls_auth_bits() & 256) <> 256 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_users required to anonymize another entity'
      USING ERRCODE = '42501';
  END IF;
  -- 1. Marquer l'entité (marqueur d'audit, timestamp irréversible)
  UPDATE identity.entity SET anonymized_at = now() WHERE id = p_entity_id;

  -- 2. Effacement des données nominatives (person_identity)
  UPDATE identity.person_identity
  SET    given_name      = NULL, family_name     = NULL, usual_name  = NULL,
         nickname        = NULL, prefix          = NULL, suffix      = NULL,
         additional_name = NULL, gender          = NULL, nationality = NULL
  WHERE  entity_id = p_entity_id;

  -- 3. Effacement des données de contact (person_contact)
  UPDATE identity.person_contact
  SET    email = NULL, phone = NULL, phone2 = NULL, fax = NULL, url = NULL
  WHERE  entity_id = p_entity_id;

  -- 4. Effacement des données biographiques (person_biography)
  UPDATE identity.person_biography
  SET    birth_date = NULL, death_date     = NULL,
         birth_place_id = NULL, death_place_id = NULL
  WHERE  entity_id = p_entity_id;

  -- 5. Effacement du contenu personnel (person_content)
  UPDATE identity.person_content
  SET    occupation = NULL, bias = NULL, hobby = NULL, award = NULL,
         devise = NULL, description = NULL, media_id = NULL
  WHERE  entity_id = p_entity_id;

  -- 6. Neutralisation du compte public (username et slug non-nominatifs)
  UPDATE identity.account_core
  SET    username = 'user_' || p_entity_id::text,
         slug     = 'user-' || p_entity_id::text
  WHERE  entity_id = p_entity_id;

  -- 7. Invalidation des credentials (hash non fonctionnel + bannissement)
  UPDATE identity.auth
  SET    password_hash = 'ANONYMIZED',
         is_banned     = true
  WHERE  entity_id = p_entity_id;

  -- 8. Purge des appartenances aux groupes (donnée de traçabilité sociale)
  DELETE FROM identity.group_to_account WHERE account_entity_id = p_entity_id;
END;
$$;

-- Enregistrement d'une connexion (hot path — LANGUAGE sql pour inlining)
CREATE PROCEDURE identity.record_login(p_entity_id INT)
LANGUAGE sql AS $$
  UPDATE identity.auth SET last_login_at = now() WHERE entity_id = p_entity_id;
$$;

-- Ajout/révocation de permission sur un rôle
-- Garde d'autorisation (ADR-020 rev.) : manage_users (bit 8, valeur 256) requis.
-- Opérations structurelles : modifier les permissions d'un rôle affecte tous ses membres.
CREATE PROCEDURE identity.grant_permission(p_role_id SMALLINT, p_permission INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 256) <> 256 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_users required'
      USING ERRCODE = '42501';
  END IF;
  UPDATE identity.role SET permissions = permissions | p_permission WHERE id = p_role_id;
END;
$$;

CREATE PROCEDURE identity.revoke_permission(p_role_id SMALLINT, p_permission INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 256) <> 256 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_users required'
      USING ERRCODE = '42501';
  END IF;
  UPDATE identity.role SET permissions = permissions & (~p_permission) WHERE id = p_role_id;
END;
$$;

-- Création d'une organisation (entity + org_core + org_identity)
-- Garde d'autorisation (ADR-020 rev.) : manage_system (bit 19, valeur 524288) requis.
CREATE PROCEDURE org.create_organization(
  p_name       VARCHAR(64),
  p_slug       VARCHAR(64),
  p_type       VARCHAR(30) DEFAULT NULL,
  p_place_id   INT         DEFAULT NULL,
  p_contact_id INT         DEFAULT NULL,
  OUT p_entity_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 524288) <> 524288 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_system required'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO org.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO org.org_core     (created_at, entity_id, place_id, contact_entity_id, type)
  VALUES (now(), p_entity_id, p_place_id, p_contact_id, p_type);
  INSERT INTO org.org_identity (entity_id, name, slug)
  VALUES (p_entity_id, p_name, p_slug);
END;
$$;

-- Insertion d'une organisation dans la hiérarchie Nested Set
-- Verrouillage exclusif obligatoire : toute insertion décale les intervalles de tous
-- les nœuds à droite du point d'insertion — opération non concurrente par nature.
-- Garde : manage_system (524288) requis (opération structurelle sur la hiérarchie).
-- p_parent_entity_id NULL → organisation racine (lft=1, rgt=2 dans un arbre vide,
-- ou décalée à la fin des racines existantes).
CREATE PROCEDURE org.add_organization_to_hierarchy(
  p_entity_id        INT,
  p_parent_entity_id INT DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
  v_parent_rgt  INT;
  v_new_lft     INT;
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 524288) <> 524288 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_system required'
      USING ERRCODE = '42501';
  END IF;

  -- Verrou exclusif : bloque toute lecture/écriture concurrente sur org_hierarchy
  -- pendant le décalage des intervalles.
  LOCK TABLE org.org_hierarchy IN EXCLUSIVE MODE;

  IF p_parent_entity_id IS NULL THEN
    -- Organisation racine : insertion à la fin des nœuds existants.
    SELECT COALESCE(MAX(rgt), 0) + 1 INTO v_new_lft FROM org.org_hierarchy;
    INSERT INTO org.org_hierarchy (entity_id, lft, rgt, depth)
    VALUES (p_entity_id, v_new_lft, v_new_lft + 1, 0);
  ELSE
    -- Vérifier l'existence du parent
    SELECT rgt INTO v_parent_rgt FROM org.org_hierarchy
    WHERE entity_id = p_parent_entity_id;
    IF v_parent_rgt IS NULL THEN
      RAISE EXCEPTION 'Organisation parente introuvable dans la hiérarchie (entity_id=%)', p_parent_entity_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    v_new_lft := v_parent_rgt;

    -- Décalage de tous les nœuds à droite du point d'insertion
    UPDATE org.org_hierarchy SET rgt = rgt + 2 WHERE rgt >= v_parent_rgt;
    UPDATE org.org_hierarchy SET lft = lft + 2 WHERE lft >= v_parent_rgt;

    -- Insertion de la nouvelle feuille
    INSERT INTO org.org_hierarchy (entity_id, lft, rgt, depth)
    SELECT p_entity_id, v_new_lft, v_new_lft + 1,
           (SELECT depth + 1 FROM org.org_hierarchy WHERE entity_id = p_parent_entity_id)
    FROM   org.org_hierarchy
    WHERE  entity_id = p_parent_entity_id;
  END IF;
END;
$$;


-- Création d'un document (spine + core + identity + body optionnel + première révision)
-- Gardes d'autorisation (ADR-020 rev.) :
--   create_contents (bit 1, valeur 2) requis.
--   p_author_id doit correspondre à rls_user_id() sauf si edit_others_contents (32768)
--   (interdit l'usurpation d'identité d'auteur par un utilisateur standard).
CREATE PROCEDURE content.create_document(
  p_author_id     INT,
  p_name          VARCHAR(255),
  p_slug          VARCHAR(255),
  p_doc_type      SMALLINT      DEFAULT 0,
  p_status        SMALLINT      DEFAULT 0,
  p_content       TEXT          DEFAULT NULL,
  p_description   VARCHAR(1000) DEFAULT NULL,
  p_alt_headline  VARCHAR(255)  DEFAULT NULL,
  OUT p_document_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 2) <> 2 THEN
      RAISE EXCEPTION 'insufficient_privilege: create_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF p_author_id <> identity.rls_user_id()
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: cannot create document attributed to another author'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  INSERT INTO content.document (doc_type) VALUES (p_doc_type) RETURNING id INTO p_document_id;
  INSERT INTO content.core (document_id, author_entity_id, status, published_at, created_at)
  VALUES (p_document_id, p_author_id, p_status,
          CASE WHEN p_status = 1 THEN now() ELSE NULL END, now());
  INSERT INTO content.identity (document_id, slug, headline, alternative_headline, description)
  VALUES (p_document_id, p_slug, p_name, p_alt_headline, p_description);
  IF p_content IS NOT NULL THEN
    INSERT INTO content.body (document_id, content) VALUES (p_document_id, p_content);
  END IF;
  -- La colonne revision_num est intentionnellement omise :
  -- le trigger BEFORE INSERT fn_revision_num() calcule COALESCE(MAX, 0)+1
  -- et écrase le DEFAULT (0) avant que le CHECK revision_num > 0 ne s'évalue.
  -- Passer 0 explicitement fonctionnerait aussi (le trigger l'écrase), mais
  -- omettre la colonne exprime clairement que la valeur est déléguée au moteur.
  INSERT INTO content.revision (
    document_id, author_entity_id,
    snapshot_headline, snapshot_slug, snapshot_alternative_headline,
    snapshot_description, snapshot_body
  )
  VALUES (p_document_id, p_author_id, p_name, p_slug, p_alt_headline, p_description, p_content);
END;
$$;

-- Publication d'un document (brouillon/archivé → publié)
-- Garde d'autorisation (ADR-020 rev.) : publish_contents (bit 4, valeur 16) requis.
-- Bypass si rls_user_id() = -1 (GUC absent : contexte seed/admin sans session applicative).
CREATE PROCEDURE content.publish_document(p_document_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 16) <> 16 THEN
    RAISE EXCEPTION 'insufficient_privilege: publish_contents required'
      USING ERRCODE = '42501';
  END IF;
  UPDATE content.core
  SET status = 1, published_at = COALESCE(published_at, now())
  WHERE document_id = p_document_id AND status IN (0, 2);
END;
$$;

-- Snapshot éditorial avant modification
-- Capture l'intégralité de content.identity + content.body (ADR-021).
-- Garde d'autorisation (ADR-020 rev.) : edit_contents (4) ou edit_others_contents (32768).
CREATE PROCEDURE content.save_revision(p_document_id INT, p_author_id INT)
LANGUAGE plpgsql AS $$
DECLARE
  v_headline    VARCHAR(255);
  v_slug        VARCHAR(255);
  v_alt         VARCHAR(255);
  v_description VARCHAR(1000);
  v_body        TEXT;
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    -- Ownership check : sans edit_others_contents, l'auteur ne peut sauvegarder
    -- que ses propres documents. La procédure étant SECURITY DEFINER, la politique
    -- rls_core_delete_own est bypassée — ce filtre reconstitue explicitement l'invariant.
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id
        AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot save revision for another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  SELECT i.headline, i.slug, i.alternative_headline, i.description, b.content
  INTO   v_headline, v_slug, v_alt, v_description, v_body
  FROM   content.identity i
  LEFT JOIN content.body b ON b.document_id = i.document_id
  WHERE  i.document_id = p_document_id FOR SHARE;
  INSERT INTO content.revision (
    document_id, author_entity_id,
    snapshot_headline, snapshot_slug, snapshot_alternative_headline,
    snapshot_description, snapshot_body
  )
  VALUES (p_document_id, p_author_id, v_headline, v_slug, v_alt, v_description, v_body);
END;
$$;

-- Création d'un tag et insertion automatique dans la Closure Table (ADR-026)
-- Automatise la gestion des ancêtres : l'appelant fournit uniquement le parent_id.
-- SECURITY DEFINER : marius_user n'a pas de droits DML directs (ADR-020).
--
-- Mécanisme :
--   1. INSERT du tag dans content.tag (spine)
--   2. Self-reference (ancestor = descendant = new_tag_id, depth = 0)
--   3. Héritage des ancêtres du parent :
--      INSERT (ancestor_id, new_tag_id, parent_depth + 1)
--      FROM tag_hierarchy WHERE descendant_id = parent_id
-- Validation de profondeur : si le parent est déjà à depth=4, l'INSERT viole
-- le CHECK depth BETWEEN 0 AND 4 — l'exception est propagée à l'appelant.
-- Garde d'autorisation (ADR-020 rev.) : manage_tags (bit 11, valeur 2048) requis.
CREATE PROCEDURE content.create_tag(
  p_name      VARCHAR(64),
  p_slug      VARCHAR(64),
  p_parent_id INT      DEFAULT NULL,
  OUT p_tag_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 2048) <> 2048 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_tags required'
      USING ERRCODE = '42501';
  END IF;
  -- 1. Créer le tag (spine)
  INSERT INTO content.tag (slug, name)
  VALUES (p_slug, p_name)
  RETURNING id INTO p_tag_id;

  -- 2. Self-reference obligatoire (depth = 0)
  INSERT INTO content.tag_hierarchy (ancestor_id, descendant_id, depth)
  VALUES (p_tag_id, p_tag_id, 0);

  -- 3. Propager les ancêtres du parent (si fourni)
  IF p_parent_id IS NOT NULL THEN
    -- Valider l'existence du parent
    IF NOT EXISTS (SELECT 1 FROM content.tag_hierarchy
                   WHERE ancestor_id = p_parent_id AND descendant_id = p_parent_id) THEN
      RAISE EXCEPTION 'Tag parent introuvable dans la Closure Table (id=%)', p_parent_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;

    INSERT INTO content.tag_hierarchy (ancestor_id, descendant_id, depth)
    SELECT th.ancestor_id, p_tag_id, th.depth + 1
    FROM   content.tag_hierarchy th
    WHERE  th.descendant_id = p_parent_id;
    -- Le CHECK depth BETWEEN 0 AND 4 rejette automatiquement si depth + 1 > 4.
  END IF;
END;
$$;

-- Liaison d'un tag à un document (content_to_tag)
-- Gardes AOT (ADR-020 rev.) :
--   edit_contents (bit 2, valeur 4) OU edit_others_contents (bit 15, valeur 32768).
--   Sans edit_others_contents, ownership check : l'appelant doit être l'auteur du document.
-- ON CONFLICT DO NOTHING : idempotent — une double liaison n'est pas une erreur.
CREATE PROCEDURE content.add_tag_to_document(p_document_id INT, p_tag_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id
        AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot tag another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  INSERT INTO content.content_to_tag (content_id, tag_id)
  VALUES (p_document_id, p_tag_id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- Suppression d'un tag d'un document (content_to_tag)
-- Mêmes gardes qu'add_tag_to_document (ownership symétrique).
-- Idempotent : supprimer une liaison inexistante ne lève pas d'erreur.
CREATE PROCEDURE content.remove_tag_from_document(p_document_id INT, p_tag_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id
        AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot untag another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  DELETE FROM content.content_to_tag
  WHERE content_id = p_document_id AND tag_id = p_tag_id;
END;
$$;


-- Insertion d'un commentaire avec construction du chemin ltree (une seule écriture heap)
-- Remplace définitivement le double trigger BEFORE/AFTER (ADR-012).
-- nextval() préalable → path construit en mémoire → INSERT unique, zéro dead tuple.
-- Gardes d'autorisation (ADR-020 rev.) :
--   create_comments (bit 5, valeur 32) requis.
--   p_account_entity_id doit correspondre à rls_user_id() (interdit les commentaires
--   attribués à un autre compte).
CREATE PROCEDURE content.create_comment(
  p_document_id       INT,
  p_account_entity_id INT,
  p_content           TEXT,
  p_parent_id         INT      DEFAULT NULL,
  p_status            SMALLINT DEFAULT 1,
  OUT p_comment_id    INT
)
LANGUAGE plpgsql AS $$
DECLARE
  v_seq_name    TEXT;
  v_parent_path ltree;
  v_path        ltree;
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 32) <> 32 THEN
      RAISE EXCEPTION 'insufficient_privilege: create_comments required'
        USING ERRCODE = '42501';
    END IF;
    IF p_account_entity_id <> identity.rls_user_id() THEN
      RAISE EXCEPTION 'insufficient_privilege: cannot post comment attributed to another account'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  -- 1. Allouer l'id avant toute écriture heap
  SELECT pg_get_serial_sequence('content.comment', 'id') INTO v_seq_name;
  p_comment_id := nextval(v_seq_name);

  -- 2. Construire le chemin ltree complet en mémoire
  IF p_parent_id IS NULL THEN
    v_path := text2ltree(p_document_id::text || '.' || p_comment_id::text);
  ELSE
    SELECT path INTO v_parent_path
    FROM   content.comment
    WHERE  id = p_parent_id
      AND  document_id = p_document_id   -- invariant inter-document : le parent
                                         -- doit appartenir au même document.
                                         -- Sans cette garde, un parent_id valide
                                         -- d'un autre document produirait un chemin
                                         -- ltree incohérent silencieusement.
    FOR SHARE;
    IF v_parent_path IS NULL THEN
      RAISE EXCEPTION
        'Commentaire parent introuvable ou appartenant à un autre document (parent_id=%, document_id=%)',
        p_parent_id, p_document_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    v_path := v_parent_path || text2ltree(p_comment_id::text);
  END IF;

  -- 3. INSERT unique — chemin définitif, zéro dead tuple structurel
  INSERT INTO content.comment (
    created_at, modified_at,
    document_id, account_entity_id, parent_id,
    id, status, path, content
  )
  OVERRIDING SYSTEM VALUE
  VALUES (
    now(), NULL,
    p_document_id, p_account_entity_id, p_parent_id,
    p_comment_id, p_status, v_path, p_content
  );
END;
$$;

-- Création d'une commande (transaction_core + trois composants ECS) (ADR-023)
-- Les composants price, payment et delivery sont initialisés avec des valeurs par
-- défaut : ils existent toujours après create_transaction, sans NULL structurel.
-- La couche applicative met à jour chaque composant indépendamment via UPDATE
-- direct (marius_admin) ou via des procédures métier dédiées.
-- p_currency_code : code ISO 4217 numérique (défaut 978 = EUR).
-- Garde AOT (ADR-020 rev.) :
--   p_client_entity_id doit correspondre à rls_user_id() OU manage_commerce (262144).
--   Interdit la création de commandes au nom d'un autre client.
CREATE PROCEDURE commerce.create_transaction(
  p_client_entity_id  INT,
  p_seller_entity_id  INT,
  p_currency_code     SMALLINT DEFAULT 978,
  p_status            SMALLINT DEFAULT 0,
  p_description       TEXT     DEFAULT NULL,
  OUT p_transaction_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND p_client_entity_id <> identity.rls_user_id()
     AND (identity.rls_auth_bits() & 262144) <> 262144 THEN
    RAISE EXCEPTION 'insufficient_privilege: cannot create transaction for another client'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO commerce.transaction_core
    (client_entity_id, seller_entity_id, status, description)
  VALUES (p_client_entity_id, p_seller_entity_id, p_status, p_description)
  RETURNING id INTO p_transaction_id;

  -- Composant prix : devise et montants initialisés à zéro
  INSERT INTO commerce.transaction_price
    (transaction_id, currency_code, shipping_cents, discount_cents, tax_cents,
     tax_rate_bp, is_tax_included)
  VALUES (p_transaction_id, p_currency_code, 0, 0, 0, 0, false);

  -- Composant paiement : statut 0 = en attente
  INSERT INTO commerce.transaction_payment (transaction_id, payment_status)
  VALUES (p_transaction_id, 0);

  -- Composant livraison : statut 0 = en attente
  INSERT INTO commerce.transaction_delivery (transaction_id, delivery_status)
  VALUES (p_transaction_id, 0);
END;
$$;

-- Insertion d'une ligne de commande avec snapshot du prix
-- FOR UPDATE sur product_core (ADR-021) : verrou exclusif pour prévenir la sur-vente.
-- price_cents lue et stockée telle quelle — arithmétique entière native (ADR-022).
-- Gardes AOT (ADR-020 rev.) :
--   1. Ownership : la transaction doit appartenir à rls_user_id() OU manage_commerce.
--   2. Statut : ajout d'items uniquement sur transaction status=0 (pending).
--      Une transaction confirmée, expédiée ou annulée est verrouillée.
CREATE PROCEDURE commerce.create_transaction_item(
  p_transaction_id INT, p_product_id INT, p_quantity INT DEFAULT 1
) LANGUAGE plpgsql AS $$
DECLARE
  v_price_cents    INT8;
  v_txn_status     SMALLINT;
  v_txn_client_id  INT;
BEGIN
  -- Lire le statut et le client de la transaction (avec verrou partagé)
  SELECT status, client_entity_id
  INTO   v_txn_status, v_txn_client_id
  FROM   commerce.transaction_core
  WHERE  id = p_transaction_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction % introuvable', p_transaction_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  -- Garde ownership : le client ou un gestionnaire commerce
  IF identity.rls_user_id() <> -1
     AND v_txn_client_id <> identity.rls_user_id()
     AND (identity.rls_auth_bits() & 262144) <> 262144 THEN
    RAISE EXCEPTION 'insufficient_privilege: cannot add item to another client''s transaction'
      USING ERRCODE = '42501';
  END IF;

  -- Garde statut : transaction doit être en attente (status=0)
  IF v_txn_status <> 0 THEN
    RAISE EXCEPTION 'Transaction % is not in pending state (status=%): items cannot be added',
      p_transaction_id, v_txn_status
      USING ERRCODE = '55000';
  END IF;

  SELECT price_cents INTO v_price_cents
  FROM   commerce.product_core WHERE id = p_product_id FOR UPDATE;
  IF v_price_cents IS NULL THEN
    RAISE EXCEPTION 'Produit % introuvable ou prix non défini', p_product_id;
  END IF;
  INSERT INTO commerce.transaction_item
    (unit_price_snapshot_cents, transaction_id, product_id, quantity)
  VALUES (v_price_cents, p_transaction_id, p_product_id, p_quantity);
  UPDATE commerce.product_core SET stock = stock - p_quantity WHERE id = p_product_id;
END;
$$;


-- ==============================================================================
-- SECTION 12 : VUES SÉMANTIQUES (INTERFACE schema.org — snake_case, ADR-025)
-- Couche de traduction : composants ECS physiques → contrat d'accès public.
-- snake_case systématique : pas de guillemets requis dans les requêtes SQL.
-- Suffixes DOD conservés : _at (TIMESTAMPTZ), _cents (INT8), _id (FK), _code.
-- ==============================================================================

-- IDENTITY : v_role — décompose le bitmask en colonnes booléennes nommées
-- Bits 0–20 exposés (ADR-027 : expansion 15→21 bits sur INT4).
CREATE VIEW identity.v_role AS
SELECT id, name, permissions,
  (permissions &       1) <> 0  AS access_admin,
  (permissions &       2) <> 0  AS create_contents,
  (permissions &       4) <> 0  AS edit_contents,
  (permissions &       8) <> 0  AS delete_contents,
  (permissions &      16) <> 0  AS publish_contents,
  (permissions &      32) <> 0  AS create_comments,
  (permissions &      64) <> 0  AS edit_comments,
  (permissions &     128) <> 0  AS delete_comments,
  (permissions &     256) <> 0  AS manage_users,
  (permissions &     512) <> 0  AS manage_groups,
  (permissions &    1024) <> 0  AS manage_contents,
  (permissions &    2048) <> 0  AS manage_tags,
  (permissions &    4096) <> 0  AS manage_menus,
  (permissions &    8192) <> 0  AS upload_files,
  (permissions &   16384) <> 0  AS can_read,
  (permissions &   32768) <> 0  AS edit_others_contents,
  (permissions &   65536) <> 0  AS moderate_comments,
  (permissions &  131072) <> 0  AS view_transactions,
  (permissions &  262144) <> 0  AS manage_commerce,
  (permissions &  524288) <> 0  AS manage_system,
  (permissions & 1048576) <> 0  AS export_data
FROM identity.role;

-- IDENTITY : v_auth — hot path authentification
CREATE VIEW identity.v_auth AS
SELECT a.entity_id, a.password_hash, a.is_banned, a.role_id,
  r.name AS role_name, r.permissions AS role_permissions
FROM identity.auth a JOIN identity.role r ON r.id = a.role_id;

-- IDENTITY : v_account — schema.org/Person (compte utilisateur)
-- Sécurité : WHERE GUC miroir de rls_account_select (ADR-029 invariant 2 révisé).
CREATE VIEW identity.v_account AS
SELECT
  ac.entity_id             AS identifier,
  ac.username, ac.slug,
  ac.language, ac.time_zone,
  ac.is_visible,
  ac.display_mode,
  ac.media_id              AS image_id,
  ac.tos_accepted_at,
  a.role_id,
  a.is_banned,
  a.created_at,
  a.modified_at,
  a.last_login_at,
  pi.given_name,
  pi.family_name,
  pi.usual_name            AS alternative_name,
  pi.nickname              AS alternate_name,
  pi.prefix                AS honorific_prefix,
  pi.suffix                AS honorific_suffix,
  pi.nationality
FROM        identity.account_core    ac
JOIN        identity.auth            a  ON a.entity_id  = ac.entity_id
LEFT JOIN   identity.person_identity pi ON pi.entity_id = ac.person_entity_id
WHERE (
  ac.entity_id = identity.rls_user_id()        -- utilisateur : son propre compte
  OR (identity.rls_auth_bits() & 256) = 256    -- manage_users
);

-- IDENTITY : v_person — schema.org/Person (profil public)
-- Colonnes PII retirées de la projection (audit RLS global) :
--   email, phone/telephone, fax — REVOKE SELECT sur identity.person_contact ;
--   la vue étant owned par postgres (BYPASSRLS), elle pouvait lire person_contact
--   malgré le REVOKE, exposant email/téléphone à tout marius_user.
--   url (site web) conservé : donnée de contact intentionnellement publique.
--   address_id (place_id) conservé : référence géographique, pas de PII directe.
-- Accès aux données de contact (email, phone) : réservé aux sessions manage_users
--   via connexion marius_admin ou procédure SECURITY DEFINER dédiée.
CREATE VIEW identity.v_person AS
SELECT
  e.id                     AS identifier,
  e.anonymized_at,
  pi.given_name,
  pi.additional_name,
  pi.family_name,
  pi.usual_name            AS alternative_name,
  pi.nickname              AS alternate_name,
  pi.prefix                AS honorific_prefix,
  pi.suffix                AS honorific_suffix,
  pi.gender, pi.nationality,
  pb.birth_date,
  pb.birth_place_id,
  pb.death_date,
  pb.death_place_id,
  pc.url,
  pc.place_id              AS address_id,
  pco.media_id             AS image_id,
  pco.occupation,
  pco.devise               AS description,
  pco.description          AS disambiguating_description
FROM        identity.entity           e
JOIN        identity.person_identity  pi  ON pi.entity_id = e.id
LEFT JOIN   identity.person_biography pb  ON pb.entity_id = e.id
LEFT JOIN   identity.person_contact   pc  ON pc.entity_id = e.id
LEFT JOIN   identity.person_content   pco ON pco.entity_id = e.id;

-- GEO : v_place — schema.org/Place + PostalAddress (ADR-024)
-- Jointure spine spatial (place_core) + composant postal (postal_address).
-- LEFT JOIN : un lieu peut exister sans adresse postale (ex : point GPS pur).
-- country_code (SMALLINT) conserve son nom physique — ADR-025 : un code entier
-- n'est pas un pays textuel.
CREATE VIEW geo.v_place AS
SELECT
  c.id                     AS identifier,
  c.name,
  c.elevation,
  CASE WHEN c.coordinates IS NOT NULL
    THEN ST_AsGeoJSON(c.coordinates)::jsonb ELSE NULL
  END                      AS geo,
  ST_Y(c.coordinates)      AS latitude,
  ST_X(c.coordinates)      AS longitude,
  pa.street_address,
  pa.postal_code,
  pa.address_locality,
  pa.address_region,
  pa.country_code,
  co.description
FROM      geo.place_core    c
LEFT JOIN geo.postal_address pa ON pa.place_id = c.id
LEFT JOIN geo.place_content  co ON co.place_id = c.id;

-- ORG : v_organization — schema.org/Organization (catalogue public)
-- Données légales (SIRET, DUNS, TVA) exclues de la projection :
--   org.org_legal est sous REVOKE SELECT pour marius_user. La vue étant owned par
--   postgres, elle pourrait techniquement joindre org_legal malgré le REVOKE —
--   mais exposer des identifiants légaux dans un catalogue public viole le principe
--   de moindre exposition. L'accès aux données légales passe par marius_admin.
-- Pas de filtre GUC : les organisations sont un catalogue global non multi-tenant.
CREATE VIEW org.v_organization AS
SELECT
  e.id                     AS identifier,
  oi.name, oi.slug, oi.brand,
  oc.type                  AS org_type,
  oc.purpose,
  oc.created_at            AS founding_date,
  oct.email,
  oct.phone                AS telephone,
  oct.url,
  gp.name                  AS location_name,
  gp.address_locality,
  gp.country_code,
  gp.geo,
  oc.parent_entity_id      AS parent_organization_id
FROM        org.entity          e
JOIN        org.org_identity    oi  ON oi.entity_id = e.id
JOIN        org.org_core        oc  ON oc.entity_id = e.id
LEFT JOIN   org.org_contact     oct ON oct.entity_id = e.id
LEFT JOIN   geo.v_place         gp  ON gp.identifier  = oc.place_id;

-- COMMERCE : v_product — schema.org/Product
-- price_cents (INT8) — conversion décimale déléguée à l'applicatif (ADR-022).
CREATE VIEW commerce.v_product AS
SELECT
  pc.id                    AS identifier,
  pi.name, pi.slug,
  pi.isbn_ean              AS gtin13,
  pc.price_cents,
  pc.stock,
  pc.is_available,
  pc.media_id              AS image_id,
  pco.description, pco.tags
FROM        commerce.product_core     pc
JOIN        commerce.product_identity pi  ON pi.product_id  = pc.id
LEFT JOIN   commerce.product_content  pco ON pco.product_id = pc.id;

-- COMMERCE : v_transaction — schema.org/Order enrichi (ADR-023)
-- snake_case + suffixes _cents conservés (ADR-025).
-- PUSHDOWN GARANTI : WHERE identifier = :id → WHERE tc.id = :id avant json_agg().
-- Sécurité : la vue est owned par postgres (BYPASSRLS). Le WHERE GUC ci-dessous
-- est le mécanisme de contrôle d'accès primaire (ADR-029 invariant 2 révisé).
-- Miroir de rls_transaction_select : client OU view_transactions OU manage_commerce.
CREATE VIEW commerce.v_transaction AS
SELECT
  -- Core (schema.org/Order)
  tc.id                    AS identifier,
  tc.status                AS order_status,
  tc.created_at,
  tc.modified_at,
  tc.client_entity_id      AS customer_id,
  tc.seller_entity_id      AS seller_id,
  tc.description,
  -- Price component (schema.org/PriceSpecification)
  tp.currency_code,
  tp.shipping_cents,
  tp.discount_cents,
  tp.tax_cents,
  tp.tax_rate_bp,
  tp.is_tax_included,
  -- Payment component (schema.org/PaymentChargeSpecification)
  tpay.payment_status,
  tpay.payment_method,
  tpay.invoice_number,
  tpay.paid_at,
  tpay.billing_place_id,
  -- Delivery component (schema.org/ParcelDelivery)
  tdel.delivery_status,
  tdel.shipping_place_id,
  tdel.carrier,
  tdel.tracking_number,
  tdel.shipped_at,
  tdel.estimated_at,
  tdel.delivered_at,
  -- Items aggregation (JSON keys en snake_case)
  json_agg(json_build_object(
    'product_id',            ti.product_id,
    'product_name',          pi.name,
    'quantity',              ti.quantity,
    'unit_price_cents',      ti.unit_price_snapshot_cents,
    'line_total_cents',      ti.quantity * ti.unit_price_snapshot_cents
  ) ORDER BY ti.product_id) AS ordered_items,
  SUM(ti.quantity * ti.unit_price_snapshot_cents)               AS subtotal_cents,
  SUM(ti.quantity * ti.unit_price_snapshot_cents)
    + COALESCE(tp.shipping_cents, 0)
    + COALESCE(tp.tax_cents,      0)
    - COALESCE(tp.discount_cents, 0)                            AS total_cents
FROM        commerce.transaction_core    tc
JOIN        commerce.transaction_item    ti   ON ti.transaction_id   = tc.id
JOIN        commerce.product_identity    pi   ON pi.product_id       = ti.product_id
LEFT JOIN   commerce.transaction_price   tp   ON tp.transaction_id   = tc.id
LEFT JOIN   commerce.transaction_payment tpay ON tpay.transaction_id = tc.id
LEFT JOIN   commerce.transaction_delivery tdel ON tdel.transaction_id = tc.id
WHERE (
  tc.client_entity_id = identity.rls_user_id()      -- client : ses propres commandes
  OR (identity.rls_auth_bits() & 131072) = 131072   -- view_transactions
  OR (identity.rls_auth_bits() & 262144) = 262144   -- manage_commerce
)
GROUP BY
  tc.id, tc.status, tc.created_at, tc.modified_at,
  tc.client_entity_id, tc.seller_entity_id, tc.description,
  tp.currency_code, tp.shipping_cents, tp.discount_cents,
  tp.tax_cents, tp.tax_rate_bp, tp.is_tax_included,
  tpay.payment_status, tpay.payment_method, tpay.invoice_number,
  tpay.paid_at, tpay.billing_place_id,
  tdel.delivery_status, tdel.shipping_place_id, tdel.carrier,
  tdel.tracking_number, tdel.shipped_at, tdel.estimated_at, tdel.delivered_at;

-- CONTENT : v_article_list — hot path listing (zéro TOAST, zéro agrégat)
-- Sécurité : la vue est owned par postgres (BYPASSRLS). Le RLS physique sur
-- content.core est inopérant sur ce chemin (ADR-029 invariant 2 révisé).
-- Le WHERE ci-dessous constitue le mécanisme de contrôle d'accès primaire
-- pour ce chemin de lecture. Les helpers rls_user_id() / rls_auth_bits()
-- lisent le GUC de session — invariant par rapport au security context de la vue.
-- Comportement anonyme (GUC absent) : (0&16)=0, (0&32768)=0, author=-1 →
--   seul status=1 passe → comportement public préservé.
CREATE VIEW content.v_article_list AS
SELECT
  d.id                     AS identifier,
  ci.headline,
  ci.slug,
  ci.alternative_headline,
  ci.description,
  co.published_at,
  co.author_entity_id      AS author_id,
  co.status
FROM        content.document  d
JOIN        content.core      co ON co.document_id = d.id
JOIN        content.identity  ci ON ci.document_id = d.id
WHERE (
  co.status = 1
  OR (identity.rls_auth_bits() & 16)    = 16       -- publish_contents
  OR (identity.rls_auth_bits() & 32768) = 32768    -- edit_others_contents
  OR co.author_entity_id = identity.rls_user_id()  -- auteur : ses propres brouillons
);

-- CONTENT : v_article — schema.org/Article (page complète avec TOAST + agrégats)
-- doc_type remplace "@type" (caractère @ incompatible avec les identifiants SQL nus).
-- is_readable remplace "isAccessibleForFree" (miroir exact du nom physique).
CREATE VIEW content.v_article AS
SELECT
  d.id                     AS identifier,
  d.doc_type,
  ci.headline,
  ci.slug,
  ci.alternative_headline,
  ci.description,
  co.status,
  co.is_readable,
  co.is_commentable,
  co.published_at,
  co.created_at,
  co.modified_at,
  co.author_entity_id      AS author_id,
  b.content                AS article_body,
  (SELECT json_agg(json_build_object(
    'id', t.id, 'name', t.name, 'slug', t.slug, 'path', t.path::text
  ) ORDER BY t.path)
   FROM content.content_to_tag ct JOIN content.tag t ON t.id = ct.tag_id
   WHERE ct.content_id = d.id) AS keywords,
  (SELECT json_agg(json_build_object(
    'id', m.id, 'name', mc.name,
    'url', m.folder_url || '/' || m.file_name,
    'mime_type', m.mime_type, 'width', m.width,
    'height', m.height, 'position', ctm.position
  ) ORDER BY ctm.position)
   FROM  content.content_to_media ctm
   JOIN  content.media_core m   ON m.id       = ctm.media_id
   LEFT JOIN content.media_content mc ON mc.media_id = m.id
   WHERE ctm.content_id = d.id) AS images
FROM        content.document  d
JOIN        content.core      co ON co.document_id = d.id
JOIN        content.identity  ci ON ci.document_id = d.id
LEFT JOIN   content.body      b  ON b.document_id  = d.id
WHERE (
  co.status = 1
  OR (identity.rls_auth_bits() & 16)    = 16       -- publish_contents
  OR (identity.rls_auth_bits() & 32768) = 32768    -- edit_others_contents
  OR co.author_entity_id = identity.rls_user_id()  -- auteur : ses propres brouillons
);
-- Sécurité : voir note v_article_list — même mécanisme WHERE GUC.

-- CONTENT : v_tag_tree — taxonomie avec Closure Table (ADR-026)
-- depth = distance depuis la racine (0 = racine, 4 = feuille maximale).
-- parent_id = ancêtre immédiat (depth = 1), NULL si racine.
-- breadcrumb = chemin textuel racine→tag, séparateurs " > ".
-- article_count = articles directement taggés (pas subtree — requête explicite via tag_hierarchy).
--
-- Navigation de sous-arbre côté applicatif :
--   SELECT descendant_id FROM content.tag_hierarchy
--   WHERE ancestor_id = :tag_id AND depth > 0
CREATE VIEW content.v_tag_tree AS
SELECT
  t.id         AS identifier,
  t.name,
  t.slug,
  -- Profondeur depuis la racine (0 = racine)
  COALESCE((
    SELECT MAX(th.depth) FROM content.tag_hierarchy th
    WHERE  th.descendant_id = t.id AND th.ancestor_id <> t.id
  ), 0)        AS depth,
  -- Parent immédiat (NULL si racine)
  (SELECT th_p.ancestor_id FROM content.tag_hierarchy th_p
   WHERE  th_p.descendant_id = t.id AND th_p.depth = 1
   LIMIT  1)   AS parent_id,
  -- Breadcrumb : ancêtres ordonnés racine en tête (depth DESC)
  (SELECT string_agg(a.name, ' > ' ORDER BY th_a.depth DESC)
   FROM   content.tag_hierarchy th_a
   JOIN   content.tag           a  ON a.id = th_a.ancestor_id
   WHERE  th_a.descendant_id = t.id AND th_a.depth > 0) AS breadcrumb,
  -- Articles directement associés à ce tag (statut publié)
  (SELECT COUNT(*) FROM content.content_to_tag ct
   JOIN   content.core co ON co.document_id = ct.content_id
   WHERE  ct.tag_id = t.id AND co.status = 1) AS article_count
FROM content.tag t;


-- ==============================================================================
-- SECTION 13 : PERMISSIONS — rôle applicatif marius_user
-- marius_user = SELECT (tables/vues) + EXECUTE (procédures/fonctions)
-- Les procédures de mutation s'exécutent en SECURITY DEFINER (SECTION 14).
-- marius_user n'a jamais de droits INSERT/UPDATE/DELETE directs sur les tables.
-- ==============================================================================

-- Accès aux schémas (USAGE obligatoire pour référencer les objets)
GRANT USAGE ON SCHEMA identity  TO marius_user;
GRANT USAGE ON SCHEMA geo       TO marius_user;
GRANT USAGE ON SCHEMA org       TO marius_user;
GRANT USAGE ON SCHEMA commerce  TO marius_user;
GRANT USAGE ON SCHEMA content   TO marius_user;

-- Lecture des tables et vues (interface applicative en lecture)
-- GRANT large par schéma, puis REVOKE ciblé sur les tables sensibles (ADR-028 audit).
-- Interface contractuelle : les vues de Section 12 sont le chemin de lecture attendu.
GRANT SELECT ON ALL TABLES IN SCHEMA identity  TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA geo       TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA org       TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA commerce  TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA content   TO marius_user;

-- REVOKE SELECT sur les tables physiques sensibles :
-- Accès à leur contenu uniquement via les vues sémantiques de Section 12,
-- qui appliquent le RLS ou contrôlent la projection (pas de colonne credential exposée).

-- identity.auth : hashes argon2id, état de bannissement — jamais exposés directement.
--   Interface contrôlée : identity.v_auth (SECURITY DEFINER, usage login uniquement).
REVOKE SELECT ON identity.auth FROM marius_user;

-- identity.person_contact : email, téléphone — PII au sens RGPD.
--   Interface contrôlée : identity.v_person (projection maîtrisée).
REVOKE SELECT ON identity.person_contact FROM marius_user;

-- commerce.transaction_payment : numéro de facture, méthode de paiement, référence PSP.
--   Interface contrôlée : commerce.v_transaction (RLS via transaction_core).
REVOKE SELECT ON commerce.transaction_payment FROM marius_user;

-- commerce.transaction_delivery : numéro de suivi logistique (données transporteur).
--   Interface contrôlée : commerce.v_transaction.
REVOKE SELECT ON commerce.transaction_delivery FROM marius_user;

-- commerce.transaction_price : montants, devise, taux de taxe — données financières.
--   Interface contrôlée : commerce.v_transaction (RLS via transaction_core).
--   ADR-029 : sans ce REVOKE, un SELECT direct bypasse le RLS de transaction_core
--   (fragmentation ECS — le RLS d'un composant Core ne se propage pas aux satellites).
REVOKE SELECT ON commerce.transaction_price FROM marius_user;

-- commerce.transaction_item : lignes de commande, produits, quantités, prix snapshot.
--   Interface contrôlée : commerce.v_transaction.
--   ADR-029 : même vecteur de fuite que transaction_price.
REVOKE SELECT ON commerce.transaction_item FROM marius_user;

-- Composants satellites éditoriaux — ADR-029 invariant 1 (ECS × RLS).
-- Le RLS de content.core ne se propage pas aux satellites : un SELECT direct
-- sur ces tables retourne l'intégralité des données (brouillons inclus) sans
-- que rls_core_select ne soit jamais évalué.
-- Interface contrôlée : content.v_article_list, content.v_article.

-- Gap documenté et accepté : content.content_to_tag et content.content_to_media
-- sont accessibles en SELECT direct (pas de REVOKE, pas de RLS propre). Un SELECT
-- sur ces tables de liaison révèle quels tags/médias sont associés à des brouillons.
-- Les tags eux-mêmes sont publics — seule la liaison brouillon+tag est exposée, pas
-- le contenu du brouillon. Risque évalué faible. Le correctif (REVOKE) casserait
-- v_tag_tree (article_count via content_to_tag) sans gain de sécurité significatif.
-- Référence : audit RLS global, ADR-029 invariant 1 note de limitation.

-- content.identity : headline, slug, description — métadonnées de tous les documents.
REVOKE SELECT ON content.identity FROM marius_user;

-- content.body : corps HTML complet — contenu de tous les documents.
REVOKE SELECT ON content.body FROM marius_user;

-- content.revision : snapshots éditoriaux complets (headline + body).
REVOKE SELECT ON content.revision FROM marius_user;

-- org.org_legal : DUNS, SIRET, TVA — identifiants légaux sensibles.
--   Interface contrôlée : org.v_organization, projetés uniquement pour manage_system.
--   ADR-029 inv.1 : satellite d'org.org_core, accessible directement sans ce REVOKE.
REVOKE SELECT ON org.org_legal FROM marius_user;

-- identity.v_auth : hash argon2id, is_banned, role_id — interface d'authentification.
--   Usage réservé au middleware d'authentification via connexion postgres ou fonction
--   SECURITY DEFINER dédiée. La vue étant owned par postgres (BYPASSRLS), elle lit
--   identity.auth malgré le REVOKE SELECT sur la table physique. Sans ce REVOKE sur
--   la vue, tout marius_user peut lire les hashes de mots de passe de tous les comptes.
REVOKE SELECT ON identity.v_auth FROM marius_user;

-- USAGE séquences : permet currval() et inspection — les nextval() des procédures
-- passent via SECURITY DEFINER (owner = postgres) et n'en ont pas besoin.
GRANT USAGE ON ALL SEQUENCES IN SCHEMA identity  TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA geo       TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA org       TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA commerce  TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA content   TO marius_user;

-- Exécution des procédures et fonctions (seul chemin d'écriture autorisé)
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA identity TO marius_user;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA content  TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA identity TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA org      TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA commerce TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA content  TO marius_user;

-- Calibrage autovacuum sur content.comment
-- Valeurs relâchées par rapport au modèle précédent à double trigger :
-- plus aucun dead tuple structurel généré par la construction du chemin ltree.
-- Les dead tuples résiduels proviennent uniquement des suppressions de modération.
ALTER TABLE content.comment SET (
  autovacuum_vacuum_scale_factor  = 0.05,
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_delay    = 10
);


-- ==============================================================================
-- SECTION 14 : VERROUILLAGE ECS STRICT — ADR-020
-- ==============================================================================
-- Scelle le contrat d'interface d'écriture :
--   marius_user → SELECT + EXECUTE uniquement (zéro DML direct)
--   marius_admin → maintenance/migrations (hérite marius_user + DML direct)
--   Procédures  → SECURITY DEFINER (s'exécutent avec les droits du propriétaire)
--
-- Rationalise et absorbe :
--   • ADR-012 : REVOKE INSERT ON content.comment (désormais couvert globalement)
-- ==============================================================================

-- 14.1 — Rôle de maintenance production
-- Hérite de marius_user (SELECT + EXECUTE + USAGE séquences + USAGE schémas).
-- Reçoit en sus l'écriture directe sur toutes les tables physiques.
-- LOGIN activé pour les sessions de maintenance ; désactiver en environnement
-- hautement sécurisé et passer par SET ROLE depuis une session postgres.
CREATE ROLE marius_admin WITH LOGIN ENCRYPTED PASSWORD 'change_in_production';
GRANT marius_user TO marius_admin WITH INHERIT TRUE;

GRANT USAGE ON SCHEMA identity  TO marius_admin;
GRANT USAGE ON SCHEMA geo       TO marius_admin;
GRANT USAGE ON SCHEMA org       TO marius_admin;
GRANT USAGE ON SCHEMA commerce  TO marius_admin;
GRANT USAGE ON SCHEMA content   TO marius_admin;

GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA identity  TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA geo       TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA org       TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA commerce  TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA content   TO marius_admin;

GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA identity  TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA geo       TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA org       TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA commerce  TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA content   TO marius_admin;

-- marius_admin doit contourner le RLS pour les opérations de maintenance et migrations.
-- Sans BYPASSRLS, ses UPDATE/INSERT directs seraient bloqués par les politiques RLS
-- activées en SECTION 15 sur content.core, commerce.transaction_core, identity.account_core.
GRANT BYPASSRLS TO marius_admin;

-- 14.2 — Révocation globale DML sur marius_user (défense en profondeur)
-- Idempotent : marius_user n'a jamais reçu ces droits en SECTION 13.
-- Ce bloc garantit l'invariant même si une migration future ajoute
-- accidentellement un GRANT DML sur marius_user.
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA identity  FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA geo       FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA org       FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA commerce  FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA content   FROM marius_user;

-- 14.3 — Élévation SECURITY DEFINER sur toutes les procédures de mutation
-- Mécanisme : la procédure s'exécute avec les droits de son propriétaire
-- (postgres), non ceux de l'appelant (marius_user).
-- SET search_path : neutralise l'injection de schéma via search_path de session.
-- Seconde ligne de défense : tous les noms d'objets dans les corps de procédures
-- sont entièrement qualifiés (schema.table), indépendamment du search_path.

ALTER PROCEDURE identity.anonymize_person(integer)
  SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.create_account(
  character varying, character varying, character varying, smallint, character
) SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.create_person(
  character varying, character varying, smallint, character
) SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.record_login(integer)
  SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.grant_permission(smallint, integer)
  SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.revoke_permission(smallint, integer)
  SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE org.create_organization(
  character varying, character varying, character varying, integer, integer
) SECURITY DEFINER SET search_path = 'org', 'identity', 'pg_catalog';

ALTER PROCEDURE org.add_organization_to_hierarchy(integer, integer)
  SECURITY DEFINER SET search_path = 'org', 'identity', 'pg_catalog';

-- content.create_document déclenche fn_slug_deduplicate (schéma public).
-- Le trigger est résolu par OID — pas de risque fonctionnel lié au search_path.
-- 'public' inclus pour la résolution des fonctions utilitaires dans le corps.
ALTER PROCEDURE content.create_document(
  integer, character varying, character varying,
  smallint, smallint, text, character varying, character varying
) SECURITY DEFINER SET search_path = 'content', 'identity', 'public', 'pg_catalog';

ALTER PROCEDURE content.publish_document(integer)
  SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.save_revision(integer, integer)
  SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.create_comment(integer, integer, text, integer, smallint)
  SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.create_tag(character varying, character varying, integer)
  SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.add_tag_to_document(integer, integer)
  SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE content.remove_tag_from_document(integer, integer)
  SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE commerce.create_transaction(integer, integer, smallint, smallint, text)
  SECURITY DEFINER SET search_path = 'commerce', 'identity', 'pg_catalog';

ALTER PROCEDURE commerce.create_transaction_item(integer, integer, integer)
  SECURITY DEFINER SET search_path = 'commerce', 'pg_catalog';


-- ==============================================================================
-- SECTION 15 : ROW-LEVEL SECURITY (RLS) — Pattern Stateless GUC (ADR-028)
-- ==============================================================================
-- Architecture : la couche applicative injecte deux GUC dans chaque session avant
-- toute requête :
--   SET LOCAL marius.user_id  = '<entity_id>'   -- identifiant de l'utilisateur connecté
--   SET LOCAL marius.auth_bits = '<bitmask INT4>' -- permissions du rôle (ADR-003/027)
--
-- Les politiques lisent ces GUC via current_setting(..., true) — le paramètre `true`
-- retourne NULL au lieu de lever une erreur si le GUC n'est pas défini (session système,
-- seed CI/CD, connexion postgres directe).
-- Fallback : user_id → -1 (ne correspondra à aucune ligne), auth_bits → 0 (tous bits off).
--
-- Superutilisateurs (postgres) et marius_admin (BYPASSRLS) contournent le RLS.
-- Ce contournement est intentionnel : les procédures SECURITY DEFINER s'exécutent
-- en tant que postgres et doivent pouvoir écrire sans restriction (ADR-020).
-- Le RLS sécurise le chemin de LECTURE (SELECT sur vues par marius_user).
-- Les tables les plus sensibles (identity.auth, person_contact, transaction_payment,
-- transaction_delivery) ont vu leur SELECT révoqué en Section 13. La vue identity.v_auth
-- a également un REVOKE SELECT (audit RLS global) : password_hash ne doit jamais être
-- accessible à marius_user, même via la vue. Le RLS est une défense complémentaire.
-- ==============================================================================

-- Helper functions — évitent de répéter le COALESCE/casting dans chaque politique.
-- STABLE : retourne la même valeur pour toutes les lignes d'un même statement.
-- SECURITY INVOKER : pas besoin d'élévation pour lire un GUC de session.

CREATE FUNCTION identity.rls_user_id()
RETURNS INT LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT COALESCE(current_setting('marius.user_id',  true)::INT, -1);
$$;

CREATE FUNCTION identity.rls_auth_bits()
RETURNS INT LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT COALESCE(current_setting('marius.auth_bits', true)::INT, 0);
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 15.1 — content.core
-- Politique SELECT :
--   Ligne visible si publiée (status=1)
--   OU si l'utilisateur possède publish_contents (bit 4, valeur 16) → accès éditorial
--   OU si l'utilisateur possède edit_others_contents (bit 15, valeur 32768) → éditeur/modérateur
--   OU si l'utilisateur est l'auteur de la ligne.
-- Note ADR-029 : tout bit accordant UPDATE ou DELETE sur cette table doit figurer
-- aussi dans le USING SELECT, sans quoi la politique d'écriture est structurellement
-- inatteignable (PostgreSQL évalue le filtre SELECT avant d'accorder l'écriture).
-- Politique UPDATE/DELETE :
--   Permissive A : auteur de la ligne ET edit_contents(4) pour UPDATE
--                  auteur de la ligne ET delete_contents(8) pour DELETE (ADR-029)
--   Permissive B : edit_others_contents(32768) → édition/suppression globale
-- Note ADR-029 : delete_own vérifie delete_contents (8) et non edit_contents (4).
--   Utiliser edit_contents pour garder une suppression est un mismatch sémantique :
--   un rôle perdant uniquement edit_contents conserverait sa capacité destructrice.
-- Note : INSERT est géré exclusivement par content.create_document (SECURITY DEFINER).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE content.core ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_core_select ON content.core
  FOR SELECT
  USING (
    status = 1                                             -- article publié : visible de tous
    OR (identity.rls_auth_bits() & 16)    = 16            -- publish_contents : accès éditorial
    OR (identity.rls_auth_bits() & 32768) = 32768         -- edit_others_contents : éditeur/modérateur
    OR author_entity_id = identity.rls_user_id()          -- auteur : voit ses propres brouillons
  );

-- Auteur peut modifier son propre contenu (edit_contents requis)
CREATE POLICY rls_core_update_own ON content.core
  FOR UPDATE
  USING (
    author_entity_id = identity.rls_user_id()
    AND (identity.rls_auth_bits() & 4) = 4             -- edit_contents
  )
  WITH CHECK (
    author_entity_id = identity.rls_user_id()
    AND (identity.rls_auth_bits() & 4) = 4
  );

-- Éditeur peut modifier n'importe quel contenu (edit_others_contents)
CREATE POLICY rls_core_update_others ON content.core
  FOR UPDATE
  USING (
    (identity.rls_auth_bits() & 32768) = 32768         -- edit_others_contents
  )
  WITH CHECK (
    (identity.rls_auth_bits() & 32768) = 32768
  );

-- Suppression propre : auteur ET delete_contents (bit 3, valeur 8)
-- ADR-029 : corrigé de edit_contents(4) → delete_contents(8). Le rôle author
-- inclut delete_contents depuis ADR-029. Utiliser le bit d'édition pour garder
-- une suppression crée un sur-privilège silencieux lors d'un déclassement de rôle.
CREATE POLICY rls_core_delete_own ON content.core
  FOR DELETE
  USING (
    author_entity_id = identity.rls_user_id()
    AND (identity.rls_auth_bits() & 8) = 8             -- delete_contents
  );

-- Suppression globale : edit_others_contents (bit 15, valeur 32768)
CREATE POLICY rls_core_delete_others ON content.core
  FOR DELETE
  USING (
    (identity.rls_auth_bits() & 32768) = 32768         -- edit_others_contents
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 15.2 — commerce.transaction_core
-- Politique SELECT :
--   Ligne visible si l'utilisateur est le client (isolation stricte)
--   OU si le bit view_transactions (bit 17, valeur 131072) est présent.
--   OU si le bit manage_commerce (bit 18, valeur 262144) est présent.
--   Note ADR-029 (invariant 3) : manage_commerce est requis dans le USING UPDATE ;
--   il doit donc figurer aussi dans le USING SELECT pour que la politique d'écriture
--   soit atteignable. Un profil portant manage_commerce mais pas view_transactions
--   (bits orthogonaux) échouerait silencieusement (0 rows updated) sans ce critère.
-- Politique UPDATE :
--   Uniquement si le bit manage_commerce (bit 18, valeur 262144) est présent.
--   Un client ne peut jamais modifier sa propre transaction — seul un gestionnaire
--   commerce le peut (remboursement, correction de statut).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE commerce.transaction_core ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_transaction_select ON commerce.transaction_core
  FOR SELECT
  USING (
    client_entity_id = identity.rls_user_id()          -- client : ses propres commandes
    OR (identity.rls_auth_bits() & 131072) = 131072    -- view_transactions
    OR (identity.rls_auth_bits() & 262144) = 262144    -- manage_commerce (ADR-029 invariant 3)
  );

CREATE POLICY rls_transaction_update ON commerce.transaction_core
  FOR UPDATE
  USING (
    (identity.rls_auth_bits() & 262144) = 262144       -- manage_commerce uniquement
  )
  WITH CHECK (
    (identity.rls_auth_bits() & 262144) = 262144
  );


-- ─────────────────────────────────────────────────────────────────────────────
-- 15.3 — identity.account_core
-- Politique SELECT :
--   Un compte voit uniquement sa propre ligne
--   OU si le bit manage_users (bit 8, valeur 256) est présent.
-- Politique UPDATE :
--   Identique au SELECT (un utilisateur peut modifier son propre profil).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE identity.account_core ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_account_select ON identity.account_core
  FOR SELECT
  USING (
    entity_id = identity.rls_user_id()                 -- lecture de son propre compte
    OR (identity.rls_auth_bits() & 256) = 256          -- manage_users : accès admin
  );

CREATE POLICY rls_account_update ON identity.account_core
  FOR UPDATE
  USING (
    entity_id = identity.rls_user_id()                 -- modification de son propre compte
    OR (identity.rls_auth_bits() & 256) = 256          -- manage_users
  )
  WITH CHECK (
    entity_id = identity.rls_user_id()
    OR (identity.rls_auth_bits() & 256) = 256
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 15.4 — content.comment
-- Politique SELECT :
--   status = 1 (commentaire approuvé) : visible de tous.
--   OU auteur du commentaire (account_entity_id = rls_user_id()) : voit ses propres
--      commentaires en attente ou rejetés.
--   OU moderate_comments (bit 16, valeur 65536) : modérateurs voient tout.
-- Note ADR-029 invariant 3 : marius_user n'a pas de DML sur content.comment
-- (ADR-020) → pas de politique UPDATE/DELETE nécessaire sur ce chemin.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE content.comment ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_comment_select ON content.comment
  FOR SELECT
  USING (
    status = 1                                             -- commentaire approuvé : visible de tous
    OR account_entity_id = identity.rls_user_id()         -- auteur : voit ses propres commentaires
    OR (identity.rls_auth_bits() & 65536) = 65536         -- moderate_comments : accès modération
  );


-- Permissions EXECUTE sur les helpers RLS (lecture des GUC uniquement)
GRANT EXECUTE ON FUNCTION identity.rls_user_id()   TO marius_user;
GRANT EXECUTE ON FUNCTION identity.rls_auth_bits() TO marius_user;


-- ==============================================================================
-- FIN DU DDL — master_schema_ddl.pgsql
-- Pour insérer les données de test : psql -U postgres -d marius -f master_schema_dml.pgsql
-- ==============================================================================
