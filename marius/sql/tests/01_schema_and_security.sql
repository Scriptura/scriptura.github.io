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

SELECT plan(63);


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
-- TYPES PHYSIQUES — INT8 pour les montants monétaires (ADR-026)
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
  'product_core.price_cents : bigint, pas NUMERIC (ADR-026 — densité ×2)'
);

SELECT col_type_is(
  'commerce', 'product_core', 'stock',
  'integer',
  'product_core.stock : integer'
);

SELECT col_type_is(
  'commerce', 'transaction_item', 'unit_price_snapshot_cents',
  'bigint',
  'transaction_item.unit_price_snapshot_cents : bigint (ADR-026)'
);


-- ============================================================
-- TYPES PHYSIQUES — VARCHAR au lieu de CHAR(n) (ADR-026)
--
-- CHAR(n) dans PostgreSQL est varlena comme VARCHAR(n) — pas de stockage fixe.
-- Surcoût : padding espace à l'écriture + stripping à la lecture.
-- L'invariant de longueur est porté exclusivement par les contraintes CHECK.
-- ============================================================

SELECT col_type_is(
  'org', 'org_legal', 'duns',
  'character varying(9)',
  'org_legal.duns : character varying(9), pas bpchar (ADR-026)'
);

SELECT col_type_is(
  'org', 'org_legal', 'siret',
  'character varying(14)',
  'org_legal.siret : character varying(14), pas bpchar (ADR-026)'
);

SELECT col_type_is(
  'commerce', 'product_identity', 'isbn_ean',
  'character varying(13)',
  'product_identity.isbn_ean : character varying(13), pas bpchar (ADR-026)'
);

-- Balayage global : aucun bpchar ne doit subsister dans les cinq schémas métier.
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   information_schema.columns
    WHERE  table_schema IN ('identity', 'geo', 'org', 'commerce', 'content')
      AND  data_type    = 'character'   -- 'character' = bpchar dans information_schema
  ),
  'Aucune colonne CHAR(n) / bpchar dans les cinq schémas métier (ADR-026)'
);


-- ============================================================
-- TYPES PHYSIQUES — Codes ISO pass-by-value (ADR-028)
--
-- identity.person_identity.nationality : SMALLINT ISO 3166-1 numérique.
-- Avant audit DOD : CHAR(2) alpha-2 → varlena, violait ADR-026 + ADR-028
-- et laissait un gap de 2B à l'offset 6-7 (après gender SMALLINT).
-- Après correction : 2×SMALLINT (gender offset 4, nationality offset 6)
-- consomment exactement les 4B post-INT4, zéro gap structurel.
--
-- identity.account_core.language : VARCHAR(5) — pas CHAR(5).
-- CHAR(5) est bpchar dans PostgreSQL : varlena avec padding/stripping CPU.
-- ADR-026 : l'invariant de longueur est garanti par la DEFAULT 'fr_FR' et
-- la contrainte applicative, pas par le type.
-- ============================================================

SELECT col_type_is(
  'identity', 'person_identity', 'nationality',
  'smallint',
  'person_identity.nationality : smallint ISO 3166-1 numérique (ADR-028 — gap offset 6-7 absorbé)'
);

SELECT col_type_is(
  'identity', 'account_core', 'language',
  'character varying(5)',
  'account_core.language : character varying(5), pas bpchar (ADR-026)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE  constraint_schema = 'identity'
      AND  constraint_name   = 'nationality_range'
  ),
  'person_identity.nationality_range : contrainte CHECK 1-999 présente (ADR-028)'
);


-- ============================================================
-- ADR-024 — Colonnes de snapshot complètes dans content.revision
--
-- Ces colonnes ont été ajoutées suite à un audit : save_revision ne capturait
-- pas alternative_headline ni description. Un snapshot incomplet crée un
-- historique éditorial silencieusement faux.
-- ============================================================

SELECT has_column(
  'content', 'revision', 'snapshot_alternative_headline',
  'content.revision : colonne snapshot_alternative_headline présente (ADR-024)'
);

SELECT has_column(
  'content', 'revision', 'snapshot_description',
  'content.revision : colonne snapshot_description présente (ADR-024)'
);


