-- ==============================================================================
-- 08_dcl/02_secdef.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : élévation SECURITY DEFINER + verrouillage SET search_path
--           sur toutes les procédures de mutation (section 14.3)
--
-- Mécanisme : la procédure s'exécute avec les droits de son propriétaire
-- (postgres), non ceux de l'appelant (marius_user).
-- SET search_path : neutralise l'injection de schéma via search_path de session.
-- Seconde ligne de défense : tous les noms d'objets dans les corps de procédures
-- sont entièrement qualifiés (schema.table), indépendamment du search_path.
--
-- Pré-requis : toutes les procédures des domaines 02–06 doivent exister.
-- Ordre interne : sans contrainte (ALTER PROCEDURE est idempotent sur les attributs).
-- ==============================================================================

-- ── IDENTITY ──────────────────────────────────────────────────────────────────

ALTER PROCEDURE identity.anonymize_person(integer)
    SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.create_account(
    character varying, character varying, character varying, smallint, character varying
) SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

-- create_person : OUT p_entity_id (integer) exclu de la signature ALTER PROCEDURE.
-- Paramètres IN effectifs : given_name, family_name, gender, nationality.
ALTER PROCEDURE identity.create_person(
    character varying, character varying, smallint, smallint
) SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.record_login(integer)
    SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.grant_permission(smallint, integer)
    SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.revoke_permission(smallint, integer)
    SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.create_group(character varying)
    SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';

ALTER PROCEDURE identity.add_account_to_group(integer, integer)
    SECURITY DEFINER SET search_path = 'identity', 'pg_catalog';


-- ── GEO ───────────────────────────────────────────────────────────────────────
-- 'public' retiré du search_path (ADR-001 v2.1) : les appels PostGIS sont
-- entièrement qualifiés (public.ST_SetSRID, public.ST_MakePoint) dans le corps.

ALTER PROCEDURE geo.create_place(
    character varying, smallint, smallint,
    double precision, double precision,
    smallint, character varying, character varying, character varying, character varying
) SECURITY DEFINER SET search_path = 'geo', 'identity', 'pg_catalog';


-- ── ORG ───────────────────────────────────────────────────────────────────────

ALTER PROCEDURE org.create_organization(
    character varying, character varying, character varying, integer, integer
) SECURITY DEFINER SET search_path = 'org', 'identity', 'pg_catalog';

ALTER PROCEDURE org.add_organization_to_hierarchy(integer, integer)
    SECURITY DEFINER SET search_path = 'org', 'identity', 'pg_catalog';


-- ── CONTENT ───────────────────────────────────────────────────────────────────
-- 'public' retiré du search_path sur create_document (ADR-001 v2.1) :
-- fn_slug_deduplicate est un trigger résolu par OID, pas par nom qualifié.
-- Aucun appel à une fonction public.* dans le corps.

ALTER PROCEDURE content.create_document(
    integer, character varying, character varying,
    smallint, smallint, text, character varying, character varying
) SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE content.publish_document(integer)
    SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.save_revision(integer, integer)
    SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.create_tag(character varying, character varying, integer)
    SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.add_tag_to_document(integer, integer)
    SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE content.remove_tag_from_document(integer, integer)
    SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE content.create_comment(integer, integer, text, integer, smallint)
    SECURITY DEFINER SET search_path = 'content', 'pg_catalog';

ALTER PROCEDURE content.create_media(
    integer, character varying, character varying, character varying,
    integer, integer, character varying, character varying, character varying
) SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE content.add_media_to_document(integer, integer, smallint)
    SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';

ALTER PROCEDURE content.remove_media_from_document(integer, integer)
    SECURITY DEFINER SET search_path = 'content', 'identity', 'pg_catalog';


-- ── COMMERCE ──────────────────────────────────────────────────────────────────

ALTER PROCEDURE commerce.create_product(
    character varying, character varying, bigint, integer, character varying
) SECURITY DEFINER SET search_path = 'commerce', 'identity', 'pg_catalog';

ALTER PROCEDURE commerce.create_transaction(integer, integer, smallint, smallint, text)
    SECURITY DEFINER SET search_path = 'commerce', 'identity', 'pg_catalog';

ALTER PROCEDURE commerce.create_transaction_item(integer, integer, integer)
    SECURITY DEFINER SET search_path = 'commerce', 'pg_catalog';
