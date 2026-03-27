-- ==============================================================================
-- 01_schema_and_security.sql
-- Tests structurels : types physiques, paramètres d'index, RBAC, triggers
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Ce fichier valide les invariants qui ne sont pas testables à la lecture
-- du code applicatif : topologie physique, verrouillage moteur, paramétrage
-- des structures d'index.
--
-- Exécution : psql -U postgres -d marius -f 01_schema_and_security.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(46);


-- ============================================================
-- EXTENSIONS
-- Leur absence rend silencieusement caduques les index GiST (ltree, postgis)
-- et les recherches trigrammes.
-- ============================================================

SELECT has_extension('unaccent', 'Extension unaccent présente');
SELECT has_extension('ltree',    'Extension ltree présente');
SELECT has_extension('pg_trgm', 'Extension pg_trgm présente');
SELECT has_extension('postgis',  'Extension postgis présente');


-- ============================================================
-- TYPES PHYSIQUES — INT8 pour les montants monétaires (ADR-022)
--
-- NUMERIC est varlena sans exception dans PostgreSQL (en-tête 4 B, arithmétique
-- émulée en base 10000, padding d'alignement forcé). INT8 est pass-by-value,
-- arithmétique ALU native, aligné sur 8 B comme TIMESTAMPTZ.
--
-- Si ces colonnes redeviennent NUMERIC (ex. après un ALTER TABLE non maîtrisé),
-- la densité de product_core et transaction_item est divisée par ~2 sans alerte.
-- ============================================================

SELECT col_type_is(
  'commerce', 'product_core', 'price_cents',
  'bigint',
  'product_core.price_cents : bigint, pas NUMERIC (ADR-022 — densité ×2)'
);

SELECT col_type_is(
  'commerce', 'product_core', 'stock',
  'integer',
  'product_core.stock : integer'
);

SELECT col_type_is(
  'commerce', 'transaction_item', 'unit_price_snapshot_cents',
  'bigint',
  'transaction_item.unit_price_snapshot_cents : bigint (ADR-022)'
);


-- ============================================================
-- TYPES PHYSIQUES — VARCHAR au lieu de CHAR(n) (ADR-022)
--
-- CHAR(n) dans PostgreSQL est varlena comme VARCHAR(n) — pas de stockage fixe.
-- Surcoût : padding espace à l'écriture + stripping à la lecture.
-- L'invariant de longueur est porté exclusivement par les contraintes CHECK.
-- ============================================================

SELECT col_type_is(
  'org', 'org_legal', 'duns',
  'character varying(9)',
  'org_legal.duns : character varying(9), pas bpchar (ADR-022)'
);

SELECT col_type_is(
  'org', 'org_legal', 'siret',
  'character varying(14)',
  'org_legal.siret : character varying(14), pas bpchar (ADR-022)'
);

SELECT col_type_is(
  'commerce', 'product_identity', 'isbn_ean',
  'character varying(13)',
  'product_identity.isbn_ean : character varying(13), pas bpchar (ADR-022)'
);

-- Balayage global : aucun bpchar ne doit subsister dans les cinq schémas métier.
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   information_schema.columns
    WHERE  table_schema IN ('identity', 'geo', 'org', 'commerce', 'content')
      AND  data_type    = 'character'   -- 'character' = bpchar dans information_schema
  ),
  'Aucune colonne CHAR(n) / bpchar dans les cinq schémas métier (ADR-022)'
);


-- ============================================================
-- ADR-021 — Colonnes de snapshot complètes dans content.revision
--
-- Ces colonnes ont été ajoutées suite à un audit : save_revision ne capturait
-- pas alternative_headline ni description. Un snapshot incomplet crée un
-- historique éditorial silencieusement faux.
-- ============================================================

SELECT has_column(
  'content', 'revision', 'snapshot_alternative_headline',
  'content.revision : colonne snapshot_alternative_headline présente (ADR-021)'
);

SELECT has_column(
  'content', 'revision', 'snapshot_description',
  'content.revision : colonne snapshot_description présente (ADR-021)'
);


-- ============================================================
-- INDEX BRIN — paramètre pages_per_range (ADR-017)
--
-- Un BRIN avec pages_per_range inadapté dégrade silencieusement l'efficacité
-- des requêtes temporelles (plus de blocs candidats chargés). Ces tests figent
-- les valeurs calibrées dans le blueprint — toute régression sera immédiatement
-- détectée.
-- ============================================================

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['pages_per_range=128']
     FROM   pg_class
     WHERE  relname = 'auth_created_at_brin'),
    false
  ),
  'BRIN identity.auth.created_at : pages_per_range = 128'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['pages_per_range=128']
     FROM   pg_class
     WHERE  relname = 'core_created_brin'),
    false
  ),
  'BRIN content.core.created_at : pages_per_range = 128'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['pages_per_range=128']
     FROM   pg_class
     WHERE  relname = 'transaction_created_brin'),
    false
  ),
  'BRIN commerce.transaction.created_at : pages_per_range = 128'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['pages_per_range=64']
     FROM   pg_class
     WHERE  relname = 'org_core_created_brin'),
    false
  ),
  'BRIN org.org_core.created_at : pages_per_range = 64'
);


