-- ==============================================================================
-- 05_content/01_components.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : spine content.document · content.media_core · content.media_content
--           · composants éditoriaux · tags · liaisons N:N · commentaires
--
-- FK cross-schéma RETIRÉES (→ 07_cross_fk/01_constraints.sql) :
--   content.media_core.author_id       → identity.entity(id)   ON DELETE SET NULL
--   content.core.author_entity_id      → identity.entity(id)   ON DELETE SET NULL
--   content.revision.author_entity_id  → identity.entity(id)   ON DELETE SET NULL
--   content.comment.account_entity_id  → identity.entity(id)   ON DELETE SET NULL
--
-- FK intra-domaine conservées inline (toutes référencent content.document ou
-- content.media_core ou content.tag — tables définies dans ce même fichier).
--
-- NOTE cycle identity ↔ content :
--   identity.account_core.media_id     → content.media_core (→ 07_cross_fk)
--   identity.person_content.media_id   → content.media_core (→ 07_cross_fk)
--   org.org_core.media_id              → content.media_core (→ 07_cross_fk)
--   commerce.product_core.media_id     → content.media_core (→ 07_cross_fk)
--   content.media_core.author_id       → identity.entity    (→ 07_cross_fk)
--   Ce cycle est intégralement résolu en étape 7.
-- ==============================================================================

-- ==============================================================================
-- SPINE DOCUMENT — documents éditoriaux
-- ==============================================================================
-- Documents éditoriaux (articles, pages, newsletters)
-- doc_type : 0=article · 1=page · 2=billet · 3=newsletter
CREATE TABLE content.document (
  id        INT       GENERATED ALWAYS AS IDENTITY,
  doc_type  SMALLINT  NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  CONSTRAINT doc_type_range CHECK (doc_type IN (0, 1, 2, 3))
);


