-- ==============================================================================
-- 06_security_audit.sql
-- Tests d'étanchéité procédurale — Audit 2 (ADR-001)
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre :
--   A — Shadow Write Detection : infrastructure d'audit présente + RBAC enforced
--   B — Qualification des objets : aucun nom non qualifié dans les corps SECURITY DEFINER
--   C — Bypass admin : ALTER PROCEDURE signatures alignées, marius_admin hors runtime
--
-- Exécution : psql -U postgres -d marius -f 06_security_audit.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(20);


-- ============================================================
-- A.1 — Infrastructure d'audit : table dml_audit_log présente
-- ============================================================

SELECT has_table(
  'identity', 'dml_audit_log',
  'identity.dml_audit_log : table d''audit shadow writes présente (ADR-001)'
);


-- ============================================================
-- A.2 — Triggers d'audit déployés sur les tables sensibles
-- ============================================================

SELECT has_trigger(
  'identity', 'auth', 'audit_identity_auth',
  'Trigger audit_identity_auth sur identity.auth'
);

SELECT has_trigger(
  'identity', 'entity', 'audit_identity_entity',
  'Trigger audit_identity_entity sur identity.entity'
);

SELECT has_trigger(
  'commerce', 'transaction_core', 'audit_commerce_transaction_core',
  'Trigger audit_commerce_transaction_core sur commerce.transaction_core'
);

SELECT has_trigger(
  'commerce', 'transaction_item', 'audit_commerce_transaction_item',
  'Trigger audit_commerce_transaction_item sur commerce.transaction_item'
);

SELECT has_trigger(
  'identity', 'account_core', 'audit_identity_account_core',
  'Trigger audit_identity_account_core sur identity.account_core'
);


-- ============================================================
-- A.3 — Shadow write effectif détecté dans dml_audit_log
--
-- On exécute un INSERT via marius_user APRÈS avoir accordé un droit
-- temporaire (dans le contexte rollbacké de ce test uniquement).
-- Cela simule exactement un ORM mal configuré : session_user = marius_user,
-- current_user = marius_user (pas de SECURITY DEFINER en jeu).
--
-- Note : ce test requiert un GRANT DML temporaire dans la transaction,
-- révoqué au ROLLBACK final. L'invariant ADR-001 n'est pas violé en
-- production : le GRANT n'existe que dans cette transaction de test.
-- ============================================================

-- Octroi temporaire (scoped à la transaction de test)
GRANT INSERT ON identity.entity TO marius_user;
GRANT INSERT ON identity.auth   TO marius_user;
GRANT INSERT ON identity.account_core TO marius_user;

-- Simulation d'un shadow write : marius_user INSERT direct
SET LOCAL ROLE marius_user;
INSERT INTO identity.entity DEFAULT VALUES;  -- declenche audit_identity_entity
RESET ROLE;

-- Révocation immédiate (avant toute autre opération dans la transaction)
REVOKE INSERT ON identity.entity       FROM marius_user;
REVOKE INSERT ON identity.auth         FROM marius_user;
REVOKE INSERT ON identity.account_core FROM marius_user;

-- La vue v_shadow_writes doit avoir capturé l'événement
SELECT ok(
  EXISTS (
    SELECT 1 FROM identity.v_shadow_writes
    WHERE  table_name = 'entity'
      AND  operation  = 'INSERT'
  ),
  'v_shadow_writes : shadow write INSERT sur identity.entity détecté (session_user = current_user = marius_user)'
);


-- ============================================================
-- A.4 — Vues de surveillance présentes
-- ============================================================

SELECT has_view(
  'identity', 'v_shadow_writes',
  'identity.v_shadow_writes : vue de détection des shadow writes présente'
);

SELECT has_view(
  'identity', 'v_admin_sessions',
  'identity.v_admin_sessions : vue de surveillance des sessions marius_admin présente'
);


