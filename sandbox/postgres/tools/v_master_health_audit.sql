-- ==============================================================================
-- meta.v_master_health_audit
-- Architecture ECS/DOD · Projet Marius
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
-- Pré-requis : ANALYZE exécuté sur les tables auditées
--   (v_performance_sentinel requiert pg_stats.correlation et pg_stat_user_tables).
-- ==============================================================================

CREATE OR REPLACE VIEW meta.v_master_health_audit AS
WITH component_status AS (
    SELECT
        m.component_name,
        m.density_drift_alert,
        m.security_breach_alert,
        COALESCE(s.hot_blocker_alert, false)  AS hot_blocker_alert,
        COALESCE(s.brin_drift_alert,  false)  AS brin_drift_alert,
        -- bloat_alert brut : valeur physique réelle (toujours exposée pour diagnostic)
        COALESCE(s.bloat_alert, false)         AS bloat_alert,
        -- exempt_bloat_check : JOIN direct (tout composant de ECSM vient de containment_intent)
        ci.exempt_bloat_check
    FROM meta.v_extended_containment_security_matrix m
    LEFT JOIN meta.v_performance_sentinel s
        ON s.component_id = m.component_name
    -- JOIN (pas LEFT JOIN) : v_extended_containment_security_matrix est dérivé de
    -- meta.containment_intent → la clé existe toujours.
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
        -- bloat effectif : FALSE si le composant est exempté
        (bloat_alert AND NOT exempt_bloat_check) AS effective_bloat_alert,
        (
            (CASE WHEN security_breach_alert                         THEN 100 ELSE 0 END) +
            (CASE WHEN hot_blocker_alert                             THEN  60 ELSE 0 END) +
            (CASE WHEN density_drift_alert                           THEN  30 ELSE 0 END) +
            -- La pénalité bloat est neutralisée si exempt_bloat_check = TRUE
            (CASE WHEN bloat_alert AND NOT exempt_bloat_check        THEN  30 ELSE 0 END) +
            (CASE WHEN brin_drift_alert                              THEN  20 ELSE 0 END)
        ) AS debt_score
    FROM component_status
)
SELECT
    component_name,
    GREATEST(100 - debt_score, 0)                               AS health_score_pct,
    CASE
        WHEN debt_score = 0                THEN 'OPTIMAL'
        WHEN debt_score >= 100             THEN 'CRITICAL (SECURITY BREACH)'
        WHEN hot_blocker_alert             THEN 'SEVERE (HOT PATH BLOCKED)'
        ELSE                                    'WARNING (LAYOUT/DRIFT DEGRADATION)'
    END                                                         AS triage_status,
    security_breach_alert,
    hot_blocker_alert,
    density_drift_alert,
    -- bloat_alert : valeur physique brute (v_performance_sentinel) — diagnostic
    bloat_alert,
    -- effective_bloat_alert : après application de l'exemption — décision scoring
    effective_bloat_alert,
    -- exempt_bloat_check : flag source (pour audit du registre)
    exempt_bloat_check,
    brin_drift_alert
FROM scoring
ORDER BY health_score_pct ASC, component_name;

-- Sécurisation
REVOKE ALL ON meta.v_master_health_audit FROM PUBLIC;
GRANT SELECT ON meta.v_master_health_audit TO marius_admin;
