-- ==============================================================================
-- 01_meta/01_tables.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : meta.containment_intent (registre d'intention AOT) + migrations
-- Source  : meta_registry.sql v2.2
-- ==============================================================================

-- ==============================================================================
-- REGISTRE D'INTENTION (Source of Truth architecturale)
-- ==============================================================================
-- Chaque ligne déclare les invariants d'un composant ECS. L'outil compare
-- cette intention à la réalité extraite de pg_catalog.
--
-- component_id TEXT (pas regclass) :
--   Stocke le nom qualifié ('schema.table'). to_regclass() est utilisé dans
--   les vues pour la résolution — retourne NULL si la table n'existe pas encore
--   au lieu de lever une erreur. Permet la pré-déclaration d'un composant avant
--   sa création physique (workflow migration : intention déclarée → DDL appliqué
--   → alerte component_not_found_alert passe de TRUE à FALSE).
--   Contrepartie : un renommage de table n'est pas suivi automatiquement
--   (contrairement à regclass qui stocke l'OID). Mise à jour manuelle requise.
--
-- mutation_procedures TEXT[] (pas regprocedure) :
--   Plusieurs procédures peuvent écrire le même composant (ex: identity.auth
--   est écrit par create_account, record_login ET anonymize_person). Le modèle
--   1:1 est architecturalement incorrect pour un système ECS. Format attendu :
--   signature complète avec types d'arguments pour to_regprocedure() :
--   'identity.record_login(integer)'.
--
-- immutable_keys name[] :
--   Colonnes scellées post-INSERT (FK spine, clés de tri BRIN...). Métadonnée
--   documentaire — les triggers d'immuabilité correspondants sont vérifiés
--   dans les tests pgTAP (11_meta_audit.sql).
--
-- exempt_bloat_check BOOLEAN :
--   Neutralise la contribution bloat dans le scoring de v_master_health_audit.
--   Réservé aux tables de configuration structurelle (cardinalité fixe, mutations
--   REVOKE'd en production). N'affecte pas v_performance_sentinel ni
--   density_drift_alert — la réalité physique reste visible pour diagnostic.
--
-- naive_density_bytes SMALLINT NULL (v2.2) :
--   Taille du tuple padded si les colonnes étaient dans leur ordre naturel pré-DOD
--   (non optimisé), produite par f_generate_dod_template sur la liste originale.
--   NULL = non renseigné (métrique optionnelle, aucun effet sur les alertes).
--   Le ratio dod_efficiency_ratio = naive / intent est exposé dans
--   v_extended_containment_security_matrix comme KPI architectural.

CREATE TABLE IF NOT EXISTS meta.containment_intent (
    component_id          TEXT      NOT NULL PRIMARY KEY,
    intent_density_bytes  SMALLINT  NOT NULL,
    rls_guard_bitmask     INT       NULL,
    mutation_procedures   TEXT[]    NULL,
    immutable_keys        name[]    NULL,

    CONSTRAINT intent_density_positive  CHECK (intent_density_bytes > 0),
    CONSTRAINT component_id_format      CHECK (component_id ~ '^[a-z_]+\.[a-z_0-9]+$')
);

-- ── Migrations idempotentes ────────────────────────────────────────────────────
-- Chaque colonne ajoutée après la version initiale est déclarée via ADD COLUMN IF
-- NOT EXISTS. Ce bloc est sans effet sur une base fraîche (les colonnes sont déjà
-- présentes via CREATE TABLE IF NOT EXISTS qui aurait créé la table complète) et
-- applique uniquement les colonnes manquantes sur une base existante à une version
-- antérieure.

-- v2.1 — exempt_bloat_check
ALTER TABLE meta.containment_intent
    ADD COLUMN IF NOT EXISTS exempt_bloat_check BOOLEAN NOT NULL DEFAULT false;

-- v2.2 — naive_density_bytes + contraintes associées
ALTER TABLE meta.containment_intent
    ADD COLUMN IF NOT EXISTS naive_density_bytes SMALLINT NULL;

-- Contraintes ajoutées en v2.2 — idempotentes via DO/EXCEPTION.
-- pg_constraint n'a pas de IF NOT EXISTS ; on teste l'existence avant d'ajouter.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'naive_density_positive'
          AND conrelid = 'meta.containment_intent'::regclass
    ) THEN
        ALTER TABLE meta.containment_intent
            ADD CONSTRAINT naive_density_positive
            CHECK (naive_density_bytes IS NULL OR naive_density_bytes > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'naive_gte_intent'
          AND conrelid = 'meta.containment_intent'::regclass
    ) THEN
        ALTER TABLE meta.containment_intent
            ADD CONSTRAINT naive_gte_intent
            CHECK (naive_density_bytes IS NULL OR naive_density_bytes >= intent_density_bytes);
    END IF;
END;
$$;
