-- ==============================================================================
-- 06_rls_policies.sql
-- Tests fonctionnels : Row-Level Security — Pattern GUC Stateless (ADR-002/029)
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Stratégie : chaque scénario suit le cycle
--   1. SET LOCAL marius.user_id / marius.auth_bits (injection GUC middleware)
--   2. SET LOCAL ROLE marius_user (on se place dans le contexte applicatif)
--   3. assertion via is() / ok() / throws_ok()
--   4. RESET ROLE entre chaque scénario
--
-- Prérequis : master_schema_ddl.pgsql exécuté + seed DML chargé
--   (les entités 1-8 et les documents 1-16 doivent exister)
--
-- Exécution : psql -U postgres -d marius -f tests/06_rls_policies.sql
--
-- Révisions :
--   ADR-003 — A4  : auth_bits corrigé (59430→124990, moderator)
--             A8  : éditeur voit brouillon d'autrui via edit_others_contents (32768)
--             A9  : auteur DELETE son propre contenu via delete_contents (8)
--             A10 : subscriber ne peut pas DELETE le contenu d'autrui
--             B4  : gestionnaire manage_commerce sans view_transactions peut UPDATE
--             D4  : REVOKE SELECT commerce.transaction_price
--             D5  : REVOKE SELECT commerce.transaction_item
--             D6  : REVOKE SELECT content.identity
--             D7  : REVOKE SELECT content.body
--             D8  : REVOKE SELECT content.revision
--   ADR-001 rev. — E1-E4 : gardes d'autorisation dans procédures SECURITY DEFINER
--   ADR-002 rev. — F1-F4 : RLS content.comment
--   ADR-003 inv.2 — G1-G3 : WHERE GUC dans vues (security context postgres/BYPASSRLS)
--   ADR-003 inv.3 — G4   : save_revision ownership check
--   ADR-001 rev. — H1-H4 : add_tag_to_document / remove_tag_from_document
--   Audit org   — I1-I5 : schéma org (REVOKE legal, guard create_organization, hiérarchie)
--   Perm audit  — moderator 124990→124990 (+manage_tags=2048)
--   Audit RLS global — J1-J3 : v_auth REVOKE, v_person no PII, content_to_tag gap note
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(48);


-- ============================================================
-- SECTION A — content.core
-- Document 7 (auteur = entity_id 1, status = 1 = publié)
-- ============================================================

-- ── A1 : article publié visible sans aucun GUC positionné
-- Simule une connexion anonyme : user_id et auth_bits non définis.
-- status = 1 → visible pour tous (premier critère de la politique).
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 7) = 1,
  'RLS content.core : article publié (status=1) visible sans GUC (accès anonyme)'
);

RESET ROLE;


-- ── A2 : brouillon de l'auteur visible par l'auteur lui-même
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '24622', true);   -- author (ADR-003 : +delete_contents)
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core
   WHERE document_id = 7 AND author_entity_id = 1) = 1,
  'RLS content.core : auteur (entity_id=1) voit son propre article'
);

RESET ROLE;


-- ── A3 : subscriber ne voit pas les brouillons d'autrui
INSERT INTO content.document (id) OVERRIDING SYSTEM VALUE VALUES (9999);
INSERT INTO content.core
  (published_at, created_at, document_id, author_entity_id, status)
VALUES (NULL, now(), 9999, 1, 0);   -- brouillon, auteur = entity_id 1

SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true); -- subscriber : can_read uniquement
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 9999) = 0,
  'RLS content.core : subscriber (entity_id=5) ne voit pas le brouillon d''autrui'
);

RESET ROLE;


-- ── A4 : modérateur avec publish_contents(16) voit les brouillons
-- auth_bits = 124990 (moderator) : 124990 & 16 = 16 → critère publish_contents satisfait.
-- Le scénario éditeur (bit 32768 sans bit 16) est couvert par A8.
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '124990', true);  -- moderator
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 9999) = 1,
  'RLS content.core : moderator (publish_contents=16) voit le brouillon'
);

RESET ROLE;


-- ── A5 : auteur peut UPDATE son propre contenu (edit_contents requis)
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '24622', true);  -- author
SET LOCAL ROLE marius_user;

SELECT lives_ok(
  $$UPDATE content.core SET is_commentable = false WHERE document_id = 9999$$,
  'RLS content.core : auteur peut UPDATE son propre contenu (edit_contents présent)'
);

