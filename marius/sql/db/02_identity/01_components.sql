-- ==============================================================================
-- 02_identity/01_components.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : spine identity.entity + tous les composants du domaine identity
-- FK cross-schéma RETIRÉES (→ 07_cross_fk/01_constraints.sql) :
--   identity.account_core.media_id       → content.media_core
--   identity.person_contact.place_id     → geo.place_core
--   identity.person_biography.*_place_id → geo.place_core
--   identity.person_content.media_id     → content.media_core
-- ==============================================================================

-- ==============================================================================
-- SPINE IDENTITY — acteurs du système
-- ==============================================================================
-- Acteurs du système (utilisateurs, profils publics, contacts)
-- anonymized_at : timestamp de la dernière anonymisation RGPD (irréversible).
-- NULL = entité active. Non-NULL = données nominatives effacées (ADR-017).
-- L'entité physique est conservée pour maintenir l'intégrité des FK commerce.
CREATE TABLE identity.entity (
  anonymized_at  TIMESTAMPTZ  NULL,
  id             INT          GENERATED ALWAYS AS IDENTITY,
  PRIMARY KEY (id)
);


-- ==============================================================================
-- 4b — IDENTITY : PERMISSIONS & RÔLES (bitmask INT4)
-- ==============================================================================

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

-- Valeurs calculées : somme des puissances de 2 des permissions actives.
-- Valeurs recalculées avec les bits 15-20 (ADR-004) ; delete_contents(8) ajouté à base_author (ADR-003).
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
-- ==============================================================================

-- AUTH — hot path · fillfactor=70 pour HOT updates
CREATE TABLE identity.auth (
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
  last_login_at  TIMESTAMPTZ   NULL,
  modified_at    TIMESTAMPTZ   NULL,
  entity_id      INT           NOT NULL,
  role_id        SMALLINT      NOT NULL DEFAULT 7,
  is_banned      BOOLEAN       NOT NULL DEFAULT false,
  password_hash  VARCHAR(255)  NOT NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (role_id)   REFERENCES identity.role(id)
) WITH (fillfactor = 70);

ALTER TABLE identity.auth ALTER COLUMN password_hash SET STORAGE MAIN;

CREATE INDEX auth_created_at_brin ON identity.auth USING brin (created_at)
  WITH (pages_per_range = 128);

-- ACCOUNT CORE — données publiques du compte
-- FK cross-schéma RETIRÉE : media_id → content.media_core (→ 07_cross_fk)
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
  language            VARCHAR(5)   NOT NULL DEFAULT 'fr_FR',
  time_zone           TEXT         NULL,
  PRIMARY KEY (entity_id),
  UNIQUE (username),
  UNIQUE (slug),
  FOREIGN KEY (entity_id)        REFERENCES identity.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (person_entity_id) REFERENCES identity.entity(id) ON DELETE SET NULL,
  -- FOREIGN KEY (media_id) REFERENCES content.media_core(id) ON DELETE SET NULL
  -- → déplacé dans 07_cross_fk/01_constraints.sql (cycle identity ↔ content)
  CONSTRAINT display_mode_range  CHECK (display_mode BETWEEN 0 AND 3),
  CONSTRAINT slug_format         CHECK (slug ~ '^[a-z0-9-]+$')
);

ALTER TABLE identity.account_core ALTER COLUMN username  SET STORAGE MAIN;
ALTER TABLE identity.account_core ALTER COLUMN slug      SET STORAGE MAIN;
ALTER TABLE identity.account_core ALTER COLUMN language  SET STORAGE MAIN;
ALTER TABLE identity.account_core ALTER COLUMN time_zone SET STORAGE MAIN;

-- PERSON IDENTITY — noms
-- FK cross-schéma : aucune (entity_id → identity.entity est intra-schéma)
CREATE TABLE identity.person_identity (
  entity_id        INT          NOT NULL,
  gender           SMALLINT     NULL,
  nationality      SMALLINT     NULL,
  given_name       VARCHAR(32)  NULL,
  family_name      VARCHAR(32)  NULL,
  usual_name       VARCHAR(32)  NULL,
  nickname         VARCHAR(32)  NULL,
  prefix           VARCHAR(32)  NULL,
  suffix           VARCHAR(32)  NULL,
  additional_name  VARCHAR(32)  NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE,
  CONSTRAINT nationality_range CHECK (nationality IS NULL OR nationality BETWEEN 1 AND 999)
);

