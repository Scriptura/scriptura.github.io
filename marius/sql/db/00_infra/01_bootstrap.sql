-- ==============================================================================
-- 00_infra/01_bootstrap.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Exécution : depuis la base postgres (via master_init.sql)
-- Rôle      : réinitialisation complète (DROP DATABASE + rôles + re-création)
-- ==============================================================================

DROP DATABASE IF EXISTS marius;

-- marius_admin doit être nettoyé avant marius_user (héritage GRANT marius_user TO marius_admin).
-- Sans cet ordre, DROP USER marius_user échoue si le GRANT existe encore.
-- Ces trois commandes échouent silencieusement si marius_admin n'existe pas encore (premier déploiement).
REASSIGN OWNED BY marius_admin TO postgres;
DROP OWNED BY marius_admin;
DROP ROLE IF EXISTS marius_admin;

REASSIGN OWNED BY marius_user TO postgres;
DROP OWNED BY marius_user;
DROP USER IF EXISTS marius_user;

CREATE USER marius_user WITH ENCRYPTED PASSWORD 'root';
CREATE DATABASE marius OWNER marius_user;
