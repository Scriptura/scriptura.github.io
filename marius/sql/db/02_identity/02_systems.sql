-- ==============================================================================
-- 02_identity/02_systems.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : fonctions partagées · triggers identity · procédures identity
--           · helpers RLS (GUC) · vues identity
--
-- NOTE sur les fonctions partagées cross-schéma :
--   fn_update_modified_at(), fn_deny_created_at_update(), fn_deny_entity_id_update()
--   sont définies ici (schéma identity) mais utilisées comme trigger functions
--   sur des tables d'autres domaines. Les CREATE TRIGGER correspondants sont dans
--   les fichiers systems de chaque domaine concerné :
--     content.core / content.media_core → 05_content/02_systems.sql
--     commerce.transaction_core         → 06_commerce/02_systems.sql
--     org.org_core                      → 04_org/02_systems.sql
--
-- NOTE sur les triggers d'audit cross-schéma :
--   audit_commerce_transaction_core / audit_commerce_transaction_item /
--   audit_commerce_transaction_payment → 06_commerce/02_systems.sql
-- ==============================================================================


-- ==============================================================================
-- SECTION 8b suite : FONCTIONS D'AUDIT (Shadow Write Detection — ADR-001 rev.)
-- ==============================================================================

-- Fonction de trigger d'audit (AFTER, chaque ligne)
-- session_user : rôle de connexion TCP — non spoofable via SET ROLE.
-- current_user : rôle effectif (postgres pour une procédure SECURITY DEFINER).
-- Un shadow write se distingue : session_user = 'marius_user' ET current_user = 'marius_user'.
CREATE FUNCTION identity.fn_dml_audit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'identity', 'pg_catalog' AS $$
BEGIN
  INSERT INTO identity.dml_audit_log
    (db_session_user, db_current_user, schema_name, table_name, operation, row_pk)
  VALUES (
    session_user::varchar(64),
    current_user::varchar(64),
    TG_TABLE_SCHEMA,
    TG_TABLE_NAME,
    TG_OP,
    CASE TG_OP
      WHEN 'DELETE' THEN row_to_json(OLD)::text
      ELSE               row_to_json(NEW)::text
    END
  );
  RETURN NULL;  -- AFTER trigger : valeur de retour ignorée
END;
$$;

-- Déploiement du trigger d'audit sur les tables identity
CREATE TRIGGER audit_identity_auth
AFTER INSERT OR UPDATE OR DELETE ON identity.auth
FOR EACH ROW EXECUTE FUNCTION identity.fn_dml_audit();

CREATE TRIGGER audit_identity_entity
AFTER INSERT OR UPDATE OR DELETE ON identity.entity
FOR EACH ROW EXECUTE FUNCTION identity.fn_dml_audit();

CREATE TRIGGER audit_identity_account_core
AFTER INSERT OR UPDATE OR DELETE ON identity.account_core
FOR EACH ROW EXECUTE FUNCTION identity.fn_dml_audit();

-- Les triggers audit sur commerce.transaction_core / transaction_item /
-- transaction_payment sont dans 06_commerce/02_systems.sql.


-- ==============================================================================
-- SECTION 8c : VUES DE SURVEILLANCE — ADR-001 rev.
-- ==============================================================================

-- Sessions actives de marius_admin (toute ligne en production = anomalie)
CREATE VIEW identity.v_admin_sessions AS
SELECT
  pid,
  usename          AS connected_as,
  application_name,
  client_addr,
  backend_start,
  state,
  query_start,
  left(query, 120) AS query_preview
FROM pg_stat_activity
WHERE usename = 'marius_admin'
  AND pid <> pg_backend_pid();

COMMENT ON VIEW identity.v_admin_sessions IS
  'Sessions actives de marius_admin. Toute ligne en production normale est une anomalie. ADR-001.';

-- Shadow writes détectés : session_user = current_user = marius_user
CREATE VIEW identity.v_shadow_writes AS
SELECT
  logged_at,
  schema_name,
  table_name,
  operation,
  row_pk
