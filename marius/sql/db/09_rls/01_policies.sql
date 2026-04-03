-- ==============================================================================
-- 09_rls/01_policies.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : activation RLS + politiques sur content.core, commerce.transaction_core,
--           identity.account_core, content.comment (section 15)
--
-- Architecture : la couche applicative injecte deux GUC dans chaque session :
--   SET LOCAL marius.user_id   = '<entity_id>'
--   SET LOCAL marius.auth_bits = '<bitmask INT4>'
--
-- Les helpers rls_user_id() / rls_auth_bits() (définis en 02_identity/02_systems.sql)
-- lisent ces GUC via current_setting(..., true) — retourne NULL si absent
-- (session système, seed CI/CD, connexion postgres directe) → fallback -1 / 0.
--
-- Superutilisateurs (postgres) et marius_admin (BYPASSRLS) contournent le RLS.
-- Ce contournement est intentionnel : les procédures SECURITY DEFINER s'exécutent
-- en tant que postgres et doivent pouvoir écrire sans restriction (ADR-001).
-- Les tables sensibles (identity.auth, person_contact, transaction_payment,
-- transaction_delivery) ont leur SELECT révoqué en 08_dcl/01_grants.sql —
-- le RLS est une défense complémentaire, pas le seul mécanisme.
-- ==============================================================================

-- ── 15.1 — content.core ──────────────────────────────────────────────────────
-- Politique SELECT :
--   Ligne visible si publiée (status=1)
--   OU si l'utilisateur possède publish_contents (bit 4, valeur 16)
--   OU si l'utilisateur possède edit_others_contents (bit 15, valeur 32768)
--   OU si l'utilisateur est l'auteur de la ligne.
-- Note ADR-003 : tout bit accordant UPDATE ou DELETE sur cette table doit figurer
-- aussi dans le USING SELECT, sans quoi la politique d'écriture est structurellement
-- inatteignable (PostgreSQL évalue le filtre SELECT avant d'accorder l'écriture).
--
-- Politique UPDATE/DELETE :
--   Permissive A : auteur ET edit_contents(4) pour UPDATE
--                  auteur ET delete_contents(8) pour DELETE (ADR-003)
--   Permissive B : edit_others_contents(32768) → édition/suppression globale
-- Note ADR-003 : delete_own vérifie delete_contents(8) et non edit_contents(4).

ALTER TABLE content.core ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_core_select ON content.core
    FOR SELECT
    USING (
        status = 1
        OR (identity.rls_auth_bits() & 16)    = 16
        OR (identity.rls_auth_bits() & 32768) = 32768
        OR author_entity_id = identity.rls_user_id()
    );

-- Auteur peut modifier son propre contenu (edit_contents requis)
CREATE POLICY rls_core_update_own ON content.core
    FOR UPDATE
    USING (
        author_entity_id = identity.rls_user_id()
        AND (identity.rls_auth_bits() & 4) = 4
    )
    WITH CHECK (
        author_entity_id = identity.rls_user_id()
        AND (identity.rls_auth_bits() & 4) = 4
    );

-- Éditeur peut modifier n'importe quel contenu
CREATE POLICY rls_core_update_others ON content.core
    FOR UPDATE
    USING (
        (identity.rls_auth_bits() & 32768) = 32768
    )
    WITH CHECK (
        (identity.rls_auth_bits() & 32768) = 32768
    );

-- Suppression propre : auteur ET delete_contents (bit 3, valeur 8)
CREATE POLICY rls_core_delete_own ON content.core
    FOR DELETE
    USING (
        author_entity_id = identity.rls_user_id()
        AND (identity.rls_auth_bits() & 8) = 8
    );

-- Suppression globale : edit_others_contents
CREATE POLICY rls_core_delete_others ON content.core
    FOR DELETE
    USING (
        (identity.rls_auth_bits() & 32768) = 32768
    );


-- ── 15.2 — commerce.transaction_core ─────────────────────────────────────────
-- Politique SELECT :
--   Ligne visible si l'utilisateur est le client (isolation stricte)
--   OU view_transactions (bit 17, valeur 131072)
--   OU manage_commerce (bit 18, valeur 262144)
-- Note ADR-003 invariant 3 : manage_commerce est requis dans USING UPDATE ;
-- il doit figurer aussi dans USING SELECT pour que la politique soit atteignable.
--
-- Politique UPDATE : uniquement manage_commerce.
-- Un client ne peut jamais modifier sa propre transaction.

ALTER TABLE commerce.transaction_core ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_transaction_select ON commerce.transaction_core
    FOR SELECT
    USING (
        client_entity_id = identity.rls_user_id()
        OR (identity.rls_auth_bits() & 131072) = 131072
        OR (identity.rls_auth_bits() & 262144) = 262144
    );

CREATE POLICY rls_transaction_update ON commerce.transaction_core
    FOR UPDATE
    USING (
        (identity.rls_auth_bits() & 262144) = 262144
    )
    WITH CHECK (
        (identity.rls_auth_bits() & 262144) = 262144
    );


-- ── 15.3 — identity.account_core ─────────────────────────────────────────────
-- Politique SELECT : compte visible si c'est le sien OU manage_users (256).
-- Politique UPDATE : identique au SELECT.

ALTER TABLE identity.account_core ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_account_select ON identity.account_core
    FOR SELECT
    USING (
        entity_id = identity.rls_user_id()
        OR (identity.rls_auth_bits() & 256) = 256
    );

CREATE POLICY rls_account_update ON identity.account_core
    FOR UPDATE
    USING (
        entity_id = identity.rls_user_id()
        OR (identity.rls_auth_bits() & 256) = 256
    )
    WITH CHECK (
        entity_id = identity.rls_user_id()
        OR (identity.rls_auth_bits() & 256) = 256
    );


-- ── 15.4 — content.comment ───────────────────────────────────────────────────
-- Politique SELECT :
--   status = 1 (commentaire approuvé) : visible de tous.
--   OU auteur du commentaire : voit ses propres commentaires en attente/rejetés.
--   OU moderate_comments (bit 16, valeur 65536) : modérateurs voient tout.
-- Note ADR-003 invariant 3 : marius_user n'a pas de DML direct sur content.comment
-- (ADR-001) → pas de politique UPDATE/DELETE nécessaire sur ce chemin.

ALTER TABLE content.comment ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_comment_select ON content.comment
    FOR SELECT
    USING (
        status = 1
        OR account_entity_id = identity.rls_user_id()
        OR (identity.rls_auth_bits() & 65536) = 65536
    );
