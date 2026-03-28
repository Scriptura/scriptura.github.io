-- ==============================================================================
-- 10_mutation_interface.sql
-- Audit Interface de Mutation — Audit collision 2 (ADR-001 scellement)
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre :
--   A — Composants orphelins : nouvelles procédures présentes et SECURITY DEFINER
--   B — Invariants structurels : entity_id/document_id immuables (trigger)
--   C — Gardes bitwise des nouvelles procédures
--   D — Atomicité des nouvelles procédures (composants créés ensemble)
--   E — Composants low-risk documentés (accès direct marius_admin acceptable)
--
-- Exécution : psql -U postgres -d marius -f 10_mutation_interface.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(21);


-- ============================================================
-- A — Nouvelles procédures SECURITY DEFINER présentes
-- ============================================================

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'geo' AND p.proname = 'create_place' AND p.prokind = 'p'), false),
  'geo.create_place : SECURITY DEFINER présente (ADR-001 — composant orphelin corrigé)'
);

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'identity' AND p.proname = 'create_group' AND p.prokind = 'p'), false),
  'identity.create_group : SECURITY DEFINER présente (ADR-001)'
);

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'identity' AND p.proname = 'add_account_to_group' AND p.prokind = 'p'), false),
  'identity.add_account_to_group : SECURITY DEFINER présente (ADR-001)'
);

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'commerce' AND p.proname = 'create_product' AND p.prokind = 'p'), false),
  'commerce.create_product : SECURITY DEFINER présente (ADR-001 — composant orphelin corrigé)'
);

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'content' AND p.proname = 'create_media' AND p.prokind = 'p'), false),
  'content.create_media : SECURITY DEFINER présente (ADR-001 — composant orphelin corrigé)'
);

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'content' AND p.proname = 'add_media_to_document' AND p.prokind = 'p'), false),
  'content.add_media_to_document : SECURITY DEFINER présente (ADR-001)'
);

SELECT ok(
  COALESCE((SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'content' AND p.proname = 'remove_media_from_document' AND p.prokind = 'p'), false),
  'content.remove_media_from_document : SECURITY DEFINER présente (ADR-001)'
);


-- ============================================================
-- B — Immuabilité entity_id / document_id (invariants structurels)
-- ============================================================

CREATE TEMP TABLE _ids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'mut_iface_user', '$argon2id$v=19$m=65536$mi',
    'mut-iface-user', 7, 'fr_FR', v_id
  );
  INSERT INTO _ids VALUES ('entity_id', v_id);
END;
$$;

DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_document(
    (SELECT val FROM _ids WHERE key = 'entity_id'),
    'Doc Interface Audit', 'doc-interface-audit',
    0, 0, NULL, NULL, NULL, v_id
  );
  INSERT INTO _ids VALUES ('doc_id', v_id);
END;
$$;

-- B.1 : entity_id immuable sur identity.auth
SELECT throws_ok(
  format($$UPDATE identity.auth SET entity_id = -999 WHERE entity_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'entity_id')),
  '55000', NULL,
  'identity.auth : UPDATE entity_id rejeté → invariant ECS sub-type (ADR-001)'
);

-- B.2 : entity_id immuable sur identity.account_core
SELECT throws_ok(
  format($$UPDATE identity.account_core SET entity_id = -999 WHERE entity_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'entity_id')),
  '55000', NULL,
  'identity.account_core : UPDATE entity_id rejeté (ADR-001)'
);

-- B.3 : entity_id immuable sur identity.person_identity
-- Créer d'abord un enregistrement person_identity
INSERT INTO identity.person_identity (entity_id, given_name)
VALUES ((SELECT val FROM _ids WHERE key = 'entity_id'), 'Test');

SELECT throws_ok(
  format($$UPDATE identity.person_identity SET entity_id = -999 WHERE entity_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'entity_id')),
  '55000', NULL,
  'identity.person_identity : UPDATE entity_id rejeté (ADR-001)'
);

-- B.4 : document_id immuable sur content.core
SELECT throws_ok(
  format($$UPDATE content.core SET document_id = -999 WHERE document_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'doc_id')),
  '55000', NULL,
  'content.core : UPDATE document_id rejeté → invariant ECS sub-type (ADR-001)'
);

-- B.5 : id immuable sur commerce.transaction_core
DO $$
DECLARE v_org INT; v_txn INT;
BEGIN
  CALL org.create_organization('Org Test Inv', 'org-test-inv', 'company', NULL, NULL, v_org);
  CALL commerce.create_transaction(
    (SELECT val FROM _ids WHERE key = 'entity_id'), v_org, 978, 0, NULL, v_txn
  );
  INSERT INTO _ids VALUES ('txn_id', v_txn);
