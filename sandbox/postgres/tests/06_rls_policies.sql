-- ==============================================================================
-- 06_rls_policies.sql
-- Tests fonctionnels : Row-Level Security — Pattern GUC Stateless (ADR-028)
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
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(15);


-- ============================================================
-- SECTION A — content.core
-- Document 7 (auteur = entity_id 1, status = 1 = publié)
-- Document 3 (auteur = entity_id 2, status = 1 = publié)
-- ============================================================

-- ── A1 : article publié visible sans aucun GUC positionné
-- Simule une connexion anonyme / seed : user_id et auth_bits non définis.
-- status = 1 → visible pour tous (premier critère de la politique).
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 7) = 1,
  'RLS content.core : article publié (status=1) visible sans GUC (accès anonyme)'
);

RESET ROLE;


-- ── A2 : brouillon de l'auteur visible par l'auteur lui-même
-- On ne peut pas créer de brouillon dans ce test sans procédure, mais on peut
-- vérifier la mécanique sur un article existant en simulant son auteur.
-- Document 7, auteur entity_id=1, status=1.
-- En tant qu'entity_id=1 avec auth_bits=24614 (author), la ligne est visible
-- via le critère "author_entity_id = rls_user_id()" (redondant ici car publié,
-- mais valide le chemin auteur).

SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '24614', true);   -- author
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core
   WHERE document_id = 7 AND author_entity_id = 1) = 1,
  'RLS content.core : auteur (entity_id=1) voit son propre article'
);

RESET ROLE;


-- ── A3 : utilisateur sans droits éditoriaux ne voit pas les brouillons d'autrui
-- Scenario : entity_id=5 (subscriber, auth_bits=16384) ne peut pas voir un
-- article de status=0 dont il n'est pas l'auteur.
-- On insère temporairement un brouillon signé entity_id=1 visible seulement
-- par son auteur ou un éditeur.

INSERT INTO content.document (id) OVERRIDING SYSTEM VALUE VALUES (9999);
INSERT INTO content.core
  (published_at, created_at, document_id, author_entity_id, status)
VALUES (NULL, now(), 9999, 1, 0);   -- brouillon, auteur = entity_id 1

SELECT set_config('marius.user_id',   '5', true);    -- subscriber, pas auteur
SELECT set_config('marius.auth_bits', '16384', true); -- can_read uniquement
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 9999) = 0,
  'RLS content.core : subscriber (entity_id=5) ne voit pas le brouillon d''autrui'
);

RESET ROLE;


-- ── A4 : éditeur avec publish_contents voit les brouillons
SELECT set_config('marius.user_id',   '6', true);     -- autre utilisateur
SELECT set_config('marius.auth_bits', '59430', true);  -- editor (inclut publish_contents bit 4=16)
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM content.core WHERE document_id = 9999) = 1,
  'RLS content.core : editor (auth_bits contient publish_contents=16) voit le brouillon'
);

RESET ROLE;


-- ── A5 : auteur peut UPDATE son propre contenu (edit_contents requis)
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '24614', true);  -- author : inclut edit_contents(4)
SET LOCAL ROLE marius_user;

SELECT lives_ok(
  $$UPDATE content.core SET is_commentable = false WHERE document_id = 9999$$,
  'RLS content.core : auteur peut UPDATE son propre contenu (edit_contents présent)'
);

RESET ROLE;


-- ── A6 : utilisateur sans edit_others_contents ne peut pas UPDATE le contenu d'autrui
-- entity_id=5 (subscriber) essaie de modifier le document 9999 (auteur=1)
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '16384', true);  -- can_read uniquement
SET LOCAL ROLE marius_user;

-- L'UPDATE ne lève pas d'erreur mais affecte 0 lignes (RLS filtre silencieusement)
SELECT is(
  (WITH upd AS (
    UPDATE content.core SET is_commentable = true
    WHERE  document_id = 9999
    RETURNING document_id
  ) SELECT COUNT(*)::INT FROM upd),
  0,
  'RLS content.core : subscriber ne peut pas UPDATE le contenu d''autrui (0 lignes affectées)'
);

RESET ROLE;


-- ── A7 : utilisateur avec edit_others_contents peut UPDATE n'importe quel contenu
SELECT set_config('marius.user_id',   '6', true);
SELECT set_config('marius.auth_bits', '122934', true);  -- moderator : inclut edit_others_contents
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


-- ============================================================
-- SECTION B — commerce.transaction_core
-- ============================================================

-- Insérer une transaction de test (auteur = entity_id 5)
DO $$
DECLARE v_id INT;
BEGIN
  CALL commerce.create_transaction(5, 1, 978, 0, 'txn rls test', v_id);
  PERFORM set_config('test.txn_id', v_id::text, true);
END;
$$;


-- ── B1 : client voit sa propre transaction
SELECT set_config('marius.user_id',   '5', true);
SELECT set_config('marius.auth_bits', '24614', true);  -- author, pas view_transactions
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
SELECT set_config('marius.auth_bits', '24614', true);  -- author, sans view_transactions
SET LOCAL ROLE marius_user;

SELECT ok(
  (SELECT COUNT(*)::INT FROM commerce.transaction_core
   WHERE id = current_setting('test.txn_id')::INT) = 0,
  'RLS transaction_core : autre utilisateur sans view_transactions ne voit pas la transaction'
);

RESET ROLE;


-- ── B3 : gestionnaire commerce avec manage_commerce peut UPDATE n'importe quelle transaction
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
-- SECTION D — Frontière de privilège par REVOKE SELECT (audit ADR-028)
-- Ces tests vérifient le mécanisme de REVOKE SELECT (Section 13), distinct du RLS.
-- REVOKE SELECT = suppression du privilège : PostgreSQL refuse avant d'évaluer la requête.
-- RLS = filtrage par ligne : s'applique uniquement sur les tables où SELECT est accordé.
-- Les GUC marius.user_id / marius.auth_bits sont sans effet sur un REVOKE SELECT.
-- ============================================================

-- ── D1 : identity.auth inaccessible à marius_user
-- Ce test valide le REVOKE SELECT (frontière de privilège), PAS le RLS.
-- Le 42501 est émis avant évaluation de toute politique — les GUC sont sans effet.
SELECT set_config('marius.user_id',   '1', true);
SELECT set_config('marius.auth_bits', '2097151', true);   -- même administrator
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT password_hash FROM identity.auth LIMIT 1$$,
  '42501',
  NULL,
  'REVOKE SELECT (pas RLS) : identity.auth inaccessible à marius_user, même administrator'
);

RESET ROLE;


-- ── D2 : identity.person_contact inaccessible (REVOKE SELECT, pas RLS)
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT email FROM identity.person_contact LIMIT 1$$,
  '42501',
  NULL,
  'REVOKE SELECT : identity.person_contact.email inaccessible à marius_user'
);

RESET ROLE;


-- ── D3 : commerce.transaction_payment inaccessible (REVOKE SELECT, pas RLS)
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$SELECT invoice_number FROM commerce.transaction_payment LIMIT 1$$,
  '42501',
  NULL,
  'REVOKE SELECT : commerce.transaction_payment inaccessible à marius_user'
);

RESET ROLE;


SELECT * FROM finish();
ROLLBACK;