FROM identity.dml_audit_log
WHERE db_session_user = 'marius_user'
  AND db_current_user = 'marius_user'
ORDER BY logged_at DESC;

COMMENT ON VIEW identity.v_shadow_writes IS
  'DML émis directement par marius_user, hors procédures SECURITY DEFINER. Toute ligne est une violation ADR-001.';


-- ==============================================================================
-- SECTION 9 : FONCTIONS PARTAGÉES (définies avant les triggers qui les référencent)
-- ==============================================================================

-- Fonction partagée : mise à jour du champ modified_at
-- Utilisée cross-schéma : identity.auth, content.core, content.media_core,
-- commerce.transaction_core, org.org_core.
-- Les CREATE TRIGGER sur les tables hors identity sont dans les fichiers
-- systems de chaque domaine.
CREATE FUNCTION identity.fn_update_modified_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.modified_at = now();
  RETURN NEW;
END;
$$;

-- Garde d'immuabilité de created_at (Audit 3 — ADR-010 rev.)
-- Contexte : created_at est la colonne de séquençage des index BRIN sur les tables
-- suivantes : identity.auth, content.core, commerce.transaction_core, org.org_core.
-- Un index BRIN perd son invariant structural si created_at est modifié après INSERT.
-- Clause WHEN ciblée dans chaque trigger : coût nul sur les UPDATE nominaux.
CREATE FUNCTION identity.fn_deny_created_at_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'created_at is immutable on %.%: BRIN index correlation would be invalidated (Audit 3 — ADR-010)',
    TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$$;

-- Garde d'immuabilité de entity_id / document_id / id (invariant ECS — ADR-001 rev.)
-- entity_id est la FK vers le spine identity.entity. C'est l'invariant de
-- sous-type ECS : chaque composant est défini par son appartenance au spine.
-- Un UPDATE entity_id après l'INSERT briserait cette appartenance et
-- produirait silencieusement un composant orphelin ou mal attaché.
CREATE FUNCTION identity.fn_deny_entity_id_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'entity_id is immutable on %.%: it is the ECS sub-type key and cannot be reassigned (ADR-001)',
    TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = '55000';
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

-- Helpers GUC RLS — définis ici car référencés par les vues (section 12)
-- ET les politiques RLS (section 15). PostgreSQL valide les références de
-- fonctions à la création des vues — elles doivent exister avant.
-- STABLE : retourne la même valeur pour toutes les lignes d'un même statement.
-- SECURITY INVOKER : pas besoin d'élévation pour lire un GUC de session.
CREATE FUNCTION identity.rls_user_id()
RETURNS INT LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT COALESCE(current_setting('marius.user_id', true)::INT, -1);
$$;

CREATE FUNCTION identity.rls_auth_bits()
RETURNS INT LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT COALESCE(current_setting('marius.auth_bits', true)::INT, 0);
$$;


-- ==============================================================================
-- SECTION 10 : TRIGGERS — tables identity uniquement
-- ==============================================================================

-- AUTH : modified_at sur changement de rôle/statut/password uniquement
-- WHEN clause : évite de déclencher à chaque record_login (hot path)
CREATE TRIGGER auth_modified_at
BEFORE UPDATE ON identity.auth
FOR EACH ROW WHEN (
  OLD.password_hash IS DISTINCT FROM NEW.password_hash OR
  OLD.role_id       IS DISTINCT FROM NEW.role_id       OR
  OLD.is_banned     IS DISTINCT FROM NEW.is_banned
) EXECUTE FUNCTION identity.fn_update_modified_at();

-- ACCOUNT CORE : déduplication de slug
CREATE TRIGGER account_slug_dedup
BEFORE INSERT OR UPDATE OF slug ON identity.account_core
FOR EACH ROW EXECUTE FUNCTION public.fn_slug_deduplicate();

-- BRIN IMMUTABILITY — identity.auth
CREATE TRIGGER auth_deny_created_at_update
BEFORE UPDATE ON identity.auth
FOR EACH ROW WHEN (OLD.created_at IS DISTINCT FROM NEW.created_at)
EXECUTE FUNCTION identity.fn_deny_created_at_update();

