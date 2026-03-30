-- ==============================================================================
-- meta.v_master_health_audit
-- Architecture ECS/DOD · Projet Marius
-- ==============================================================================

CREATE OR REPLACE VIEW meta.v_master_health_audit AS
WITH component_status AS (
    SELECT 
        m.component_name,
        m.density_drift_alert,
        m.security_breach_alert,
        COALESCE(s.hot_blocker_alert, false) AS hot_blocker_alert,
        COALESCE(s.brin_drift_alert, false) AS brin_drift_alert,
        COALESCE(s.bloat_alert, false) AS bloat_alert
    FROM meta.v_extended_containment_security_matrix m
    LEFT JOIN meta.v_performance_sentinel s 
        ON m.component_name = s.component_id
),
scoring AS (
    SELECT 
        component_name,
        density_drift_alert,
        security_breach_alert,
        hot_blocker_alert,
        brin_drift_alert,
        bloat_alert,
        (
            (CASE WHEN security_breach_alert THEN 100 ELSE 0 END) +
            (CASE WHEN hot_blocker_alert THEN 60 ELSE 0 END) +
            (CASE WHEN density_drift_alert THEN 30 ELSE 0 END) +
            (CASE WHEN bloat_alert THEN 30 ELSE 0 END) +
            (CASE WHEN brin_drift_alert THEN 20 ELSE 0 END)
        ) AS debt_score
    FROM component_status
)
SELECT 
    component_name,
    GREATEST(100 - debt_score, 0) AS health_score_pct,
    CASE 
        WHEN debt_score = 0 THEN 'OPTIMAL'
        WHEN debt_score >= 100 THEN 'CRITICAL (SECURITY BREACH)'
        WHEN hot_blocker_alert THEN 'SEVERE (HOT PATH BLOCKED)'
        ELSE 'WARNING (LAYOUT/DRIFT DEGRADATION)'
    END AS triage_status,
    security_breach_alert,
    hot_blocker_alert,
    density_drift_alert,
    bloat_alert,
    brin_drift_alert
FROM scoring
ORDER BY health_score_pct ASC, component_name;

-- Sécurisation
REVOKE ALL ON meta.v_master_health_audit FROM PUBLIC;
GRANT SELECT ON meta.v_master_health_audit TO marius_admin;