-- ==============================================================================
-- MEDIA CORE + MEDIA CONTENT
-- ==============================================================================
-- Pré-déclarés en premier dans ce domaine : content.media_core est référencé
-- par FK intra-domaine dans content.content_to_media et par FK cross-schéma
-- depuis identity.account_core, identity.person_content, org.org_core,
-- commerce.product_core (toutes → 07_cross_fk).
--
-- MEDIA CORE — métadonnées fichiers (MOYENNE fréquence)
-- author_id : NULL après anonymisation RGPD (ADR-017 + Audit 4).
-- FK cross-schéma RETIRÉE :
--   author_id → identity.entity(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE content.media_core (
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at  TIMESTAMPTZ   NULL,
  id           INT           GENERATED ALWAYS AS IDENTITY,
  author_id    INT           NULL,
  width        INT           NULL,
  height       INT           NULL,
  mime_type    VARCHAR(255)  NULL,
  folder_url   VARCHAR(255)  NULL,
  file_name    VARCHAR(255)  NULL,
  PRIMARY KEY (id)
  -- FOREIGN KEY (author_id) REFERENCES identity.entity(id) ON DELETE SET NULL → 07_cross_fk
);

-- MEDIA CONTENT — titre, texte alternatif, mention de droits (BASSE fréquence)
-- copyright_notice : mention légale du titulaire des droits (ADR-017).
CREATE TABLE content.media_content (
  media_id          INT           NOT NULL,
  name              VARCHAR(255)  NULL,
  description       VARCHAR(255)  NULL,
  copyright_notice  VARCHAR(255)  NULL,
  PRIMARY KEY (media_id),
  FOREIGN KEY (media_id) REFERENCES content.media_core(id) ON DELETE CASCADE
);


-- ==============================================================================
-- SECTION 8 : COMPOSANTS CONTENT
-- ==============================================================================

-- CONTENT CORE — status / dates / auteur (TRÈS HAUTE fréquence)
-- Layout : 3×TIMESTAMPTZ · document_id INT4 · author_entity_id INT4 · status SMALLINT
--          · 3×BOOL
-- Tuple 64 B → ~127 tuples/page. fillfactor retiré (Audit 3 : zéro HOT path).
-- FK cross-schéma RETIRÉE :
--   author_entity_id → identity.entity(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE content.core (
  published_at        TIMESTAMPTZ   NULL,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at         TIMESTAMPTZ   NULL,
  document_id         INT           NOT NULL,
  author_entity_id    INT           NULL,
  status              SMALLINT      NOT NULL DEFAULT 0,
  is_readable         BOOLEAN       NOT NULL DEFAULT true,
  is_commentable      BOOLEAN       NOT NULL DEFAULT false,
  is_visible_comments BOOLEAN       NOT NULL DEFAULT true,
  PRIMARY KEY (document_id),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE,
  -- FOREIGN KEY (author_entity_id) REFERENCES identity.entity(id) ON DELETE SET NULL → 07_cross_fk
  CONSTRAINT status_range CHECK (status IN (0, 1, 2, 9))
);

CREATE INDEX core_published ON content.core (published_at DESC) WHERE status = 1;
CREATE INDEX core_author ON content.core (author_entity_id, published_at DESC)
  WHERE status = 1 AND author_entity_id IS NOT NULL;
CREATE INDEX core_created_brin ON content.core USING brin (created_at)
  WITH (pages_per_range = 128);
CREATE INDEX core_modified ON content.core (modified_at DESC)
  WHERE modified_at IS NOT NULL;


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
  USING gin (public.immutable_unaccent(headline) gin_trgm_ops);

ALTER TABLE content.identity ALTER COLUMN headline             SET STORAGE MAIN;
ALTER TABLE content.identity ALTER COLUMN slug                 SET STORAGE MAIN;
ALTER TABLE content.identity ALTER COLUMN alternative_headline SET STORAGE MAIN;


-- CONTENT BODY — corps HTML (BASSE fréquence) · TOAST EXTENDED systématique
CREATE TABLE content.body (
  document_id  INT   NOT NULL,
  content      TEXT  NULL,
  PRIMARY KEY (document_id),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE
) WITH (toast_tuple_target = 128);

ALTER TABLE content.body ALTER COLUMN content SET STORAGE EXTENDED;


-- CONTENT REVISION — cold storage des snapshots éditoriaux
-- FK cross-schéma RETIRÉE :
--   author_entity_id → identity.entity(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE content.revision (
  saved_at                      TIMESTAMPTZ    NOT NULL DEFAULT now(),
  document_id                   INT            NOT NULL,
  author_entity_id              INT            NULL,
  revision_num                  SMALLINT       NOT NULL DEFAULT 0,
  snapshot_headline             VARCHAR(255)   NOT NULL,
  snapshot_slug                 VARCHAR(255)   NOT NULL,
  snapshot_alternative_headline VARCHAR(255)   NULL,
  snapshot_description          VARCHAR(1000)  NULL,
  snapshot_body                 TEXT           NULL,
  PRIMARY KEY (document_id, revision_num),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE,
  -- FOREIGN KEY (author_entity_id) REFERENCES identity.entity(id) ON DELETE SET NULL → 07_cross_fk
  CONSTRAINT revision_num_positive CHECK (revision_num > 0)
) WITH (toast_tuple_target = 128);

CREATE INDEX revision_recent ON content.revision (document_id, revision_num DESC);


-- CONTENT TAG — spine taxonomique (Closure Table, ADR-018)
CREATE TABLE content.tag (
  id    INT          GENERATED ALWAYS AS IDENTITY,
  slug  VARCHAR(64)  NOT NULL,
  name  VARCHAR(64)  NOT NULL,
  PRIMARY KEY (id),
  UNIQUE (slug),
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);


-- TAG HIERARCHY — Closure Table (ADR-018)
-- Stocke toutes les paires (ancêtre, descendant) avec leur distance.
-- Profondeur maximale : 4 niveaux.
-- Layout (ADR-006) :
--   ancestor_id INT4 (offset 0) · descendant_id INT4 (4) · depth SMALLINT (8) · 2B pad
CREATE TABLE content.tag_hierarchy (
  ancestor_id    INT       NOT NULL,
  descendant_id  INT       NOT NULL,
  depth          SMALLINT  NOT NULL,
  PRIMARY KEY (ancestor_id, descendant_id),
  FOREIGN KEY (ancestor_id)   REFERENCES content.tag(id) ON DELETE CASCADE,
  FOREIGN KEY (descendant_id) REFERENCES content.tag(id) ON DELETE CASCADE,
  CONSTRAINT depth_range CHECK (depth BETWEEN 0 AND 4)
);

CREATE INDEX tag_hierarchy_descendant ON content.tag_hierarchy (descendant_id, depth);


-- LIAISON Document ↔ Tag (N:N)
CREATE TABLE content.content_to_tag (
  content_id  INT  NOT NULL,
  tag_id      INT  NOT NULL,
  PRIMARY KEY (content_id, tag_id),
  FOREIGN KEY (content_id) REFERENCES content.document(id) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (tag_id)     REFERENCES content.tag(id)      ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX content_to_tag_inv ON content.content_to_tag (tag_id, content_id);


-- LIAISON Document ↔ Média (N:N)
-- position SMALLINT pour l'ordre de galerie
CREATE TABLE content.content_to_media (
  content_id  INT       NOT NULL,
  media_id    INT       NOT NULL,
  position    SMALLINT  NOT NULL DEFAULT 0,
  PRIMARY KEY (content_id, media_id),
  FOREIGN KEY (content_id) REFERENCES content.document(id)   ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (media_id)   REFERENCES content.media_core(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT position_range CHECK (position >= 0)
);

CREATE INDEX content_to_media_inv ON content.content_to_media (media_id, content_id);
CREATE INDEX content_to_media_pos ON content.content_to_media (content_id, position);


-- COMMENT — arborescence ltree
-- path : déclaré NULL DEFAULT NULL pour permettre l'INSERT via OVERRIDING SYSTEM VALUE
-- dans content.create_comment(). La contrainte NOT NULL effective est portée par le
-- CHECK comment_path_not_null (Voir ADR-007).
-- FK cross-schéma RETIRÉE :
--   account_entity_id → identity.entity(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE content.comment (
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at         TIMESTAMPTZ   NULL,
  document_id         INT           NOT NULL,
  account_entity_id   INT           NULL,
  parent_id           INT           NULL,
  id                  INT           GENERATED ALWAYS AS IDENTITY,
  status              SMALLINT      NOT NULL DEFAULT 1,
  path                ltree         NULL     DEFAULT NULL,
  content             TEXT          NOT NULL,
  PRIMARY KEY (id),
  FOREIGN KEY (document_id) REFERENCES content.document(id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id)   REFERENCES content.comment(id)  ON DELETE SET NULL,
  -- FOREIGN KEY (account_entity_id) REFERENCES identity.entity(id) ON DELETE SET NULL → 07_cross_fk
  CONSTRAINT status_range        CHECK (status IN (0, 1, 9)),
  CONSTRAINT content_notempty    CHECK (char_length(trim(content)) > 0),
  CONSTRAINT comment_path_not_null CHECK (path IS NOT NULL)
);

CREATE INDEX comment_path_gist ON content.comment USING gist (path);
CREATE INDEX comment_doc_path  ON content.comment (document_id, path);
CREATE INDEX comment_approved  ON content.comment (document_id, created_at)
  WHERE status = 1;

-- MAIN : inline pour les cas nominaux, zéro tentative PGLZ sur le write path fréquent.
ALTER TABLE content.comment ALTER COLUMN content SET STORAGE MAIN;

-- Calibrage autovacuum : plus aucun dead tuple structurel depuis create_comment()
-- (chemin INSERT unique avec nextval() préalable — ADR-007).
-- Dead tuples résiduels = suppressions de modération uniquement.
ALTER TABLE content.comment SET (
  autovacuum_vacuum_scale_factor  = 0.05,
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_delay    = 10
);