RESET ROLE;


-- ── A6 : subscriber ne peut pas UPDATE le contenu d'autrui (0 lignes, pas d'erreur)
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT is(
  (WITH upd AS (
    UPDATE content.core SET is_commentable = true
    WHERE  document_id = 9999
    RETURNING document_id
  ) SELECT COUNT(*)::INT FROM upd),
  0,
  'RLS content.core : subscriber ne peut pas UPDATE le contenu d''autrui (0 lignes)'
);

RESET ROLE;


-- ── A7 : modérateur avec edit_others_contents peut UPDATE n'importe quel contenu
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '124990', true);  -- moderator
SET LOCAL ROLE marius_user;

SELECT is(
  (WITH upd AS (
    UPDATE content.core SET is_commentable = false
    WHERE  document_id = 9999
    RETURNING document_id
  ) SELECT COUNT(*)::INT FROM upd),
  1,
  'RLS content.core : moderator (edit_others_contents=32768) peut UPDATE n''importe quel contenu'
);

RESET ROLE;


-- ── A8 : éditeur (edit_others_contents=32768, sans publish_contents) voit les brouillons d'autrui
-- ADR-003 invariant 3 : rls_core_select inclut le bit 32768.
-- editor (59438) : 59438 & 16 = 0 (publish_contents absent)
--                  59438 & 32768 = 32768 (edit_others_contents présent)
-- Sans ce critère dans SELECT, les politiques UPDATE/DELETE d'éditeur sont inatteignables.
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '59438', true);   -- editor
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 9999) = 1,
  'RLS content.core : editor (edit_others_contents=32768, sans publish_contents) voit le brouillon d''autrui'
);

RESET ROLE;


-- ── A9 : auteur peut DELETE son propre contenu (delete_contents=8 requis)
-- ADR-003 : rls_core_delete_own vérifie le bit 8 (delete_contents) et non le bit 4
-- (edit_contents). Le rôle author (24622) inclut delete_contents depuis ADR-003.
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '24622', true);   -- author
SET LOCAL ROLE marius_user;

SELECT is(
  (WITH del AS (
    DELETE FROM content.core
    WHERE  document_id = 9999
      AND  author_entity_id = 1
    RETURNING document_id
  ) SELECT COUNT(*)::INT FROM del),
  1,
  'RLS content.core : auteur peut DELETE son propre contenu (delete_contents=8 présent)'
);

RESET ROLE;


-- ── A10 : subscriber ne peut pas DELETE le contenu d'autrui
-- Réinsérer le brouillon pour ce test (A9 l'a supprimé).
INSERT INTO content.core
  (published_at, created_at, document_id, author_entity_id, status)
VALUES (NULL, now(), 9999, 1, 0);

SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber
SET LOCAL ROLE marius_user;

SELECT is(
  (WITH del AS (
    DELETE FROM content.core WHERE document_id = 9999
    RETURNING document_id
  ) SELECT COUNT(*)::INT FROM del),
  0,
  'RLS content.core : subscriber ne peut pas DELETE le contenu d''autrui (0 lignes)'
);

RESET ROLE;

-- Nettoyage
DELETE FROM content.core     WHERE document_id = 9999;
DELETE FROM content.document WHERE id          = 9999;


-- ============================================================
-- SECTION B — commerce.transaction_core
-- ============================================================

DO $$
DECLARE v_id INT;
BEGIN
  CALL commerce.create_transaction(5, 1, 978, 0, 'txn rls test', v_id);
  PERFORM set_config('test.txn_id', v_id::text, true);
END;
$$;


-- ── B1 : client voit sa propre transaction
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '24622', true);  -- author, pas view_transactions
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM commerce.transaction_core
   WHERE id = current_setting('test.txn_id')::INT
     AND client_entity_id = 5) = 1,
  'RLS transaction_core : client (entity_id=5) voit sa propre transaction'
);

RESET ROLE;


-- ── B2 : autre utilisateur sans view_transactions ne voit pas la transaction d'autrui
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '24622', true);  -- author, sans view_transactions
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM commerce.transaction_core
   WHERE id = current_setting('test.txn_id')::INT) = 0,
  'RLS transaction_core : utilisateur sans view_transactions ne voit pas la transaction d''autrui'
);

RESET ROLE;