-- IMMUABILITÉ entity_id — composants identity
CREATE TRIGGER auth_deny_entity_id_update
BEFORE UPDATE ON identity.auth
FOR EACH ROW WHEN (OLD.entity_id IS DISTINCT FROM NEW.entity_id)
EXECUTE FUNCTION identity.fn_deny_entity_id_update();

CREATE TRIGGER account_core_deny_entity_id_update
BEFORE UPDATE ON identity.account_core
FOR EACH ROW WHEN (OLD.entity_id IS DISTINCT FROM NEW.entity_id)
EXECUTE FUNCTION identity.fn_deny_entity_id_update();

CREATE TRIGGER person_identity_deny_entity_id_update
BEFORE UPDATE ON identity.person_identity
FOR EACH ROW WHEN (OLD.entity_id IS DISTINCT FROM NEW.entity_id)
EXECUTE FUNCTION identity.fn_deny_entity_id_update();

-- Les triggers BRIN/entity_id sur content.core, commerce.transaction_core,
-- org.org_core sont dans les fichiers systems de chaque domaine.


-- ==============================================================================
-- SECTION 11 : PROCÉDURES D'ÉCRITURE identity
-- (SECURITY DEFINER + SET search_path appliqués en 08_dcl/02_secdef.sql)
-- ==============================================================================