-- ============================================================
-- SECURITY DEFINER — toutes les procédures de mutation (ADR-020)
--
-- Sans SECURITY DEFINER, une procédure hérite des droits de l'appelant
-- (marius_user), qui n'a pas de droits DML directs. Toute procédure sans
-- SECURITY DEFINER est donc non fonctionnelle pour le rôle applicatif.
-- Ce test détecte toute régression silencieuse après un ALTER PROCEDURE.
-- ============================================================

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'create_account' AND p.prokind = 'p'
  ), false),
  'identity.create_account : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'create_person' AND p.prokind = 'p'
  ), false),
  'identity.create_person : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'record_login' AND p.prokind = 'p'
  ), false),
  'identity.record_login : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'grant_permission' AND p.prokind = 'p'
  ), false),
  'identity.grant_permission : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'revoke_permission' AND p.prokind = 'p'
  ), false),
  'identity.revoke_permission : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'org' AND p.proname = 'create_organization' AND p.prokind = 'p'
  ), false),
  'org.create_organization : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'create_document' AND p.prokind = 'p'
  ), false),
  'content.create_document : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'publish_document' AND p.prokind = 'p'
  ), false),
  'content.publish_document : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'save_revision' AND p.prokind = 'p'
  ), false),
  'content.save_revision : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'create_comment' AND p.prokind = 'p'
  ), false),
  'content.create_comment : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'commerce' AND p.proname = 'create_transaction_item' AND p.prokind = 'p'
  ), false),
  'commerce.create_transaction_item : SECURITY DEFINER (ADR-020)'
);


-- ============================================================
-- RBAC — marius_user ne peut pas écrire directement (ADR-020)
--
-- Ces tests valident que l'invariant ECS est enforced au niveau moteur, pas
-- seulement documenté. Un INSERT/UPDATE/DELETE direct par le rôle applicatif
-- doit échouer avec SQLSTATE 42501 (insufficient_privilege).
--
-- Note : throws_ok exécute la requête avec les droits du rôle courant au
-- moment de l'appel. SET LOCAL ROLE est scoped à la transaction de test.
-- ============================================================

SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$INSERT INTO identity.entity DEFAULT VALUES$$,
  '42501',
  NULL,
  'marius_user : INSERT direct interdit sur identity.entity'
);

SELECT throws_ok(
  $$UPDATE identity.auth SET is_banned = false WHERE entity_id = -1$$,
  '42501',
  NULL,
  'marius_user : UPDATE direct interdit sur identity.auth'
);

SELECT throws_ok(
  $$DELETE FROM content.comment WHERE id = -1$$,
  '42501',
  NULL,
  'marius_user : DELETE direct interdit sur content.comment'
);

RESET ROLE;



SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'anonymize_person' AND p.prokind = 'p'
  ), false),
  'identity.anonymize_person : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'org' AND p.proname = 'add_organization_to_hierarchy' AND p.prokind = 'p'
  ), false),
  'org.add_organization_to_hierarchy : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'add_tag_to_document' AND p.prokind = 'p'
  ), false),
  'content.add_tag_to_document : SECURITY DEFINER (ADR-020)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'remove_tag_from_document' AND p.prokind = 'p'
  ), false),
  'content.remove_tag_from_document : SECURITY DEFINER (ADR-020)'
);

-- ============================================================
-- TRIGGERS modified_at — cohérence des métadonnées temporelles
--
-- L'absence d'un trigger laisse modified_at figé à NULL après mutation.
-- Le trigger media_core_modified_at a été ajouté suite à un audit (ADR-021) :
-- c'était la seule table mutable exposant modified_at sans trigger associé.
-- ============================================================

SELECT has_trigger(
  'identity', 'auth', 'auth_modified_at',
  'Trigger auth_modified_at présent sur identity.auth'
);

SELECT has_trigger(
  'content', 'core', 'content_core_modified_at',
  'Trigger content_core_modified_at présent sur content.core'
);

SELECT has_trigger(
  'content', 'media_core', 'media_core_modified_at',
  'Trigger media_core_modified_at présent sur content.media_core (ADR-021)'
);

SELECT has_trigger(
  'commerce', 'transaction', 'transaction_modified_at',
  'Trigger transaction_modified_at présent sur commerce.transaction'
);


SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'commerce' AND p.proname = 'create_transaction' AND p.prokind = 'p'
  ), false),
  'commerce.create_transaction : SECURITY DEFINER (ADR-020 + ADR-023)'
);

-- transaction_core, transaction_price, transaction_payment, transaction_delivery all exist
SELECT ok(
  (SELECT COUNT(*) FROM information_schema.tables
   WHERE  table_schema = 'commerce'
     AND  table_name   IN (
       'transaction_core','transaction_price',
       'transaction_payment','transaction_delivery'
     )
  ) = 4,
  'Quatre composants ECS de commande présents dans le schéma commerce (ADR-023)'
);

-- Bits 0-20 définis dans identity.permission_bit (ADR-027)
SELECT is(
  (SELECT COUNT(*)::INT FROM identity.permission_bit),
  21,
  'identity.permission_bit : 21 entrées (bits 0-20, ADR-027)'
);

-- Bit 20 (export_data = 1048576) présent
SELECT ok(
  EXISTS (SELECT 1 FROM identity.permission_bit WHERE bit_value = 1048576 AND bit_index = 20),
  'identity.permission_bit : export_data (bit 20 = 1048576) présent (ADR-027)'
);

-- content.tag ne doit plus avoir de colonne ltree path (ADR-026)
SELECT hasnt_column(
  'content', 'tag', 'path',
  'content.tag : colonne path ltree supprimée (ADR-026 — Closure Table)'
);

-- content.tag_hierarchy existe avec la PK composite attendue
SELECT has_table('content', 'tag_hierarchy', 'content.tag_hierarchy présente (ADR-026)');

-- create_tag : SECURITY DEFINER
SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'create_tag' AND p.prokind = 'p'
  ), false),
  'content.create_tag : SECURITY DEFINER (ADR-020 + ADR-026)'
);


SELECT * FROM finish();
ROLLBACK;