-- ── B3 : administrator peut UPDATE n'importe quelle transaction
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '2097151', true);  -- administrator
SET LOCAL ROLE marius_user;

SELECT is(
  (WITH upd AS (
    UPDATE commerce.transaction_core SET status = 1
    WHERE  id = current_setting('test.txn_id')::INT
    RETURNING id
  ) SELECT COUNT(*)::INT FROM upd),
  1,
  'RLS transaction_core : administrator (manage_commerce=262144) peut UPDATE'
);

RESET ROLE;


-- ── B4 : gestionnaire avec manage_commerce seul (sans view_transactions) peut UPDATE
-- ADR-003 invariant 3 : manage_commerce (262144) ajouté dans rls_transaction_select.
-- view_transactions (131072) et manage_commerce (262144) sont orthogonaux.
-- Sans le critère 262144 dans SELECT, cet UPDATE renverrait 0 lignes silencieusement.
-- On construit un bitmask minimal : manage_commerce seul, sans view_transactions.
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '262144', true);   -- manage_commerce uniquement
SET LOCAL ROLE marius_user;

SELECT is(
  (WITH upd AS (
    UPDATE commerce.transaction_core SET status = 2
    WHERE  id = current_setting('test.txn_id')::INT
    RETURNING id
  ) SELECT COUNT(*)::INT FROM upd),
  1,
  'RLS transaction_core : manage_commerce seul (sans view_transactions) peut UPDATE (ADR-003 inv.3)'
);

RESET ROLE;


-- ============================================================
-- SECTION C — identity.account_core
-- ============================================================

-- ── C1 : utilisateur voit son propre compte uniquement
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);  -- subscriber
SET LOCAL ROLE marius_user;

SELECT is(
  (SELECT COUNT(*)::INT FROM identity.account_core WHERE entity_id = 5),
  1,
  'RLS account_core : entity_id=5 voit son propre compte'
);

RESET ROLE;


-- ── C2 : administrateur avec manage_users voit tous les comptes
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '2097151', true);  -- administrator
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM identity.account_core) > 1,
  'RLS account_core : administrator (manage_users=256) voit tous les comptes'
);

RESET ROLE;


-- ============================================================
-- SECTION D — Frontière de privilège par REVOKE SELECT (ADR-002/029)
-- Ces tests vérifient le mécanisme REVOKE SELECT, distinct du RLS.
-- REVOKE SELECT = suppression du privilège : PostgreSQL refuse avant d'évaluer
-- la requête, quel que soit le GUC positionné. Résultat : erreur 42501.
-- ============================================================

-- ── D1 : identity.auth inaccessible (REVOKE SELECT)
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '2097151', true);   -- même administrator
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT password_hash FROM identity.auth LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : identity.auth inaccessible à marius_user (même administrator)'
);

RESET ROLE;


-- ── D2 : identity.person_contact inaccessible (REVOKE SELECT)
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT email FROM identity.person_contact LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : identity.person_contact inaccessible à marius_user'
);

RESET ROLE;


-- ── D3 : commerce.transaction_payment inaccessible (REVOKE SELECT)
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT invoice_number FROM commerce.transaction_payment LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : commerce.transaction_payment inaccessible à marius_user'
);

RESET ROLE;


-- ── D4 : commerce.transaction_price inaccessible (REVOKE SELECT — ADR-003 inv.1)
-- Satellite de transaction_core : SELECT direct bypasse rls_transaction_select.
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT shipping_cents FROM commerce.transaction_price LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : commerce.transaction_price inaccessible (ADR-003 inv.1)'
);

RESET ROLE;


-- ── D5 : commerce.transaction_item inaccessible (REVOKE SELECT — ADR-003 inv.1)
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT quantity FROM commerce.transaction_item LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : commerce.transaction_item inaccessible (ADR-003 inv.1)'
);

RESET ROLE;


-- ── D6 : content.identity inaccessible (REVOKE SELECT — ADR-003 inv.1)
-- Satellite de content.core : SELECT direct exposerait titres et slugs de tous
-- les brouillons sans que rls_core_select ne soit évalué.
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT headline FROM content.identity LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : content.identity inaccessible (ADR-003 inv.1)'
);

RESET ROLE;


-- ── D7 : content.body inaccessible (REVOKE SELECT — ADR-003 inv.1)
-- Corps HTML complet de tous les documents, brouillons inclus.
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT content FROM content.body LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : content.body inaccessible (ADR-003 inv.1)'
);