CREATE INDEX person_identity_name ON identity.person_identity (family_name, given_name)
  WHERE family_name IS NOT NULL;

-- PERSON CONTACT — FK cross-schéma RETIRÉE : place_id → geo.place_core (→ 07_cross_fk)
CREATE TABLE identity.person_contact (
  entity_id  INT           NOT NULL,
  place_id   INT           NULL,
  email      VARCHAR(128)  NULL,
  phone      VARCHAR(32)   NULL,
  phone2     VARCHAR(32)   NULL,
  fax        VARCHAR(32)   NULL,
  url        VARCHAR(255)  NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE
  -- FOREIGN KEY (place_id) REFERENCES geo.place_core(id) ON DELETE SET NULL
  -- → déplacé dans 07_cross_fk/01_constraints.sql
);

-- PERSON BIOGRAPHY — FK cross-schéma RETIRÉES : *_place_id → geo.place_core (→ 07_cross_fk)
CREATE TABLE identity.person_biography (
  entity_id       INT   NOT NULL,
  birth_place_id  INT   NULL,
  death_place_id  INT   NULL,
  birth_date      DATE  NULL,
  death_date      DATE  NULL,
  PRIMARY KEY (entity_id),
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE
  -- FOREIGN KEY (birth_place_id) REFERENCES geo.place_core(id) ON DELETE SET NULL
  -- FOREIGN KEY (death_place_id) REFERENCES geo.place_core(id) ON DELETE SET NULL
  -- → déplacées dans 07_cross_fk/01_constraints.sql
);

-- PERSON CONTENT — FK cross-schéma RETIRÉE : media_id → content.media_core (→ 07_cross_fk)
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
  FOREIGN KEY (entity_id) REFERENCES identity.entity(id) ON DELETE CASCADE
  -- FOREIGN KEY (media_id) REFERENCES content.media_core(id) ON DELETE SET NULL
  -- → déplacé dans 07_cross_fk/01_constraints.sql
) WITH (toast_tuple_target = 128);

-- GROUP
CREATE TABLE identity.group (
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
  id           INT           GENERATED ALWAYS AS IDENTITY,
  name         VARCHAR(32)   NOT NULL UNIQUE,
  description  TEXT          NULL,
  PRIMARY KEY (id)
);

-- Liaison Group ↔ Account (N:N)
CREATE TABLE identity.group_to_account (
  group_id          INT  NOT NULL,
  account_entity_id INT  NOT NULL,
  PRIMARY KEY (group_id, account_entity_id),
  FOREIGN KEY (group_id)          REFERENCES identity.group(id)  ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (account_entity_id) REFERENCES identity.entity(id) ON UPDATE CASCADE ON DELETE CASCADE
);


-- ==============================================================================
-- SECTION 8b : INFRASTRUCTURE D'AUDIT — Shadow Write Detection (ADR-001 rev.)
-- ==============================================================================

-- Table d'audit — cold storage
CREATE TABLE identity.dml_audit_log (
  logged_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  db_session_user  VARCHAR(64)  NOT NULL,
  db_current_user  VARCHAR(64)  NOT NULL,
  schema_name      VARCHAR(64)  NOT NULL,
  table_name       VARCHAR(64)  NOT NULL,
  operation        VARCHAR(6)   NOT NULL,
  row_pk           TEXT         NULL
) WITH (toast_tuple_target = 128);

CREATE INDEX dml_audit_log_ts ON identity.dml_audit_log (logged_at DESC);

-- Révocation des droits de suppression pour marius_user ET marius_admin :
-- un attaquant ayant compromis marius_admin ne doit pas pouvoir purger les traces.
REVOKE DELETE ON identity.dml_audit_log FROM PUBLIC;
