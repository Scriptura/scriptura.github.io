-- ==============================================================================
-- 11_audit/01_v_performance_sentinel.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Source  : v_performance_sentinel.sql
-- Pré-requis : meta.containment_intent (10_meta_seed/01_manifest.sql)
--              toutes les tables physiques (02–06) + ANALYZE exécuté
-- ==============================================================================

-- ==============================================================================
-- meta.v_performance_sentinel
-- Architecture ECS/DOD · PostgreSQL 18 · Projet Marius
--
-- Vue d'audit de performance : croise les statistiques runtime et le catalogue
-- pour detecter les regressions introduites par des modifications de schema.
--
-- 3 piliers d'alerte :
--
-- HOT-BLOCKER
--   Condition : n_tup_upd > 0 ET existence d'au moins une colonne indexee
--   non declaree dans immutable_keys (colonne mutable + indexee = HOT bloque).
--   Tous types d'index bloquent HOT (B-tree, BRIN, GiST, GIN, Hash).
--   hot_blocker_cols text[] : colonnes responsables, pour diagnostic.
--   Fondement : immutable_keys materialise l'invariant "post-INSERT jamais
--   modifie" (ADR-010, triggers immutabilite). Hors de cet ensemble => mutable.
--
-- BRIN-DRIFT
--   Condition : abs(correlation) < 0.90 sur la colonne d'un index BRIN.
--   Plusieurs BRIN => pire correlation retenue (MIN abs sur l'ensemble).
--   brin_worst_col : colonne la plus degradee.
--   Prerequis : ANALYZE execute (pg_stats.correlation). NULL = pas d'alerte.
--
-- BLOAT (densite DOD, fillfactor-corrige)
--   Condition : pg_relation_size / n_live_tup
--               > (intent_density_bytes / fillfactor_ratio) * 1.20
--
--   Le seuil est divise par fillfactor_ratio (ex : 0.70 pour identity.auth,
--   0.80 pour product_core). Sans cette correction, pg_relation_size / n_live_tup
--   inclut les pages reservees par fillfactor, provoquant des faux positifs
--   systematiques sur toute table avec fillfactor < 100 :
--     identity.auth    ff=70  intent=160 B : observed=241 B > naive_threshold=192 B  [FP sans correction]
--     product_core     ff=80  intent= 48 B : observed= 66 B > naive_threshold= 58 B  [FP sans correction]
--   Avec correction :
--     identity.auth    ff_threshold=274 B : 241 < 274  -> pas d'alerte [OK]
--     product_core     ff_threshold= 72 B :  66 <  72  -> pas d'alerte [OK]
--
--   Court-circuit exempt_bloat_check :
--     Lorsque le flag est TRUE dans meta.containment_intent, bloat_alert est
--     force a FALSE independamment du ratio observe. Prevu pour les tables
--     dictionnaire (faible cardinalite structurelle, immuables en production) :
--     identity.role (7 lignes, REVOKE INSERT/UPDATE/DELETE). Le "bloat" detecte
--     sur ces tables est un artefact de la page quasi-vide, pas une derive.
--
--   bloat_threshold_bytes et observed_bytes_per_tuple sont exposes pour diagnostic.
--   NULL si n_live_tup = 0 (table vide ou stats absentes).
--
-- Prerequis : ANALYZE execute sur les tables auditees.
-- ==============================================================================

CREATE OR REPLACE VIEW meta.v_performance_sentinel AS
WITH

-- ---- Base : composants enregistres, resolus, avec fillfactor ----------------
components AS (
    SELECT
        ci.component_id,
        ci.intent_density_bytes,
        ci.immutable_keys,
        ci.exempt_bloat_check,
        pc.oid                                      AS reloid,
        n.nspname                                   AS schemaname,
        pc.relname                                  AS tablename,
        -- Extraction fillfactor depuis pg_class.reloptions (defaut 100)
        COALESCE(
            (SELECT regexp_replace(opt, '^fillfactor=', '')::int
               FROM unnest(pc.reloptions) AS t(opt)
              WHERE t.opt LIKE 'fillfactor=%'
             LIMIT 1),
            100
        )::numeric / 100.0                          AS fillfactor_ratio
    FROM  meta.containment_intent      ci
    JOIN  pg_catalog.pg_class          pc ON pc.oid       = to_regclass(ci.component_id)::oid
    JOIN  pg_catalog.pg_namespace      n  ON n.oid        = pc.relnamespace
    WHERE to_regclass(ci.component_id) IS NOT NULL
),

-- ---- Statistiques runtime par table -----------------------------------------
tbl_stats AS (
    SELECT
        psu.relid,
        psu.n_tup_upd,
        psu.n_live_tup
    FROM pg_catalog.pg_stat_user_tables psu
),

-- ---- Pilier 1 : colonnes indexees mutables (HOT-blockers) -------------------
-- Pour chaque composant, collecte les colonnes incluses dans au moins un index
-- non-PK, non-EXCLUSION, et absentes de immutable_keys.
-- Ces colonnes bloquent HOT si elles sont modifiees par un UPDATE.
hot_blockers AS (
    SELECT
        c.component_id,
        array_agg(DISTINCT a.attname ORDER BY a.attname) AS blocking_cols
    FROM  components              c
    JOIN  pg_catalog.pg_index     i  ON  i.indrelid    = c.reloid
                                     AND NOT i.indisprimary
                                     AND NOT i.indisexclusion
    JOIN  pg_catalog.pg_attribute a  ON  a.attrelid    = i.indrelid
                                     AND a.attnum      = ANY(i.indkey::smallint[])
                                     AND a.attnum      > 0
                                     AND NOT a.attisdropped
    WHERE
        -- Exclure les colonnes declarees immutables dans le registre AOT
        (c.immutable_keys IS NULL OR a.attname != ALL(c.immutable_keys))
    GROUP BY c.component_id
),

-- ---- Pilier 2 : sante BRIN (correlation physique) ---------------------------
-- Pour chaque composant portant un ou plusieurs index BRIN, retient la colonne
-- avec la pire correlation (MIN abs). Un BRIN perd son efficacite quand les
-- MIN/MAX par plage de pages ne bornent plus les valeurs cibles.
brin_health AS (
    SELECT DISTINCT ON (c.component_id)
        c.component_id,
        a.attname                             AS brin_worst_col,
        ABS(ps.correlation)::numeric(5, 4)    AS min_abs_correlation
    FROM  components              c
    JOIN  pg_catalog.pg_index     i   ON  i.indrelid  = c.reloid
    JOIN  pg_catalog.pg_class     ic  ON  ic.oid      = i.indexrelid
    JOIN  pg_catalog.pg_am        am  ON  am.oid      = ic.relam
                                      AND am.amname   = 'brin'
    -- Premier token de indkey = colonne de sequencage du BRIN
    JOIN  pg_catalog.pg_attribute a   ON  a.attrelid  = i.indrelid
                                      AND a.attnum    = (i.indkey::smallint[])[1]
                                      AND a.attnum    > 0
                                      AND NOT a.attisdropped
    LEFT JOIN pg_catalog.pg_stats ps  ON  ps.schemaname = c.schemaname
                                      AND ps.tablename  = c.tablename
                                      AND ps.attname    = a.attname
    WHERE ps.correlation IS NOT NULL   -- pas d'alerte sans statistiques ANALYZE
    ORDER BY
        c.component_id,
        ABS(ps.correlation) ASC NULLS LAST   -- pire correlation en tete
)

-- ---- Assemblage final -------------------------------------------------------
SELECT
    c.component_id,

    -- ── Pilier 1 : HOT-BLOCKER ───────────────────────────────────────────────
    (   COALESCE(s.n_tup_upd, 0) > 0
        AND hb.component_id IS NOT NULL
    )::boolean                                          AS hot_blocker_alert,
    hb.blocking_cols                                    AS hot_blocker_cols,
    COALESCE(s.n_tup_upd, 0)                           AS n_tup_upd,

    -- ── Pilier 2 : BRIN-DRIFT ────────────────────────────────────────────────
    (bh.min_abs_correlation < 0.90)::boolean            AS brin_drift_alert,
    bh.brin_worst_col,
    bh.min_abs_correlation                              AS brin_correlation,

    -- ── Pilier 3 : BLOAT (fillfactor-corrige) ────────────────────────────────
    -- Court-circuit : exempt_bloat_check = TRUE → FALSE inconditionnel.
    -- Tables dictionnaire (identity.role etc.) : bloat structurel inévitable,
    -- pas une derive. La pénalité de scoring serait un faux positif permanent.
    CASE
        WHEN c.exempt_bloat_check
        THEN FALSE
        WHEN NULLIF(s.n_live_tup, 0) IS NULL
        THEN NULL::boolean
        WHEN pg_catalog.pg_relation_size(c.reloid)::numeric / s.n_live_tup
             > (c.intent_density_bytes / c.fillfactor_ratio) * 1.20
        THEN TRUE
        ELSE FALSE
    END                                                 AS bloat_alert,
    c.intent_density_bytes,
    -- Seuil effectif apres correction fillfactor (pour diagnostic)
    ((c.intent_density_bytes / c.fillfactor_ratio) * 1.20)::int
                                                        AS bloat_threshold_bytes,
    -- Densite observee brute (pg_relation_size / n_live_tup)
    CASE
        WHEN NULLIF(s.n_live_tup, 0) IS NOT NULL
        THEN (pg_catalog.pg_relation_size(c.reloid)::numeric / s.n_live_tup)::int
        ELSE NULL
    END                                                 AS observed_bytes_per_tuple,
    -- Fillfactor source pour traçabilite
    (c.fillfactor_ratio * 100)::int                    AS fillfactor_pct,
    s.n_live_tup

FROM      components   c
LEFT JOIN tbl_stats    s   ON  s.relid         = c.reloid
LEFT JOIN hot_blockers hb  ON  hb.component_id = c.component_id
LEFT JOIN brin_health  bh  ON  bh.component_id = c.component_id;

COMMENT ON VIEW meta.v_performance_sentinel IS
    'Audit de performance AOT/DOD : '
    'HOT-BLOCKER (colonnes mutables indexees via immutable_keys + pg_index), '
    'BRIN-DRIFT (correlation physique < 0.90, pire cas multi-BRIN), '
    'BLOAT (pg_relation_size / n_live_tup vs intent_density / fillfactor * 1.20). '
    'Court-circuit exempt_bloat_check : bloat_alert=FALSE pour les tables '
    'dictionnaire (faible cardinalite, immuables en production — identity.role). '
    'Correction fillfactor obligatoire : tables ff<100 (auth ff=70, product_core ff=80) '
    'produisent des faux positifs sans elle. '
    'Prerequis : ANALYZE execute. ADR-006 / ADR-010 / ADR-030 . meta_registry v2.';

-- ---- DCL : acces restreint a marius_admin -----------------------------------
-- La vue interroge pg_stats, pg_stat_user_tables et pg_relation_size --
-- informations structurelles et volumetriques internes. Hors perimetre runtime.
REVOKE ALL    ON meta.v_performance_sentinel FROM PUBLIC;
GRANT  SELECT ON meta.v_performance_sentinel TO marius_admin;