RESET ROLE;


-- ── D8 : content.revision inaccessible (REVOKE SELECT — ADR-003 inv.1)
-- Snapshots éditoriaux complets (headline + body) de tous les documents.
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT snapshot_headline FROM content.revision LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : content.revision inaccessible (ADR-003 inv.1)'
);

RESET ROLE;




-- ============================================================
-- SECTION G — Security context des vues et ownership procédural
-- (ADR-003 invariant 2 et corollaire invariant 3)
-- ============================================================

-- ── G1 : subscriber ne voit pas les brouillons via v_article_list
-- Valide que le WHERE GUC de la vue est bien le mécanisme de contrôle d'accès
-- (et non le RLS physique, bypassé par le security context postgres/BYPASSRLS).
-- Un brouillon (status=0) ne doit pas être visible par un subscriber non-auteur.
INSERT INTO content.document (id) OVERRIDING SYSTEM VALUE VALUES (8888);
INSERT INTO content.core
  (published_at, created_at, document_id, author_entity_id, status)
VALUES (NULL, now(), 8888, 1, 0);
INSERT INTO content.identity (document_id, slug, headline)
VALUES (8888, 'brouillon-test-g1', 'Brouillon test G1');

SELECT set_config('marius.user_id',   '5', true);    -- subscriber, pas auteur
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.v_article_list WHERE identifier = 8888) = 0,
  'Vue v_article_list : subscriber ne voit pas le brouillon d''autrui (WHERE GUC)'
);

RESET ROLE;


-- ── G2 : auteur voit son propre brouillon via v_article_list
SELECT set_config('marius.user_id',   '1', true);    -- auteur du document 8888
SELECT set_config('marius.auth_bits', '24622', true); -- author
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.v_article_list WHERE identifier = 8888) = 1,
  'Vue v_article_list : auteur voit son propre brouillon (WHERE GUC, co.author_entity_id = rls_user_id())'
);

RESET ROLE;


-- ── G3 : subscriber ne voit pas la transaction d'autrui via v_transaction
-- Valide le WHERE GUC dans v_transaction.
SELECT set_config('marius.user_id',   '6', true);    -- pas le client de la transaction créée en B
SELECT set_config('marius.auth_bits', '24622', true); -- author, sans view_transactions
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM commerce.v_transaction
   WHERE customer_id = 5) = 0,
  'Vue v_transaction : utilisateur non-client (sans view_transactions) ne voit pas la transaction (WHERE GUC)'
);

RESET ROLE;


-- ── G4 : auteur ne peut pas sauvegarder une révision du document d''autrui
-- Valide l''ownership check dans content.save_revision (ADR-003 inv.3 corollaire).
-- entity_id=5 a edit_contents(4) mais pas edit_others_contents(32768),
-- et n''est pas l''auteur du document 8888 (auteur = entity_id 1).
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '24622', true);   -- author (a edit_contents=4)
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL content.save_revision(8888, 5)$$,
  '42501', NULL,
  'Proc save_revision : auteur ne peut pas sauvegarder la révision du document d''autrui'
);

RESET ROLE;

-- Nettoyage
DELETE FROM content.identity WHERE document_id = 8888;
DELETE FROM content.core     WHERE document_id = 8888;
DELETE FROM content.document WHERE id          = 8888;


-- ============================================================
-- SECTION H — content.add_tag_to_document / remove_tag_from_document
-- (ADR-001 rev. — procédures de liaison taxonomique)
-- Prérequis : tag seed id=1 doit exister (chargé depuis master_schema_dml.pgsql).
-- ============================================================

-- ── H1 : subscriber ne peut pas lier un tag (sans edit_contents)
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL content.add_tag_to_document(7, 1)$$,
  '42501', NULL,
  'Proc add_tag_to_document : subscriber (sans edit_contents=4) ne peut pas lier un tag'
);

RESET ROLE;


-- ── H2 : auteur peut lier un tag à son propre document
SELECT set_config('marius.user_id',   '1', true);      -- auteur du document 7
SELECT set_config('marius.auth_bits', '24622', true);   -- author (edit_contents=4)
SET LOCAL ROLE marius_user;

SELECT lives_ok(
  $$CALL content.add_tag_to_document(7, 1)$$,
  'Proc add_tag_to_document : auteur peut lier un tag à son propre document'
);

