-- ==============================================================================
-- 04_org/01_components.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : spine org.entity + composants du domaine org
--
-- FK cross-schéma RETIRÉES (→ 07_cross_fk/01_constraints.sql) :
--   org.org_core.place_id          → geo.place_core
--   org.org_core.contact_entity_id → identity.entity
--   org.org_core.media_id          → content.media_core
--
-- FK intra-domaine conservées inline :
--   org.org_core.entity_id        → org.entity  (cascade)
--   org.org_core.parent_entity_id → org.entity  (set null, auto-référence)
--   org.org_identity.entity_id    → org.entity
--   org.org_contact.entity_id     → org.entity
--   org.org_legal.entity_id       → org.entity
--   org.org_hierarchy.entity_id   → org.entity
-- ==============================================================================

-- ==============================================================================
-- SPINE ORG — organisations
-- ==============================================================================

-- Organisations (entreprises, associations, organismes)
CREATE TABLE org.entity (
  id  INT  GENERATED ALWAYS AS IDENTITY,
  PRIMARY KEY (id)
);


-- ==============================================================================
-- SECTION 6 : COMPOSANTS ORG
-- ==============================================================================

-- ORG CORE — lookup standard · ~84 B → ~97 tuples/page
-- FK cross-schéma retirées :
--   place_id          → geo.place_core    (→ 07_cross_fk)
--   contact_entity_id → identity.entity   (→ 07_cross_fk)
--   media_id          → content.media_core (→ 07_cross_fk)
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
  FOREIGN KEY (entity_id)        REFERENCES org.entity(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_entity_id) REFERENCES org.entity(id) ON DELETE SET NULL
  -- FOREIGN KEY (place_id)          REFERENCES geo.place_core(id)    ON DELETE SET NULL  → 07_cross_fk
  -- FOREIGN KEY (contact_entity_id) REFERENCES identity.entity(id)   ON DELETE SET NULL  → 07_cross_fk
  -- FOREIGN KEY (media_id)          REFERENCES content.media_core(id) ON DELETE SET NULL → 07_cross_fk
);

-- Index B-tree sur parent_entity_id : navigation parent→enfants directs (O(log n)).
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
  USING gin (public.immutable_unaccent(name) gin_trgm_ops);

ALTER TABLE org.org_identity ALTER COLUMN name  SET STORAGE MAIN;
ALTER TABLE org.org_identity ALTER COLUMN slug  SET STORAGE MAIN;
ALTER TABLE org.org_identity ALTER COLUMN brand SET STORAGE MAIN;

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

-- ORG LEGAL — DUNS/SIRET en VARCHAR (ADR-026)
-- CHAR(n) dans PostgreSQL est varlena comme VARCHAR(n) — aucun stockage fixe,
-- mais surcoût de padding/stripping CPU. L'invariant de longueur est garanti
-- exclusivement par les contraintes CHECK.
CREATE TABLE org.org_legal (
  entity_id  INT          NOT NULL,
  duns       VARCHAR(9)   NULL,
  siret      VARCHAR(14)  NULL,
  vat_id     VARCHAR(32)  NULL,
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