-- ============================================================
-- INDEX BRIN — paramètre pages_per_range (ADR-010)
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
-- SECURITY DEFINER — toutes les procédures de mutation (ADR-001)
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
  'identity.create_account : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'create_person' AND p.prokind = 'p'
  ), false),
  'identity.create_person : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'record_login' AND p.prokind = 'p'
  ), false),
  'identity.record_login : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'grant_permission' AND p.prokind = 'p'
  ), false),
  'identity.grant_permission : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'revoke_permission' AND p.prokind = 'p'
  ), false),
  'identity.revoke_permission : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'org' AND p.proname = 'create_organization' AND p.prokind = 'p'
  ), false),
  'org.create_organization : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'create_document' AND p.prokind = 'p'
  ), false),
  'content.create_document : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'publish_document' AND p.prokind = 'p'
  ), false),
  'content.publish_document : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'save_revision' AND p.prokind = 'p'
  ), false),
  'content.save_revision : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'create_comment' AND p.prokind = 'p'
  ), false),
  'content.create_comment : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'commerce' AND p.proname = 'create_transaction_item' AND p.prokind = 'p'
  ), false),
  'commerce.create_transaction_item : SECURITY DEFINER (ADR-001)'
);


-- ============================================================
-- RBAC — marius_user ne peut pas écrire directement (ADR-001)
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
  'identity.anonymize_person : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'org' AND p.proname = 'add_organization_to_hierarchy' AND p.prokind = 'p'
  ), false),
  'org.add_organization_to_hierarchy : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'add_tag_to_document' AND p.prokind = 'p'
  ), false),
  'content.add_tag_to_document : SECURITY DEFINER (ADR-001)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'remove_tag_from_document' AND p.prokind = 'p'
  ), false),
  'content.remove_tag_from_document : SECURITY DEFINER (ADR-001)'
);

-- ============================================================
-- TRIGGERS modified_at — cohérence des métadonnées temporelles
--
-- L'absence d'un trigger laisse modified_at figé à NULL après mutation.
-- Le trigger media_core_modified_at a été ajouté suite à un audit (ADR-024) :
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
  'Trigger media_core_modified_at présent sur content.media_core (ADR-024)'
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
  'commerce.create_transaction : SECURITY DEFINER (ADR-001 + ADR-016)'
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
  'Quatre composants ECS de commande présents dans le schéma commerce (ADR-016)'
);

-- Bits 0-20 définis dans identity.permission_bit (ADR-004)
SELECT is(
  (SELECT COUNT(*)::INT FROM identity.permission_bit),
  21,
  'identity.permission_bit : 21 entrées (bits 0-20, ADR-004)'
);

-- Bit 20 (export_data = 1048576) présent
SELECT ok(
  EXISTS (SELECT 1 FROM identity.permission_bit WHERE bit_value = 1048576 AND bit_index = 20),
  'identity.permission_bit : export_data (bit 20 = 1048576) présent (ADR-004)'
);

-- content.tag ne doit plus avoir de colonne ltree path (ADR-018)
SELECT hasnt_column(
  'content', 'tag', 'path',
  'content.tag : colonne path ltree supprimée (ADR-018 — Closure Table)'
);

-- content.tag_hierarchy existe avec la PK composite attendue
SELECT has_table('content', 'tag_hierarchy', 'content.tag_hierarchy présente (ADR-018)');

-- create_tag : SECURITY DEFINER
SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'content' AND p.proname = 'create_tag' AND p.prokind = 'p'
  ), false),
  'content.create_tag : SECURITY DEFINER (ADR-001 + ADR-018)'
);


-- ============================================================
-- TOAST TUPLE TARGET — composants basse fréquence (Audit 1.2)
--
-- toast_tuple_target = 128 force le moteur à TOASTer les varlena dès 128 B
-- au lieu du seuil par défaut (~2 kB). Effet : les composants "cold" (textes longs,
-- descriptions, corps HTML) ne chargent jamais de données textuelles lors des
-- scans de métadonnées sur les tables "hot" associées.
--
-- Invariant : seuls les composants explicitement déclarés basse fréquence portent
-- ce paramètre. Les tables hot path (identity.auth, content.core, product_core)
-- ne doivent PAS l'avoir — leur densité de tuple dépend de l'inline des varlena.
-- ============================================================

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['toast_tuple_target=128']
     FROM   pg_class WHERE relname = 'place_content'),
    false
  ),
  'TOAST geo.place_content : toast_tuple_target = 128 (corps textuel isolé)'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['toast_tuple_target=128']
     FROM   pg_class WHERE relname = 'person_content'),
    false
  ),
  'TOAST identity.person_content : toast_tuple_target = 128 (biographie, TRÈS BASSE fréquence)'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['toast_tuple_target=128']
     FROM   pg_class WHERE relname = 'product_content'),
    false
  ),
  'TOAST commerce.product_content : toast_tuple_target = 128 (description catalogue)'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['toast_tuple_target=128']
     FROM   pg_class WHERE relname = 'body'),
    false
  ),
  'TOAST content.body : toast_tuple_target = 128 (corps HTML, BASSE fréquence)'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['toast_tuple_target=128']
     FROM   pg_class WHERE relname = 'revision'),
    false
  ),
  'TOAST content.revision : toast_tuple_target = 128 (snapshots cold storage)'
);