RESET ROLE;


-- ── H3 : auteur ne peut pas lier un tag au document d''autrui
-- Document 3 appartient à entity_id=2 ; l''appelant est entity_id=1.
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '24622', true);   -- author, sans edit_others_contents
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL content.add_tag_to_document(3, 1)$$,
  '42501', NULL,
  'Proc add_tag_to_document : auteur ne peut pas lier un tag au document d''autrui'
);

RESET ROLE;


-- ── H4 : éditeur (edit_others_contents) peut lier un tag à n''importe quel document
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '59438', true);   -- editor (edit_others_contents=32768)
SET LOCAL ROLE marius_user;

SELECT lives_ok(
  $$CALL content.add_tag_to_document(3, 1)$$,
  'Proc add_tag_to_document : editor (edit_others_contents=32768) peut lier un tag à n''importe quel document'
);

RESET ROLE;

-- Nettoyage des liaisons de test
DELETE FROM content.content_to_tag WHERE content_id IN (3, 7) AND tag_id = 1;


-- ============================================================
-- SECTION I — Schéma org (audit performance + sécurité)
-- ============================================================

-- ── I1 : org.org_legal inaccessible directement (REVOKE SELECT)
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '2097151', true);  -- administrator
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT duns FROM org.org_legal LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : org.org_legal inaccessible à marius_user (données légales sensibles)'
);

RESET ROLE;


-- ── I2 : v_organization ne projette pas les données légales
-- Les colonnes duns/siret/vat_id ont été retirées de la vue.
SET LOCAL ROLE marius_user;

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'org'
      AND table_name   = 'v_organization'
      AND column_name  IN ('duns', 'siret', 'vat_id')
  ),
  'Vue v_organization : colonnes légales (duns, siret, vat_id) absentes de la projection'
);

RESET ROLE;


-- ── I3 : subscriber ne peut pas créer une organisation (manage_system requis)
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL org.create_organization('Test Org', 'test-org')$$,
  '42501', NULL,
  'Proc create_organization : subscriber (sans manage_system=524288) ne peut pas créer une organisation'
);

RESET ROLE;


-- ── I4 : subscriber ne peut pas modifier la hiérarchie (manage_system requis)
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL org.add_organization_to_hierarchy(1, NULL)$$,
  '42501', NULL,
  'Proc add_organization_to_hierarchy : subscriber (sans manage_system=524288) ne peut pas modifier la hiérarchie'
);

RESET ROLE;


-- ── I5 : administrator peut insérer une organisation dans la hiérarchie
-- Crée une organisation de test, l''insère dans la hiérarchie, vérifie les intervalles,
-- puis nettoie. On utilise marius_admin (BYPASSRLS) pour le seed, marius_user pour le test.
DO $$
DECLARE v_org_id INT;
BEGIN
  -- Seed en tant que postgres (SECURITY DEFINER bypass) : GUC non injecté
  CALL org.create_organization('Org Hiérarchie Test', 'org-hierarchie-test', v_org_id);
  PERFORM set_config('test.org_id', v_org_id::text, true);
END;
$$;

SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '2097151', true);  -- administrator (manage_system=524288)
SET LOCAL ROLE marius_user;

SELECT lives_ok(
  $$CALL org.add_organization_to_hierarchy(current_setting('test.org_id')::INT, NULL)$$,
  'Proc add_organization_to_hierarchy : administrator peut insérer une org dans la hiérarchie'
);

RESET ROLE;

-- Nettoyage
DELETE FROM org.org_hierarchy WHERE entity_id = current_setting('test.org_id')::INT;
DELETE FROM org.org_identity  WHERE entity_id = current_setting('test.org_id')::INT;
DELETE FROM org.org_core      WHERE entity_id = current_setting('test.org_id')::INT;
DELETE FROM org.entity        WHERE id        = current_setting('test.org_id')::INT;


-- ============================================================
-- SECTION J — Audit RLS global : fixes v_auth et v_person
-- ============================================================

-- ── J1 : identity.v_auth inaccessible à marius_user (REVOKE SELECT sur la vue)
-- La vue lisait identity.auth (REVOKE'd) via BYPASSRLS postgres.
-- Sans REVOKE sur la vue, password_hash était lisible à tout marius_user.
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '2097151', true);
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT password_hash FROM identity.v_auth LIMIT 1$$,
  '42501', NULL,
  'REVOKE SELECT : identity.v_auth inaccessible à marius_user (password_hash protégé)'
);