-- Création d'un compte (entity + auth + account_core)
CREATE PROCEDURE identity.create_account(
  p_username      VARCHAR(32),
  p_password_hash VARCHAR(255),
  p_slug          VARCHAR(32),
  OUT p_entity_id INT,
  p_role_id       SMALLINT DEFAULT 7,
  p_language      VARCHAR(5) DEFAULT 'fr_FR'
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND p_role_id <> 7
     AND (identity.rls_auth_bits() & 256) <> 256 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_users required to assign non-default role (role_id=%)', p_role_id
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO identity.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO identity.auth (created_at, entity_id, role_id, is_banned, password_hash)
  VALUES (now(), p_entity_id, p_role_id, false, p_password_hash);
  INSERT INTO identity.account_core (entity_id, is_visible, is_private_message, display_mode, username, slug, language)
  VALUES (p_entity_id, true, false, 0, p_username, p_slug, p_language);
END;
$$;

-- Création d'une personne (entity + person_identity)
CREATE PROCEDURE identity.create_person(
  OUT p_entity_id INT,
  p_given_name  VARCHAR(32) DEFAULT NULL,
  p_family_name VARCHAR(32) DEFAULT NULL,
  p_gender      SMALLINT    DEFAULT NULL,
  p_nationality SMALLINT    DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 256) <> 256 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_users required to create a person entity'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO identity.entity DEFAULT VALUES RETURNING id INTO p_entity_id;
  INSERT INTO identity.person_identity (entity_id, given_name, family_name, gender, nationality)
  VALUES (p_entity_id, p_given_name, p_family_name, p_gender, p_nationality);
END;
$$;

-- Anonymisation RGPD d'une personne physique (ADR-017)
-- Opération irréversible. Préserve le spine pour l'intégrité des FK commerce.
CREATE PROCEDURE identity.anonymize_person(p_entity_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND p_entity_id <> identity.rls_user_id()
     AND (identity.rls_auth_bits() & 256) <> 256 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_users required to anonymize another entity'
      USING ERRCODE = '42501';
  END IF;
  UPDATE identity.entity SET anonymized_at = now() WHERE id = p_entity_id;
  UPDATE identity.person_identity
  SET    given_name = NULL, family_name = NULL, usual_name = NULL,
         nickname   = NULL, prefix      = NULL, suffix     = NULL,
         additional_name = NULL, gender = NULL, nationality = NULL
  WHERE  entity_id = p_entity_id;
  UPDATE identity.person_contact
  SET    email = NULL, phone = NULL, phone2 = NULL, fax = NULL, url = NULL
  WHERE  entity_id = p_entity_id;
  UPDATE identity.person_biography
  SET    birth_date = NULL, death_date = NULL,
         birth_place_id = NULL, death_place_id = NULL
  WHERE  entity_id = p_entity_id;
  UPDATE identity.person_content
  SET    occupation = NULL, bias = NULL, hobby = NULL, award = NULL,
         devise = NULL, description = NULL, media_id = NULL
  WHERE  entity_id = p_entity_id;
  UPDATE identity.account_core
  SET    username = 'user_' || p_entity_id::text,
         slug     = 'user-' || p_entity_id::text
  WHERE  entity_id = p_entity_id;
  UPDATE identity.auth
  SET    password_hash = 'ANONYMIZED',
         is_banned     = true
  WHERE  entity_id = p_entity_id;
  DELETE FROM identity.group_to_account WHERE account_entity_id = p_entity_id;
  -- Dissociation des contenus éditoriaux (Audit 4 — ADR-017 gap)
  UPDATE content.core    SET author_entity_id = NULL WHERE author_entity_id = p_entity_id;
  UPDATE content.revision SET author_entity_id = NULL WHERE author_entity_id = p_entity_id;
  UPDATE content.media_core SET author_id = NULL WHERE author_id = p_entity_id;
  UPDATE content.comment SET account_entity_id = NULL WHERE account_entity_id = p_entity_id;
END;
$$;

-- Enregistrement d'une connexion (hot path — LANGUAGE sql pour inlining)
CREATE PROCEDURE identity.record_login(p_entity_id INT)
LANGUAGE sql AS $$
  UPDATE identity.auth SET last_login_at = now() WHERE entity_id = p_entity_id;
$$;

-- Ajout/révocation de permission sur un rôle
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

-- Création d'un groupe
CREATE PROCEDURE identity.create_group(
  p_name        VARCHAR(32),
  OUT p_group_id INT
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 512) <> 512 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_groups required to create a group'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO identity.group (name) VALUES (p_name) RETURNING id INTO p_group_id;
END;
$$;

-- Ajout d'un compte dans un groupe
CREATE PROCEDURE identity.add_account_to_group(p_group_id INT, p_account_entity_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 512) <> 512 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_groups required'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO identity.group_to_account (group_id, account_entity_id)
  VALUES (p_group_id, p_account_entity_id)
  ON CONFLICT DO NOTHING;
END;
$$;


-- ==============================================================================
-- SECTION 12 : VUES identity
-- ==============================================================================

-- v_role — décompose le bitmask en colonnes booléennes nommées (bits 0–20)
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

-- v_auth — hot path authentification
-- REVOKE SELECT sur identity.auth (marius_user) appliqué en 08_dcl/01_grants.sql.
CREATE VIEW identity.v_auth AS
SELECT a.entity_id, a.password_hash, a.is_banned, a.role_id,
  r.name AS role_name, r.permissions AS role_permissions
FROM identity.auth a JOIN identity.role r ON r.id = a.role_id;

-- v_account — schema.org/Person (compte utilisateur)
-- WHERE GUC miroir de rls_account_select (ADR-003 invariant 2 révisé).
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
  ac.entity_id = identity.rls_user_id()
  OR (identity.rls_auth_bits() & 256) = 256
);

-- v_person — schema.org/Person (profil public)
-- Colonnes PII retirées de la projection (audit RLS global) :
--   email, phone, fax — exposés uniquement via marius_admin ou SECURITY DEFINER.
--   url (site web) conservé : donnée de contact intentionnellement publique.
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

-- GRANT EXECUTE sur les helpers RLS (lecture des GUC uniquement)
-- Appliqué ici car nécessaire avant que marius_user puisse accéder aux politiques RLS.
-- Le GRANT EXECUTE global de la section 13 (08_dcl/01_grants.sql) couvrira aussi
-- ces fonctions — cette ligne est explicite pour la traçabilité architecturale.
GRANT EXECUTE ON FUNCTION identity.rls_user_id()   TO marius_user;
GRANT EXECUTE ON FUNCTION identity.rls_auth_bits() TO marius_user;
