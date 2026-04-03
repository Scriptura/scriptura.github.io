-- ==============================================================================
-- 08_dcl/01_grants.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : création de marius_admin · GRANT marius_user (section 13)
--           · GRANT marius_admin (section 14.1) · REVOKE DML marius_user (14.2)
--
-- Pré-requis : tous les schémas, tables, vues, fonctions et procédures
--   des domaines 02–06 doivent exister (GRANT ALL TABLES / FUNCTIONS portent
--   sur les objets existants au moment de l'exécution).
-- Note : GRANT EXECUTE sur identity.rls_user_id() et identity.rls_auth_bits()
--   est émis dès 02_identity/02_systems.sql pour permettre l'accès aux vues.
--   Le GRANT ALL FUNCTIONS ci-dessous est idempotent sur ces deux fonctions.
-- ==============================================================================

-- ==============================================================================
-- 14.1 — Rôle de maintenance production marius_admin
-- ==============================================================================
-- Hérite de marius_user (SELECT + EXECUTE + USAGE séquences + USAGE schémas).
-- Reçoit en sus l'écriture directe sur toutes les tables physiques.
-- LOGIN activé pour les sessions de maintenance ; désactiver en environnement
-- hautement sécurisé et passer par SET ROLE depuis une session postgres.
CREATE ROLE marius_admin WITH LOGIN ENCRYPTED PASSWORD 'change_in_production';
GRANT marius_user TO marius_admin WITH INHERIT TRUE;

GRANT USAGE ON SCHEMA identity  TO marius_admin;
GRANT USAGE ON SCHEMA geo       TO marius_admin;
GRANT USAGE ON SCHEMA org       TO marius_admin;
GRANT USAGE ON SCHEMA commerce  TO marius_admin;
GRANT USAGE ON SCHEMA content   TO marius_admin;
GRANT USAGE ON SCHEMA meta      TO marius_admin;

GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA identity  TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA geo       TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA org       TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA commerce  TO marius_admin;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA content   TO marius_admin;

GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA identity  TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA geo       TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA org       TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA commerce  TO marius_admin;
GRANT USAGE, UPDATE ON ALL SEQUENCES IN SCHEMA content   TO marius_admin;

GRANT SELECT ON ALL TABLES IN SCHEMA meta TO marius_admin;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA meta TO marius_admin;

-- marius_admin doit contourner le RLS pour les opérations de maintenance et migrations.
-- Sans BYPASSRLS, ses UPDATE/INSERT directs seraient bloqués par les politiques RLS
-- activées sur content.core, commerce.transaction_core, identity.account_core.
-- BYPASSRLS est un attribut de rôle, pas un rôle grantable.
ALTER ROLE marius_admin BYPASSRLS;


-- ==============================================================================
-- SECTION 13 — Permissions marius_user (rôle applicatif runtime)
-- marius_user = SELECT (tables/vues) + EXECUTE (procédures/fonctions)
-- Jamais de droits INSERT/UPDATE/DELETE directs sur les tables.
-- ==============================================================================

-- Accès aux schémas (USAGE obligatoire pour référencer les objets)
GRANT USAGE ON SCHEMA identity  TO marius_user;
GRANT USAGE ON SCHEMA geo       TO marius_user;
GRANT USAGE ON SCHEMA org       TO marius_user;
GRANT USAGE ON SCHEMA commerce  TO marius_user;
GRANT USAGE ON SCHEMA content   TO marius_user;

-- Lecture des tables et vues — GRANT large par schéma, puis REVOKE ciblé
-- sur les tables sensibles (ADR-002 audit).
GRANT SELECT ON ALL TABLES IN SCHEMA identity  TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA geo       TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA org       TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA commerce  TO marius_user;
GRANT SELECT ON ALL TABLES IN SCHEMA content   TO marius_user;

-- REVOKE SELECT sur les tables physiques sensibles :
-- Accès uniquement via les vues sémantiques (Section 12) qui appliquent
-- le RLS ou contrôlent la projection (aucune colonne credential exposée).

-- identity.auth : hashes argon2id, état de bannissement
REVOKE SELECT ON identity.auth FROM marius_user;

-- identity.person_contact : email, téléphone — PII au sens RGPD
REVOKE SELECT ON identity.person_contact FROM marius_user;

-- commerce.transaction_payment : numéro de facture, méthode de paiement, référence PSP
REVOKE SELECT ON commerce.transaction_payment FROM marius_user;

-- commerce.transaction_delivery : numéro de suivi logistique
REVOKE SELECT ON commerce.transaction_delivery FROM marius_user;

-- commerce.transaction_price : montants, devise, taux de taxe
-- ADR-003 : sans ce REVOKE, un SELECT direct bypasse le RLS de transaction_core
-- (fragmentation ECS — le RLS d'un composant Core ne se propage pas aux satellites).
REVOKE SELECT ON commerce.transaction_price FROM marius_user;

-- commerce.transaction_item : lignes de commande — même vecteur de fuite
REVOKE SELECT ON commerce.transaction_item FROM marius_user;

-- content.identity : headline, slug, description de tous les documents (brouillons inclus)
REVOKE SELECT ON content.identity FROM marius_user;

-- content.body : corps HTML complet de tous les documents
REVOKE SELECT ON content.body FROM marius_user;

-- content.revision : snapshots éditoriaux complets
REVOKE SELECT ON content.revision FROM marius_user;

-- org.org_legal : DUNS, SIRET, TVA — identifiants légaux sensibles
-- ADR-003 inv.1 : satellite d'org.org_core, accessible directement sans ce REVOKE.
REVOKE SELECT ON org.org_legal FROM marius_user;

-- identity.v_auth : hash argon2id — interface d'authentification réservée
-- au middleware via connexion postgres ou fonction SECURITY DEFINER dédiée.
REVOKE SELECT ON identity.v_auth FROM marius_user;

-- USAGE séquences : permet currval() et inspection
-- Les nextval() des procédures passent via SECURITY DEFINER (owner = postgres).
GRANT USAGE ON ALL SEQUENCES IN SCHEMA identity  TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA geo       TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA org       TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA commerce  TO marius_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA content   TO marius_user;

-- Exécution des procédures et fonctions (seul chemin d'écriture autorisé)
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA identity TO marius_user;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA content  TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA identity TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA geo      TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA org      TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA commerce TO marius_user;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA content  TO marius_user;


-- ==============================================================================
-- 14.2 — Révocation globale DML sur marius_user (défense en profondeur)
-- ==============================================================================
-- Idempotent : marius_user n'a jamais reçu ces droits en section 13.
-- Ce bloc garantit l'invariant même si une migration future ajoute
-- accidentellement un GRANT DML sur marius_user.
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA identity  FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA geo       FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA org       FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA commerce  FROM marius_user;
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA content   FROM marius_user;
