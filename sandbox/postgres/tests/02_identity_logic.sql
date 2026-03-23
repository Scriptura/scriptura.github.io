-- ==============================================================================
-- 02_identity_logic.sql
-- Tests fonctionnels : domaine Identity
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre : atomicité de create_account, déduplication des slugs,
--          bitmask des permissions (ADR-003), record_login (hot path ADR-015),
--          grant_permission / revoke_permission.
--
-- Exécution : psql -U postgres -d marius -f 02_identity_logic.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(9);


-- ============================================================
-- DONNÉES DE TEST
-- La table temporaire _ids centralise les IDs générés par les procédures.
-- Elle est automatiquement supprimée au ROLLBACK final.
-- ============================================================

CREATE TEMP TABLE _ids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

-- Compte 1 : slug 'usr-idt-01'
DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'usr_idt_01',                   -- username
    '$argon2id$v=19$m=65536$test1', -- password_hash (non exploité par les tests)
    'usr-idt-01',                   -- slug
    7,                              -- role_id = subscriber (permissions = 16384)
    'fr_FR',
    v_id
  );
  INSERT INTO _ids VALUES ('acct1_id', v_id);
END;
$$;


-- ============================================================
-- create_account : atomicité des composants ECS
--
-- La procédure doit créer trois composants en une transaction atomique :
--   identity.entity    → spine (identifiant pur)
--   identity.auth      → credentials + rôle
--   identity.account_core → données publiques du compte
--
-- L'absence de l'un des composants invalide l'invariant de sous-type (ADR-019).
-- ============================================================

SELECT ok(
  EXISTS (
    SELECT 1 FROM identity.entity
    WHERE  id = (SELECT val FROM _ids WHERE key = 'acct1_id')
  ),
  'create_account : identity.entity créée'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM identity.auth
    WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'acct1_id')
  ),
  'create_account : identity.auth créée'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM identity.account_core
    WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'acct1_id')
  ),
  'create_account : identity.account_core créée'
);


-- ============================================================
-- Déduplication de slug (fn_slug_deduplicate, ADR-020 — comportement documenté)
--
-- Deux comptes avec le même slug de base → le second reçoit <slug>-1.
-- La déduplication est optimiste (SELECT EXISTS + incrément). La contrainte
-- UNIQUE est le vrai garde-fou en cas de collision concurrente (23505).
-- Ce test couvre le cas nominal en session unique.
-- ============================================================

DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'usr_idt_02',
    '$argon2id$v=19$m=65536$test2',
    'usr-idt-01',   -- slug identique au compte 1 → doit être dédupliqué
    7,
    'fr_FR',
    v_id
  );
  INSERT INTO _ids VALUES ('acct2_id', v_id);
END;
$$;

SELECT is(
  (SELECT slug FROM identity.account_core
   WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'acct2_id')),
  'usr-idt-01-1',
  'Slug dédupliqué : usr-idt-01 → usr-idt-01-1 pour le second compte'
);


-- ============================================================
-- has_permission : vérification du bitmask (ADR-003)
--
-- Le rôle subscriber (id = 7) a permissions = 16384 (can_read uniquement).
-- La fonction has_permission effectue un AND bitwise : (permissions & bit) <> 0.
-- Elle est déclarée LANGUAGE sql STABLE PARALLEL SAFE — inlinable par le planner.
-- ============================================================

SELECT ok(
  identity.has_permission(
    (SELECT val FROM _ids WHERE key = 'acct1_id'),
    16384   -- can_read (bit 14)
  ),
  'has_permission : can_read (16384) = true pour le rôle subscriber'
);

SELECT ok(
  NOT identity.has_permission(
    (SELECT val FROM _ids WHERE key = 'acct1_id'),
    1       -- access_admin (bit 0) — absent du rôle subscriber
  ),
  'has_permission : access_admin (1) = false pour le rôle subscriber'
);


-- ============================================================
-- record_login : mise à jour de last_login_at (hot path, ADR-015)
--
-- last_login_at doit être NULL avant la première connexion.
-- Après CALL record_login(), la colonne doit être renseignée.
-- Le trigger auth_modified_at NE se déclenche PAS sur cette mise à jour
-- (clause WHEN : uniquement password_hash, role_id, is_banned) — intentionnel
-- pour éliminer les dead tuples sur le hot path de connexion.
-- ============================================================

CALL identity.record_login((SELECT val FROM _ids WHERE key = 'acct1_id'));

SELECT ok(
  (SELECT last_login_at FROM identity.auth
   WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'acct1_id')) IS NOT NULL,
  'record_login : last_login_at renseigné après le premier appel'
);


-- ============================================================
-- grant_permission / revoke_permission : manipulation du bitmask
--
-- Ces procédures opèrent sur identity.role (OR / AND NOT sur la colonne
-- permissions). Elles s'appliquent ici au rôle subscriber (id = 7), dans le
-- contexte de la transaction de test — effet rollbacké en fin de fichier.
-- ============================================================

-- Ajouter le bit access_admin (1) au rôle subscriber
CALL identity.grant_permission(7::SMALLINT, 1);

SELECT ok(
  identity.has_permission(
    (SELECT val FROM _ids WHERE key = 'acct1_id'),
    1   -- access_admin
  ),
  'grant_permission : bit access_admin (1) ajouté au rôle subscriber'
);

-- Retirer le bit access_admin
CALL identity.revoke_permission(7::SMALLINT, 1);

SELECT ok(
  NOT identity.has_permission(
    (SELECT val FROM _ids WHERE key = 'acct1_id'),
    1
  ),
  'revoke_permission : bit access_admin (1) retiré du rôle subscriber'
);


SELECT * FROM finish();
ROLLBACK;
