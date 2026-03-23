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
CREATE TABLE identity.entity (
  id  INT  GENERATED ALWAYS AS IDENTITY,
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

-- Layout (colonnes décroissantes) :
--   id INT4 · elevation SMALLINT · type_id SMALLINT | puis varlena
-- Tuple moyen (adresse complète + GPS) : ~211 B → ~38 tuples/page
CREATE TABLE geo.place_core (
  id            INT                   GENERATED ALWAYS AS IDENTITY,
  elevation     SMALLINT              NULL,
  type_id       SMALLINT              NULL,
  locality      VARCHAR(64)           NULL,
  region        VARCHAR(64)           NULL,
  country       VARCHAR(64)           NULL,
  name          VARCHAR(60)           NULL,
  street        VARCHAR(60)           NULL,
  postal_code   VARCHAR(16)           NULL,
  coordinates   geometry(Point,4326)  NULL,
  PRIMARY KEY (id),
  CONSTRAINT coordinates_valid CHECK (coordinates IS NULL OR ST_IsValid(coordinates))
);

CREATE INDEX place_core_gist ON geo.place_core USING gist (coordinates)
  WHERE coordinates IS NOT NULL;
CREATE INDEX place_core_country_locality ON geo.place_core (country, locality)
  WHERE country IS NOT NULL;

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
  (16384, 14, 'can_read',         'Lire les contenus protégés (rôle minimal)');

-- Layout : permissions INT4 (offset 0) · id SMALLINT (offset 4) · 2B pad · name varlena
-- Tuple 'administrator' (13 chars) : 24+4+2+2+17 = 49 B  (vs 61 B ancien modèle booléen)
CREATE TABLE identity.role (
  permissions  INT          NOT NULL DEFAULT 16384,
  id           SMALLINT     GENERATED ALWAYS AS IDENTITY,
  name         VARCHAR(13)  NOT NULL UNIQUE,
  PRIMARY KEY (id),
  CONSTRAINT permissions_range CHECK (permissions BETWEEN 0 AND 32767)
);
-- Données de configuration structurelle — immuables en production
REVOKE INSERT, UPDATE, DELETE ON identity.role FROM PUBLIC;

-- Valeurs calculées : somme des puissances de 2 des permissions actives (voir role_bitmask_update.pgsql)
INSERT INTO identity.role (permissions, name) VALUES
  (32255, 'administrator'),  -- tous sauf manage_groups (bit 9)
  (27903, 'moderator'),
  (26622, 'editor'),
  (24830, 'author'),
  (24610, 'contributor'),
  (16608, 'commentator'),
  (16384, 'subscriber');     -- can_read uniquement · id=7, DEFAULT dans identity.auth


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

-- ACCOUNT CORE — données publiques du compte · ~77 B → ~106 tuples/page
CREATE TABLE identity.account_core (
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
  vat_number  VARCHAR(15)   NULL,
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
  name                  VARCHAR(255)   NOT NULL,
  alternative_headline  VARCHAR(255)   NULL,
  description           VARCHAR(1000)  NULL,
  PRIMARY KEY (document_id),
  UNIQUE (slug),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE,
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE INDEX content_identity_name_trgm ON content.identity
  USING gin (unaccent(name) gin_trgm_ops);

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
--          · revision_num SMALLINT · 2B pad | varlena × 5
-- snapshot_alternative_headline et snapshot_description inclus (ADR-021) :
-- un snapshot incomplet crée un historique silencieusement faux.
CREATE TABLE content.revision (
  saved_at                      TIMESTAMPTZ    NOT NULL DEFAULT now(),
  document_id                   INT            NOT NULL,
  author_entity_id              INT            NOT NULL,
  revision_num                  SMALLINT       NOT NULL DEFAULT 0,
  snapshot_name                 VARCHAR(255)   NOT NULL,
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

-- CONTENT TAG — taxonomie ltree (lectures fréquentes, insertions rares)
-- Layout : id INT4 · parent_id INT4 | puis varlena (ltree + slug + name)
CREATE TABLE content.tag (
  id         INT          GENERATED ALWAYS AS IDENTITY,
  parent_id  INT          NULL,
  path       ltree        NOT NULL,
  slug       VARCHAR(64)  NOT NULL,
  name       VARCHAR(64)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE (path),
  UNIQUE (slug),
  FOREIGN KEY (parent_id) REFERENCES content.tag(id) ON DELETE RESTRICT,
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]+$'),
  CONSTRAINT path_format  CHECK (path::text ~ '^[a-z0-9_]+(\.[a-z0-9_]+)*$')
);

CREATE INDEX tag_path_gist  ON content.tag USING gist (path);
CREATE INDEX tag_path_btree ON content.tag (path);

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

-- MEDIA CONTENT — titre et texte alternatif (BASSE fréquence)
CREATE TABLE content.media_content (
  media_id     INT           NOT NULL,
  name         VARCHAR(255)  NULL,
  description  VARCHAR(255)  NULL,
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

-- Enregistrement d'une connexion (hot path — LANGUAGE sql pour inlining)
CREATE PROCEDURE identity.record_login(p_entity_id INT)
LANGUAGE sql AS $$
  UPDATE identity.auth SET last_login_at = now() WHERE entity_id = p_entity_id;
$$;

-- Ajout/révocation de permission sur un rôle
CREATE PROCEDURE identity.grant_permission(p_role_id SMALLINT, p_permission INT)
LANGUAGE sql AS $$
  UPDATE identity.role SET permissions = permissions | p_permission WHERE id = p_role_id;
$$;

CREATE PROCEDURE identity.revoke_permission(p_role_id SMALLINT, p_permission INT)
LANGUAGE sql AS $$
  UPDATE identity.role SET permissions = permissions & (~p_permission) WHERE id = p_role_id;
$$;

-- Création d'une organisation (entity + org_core + org_identity)
CREATE PROCEDURE org.create_organization(
  p_name       VARCHAR(64),
  p_slug       VARCHAR(64),
  p_type       VARCHAR(30) DEFAULT NULL,
  p_place_id   INT         DEFAULT NULL,
  p_contact_id INT         DEFAULT NULL,
  OUT p_entity_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO org.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO org.org_core     (created_at, entity_id, place_id, contact_entity_id, type)
  VALUES (now(), p_entity_id, p_place_id, p_contact_id, p_type);
  INSERT INTO org.org_identity (entity_id, name, slug)
  VALUES (p_entity_id, p_name, p_slug);
END;
$$;

-- Création d'un document (spine + core + identity + body optionnel + première révision)
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
  INSERT INTO content.document (doc_type) VALUES (p_doc_type) RETURNING id INTO p_document_id;
  INSERT INTO content.core (document_id, author_entity_id, status, published_at, created_at)
  VALUES (p_document_id, p_author_id, p_status,
          CASE WHEN p_status = 1 THEN now() ELSE NULL END, now());
  INSERT INTO content.identity (document_id, slug, name, alternative_headline, description)
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
    snapshot_name, snapshot_slug, snapshot_alternative_headline,
    snapshot_description, snapshot_body
  )
  VALUES (p_document_id, p_author_id, p_name, p_slug, p_alt_headline, p_description, p_content);
END;
$$;

-- Publication d'un document (brouillon/archivé → publié)
CREATE PROCEDURE content.publish_document(p_document_id INT) LANGUAGE sql AS $$
  UPDATE content.core
  SET status = 1, published_at = COALESCE(published_at, now())
  WHERE document_id = p_document_id AND status IN (0, 2);
$$;

-- Snapshot éditorial avant modification
-- Capture l'intégralité de content.identity + content.body (ADR-021).
CREATE PROCEDURE content.save_revision(p_document_id INT, p_author_id INT)
LANGUAGE plpgsql AS $$
DECLARE
  v_name        VARCHAR(255);
  v_slug        VARCHAR(255);
  v_alt         VARCHAR(255);
  v_description VARCHAR(1000);
  v_body        TEXT;
BEGIN
  SELECT i.name, i.slug, i.alternative_headline, i.description, b.content
  INTO   v_name, v_slug, v_alt, v_description, v_body
  FROM   content.identity i
  LEFT JOIN content.body b ON b.document_id = i.document_id
  WHERE  i.document_id = p_document_id FOR SHARE;
  INSERT INTO content.revision (
    document_id, author_entity_id,
    snapshot_name, snapshot_slug, snapshot_alternative_headline,
    snapshot_description, snapshot_body
  )
  VALUES (p_document_id, p_author_id, v_name, v_slug, v_alt, v_description, v_body);
END;
$$;

-- Insertion d'un commentaire avec construction du chemin ltree (une seule écriture heap)
-- Remplace définitivement le double trigger BEFORE/AFTER (ADR-012).
-- nextval() préalable → path construit en mémoire → INSERT unique, zéro dead tuple.
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
CREATE PROCEDURE commerce.create_transaction(
  p_client_entity_id  INT,
  p_seller_entity_id  INT,
  p_currency_code     SMALLINT DEFAULT 978,
  p_status            SMALLINT DEFAULT 0,
  p_description       TEXT     DEFAULT NULL,
  OUT p_transaction_id INT
) LANGUAGE plpgsql AS $$
BEGIN
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
CREATE PROCEDURE commerce.create_transaction_item(
  p_transaction_id INT, p_product_id INT, p_quantity INT DEFAULT 1
) LANGUAGE plpgsql AS $$
DECLARE v_price_cents INT8;
BEGIN
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
-- SECTION 12 : VUES SÉMANTIQUES (INTERFACE schema.org)
-- Déclarées après toutes les tables et fonctions.
-- ==============================================================================

-- IDENTITY : v_role — décompose le bitmask en colonnes booléennes nommées
CREATE VIEW identity.v_role AS
SELECT id, name, permissions,
  (permissions &     1) <> 0  AS access_admin,
  (permissions &     2) <> 0  AS create_contents,
  (permissions &     4) <> 0  AS edit_contents,
  (permissions &     8) <> 0  AS delete_contents,
  (permissions &    16) <> 0  AS publish_contents,
  (permissions &    32) <> 0  AS create_comments,
  (permissions &    64) <> 0  AS edit_comments,
  (permissions &   128) <> 0  AS delete_comments,
  (permissions &   256) <> 0  AS manage_users,
  (permissions &   512) <> 0  AS manage_groups,
  (permissions &  1024) <> 0  AS manage_contents,
  (permissions &  2048) <> 0  AS manage_tags,
  (permissions &  4096) <> 0  AS manage_menus,
  (permissions &  8192) <> 0  AS upload_files,
  (permissions & 16384) <> 0  AS can_read
FROM identity.role;

-- IDENTITY : v_auth — hot path authentification (masque brut exposé)
CREATE VIEW identity.v_auth AS
SELECT a.entity_id, a.password_hash, a.is_banned, a.role_id,
  r.name AS role_name, r.permissions AS role_permissions
FROM identity.auth a JOIN identity.role r ON r.id = a.role_id;

-- IDENTITY : v_account — schema.org/Person (compte utilisateur)
CREATE VIEW identity.v_account AS
SELECT
  ac.entity_id                AS "identifier",
  ac.username, ac.slug,
  ac.language, ac.time_zone   AS "timeZone",
  ac.is_visible               AS "isVisible",
  ac.display_mode             AS "displayMode",
  ac.media_id                 AS "imageId",
  a.role_id, a.is_banned      AS "isBanned",
  a.created_at                AS "dateCreated",
  a.modified_at               AS "dateModified",
  a.last_login_at             AS "lastLoginAt",
  pi.given_name               AS "givenName",
  pi.family_name              AS "familyName",
  pi.usual_name               AS "alternativeName",
  pi.nickname                 AS "alternateName",
  pi.prefix                   AS "honorificPrefix",
  pi.suffix                   AS "honorificSuffix",
  pi.nationality
FROM        identity.account_core    ac
JOIN        identity.auth            a  ON a.entity_id  = ac.entity_id
LEFT JOIN   identity.person_identity pi ON pi.entity_id = ac.person_entity_id;

-- IDENTITY : v_person — schema.org/Person (profil public complet)
CREATE VIEW identity.v_person AS
SELECT
  e.id                          AS "identifier",
  pi.given_name                 AS "givenName",
  pi.additional_name            AS "additionalName",
  pi.family_name                AS "familyName",
  pi.usual_name                 AS "alternativeName",
  pi.nickname                   AS "alternateName",
  pi.prefix                     AS "honorificPrefix",
  pi.suffix                     AS "honorificSuffix",
  pi.gender, pi.nationality,
  pb.birth_date                 AS "birthDate",
  pb.birth_place_id             AS "birthPlaceId",
  pb.death_date                 AS "deathDate",
  pb.death_place_id             AS "deathPlaceId",
  pc.email, pc.phone            AS "telephone",
  pc.url, pc.place_id           AS "addressId",
  pco.media_id                  AS "imageId",
  pco.occupation                AS "hasOccupation",
  pco.devise                    AS "description",
  pco.description               AS "disambiguatingDescription"
FROM        identity.entity           e
JOIN        identity.person_identity  pi  ON pi.entity_id = e.id
LEFT JOIN   identity.person_biography pb  ON pb.entity_id = e.id
LEFT JOIN   identity.person_contact   pc  ON pc.entity_id = e.id
LEFT JOIN   identity.person_content   pco ON pco.entity_id = e.id;

-- GEO : v_place — schema.org/Place
CREATE VIEW geo.v_place AS
SELECT
  c.id                          AS "identifier",
  c.name, c.street              AS "streetAddress",
  c.postal_code                 AS "postalCode",
  c.locality                    AS "addressLocality",
  c.region                      AS "addressRegion",
  c.country                     AS "addressCountry",
  c.elevation,
  CASE WHEN c.coordinates IS NOT NULL
    THEN ST_AsGeoJSON(c.coordinates)::jsonb ELSE NULL
  END                           AS "geo",
  ST_Y(c.coordinates)           AS "latitude",
  ST_X(c.coordinates)           AS "longitude",
  co.description
FROM      geo.place_core    c
LEFT JOIN geo.place_content co ON co.place_id = c.id;

-- ORG : v_organization — schema.org/Organization
CREATE VIEW org.v_organization AS
SELECT
  e.id                          AS "identifier",
  oi.name, oi.slug, oi.brand,
  oc.type                       AS "@type",
  oc.purpose, oc.created_at     AS "foundingDate",
  oct.email, oct.phone          AS "telephone", oct.url,
  ol.duns, ol.siret, ol.vat_number AS "vatID",
  gp.name                       AS "locationName",
  gp."addressLocality", gp."addressCountry", gp."geo",
  oc.parent_entity_id           AS "parentOrganizationId"
FROM        org.entity          e
JOIN        org.org_identity    oi  ON oi.entity_id = e.id
JOIN        org.org_core        oc  ON oc.entity_id = e.id
LEFT JOIN   org.org_contact     oct ON oct.entity_id = e.id
LEFT JOIN   org.org_legal       ol  ON ol.entity_id  = e.id
LEFT JOIN   geo.v_place         gp  ON gp."identifier" = oc.place_id;

-- COMMERCE : v_product — schema.org/Product
-- price_cents exposé tel quel (INT8, centimes). La conversion décimale est
-- déléguée à la couche applicative (ADR-022).
CREATE VIEW commerce.v_product AS
SELECT
  pc.id                         AS "identifier",
  pi.name, pi.slug,
  pi.isbn_ean                   AS "gtin13",
  pc.price_cents                AS "priceCents",
  pc.stock,
  pc.is_available               AS "availability",
  pc.media_id                   AS "imageId",
  pco.description, pco.tags
FROM        commerce.product_core     pc
JOIN        commerce.product_identity pi  ON pi.product_id  = pc.id
LEFT JOIN   commerce.product_content  pco ON pco.product_id = pc.id;

-- COMMERCE : v_transaction — schema.org/Order enrichi (ADR-023)
-- Agrège transaction_core + trois composants ECS (price, payment, delivery) + items.
-- Montants en centimes INT8 (ADR-022) — arithmétique ALU native.
-- totalCents = subtotal + shipping + tax - discount (entiers purs).
-- PUSHDOWN GARANTI : WHERE "identifier" = :id → WHERE tc.id = :id avant json_agg().
-- OBLIGATION : toujours filtrer par "identifier" ou "customerId".
CREATE VIEW commerce.v_transaction AS
SELECT
  -- Core (schema.org/Order)
  tc.id                         AS "identifier",
  tc.status                     AS "orderStatus",
  tc.created_at                 AS "orderDate",
  tc.modified_at                AS "dateModified",
  tc.client_entity_id           AS "customerId",
  tc.seller_entity_id           AS "sellerId",
  tc.description,
  -- Price component (schema.org/PriceSpecification)
  tp.currency_code              AS "currencyCode",
  tp.shipping_cents             AS "shippingCents",
  tp.discount_cents             AS "discountCents",
  tp.tax_cents                  AS "taxCents",
  tp.tax_rate_bp                AS "taxRateBp",
  tp.is_tax_included            AS "isTaxIncluded",
  -- Payment component (schema.org/PaymentChargeSpecification)
  tpay.payment_status           AS "paymentStatus",
  tpay.payment_method           AS "paymentMethod",
  tpay.invoice_number           AS "orderNumber",
  tpay.paid_at                  AS "paymentDate",
  tpay.billing_place_id         AS "billingAddressId",
  -- Delivery component (schema.org/ParcelDelivery)
  tdel.delivery_status          AS "deliveryStatus",
  tdel.shipping_place_id        AS "deliveryAddressId",
  tdel.carrier,
  tdel.tracking_number          AS "trackingNumber",
  tdel.shipped_at               AS "shippedAt",
  tdel.estimated_at             AS "estimatedDeliveryDate",
  tdel.delivered_at             AS "deliveredAt",
  -- Items aggregation
  json_agg(json_build_object(
    'productId',      ti.product_id,
    'productName',    pi.name,
    'quantity',       ti.quantity,
    'unitPriceCents', ti.unit_price_snapshot_cents,
    'lineTotalCents', ti.quantity * ti.unit_price_snapshot_cents
  ) ORDER BY ti.product_id)     AS "orderedItem",
  SUM(ti.quantity * ti.unit_price_snapshot_cents)                AS "subtotalCents",
  SUM(ti.quantity * ti.unit_price_snapshot_cents)
    + COALESCE(tp.shipping_cents, 0)
    + COALESCE(tp.tax_cents,      0)
    - COALESCE(tp.discount_cents, 0)                             AS "totalCents"
FROM        commerce.transaction_core    tc
JOIN        commerce.transaction_item    ti   ON ti.transaction_id   = tc.id
JOIN        commerce.product_identity    pi   ON pi.product_id       = ti.product_id
LEFT JOIN   commerce.transaction_price   tp   ON tp.transaction_id   = tc.id
LEFT JOIN   commerce.transaction_payment tpay ON tpay.transaction_id = tc.id
LEFT JOIN   commerce.transaction_delivery tdel ON tdel.transaction_id = tc.id
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
CREATE VIEW content.v_article_list AS
SELECT
  d.id                          AS "identifier",
  ci.name                       AS "headline",
  ci.slug,
  ci.alternative_headline       AS "alternativeHeadline",
  ci.description,
  co.published_at               AS "datePublished",
  co.author_entity_id           AS "authorId",
  co.status
FROM        content.document  d
JOIN        content.core      co ON co.document_id = d.id
JOIN        content.identity  ci ON ci.document_id = d.id
WHERE co.status = 1;

-- CONTENT : v_article — schema.org/Article (page complète avec TOAST + agrégats)
CREATE VIEW content.v_article AS
SELECT
  d.id                          AS "identifier",
  d.doc_type                    AS "@type",
  ci.name                       AS "headline",
  ci.slug,
  ci.alternative_headline       AS "alternativeHeadline",
  ci.description,
  co.status, co.is_readable     AS "isAccessibleForFree",
  co.is_commentable,
  co.published_at               AS "datePublished",
  co.created_at                 AS "dateCreated",
  co.modified_at                AS "dateModified",
  co.author_entity_id           AS "authorId",
  b.content                     AS "articleBody",
  (SELECT json_agg(json_build_object('id', t.id, 'name', t.name, 'slug', t.slug,
                                     'path', t.path::text) ORDER BY t.path)
   FROM content.content_to_tag ct JOIN content.tag t ON t.id = ct.tag_id
   WHERE ct.content_id = d.id)  AS "keywords",
  (SELECT json_agg(json_build_object('id', m.id, 'name', mc.name,
                                     'url', m.folder_url || '/' || m.file_name,
                                     'mimeType', m.mime_type, 'width', m.width,
                                     'height', m.height, 'position', ctm.position)
                   ORDER BY ctm.position)
   FROM  content.content_to_media ctm
   JOIN  content.media_core m   ON m.id          = ctm.media_id
   LEFT JOIN content.media_content mc ON mc.media_id = m.id
   WHERE ctm.content_id = d.id) AS "image"
FROM        content.document  d
JOIN        content.core      co ON co.document_id = d.id
JOIN        content.identity  ci ON ci.document_id = d.id
LEFT JOIN   content.body      b  ON b.document_id  = d.id;

-- CONTENT : v_tag_tree — taxonomie avec métadonnées hiérarchiques
CREATE VIEW content.v_tag_tree AS
SELECT
  t.id                          AS "identifier",
  t.name, t.slug,
  t.path::text                  AS "path",
  t.parent_id                   AS "parentId",
  nlevel(t.path)                AS "depth",
  (SELECT COUNT(*) FROM content.content_to_tag ct
   JOIN content.core co ON co.document_id = ct.content_id
   WHERE ct.tag_id = t.id AND co.status = 1) AS "articleCount"
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
GRANT SELECT ON ALL TABLES IN SCHEMA identity  TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA geo       TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA org       TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA commerce  TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA content   TO marius_user;

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

ALTER PROCEDURE commerce.create_transaction(integer, integer, smallint, smallint, text)
  SECURITY DEFINER SET search_path = 'commerce', 'identity', 'pg_catalog';

ALTER PROCEDURE commerce.create_transaction_item(integer, integer, integer)
  SECURITY DEFINER SET search_path = 'commerce', 'pg_catalog';


-- ==============================================================================
-- FIN DU DDL — master_schema_ddl.pgsql
-- Pour insérer les données de test : psql -U postgres -d marius -f master_schema_dml.pgsql
-- ==============================================================================
