-- ==============================================================================
-- 03_geo/01_components.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : geo.place_core · geo.postal_address · geo.place_content
-- FK cross-schéma : aucune dans ce domaine.
--   Les FK vers geo.place_core depuis d'autres domaines sont déclarées dans
--   07_cross_fk/01_constraints.sql. Ce module est auto-suffisant.
-- Pré-requis : extension postgis (00_infra/02_extensions.sql)
-- ==============================================================================

-- ==============================================================================
-- SECTION 4a — GEO : PLACE CORE & PLACE CONTENT
-- ==============================================================================

-- Spine spatial pur — ADR-017 : données postales extraites vers geo.postal_address.
-- Layout (ADR-006) :
--   id INT4 (offset 0) · elevation SMALLINT (4) · type_id SMALLINT (6) | varlena
-- Tuple avec GPS+nom : ~46 B → ~179 tuples/page (vs ~211 B avant fragmentation)
-- Tuple GPS seul, sans nom : ~26 B → ~317 tuples/page
-- Les requêtes KNN/ST_DWithin ne chargent plus aucune donnée postale.
CREATE TABLE geo.place_core (
  id           INT                   GENERATED ALWAYS AS IDENTITY,
  elevation    SMALLINT              NULL,
  type_id      SMALLINT              NULL,
  name         VARCHAR(60)           NULL,
  coordinates  geometry(Point,4326)  NULL,
  PRIMARY KEY (id),
  CONSTRAINT coordinates_valid CHECK (coordinates IS NULL OR ST_IsValid(coordinates))
);

CREATE INDEX place_core_gist ON geo.place_core USING gist (coordinates)
  WHERE coordinates IS NOT NULL;


-- POSTAL ADDRESS — adresse postale (ADR-017 · sémantique schema.org/PostalAddress)
-- Composant logistique 1:1 sur place_id. Accès lors de l'affichage d'une adresse,
-- de la génération d'une facture ou d'un bordereau d'expédition.
-- Layout (ADR-006) :
--   place_id INT4 (offset 0) · country_code SMALLINT (4) · 2B pad (6) | varlena
-- country_code : ISO 3166-1 numérique — 2 B pass-by-value (ADR-017).
--   Le mapping vers le code alphabétique (FR, DE, US) est délégué à l'applicatif.
--   Exemples : 250 = France · 276 = Allemagne · 840 = États-Unis · 826 = Royaume-Uni.
CREATE TABLE geo.postal_address (
  place_id          INT          NOT NULL,
  country_code      SMALLINT     NULL,
  address_locality  VARCHAR(64)  NULL,
  address_region    VARCHAR(64)  NULL,
  street_address    VARCHAR(60)  NULL,
  postal_code       VARCHAR(16)  NULL,
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