END;
$$;

SELECT throws_ok(
  format($$UPDATE commerce.transaction_core SET id = -999 WHERE id = %s$$,
    (SELECT val FROM _ids WHERE key = 'txn_id')),
  '55000', NULL,
  'commerce.transaction_core : UPDATE id rejeté → invariant structurel (ADR-001)'
);

-- B.6 : UPDATE nominal sur identity.auth (non entity_id) ne doit PAS être bloqué
CALL identity.record_login((SELECT val FROM _ids WHERE key = 'entity_id'));

SELECT ok(
  (SELECT last_login_at FROM identity.auth
   WHERE entity_id = (SELECT val FROM _ids WHERE key = 'entity_id')) IS NOT NULL,
  'identity.auth : UPDATE last_login_at non bloqué par trigger entity_id (clause WHEN ciblée)'
);


-- ============================================================
-- C — Gardes bitwise des nouvelles procédures
-- ============================================================

SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'entity_id'), true);
SELECT set_config('marius.auth_bits', '16384', true);  -- subscriber : aucun bit système
SET LOCAL ROLE marius_user;

-- C.1 : create_group requiert manage_groups (512)
SELECT throws_ok(
  $$CALL identity.create_group('HackerGroup')$$,
  '42501', NULL,
  'identity.create_group : subscriber rejeté sans manage_groups (512)'
);

-- C.2 : create_product requiert manage_commerce (262144)
SELECT throws_ok(
  $$CALL identity.create_product('FreeProduct','free-product',0,0,NULL)$$,
  '42501', NULL,
  'commerce.create_product : subscriber rejeté sans manage_commerce (262144)'
);

-- C.3 : create_media requiert upload_files (8192)
SELECT throws_ok(
  format($$CALL content.create_media(%s,'image/jpeg',NULL,'test.jpg',800,600,NULL,NULL,NULL)$$,
    (SELECT val FROM _ids WHERE key = 'entity_id')),
  '42501', NULL,
  'content.create_media : subscriber rejeté sans upload_files (8192)'
);

RESET ROLE;


-- ============================================================
-- D — Atomicité des nouvelles procédures
-- ============================================================

-- D.1 : create_product crée product_core + product_identity atomiquement
DO $$
DECLARE v_id INT;
BEGIN
  CALL commerce.create_product('Produit Interface', 'produit-interface', 1999, 10, NULL, v_id);
  INSERT INTO _ids VALUES ('product_id', v_id);
END;
$$;

SELECT ok(
  EXISTS (SELECT 1 FROM commerce.product_core WHERE id = (SELECT val FROM _ids WHERE key = 'product_id')),
  'create_product : product_core créé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM commerce.product_identity
    WHERE product_id = (SELECT val FROM _ids WHERE key = 'product_id')
      AND name = 'Produit Interface'),
  'create_product : product_identity créé (atomicité spine+composant)'
);

-- D.2 : create_group + add_account_to_group
DO $$
DECLARE v_gid INT;
BEGIN
  CALL identity.create_group('Groupe Test Interface', v_gid);
  INSERT INTO _ids VALUES ('group_id', v_gid);
  CALL identity.add_account_to_group(v_gid, (SELECT val FROM _ids WHERE key = 'entity_id'));
END;
$$;

SELECT ok(
  EXISTS (SELECT 1 FROM identity.group WHERE id = (SELECT val FROM _ids WHERE key = 'group_id')),
  'create_group : identity.group créé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM identity.group_to_account
    WHERE group_id = (SELECT val FROM _ids WHERE key = 'group_id')
      AND account_entity_id = (SELECT val FROM _ids WHERE key = 'entity_id')),
  'add_account_to_group : liaison group_to_account créée'
);


-- ============================================================
-- E — Composants low-risk documentés (permission_bit immuable)
-- ============================================================

-- permission_bit : REVOKE INSERT/UPDATE/DELETE empêche toute mutation applicative
SELECT throws_ok(
  $$INSERT INTO identity.permission_bit (bit_value, bit_index, name)
    VALUES (2097152, 21, 'test_bit')$$,
  '42501', NULL,
  'identity.permission_bit : INSERT rejeté (REVOKE PUBLIC + table immuable en production)'
);


SELECT * FROM finish();
ROLLBACK;
