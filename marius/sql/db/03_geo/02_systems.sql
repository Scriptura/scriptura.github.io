-- ==============================================================================
-- 03_geo/02_systems.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : procédure geo.create_place · vue geo.v_place
-- Pré-requis : 03_geo/01_components.sql · 02_identity/02_systems.sql
--   (identity.rls_user_id / rls_auth_bits référencés dans la procédure)
-- SECURITY DEFINER + SET search_path appliqués en 08_dcl/02_secdef.sql
-- ==============================================================================

-- ==============================================================================
-- SECTION 11b : PROCÉDURE geo.create_place
-- ==============================================================================

-- GEO : création atomique d'un lieu (place_core + postal_address optionnelle)
-- Garde : manage_system (524288) — données géographiques de référence.
-- postal_address est optionnelle : un lieu peut exister sans adresse postale
-- (ex: coordonnées GPS pures, lieu naturel sans adresse).
--
-- Note ADR-001 v2.1 : 'public' retiré du search_path.
-- Les appels PostGIS sont entièrement qualifiés (public.ST_SetSRID,
-- public.ST_MakePoint) dans le corps de la procédure.
CREATE PROCEDURE geo.create_place(
  OUT p_place_id    INT,
  p_name            VARCHAR(60)   DEFAULT NULL,
  p_elevation       SMALLINT      DEFAULT NULL,
  p_type_id         SMALLINT      DEFAULT NULL,
  p_lat             FLOAT8        DEFAULT NULL,
  p_lng             FLOAT8        DEFAULT NULL,
  p_country_code    SMALLINT      DEFAULT NULL,
  p_street_address  VARCHAR(60)   DEFAULT NULL,
  p_postal_code     VARCHAR(16)   DEFAULT NULL,
  p_locality        VARCHAR(64)   DEFAULT NULL,
  p_region          VARCHAR(64)   DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 524288) <> 524288 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_system required to create a place'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO geo.place_core (name, elevation, type_id, coordinates)
  VALUES (
    p_name, p_elevation, p_type_id,
    CASE WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL
         THEN public.ST_SetSRID(public.ST_MakePoint(p_lng, p_lat), 4326)
         ELSE NULL
    END
  ) RETURNING id INTO p_place_id;

  -- Composant postal_address : créé uniquement si au moins un champ est fourni
  IF p_country_code IS NOT NULL OR p_street_address IS NOT NULL
     OR p_locality  IS NOT NULL OR p_region        IS NOT NULL
     OR p_postal_code IS NOT NULL THEN
    INSERT INTO geo.postal_address
      (place_id, country_code, street_address, postal_code, address_locality, address_region)
    VALUES (p_place_id, p_country_code, p_street_address, p_postal_code, p_locality, p_region);
  END IF;
END;
$$;


-- ==============================================================================
-- SECTION 12 : VUE geo.v_place
-- ==============================================================================

-- GEO : v_place — schema.org/Place + PostalAddress (ADR-017)
-- Jointure spine spatial (place_core) + composant postal (postal_address).
-- LEFT JOIN : un lieu peut exister sans adresse postale (ex : point GPS pur).
-- country_code (SMALLINT) conserve son nom physique — ADR-028 : un code entier
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
