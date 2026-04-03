-- ==============================================================================
-- 11_audit/02_v_master_health_audit.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Source  : v_master_health_audit.sql v2.2
-- Pré-requis : 11_audit/01_v_performance_sentinel.sql
--              meta.v_extended_containment_security_matrix (01_meta/03_views.sql)
--              meta.containment_intent (10_meta_seed/01_manifest.sql)
-- ==============================================================================

-- ==============================================================================
-- meta.v_master_health_audit
-- Architecture ECS/DOD · Projet Marius · v2.2
--
-- Vue d'audit de santé globale : croise v_extended_containment_security_matrix,
-- v_performance_sentinel et meta.containment_intent pour produire un score de
-- santé par composant.
--
-- Scoring (debt_score → health_score_pct = MAX(100 - debt_score, 0)) :
--   security_breach_alert  : 100 pts  (CRITICAL — procédure compromise)
--   hot_blocker_alert      :  60 pts  (SEVERE  — HOT path bloqué)
--   density_drift_alert    :  30 pts  (WARNING — padding structurel)
--   bloat_alert (effectif) :  30 pts  (WARNING — densité page dégradée)
--   brin_drift_alert       :  20 pts  (WARNING — corrélation BRIN < 0.90)
--
-- exempt_bloat_check (v2.1) :
--   Quand ci.exempt_bloat_check = TRUE, la contribution bloat est neutralisée
--   dans le calcul de debt_score. Le bloat_alert brut (v_performance_sentinel)
--   reste exposé pour diagnostic mais ne pénalise pas le score. Réservé aux
--   tables de configuration structurelle immuables en production (ex: identity.role)
--   dont la faible cardinalité rend le bloat physique inévitable et inoffensif.
--
-- padding_category (v2.2 — Proposition 3 Waste Management) :
--   Catégorise le gaspillage structurel en octets par tuple (padding inter-colonnes
--   + tail MAXALIGN). Colonne informative — ne contribue PAS au debt_score
--   (density_drift_alert couvre déjà les dérives de layout).
--   Seuils sur architecture 64-bit (MAXALIGN = 8B) :
--     OPTIMAL    : padding < 4B  — layout DOD correct, seul tail padding <= 3B
--     WARNING    : 4-7B          — un gap inter-colonnes subsiste
--     INVESTIGATE: >= 8B         — au moins une unité MAXALIGN gaspillée ;
--                                  sur table fixe = layout cassé ;
--                                  sur table varlena post-ANALYZE : peut être
--                                  tail padding légitime (croiser avec
--                                  density_drift_alert avant d'agir).
--     NULL       : table inexistante ou ANALYZE non exécuté
--
-- Idempotence :
--   Exécuté dans un pipeline d'installation fraîche (master_init.sql recrée
--   la base via DROP DATABASE). CREATE VIEW suffit — pas de DROP préventif.
--   Pour une réapplication isolée hors pipeline : DROP VIEW IF EXISTS
--   meta.v_master_health_audit CASCADE; avant ce fichier.
--
-- Pré-requis : ANALYZE exécuté sur les tables auditées.
-- ==============================================================================

CREATE VIEW meta.v_master_health_audit AS
WITH component_status AS (
    SELECT
        m.component_name,
        m.density_drift_alert,
        m.security_breach_alert,
        COALESCE(s.hot_blocker_alert, false)  AS hot_blocker_alert,
        COALESCE(s.brin_drift_alert,  false)  AS brin_drift_alert,
        COALESCE(s.bloat_alert, false)         AS bloat_alert,
        ci.exempt_bloat_check,
        m.padding_bytes
    FROM meta.v_extended_containment_security_matrix m
    LEFT JOIN meta.v_performance_sentinel s
        ON s.component_id = m.component_name
    JOIN meta.containment_intent ci
        ON ci.component_id = m.component_name
),
scoring AS (
    SELECT
        component_name,
        density_drift_alert,
        security_breach_alert,
        hot_blocker_alert,
        brin_drift_alert,
        bloat_alert,
        exempt_bloat_check,
        padding_bytes,
        (bloat_alert AND NOT exempt_bloat_check)  AS effective_bloat_alert,
        (
            (CASE WHEN security_breach_alert                   THEN 100 ELSE 0 END) +
            (CASE WHEN hot_blocker_alert                       THEN  60 ELSE 0 END) +
            (CASE WHEN density_drift_alert                     THEN  30 ELSE 0 END) +
            (CASE WHEN bloat_alert AND NOT exempt_bloat_check  THEN  30 ELSE 0 END) +
            (CASE WHEN brin_drift_alert                        THEN  20 ELSE 0 END)
        ) AS debt_score
    FROM component_status
)
SELECT
    component_name,
    GREATEST(100 - debt_score, 0)                   AS health_score_pct,
    CASE
        WHEN debt_score = 0     THEN 'OPTIMAL'
        WHEN debt_score >= 100  THEN 'CRITICAL (SECURITY BREACH)'
        WHEN hot_blocker_alert  THEN 'SEVERE (HOT PATH BLOCKED)'
        ELSE                         'WARNING (LAYOUT/DRIFT DEGRADATION)'
    END                                             AS triage_status,
    security_breach_alert,
    hot_blocker_alert,
    density_drift_alert,
    bloat_alert,
    effective_bloat_alert,
    exempt_bloat_check,
    brin_drift_alert,
    CASE
        WHEN padding_bytes IS NULL  THEN NULL
        WHEN padding_bytes < 4      THEN 'OPTIMAL'
        WHEN padding_bytes < 8      THEN 'WARNING'
        ELSE                             'INVESTIGATE'
    END                                             AS padding_category,
    padding_bytes
FROM scoring
ORDER BY health_score_pct ASC, component_name;

REVOKE ALL   ON meta.v_master_health_audit FROM PUBLIC;
GRANT SELECT ON meta.v_master_health_audit TO marius_admin;