-- ============================================================
-- B — QUALIFICATION DES OBJETS dans les corps SECURITY DEFINER
--
-- Méthode : on lit pg_proc.prosrc pour chaque procédure SECURITY DEFINER
-- et on cherche les patterns d'accès non qualifiés.
--
-- Patterns rejetés :
--   INTO <word>    sans point (variable locale acceptable — filtrée par INTO v_)
--   FROM <word>    sans <schema>.<table>
--   UPDATE <word>  sans schéma
--   INSERT INTO <word> sans schéma
--   DELETE FROM <word> sans schéma
--
-- Approche : requête negative — on cherche un INSERT INTO / UPDATE / DELETE FROM /
-- FROM (hors JOIN) suivi d'un identifiant simple (sans point).
-- La regex est conservatrice : un faux positif vaut mieux qu'un faux négatif.
--
-- Tables système acceptées sans schéma : pg_*, information_schema (absentes des corps).
-- Identifiants locaux (variables DECLARE) : exclus par la convention v_ des corps.
-- ============================================================

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_proc    p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  p.prosecdef = true
      AND  n.nspname IN ('identity', 'org', 'content', 'commerce')
      -- Détecte : INSERT INTO <mot_simple> (sans point dans le nom de table)
      -- Le \m \M délimitent les mots complets. Exclut les mots commençant par v_ (variables).
      AND  (
        p.prosrc ~* '\mINSERT\s+INTO\s+([a-z_][a-z0-9_]*)(\s*\(|\s+OVERRIDING)'
        AND p.prosrc !~* '\mINSERT\s+INTO\s+[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*'
        AND p.prosrc  ~* '\mINSERT\s+INTO\s+(?!v_)[a-z_][a-z0-9_]*\s'
      )
  ),
  'Qualification objets : aucun INSERT INTO non qualifié dans les procédures SECURITY DEFINER'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_proc    p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  p.prosecdef = true
      AND  n.nspname IN ('identity', 'org', 'content', 'commerce')
      AND  (
        p.prosrc ~* '\mUPDATE\s+([a-z_][a-z0-9_]*)(\s+SET)'
        AND p.prosrc !~* '\mUPDATE\s+[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\s'
      )
  ),
  'Qualification objets : aucun UPDATE non qualifié dans les procédures SECURITY DEFINER'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_proc    p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  p.prosecdef = true
      AND  n.nspname IN ('identity', 'org', 'content', 'commerce')
      AND  (
        p.prosrc ~* '\mDELETE\s+FROM\s+([a-z_][a-z0-9_]*)(\s+WHERE|\s*;)'
        AND p.prosrc !~* '\mDELETE\s+FROM\s+[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\s'
      )
  ),
  'Qualification objets : aucun DELETE FROM non qualifié dans les procédures SECURITY DEFINER'
);


-- ============================================================
-- B.2 — search_path fixé sur toutes les procédures SECURITY DEFINER
--
-- SET search_path dans la signature est la première ligne de défense.
-- Un SECURITY DEFINER sans search_path fixé est vulnérable à la substitution
-- de schéma : un attaquant peut créer un objet homonyme dans un schéma
-- placé en tête du search_path de session.
-- ============================================================

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_proc    p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  p.prosecdef = true
      AND  n.nspname IN ('identity', 'org', 'content', 'commerce')
      AND  p.prokind = 'p'
      -- proconfig est NULL si aucun SET n'est attaché à la procédure
      AND  (p.proconfig IS NULL OR NOT EXISTS (
        SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'
      ))
  ),
  'Toutes les procédures SECURITY DEFINER ont search_path fixé (ADR-001)'
);


-- ============================================================
-- C.1 — ALTER PROCEDURE signatures alignées sur les types actuels
--
-- Suite à l'Audit 1 (nationality SMALLINT, language VARCHAR),
-- les ALTER PROCEDURE de la section 14.3 utilisaient les anciens types
-- (character = bpchar) comme clé de résolution de signature.
-- PostgreSQL identifie une procédure par son nom + vecteur de types d'arguments.
-- Une signature désalignée produit un "procedure not found" silencieux au DDL
-- (ou une erreur à l'exécution) laissant la procédure sans SECURITY DEFINER.
--
-- Ce test valide que create_account et create_person ont bien SECURITY DEFINER
-- après correction de leurs signatures ALTER.
-- ============================================================

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'create_account' AND p.prokind = 'p'
  ), false),
  'identity.create_account : SECURITY DEFINER actif après correction de signature (Audit 1 → 2 sync)'
);

SELECT ok(
  COALESCE((
    SELECT p.prosecdef FROM pg_proc p
    JOIN   pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'identity' AND p.proname = 'create_person' AND p.prokind = 'p'
  ), false),
  'identity.create_person : SECURITY DEFINER actif après correction de signature (Audit 1 → 2 sync)'
);


-- ============================================================
-- C.2 — marius_admin : LOGIN actif mais absent des sessions runtime
--
-- On ne peut pas tester pg_hba.conf via pgTAP (fichier système).
-- Ce test vérifie deux invariants vérifiables en SQL :
--   1. marius_admin a bien BYPASSRLS (requis pour les migrations)
--   2. marius_admin n'est pas superuser (principe de moindre privilège)
--
-- Le monitoring runtime se fait via : SELECT * FROM identity.v_admin_sessions;
-- Toute ligne retournée en production est une anomalie.
-- ============================================================

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_roles
    WHERE  rolname      = 'marius_admin'
      AND  rolbypassrls = true
      AND  rolsuper     = false
  ),
  'marius_admin : BYPASSRLS=true, superuser=false (principe de moindre privilège)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_roles
    WHERE  rolname = 'marius_admin'
      AND  rolcanlogin = true
  ),
  'marius_admin : LOGIN actif (maintenance CI/CD) — désactiver via NOLOGIN en prod haute criticité'
);

-- Pendant ce test, marius_admin ne doit pas avoir de session active (hors cette session)
SELECT is(
  (SELECT COUNT(*)::INT FROM identity.v_admin_sessions),
  0,
  'v_admin_sessions : aucune session marius_admin active pendant le test (invariant runtime)'
);


SELECT * FROM finish();
ROLLBACK;