RESET ROLE;


-- ── J2 : identity.v_person ne projette pas email ni téléphone
-- Colonnes PII issues de identity.person_contact (REVOKE'd) retirées de la projection.
SET LOCAL ROLE marius_user;

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'identity'
      AND table_name   = 'v_person'
      AND column_name  IN ('email', 'telephone', 'phone')
  ),
  'Vue v_person : colonnes PII (email, telephone) absentes de la projection'
);

RESET ROLE;


-- ── J3 : identity.v_person conserve url (donnée de contact publique)
SET LOCAL ROLE marius_user;

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'identity'
      AND table_name   = 'v_person'
      AND column_name  = 'url'
  ),
  'Vue v_person : url (site web public) conservé dans la projection'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;

-- ============================================================
-- SECTION E — Gardes d'autorisation dans les procédures SECURITY DEFINER
-- (ADR-001 rev.)
-- Ces tests vérifient que l'élévation SECURITY DEFINER n'ouvre pas les
-- procédures à des appelants sans permission. Le GUC est positionné pour
-- simuler un contexte applicatif (rls_user_id() ≠ -1).
-- ============================================================

-- ── E1 : subscriber ne peut pas publier un document
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber : sans publish_contents
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL content.publish_document(7)$$,
  '42501', NULL,
  'Proc publish_document : subscriber (sans publish_contents=16) ne peut pas publier'
);

RESET ROLE;


-- ── E2 : subscriber ne peut pas créer un document attribué à un autre auteur
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16418', true);   -- contributor : a create_contents(2) mais sans edit_others
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL content.create_document(1, 'Titre test', 'titre-test')$$,  -- auteur = entity_id 1, caller = 5
  '42501', NULL,
  'Proc create_document : ne peut pas créer un document attribué à un autre auteur'
);

RESET ROLE;


-- ── E3 : subscriber ne peut pas créer un tag (manage_tags requis)
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL content.create_tag('test', 'test-slug')$$,
  '42501', NULL,
  'Proc create_tag : subscriber (sans manage_tags=2048) ne peut pas créer un tag'
);

RESET ROLE;


-- ── E4 : subscriber ne peut pas modifier les permissions de rôle
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL identity.grant_permission(7, 256)$$,
  '42501', NULL,
  'Proc grant_permission : subscriber (sans manage_users=256) ne peut pas modifier les permissions'
);

RESET ROLE;


-- ============================================================
-- SECTION F — content.comment RLS
-- Commentaire 9999 : status=0 (pending), auteur = entity_id 1
-- Commentaire 9998 : status=1 (approuvé), auteur = entity_id 2
-- ============================================================

INSERT INTO content.comment (
  created_at, document_id, account_entity_id, id, status, path, content
)
OVERRIDING SYSTEM VALUE VALUES
  (now(), 7, 1, 9999, 0, '7.9999', 'commentaire en attente'),
  (now(), 7, 2, 9998, 1, '7.9998', 'commentaire approuvé');


-- ── F1 : commentaire approuvé (status=1) visible sans GUC
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.comment WHERE id = 9998) = 1,
  'RLS comment : commentaire approuvé (status=1) visible sans GUC (accès anonyme)'
);

RESET ROLE;


-- ── F2 : commentaire pending invisible pour un subscriber non-auteur
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);   -- subscriber (pas l'auteur entity_id=1)
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.comment WHERE id = 9999) = 0,
  'RLS comment : commentaire pending invisible pour subscriber non-auteur'
);

RESET ROLE;


-- ── F3 : auteur voit son propre commentaire pending
SELECT set_config('marius.user_id',   '1', true);      -- entity_id 1 = auteur du commentaire 9999
SELECT set_config('marius.auth_bits', '24622', true);   -- author
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.comment WHERE id = 9999) = 1,
  'RLS comment : auteur (entity_id=1) voit son propre commentaire pending'
);

RESET ROLE;


-- ── F4 : modérateur avec moderate_comments voit tous les commentaires
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '124990', true);   -- moderator
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.comment WHERE id = 9999) = 1,
  'RLS comment : moderator (moderate_comments=65536) voit les commentaires pending'
);

RESET ROLE;

-- Nettoyage
DELETE FROM content.comment WHERE id IN (9998, 9999);

