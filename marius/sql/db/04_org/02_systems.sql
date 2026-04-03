-- ==============================================================================
-- 04_org/02_systems.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : index BRIN org.org_core · trigger BRIN immuabilité · procédures org
--           · vue org.v_organization
-- Pré-requis : 04_org/01_components.sql · 02_identity/02_systems.sql
--   (identity.fn_deny_created_at_update, rls_user_id, rls_auth_bits)
--   (03_geo/02_systems.sql pour geo.v_place référencée dans v_organization)
-- SECURITY DEFINER + SET search_path appliqués en 08_dcl/02_secdef.sql
-- ==============================================================================

-- ==============================================================================
-- INDEX BRIN — org.org_core
-- ==============================================================================

-- Index BRIN sur created_at (ADR-010) : séquençage chronologique des insertions.
-- pages_per_range = 64 : granularité plus fine que les tables identity/commerce
-- (cardinalité org plus faible, scan de plage plus court en absolu).
CREATE INDEX org_core_created_brin ON org.org_core USING brin (created_at)
  WITH (pages_per_range = 64);


-- ==============================================================================
-- SECTION 10 : TRIGGER BRIN IMMUABILITÉ — org.org_core
-- ==============================================================================

-- Garde d'immuabilité created_at (Audit 3 — ADR-010 rev.)
-- Même invariant que identity.auth, content.core, commerce.transaction_core.
-- La fonction identity.fn_deny_created_at_update() est définie dans
-- 02_identity/02_systems.sql et utilisée ici cross-schéma.
CREATE TRIGGER org_core_deny_created_at_update
BEFORE UPDATE ON org.org_core
FOR EACH ROW WHEN (OLD.created_at IS DISTINCT FROM NEW.created_at)
EXECUTE FUNCTION identity.fn_deny_created_at_update();


-- ==============================================================================
-- SECTION 11 : PROCÉDURES org
-- ==============================================================================

-- Création d'une organisation (entity + org_core + org_identity)
-- Garde d'autorisation (ADR-001 rev.) : manage_system (bit 19, valeur 524288) requis.
CREATE PROCEDURE org.create_organization(
  p_name       VARCHAR(64),
  p_slug       VARCHAR(64),
  OUT p_entity_id INT,
  p_type       VARCHAR(30) DEFAULT NULL,
  p_place_id   INT         DEFAULT NULL,
  p_contact_id INT         DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 524288) <> 524288 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_system required'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO org.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO org.org_core (created_at, entity_id, place_id, contact_entity_id, type)
  VALUES (now(), p_entity_id, p_place_id, p_contact_id, p_type);
  INSERT INTO org.org_identity (entity_id, name, slug)
  VALUES (p_entity_id, p_name, p_slug);
END;
$$;

-- Insertion d'une organisation dans la hiérarchie Nested Set
-- Verrouillage exclusif obligatoire : toute insertion décale les intervalles de tous
-- les nœuds à droite du point d'insertion — opération non concurrente par nature.
-- Garde : manage_system (524288) requis (opération structurelle sur la hiérarchie).
-- p_parent_entity_id NULL → organisation racine.
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
    SELECT COALESCE(MAX(rgt), 0) + 1 INTO v_new_lft FROM org.org_hierarchy;
    INSERT INTO org.org_hierarchy (entity_id, lft, rgt, depth)
    VALUES (p_entity_id, v_new_lft, v_new_lft + 1, 0);
  ELSE
    SELECT rgt INTO v_parent_rgt FROM org.org_hierarchy
    WHERE entity_id = p_parent_entity_id;
    IF v_parent_rgt IS NULL THEN
      RAISE EXCEPTION 'Organisation parente introuvable dans la hiérarchie (entity_id=%)', p_parent_entity_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    v_new_lft := v_parent_rgt;

    UPDATE org.org_hierarchy SET rgt = rgt + 2 WHERE rgt >= v_parent_rgt;
    UPDATE org.org_hierarchy SET lft = lft + 2 WHERE lft >= v_parent_rgt;

    INSERT INTO org.org_hierarchy (entity_id, lft, rgt, depth)
    SELECT p_entity_id, v_new_lft, v_new_lft + 1,
           (SELECT depth + 1 FROM org.org_hierarchy WHERE entity_id = p_parent_entity_id)
    FROM   org.org_hierarchy
    WHERE  entity_id = p_parent_entity_id;
  END IF;
END;
$$;


-- ==============================================================================
-- SECTION 12 : VUE org.v_organization
-- ==============================================================================

-- ORG : v_organization — schema.org/Organization (catalogue public)
-- Données légales (SIRET, DUNS, TVA) exclues de la projection :
--   org.org_legal est sous REVOKE SELECT pour marius_user. La vue étant owned par
--   postgres, elle pourrait techniquement joindre org_legal malgré le REVOKE —
--   mais exposer des identifiants légaux dans un catalogue public viole le principe
--   de moindre exposition. L'accès aux données légales passe par marius_admin.
-- Pas de filtre GUC : les organisations sont un catalogue global non multi-tenant.
--
-- Dépendance cross-schéma : geo.v_place (créée en 03_geo/02_systems.sql).
-- Cette dépendance de vue est résolue à l'exécution (pas à la création) —
-- le LEFT JOIN geo.v_place est valide même si la vue est définie après.
-- PostgreSQL valide les vues référencées à la création (pas en LAZY) :
-- geo.v_place doit donc exister avant ce fichier → ordre dans master_init.sql garanti
-- (03_geo chargé avant 04_org).
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
LEFT JOIN   geo.v_place         gp  ON gp.identifier = oc.place_id;