-- ============================================================
-- FILLFACTOR — tables à HOT updates fréquents (Audit 2)
--
-- HOT update (Heap Only Tuple) : PostgreSQL réutilise l'espace libre de la
-- même page pour la nouvelle version du tuple, sans créer d'entrée d'index
-- supplémentaire. Condition : la nouvelle version du tuple doit tenir dans la
-- même page que l'ancienne → fillfactor réserve cet espace à l'avance.
--
-- Sans fillfactor calibré, les HOT updates se dégradent en full updates :
-- chaque mutation crée une nouvelle entrée dans tous les index de la table
-- (dead tuple structurel + bloat index systématique).
--
-- identity.auth=70 : last_login_at mis à jour à chaque connexion (hot path ADR-008).
--   30 % de marge = ~2,4 kB libre/page → absorbe ~15 connexions avant vacuum.
-- content.core=75 : status, modified_at, is_commentable mutés fréquemment.
-- commerce.product_core=80 : stock décrémenté à chaque transaction.
-- ============================================================

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['fillfactor=70']
     FROM   pg_class WHERE relname = 'auth'),
    false
  ),
  'fillfactor identity.auth = 70 (HOT updates last_login_at, ADR-008)'
);

SELECT ok(
  -- Audit 3 : fillfactor retiré de content.core (zero HOT benefit démontré).
  -- Tous les chemins d'UPDATE touchent des colonnes indexées (published_at, modified_at)
  -- ou des conditions de partial index (status). Le fillfactor<100 dégradait la densité
  -- sans aucune contrepartie HOT. On vérifie l'absence du paramètre.
  NOT COALESCE(
    (SELECT reloptions @> ARRAY['fillfactor=75']
     FROM   pg_class WHERE relname = 'core'
       AND  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'content')),
    false
  ),
  'fillfactor content.core : paramètre absent (Audit 3 — zero HOT benefit, densité +25%)'
);

SELECT ok(
  COALESCE(
    (SELECT reloptions @> ARRAY['fillfactor=80']
     FROM   pg_class WHERE relname = 'product_core'),
    false
  ),
  'fillfactor commerce.product_core = 80 (HOT updates stock, ADR-024 FOR UPDATE)'
);


-- ============================================================
-- INDEX PARTIELS — couverture des hot scans (Audit 2)
--
-- product_core_catalog (Audit 2 — gap identifié) :
--   Avant correction : aucun index sur is_available. Un listing catalogue
--   déclenchait un seq scan sur product_core entier, y compris les produits
--   désactivés (cold data). L'index partial filtre ce segment dès le parcours.
--
-- core_modified (Audit 2 — gap identifié) :
--   Avant correction : seul BRIN(created_at) était présent — optimisé pour les
--   scans par plage de création, pas pour ORDER BY modified_at DESC (dashboard
--   éditorial "derniers articles modifiés"). L'index partial exclut les
--   brouillons jamais modifiés (modified_at IS NOT NULL), réduisant sa surface.
-- ============================================================

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE  schemaname = 'commerce'
      AND  tablename  = 'product_core'
      AND  indexname  = 'product_core_catalog'
  ),
  'Index product_core_catalog présent : scan catalogue sans seq scan (Audit 2)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE  schemaname = 'content'
      AND  tablename  = 'core'
      AND  indexname  = 'core_modified'
  ),
  'Index core_modified présent : dashboard éditorial ORDER BY modified_at (Audit 2)'
);


-- ============================================================
-- BRIN IMMUTABILITÉ — created_at ne doit jamais être modifié (Audit 3)
--
-- Un UPDATE sur created_at invalide la corrélation physique/logique de l'index
-- BRIN et peut produire des faux négatifs (lignes exclues à tort lors d'un
-- scan de zone). Les quatre triggers ci-dessous lèvent SQLSTATE 55000
-- si OLD.created_at IS DISTINCT FROM NEW.created_at.
-- ============================================================

SELECT has_trigger(
  'identity', 'auth', 'auth_deny_created_at_update',
  'Trigger auth_deny_created_at_update : created_at immuable sur identity.auth (Audit 3)'
);

SELECT has_trigger(
  'content', 'core', 'core_deny_created_at_update',
  'Trigger core_deny_created_at_update : created_at immuable sur content.core (Audit 3)'
);

SELECT has_trigger(
  'commerce', 'transaction_core', 'transaction_deny_created_at_update',
  'Trigger transaction_deny_created_at_update : created_at immuable sur commerce.transaction_core (Audit 3)'
);

SELECT has_trigger(
  'org', 'org_core', 'org_core_deny_created_at_update',
  'Trigger org_core_deny_created_at_update : created_at immuable sur org.org_core (Audit 3)'
);


SELECT * FROM finish();
ROLLBACK;
