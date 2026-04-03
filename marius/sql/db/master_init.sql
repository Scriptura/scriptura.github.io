-- ==============================================================================
-- MASTER INIT — Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Exécution : psql -U postgres -f db/master_init.sql
-- \ir        : chemin relatif à ce fichier (psql 9.4+) — ne pas substituer \i
-- Topologie  : Infrastructure → Meta AOT → Composants (2-6) → FK croisées
--              → DCL → RLS → Seed manifeste → Sentinelles d'audit
-- ==============================================================================

-- ── 0. Infrastructure ─────────────────────────────────────────────────────────
-- 01_bootstrap.sql s'exécute dans la base postgres (DROP DATABASE inclus).
-- La commande \c bascule la session sur marius pour tout ce qui suit.
\ir 00_infra/01_bootstrap.sql
\c marius
\ir 00_infra/02_extensions.sql
\ir 00_infra/03_schemas.sql

-- ── 1. Registre AOT (meta.containment_intent doit exister en premier) ─────────
-- Les vues d'introspection (v_extended_containment_security_matrix) utilisent
-- to_regclass() : robuste à l'absence de tables physiques (NULL silencieux).
\ir 01_meta/01_tables.sql
\ir 01_meta/02_functions.sql
\ir 01_meta/03_views.sql

-- ── 2-6. Composants par domaine (ECS : layout data avant logique) ─────────────
-- Chaque domaine : 01_components.sql (tables + index + data statique)
--                  02_systems.sql    (fonctions + triggers + procédures + vues)
-- FK intra-schéma déclarées inline. FK inter-schémas reportées en étape 7.
\ir 02_identity/01_components.sql
\ir 02_identity/02_systems.sql

\ir 03_geo/01_components.sql
\ir 03_geo/02_systems.sql

\ir 04_org/01_components.sql
\ir 04_org/02_systems.sql

\ir 05_content/01_components.sql
\ir 05_content/02_systems.sql

\ir 06_commerce/01_components.sql
\ir 06_commerce/02_systems.sql

-- ── 7. FK inter-schémas ────────────────────────────────────────────────────────
-- ALTER TABLE ADD CONSTRAINT en un seul passage.
-- Résout le cycle identity.account_core ↔ content.media_core.
\ir 07_cross_fk/01_constraints.sql

-- ── 8. DCL ────────────────────────────────────────────────────────────────────
-- 01_grants.sql   : GRANT/REVOKE marius_user + création marius_admin (section 13 + 14.1/14.2)
-- 02_secdef.sql   : ALTER PROCEDURE SECURITY DEFINER SET search_path (section 14.3)
--   Dépend des procédures de toutes les étapes 2-6 (doit suivre).
\ir 08_dcl/01_grants.sql
\ir 08_dcl/02_secdef.sql

-- ── 9. Row-Level Security ─────────────────────────────────────────────────────
-- Dépend de identity.rls_auth_bits() / rls_user_id() (chargés en étape 2).
\ir 09_rls/01_policies.sql

-- ── 10. Manifeste AOT ─────────────────────────────────────────────────────────
-- TRUNCATE + INSERT meta.containment_intent.
-- to_regclass() résout correctement : toutes les tables physiques existent.
-- La requête de vérification finale retourne des résultats fiables.
\ir 10_meta_seed/01_manifest.sql

-- ── 11. Sentinelles d'audit ───────────────────────────────────────────────────
-- Introspection catalogue complète : chargement en dernier impératif.
-- v_performance_sentinel avant v_master_health_audit (dépendance de vue).
\ir 11_audit/01_v_performance_sentinel.sql
\ir 11_audit/02_v_master_health_audit.sql

-- ==============================================================================
-- FIN DE MASTER_INIT
-- Pour les données de test : psql -U postgres -d marius -f master_schema_dml.pgsql
-- ==============================================================================
