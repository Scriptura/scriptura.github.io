-- ==============================================================================
-- 01_meta/03_views.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : v_introspection_layout · v_introspection_security
--           · v_extended_containment_security_matrix
-- Source  : meta_registry.sql v2.2
-- Pré-requis : meta.containment_intent (01_tables.sql)
-- ==============================================================================

CREATE OR REPLACE VIEW meta.v_introspection_layout AS
WITH RECURSIVE

-- Ensemble des OIDs des composants enregistrés (résolution lazy via to_regclass)
registered_oids AS (
    SELECT to_regclass(component_id)::oid AS relid
    FROM   meta.containment_intent
    WHERE  to_regclass(component_id) IS NOT NULL
),

cols AS (
    SELECT
        a.attrelid,
        a.attnum,
        a.attname,
        -- Header dynamique : 23B fixe + null bitmap + MAXALIGN(8)
        -- Calculé une fois par relation via pg_class.relnatts
        (((23 + ceil(c.relnatts::numeric / 8))::int + 7) / 8 * 8) AS header_bytes,
        -- Taille effective : pg_stats pour varlena (avg_width inclut le header
        -- varlena et reflète les données réelles post-ANALYZE), taille fixe sinon.
        CASE
            WHEN a.attlen = -1 THEN
                COALESCE(
                    (SELECT s.avg_width
                     FROM   pg_stats s
                     WHERE  s.schemaname = n.nspname
                       AND  s.tablename  = c.relname
                       AND  s.attname    = a.attname
                     LIMIT 1),
                    4   -- Fallback si ANALYZE non exécuté : header varlena seul
                )
            ELSE a.attlen
        END AS effective_len,
        -- Alignement CPU de la colonne
        CASE a.attalign
            WHEN 'c' THEN 1   -- char  : 1B
            WHEN 's' THEN 2   -- short : 2B
            WHEN 'i' THEN 4   -- int   : 4B
            WHEN 'd' THEN 8   -- double: 8B
            ELSE             4
        END AS align_bytes,
        ROW_NUMBER() OVER (PARTITION BY a.attrelid ORDER BY a.attnum) AS seq
    FROM   pg_attribute  a
    JOIN   pg_class      c ON c.oid = a.attrelid
    JOIN   pg_namespace  n ON n.oid = c.relnamespace
    WHERE  a.attnum > 0
      AND  NOT a.attisdropped
      -- Performance : limite le scan aux composants enregistrés uniquement
      AND  a.attrelid = ANY(SELECT relid FROM registered_oids)
),

layout_calc (attrelid, seq, attname, offset_bytes, len_bytes, align_bytes, header_bytes) AS (
    -- Cas de base : première colonne à l'offset = header dynamique
    SELECT
        attrelid, seq, attname,
        header_bytes   AS offset_bytes,
        effective_len  AS len_bytes,
        align_bytes,
        header_bytes
    FROM cols
    WHERE seq = 1

    UNION ALL

    -- Récursion : offset = fin de la colonne précédente + padding d'alignement
    -- Formule : (align - (raw % align)) % align
    -- Le second modulo neutralise le cas "déjà aligné" (résultat = 0, pas align).
    SELECT
        c.attrelid,
        c.seq,
        c.attname,
        (l.offset_bytes + l.len_bytes
         + (c.align_bytes - ((l.offset_bytes + l.len_bytes) % c.align_bytes))
           % c.align_bytes
        )::int AS offset_bytes,
        c.effective_len,
        c.align_bytes,
        l.header_bytes
    FROM   cols c
    JOIN   layout_calc l
        ON c.attrelid = l.attrelid AND c.seq = l.seq + 1
)

SELECT
    attrelid                                                       AS component_id,
    -- Tuple final : MAXALIGN(8) sur la fin du dernier champ
    ((MAX(offset_bytes + len_bytes) + 7) / 8 * 8)::smallint       AS actual_density_bytes,
    -- Expose le header calculé pour diagnostic (colonne informative)
    MAX(header_bytes)::smallint                                     AS header_bytes_used,
    -- raw_data_bytes (v2.2 — Proposition 3 Waste Management) :
    --   Somme brute : header + données sans padding inter-colonnes ni tail MAXALIGN.
    --   padding_bytes = actual_density_bytes - raw_data_bytes.
    --   Interprétation : tout octet entre raw_data_bytes et actual_density_bytes est
    --   du padding d'alignement CPU — soit inter-colonnes (layout sous-optimal) soit
    --   tail padding MAXALIGN (inévitable sur toute table, ≤ 7B).
    (MAX(header_bytes) + SUM(len_bytes))::smallint                  AS raw_data_bytes
FROM layout_calc
GROUP BY attrelid;


-- ==============================================================================
-- 3. SCANNER DE SÉCURITÉ PROCÉDURALE (Introspection AOT)
-- ==============================================================================
-- Valide deux invariants ADR-001 sur chaque procédure déclarée :
--   A — SECURITY DEFINER actif (prosecdef = true)
--   B — search_path fixé ET sans schéma dangereux (public, $user)
--
-- CORRECTIONS v2 :
--
-- A — prokind = 'p' : filtrage sur les procédures (CALL) uniquement.
--   v1 incluait toutes les fonctions (triggers, helpers RLS, aggrégats).
--   Les fonctions SECURITY INVOKER par design (ex: rls_user_id()) généraient
--   des faux positifs dans la matrice.
--
-- B — Validation robuste du search_path
--   v1 : LIKE '%search_path=%' → TRUE pour search_path='' (dangereux)
--        et pour search_path='public,identity' (public en tête = injectable).
--   v2 : extrait la valeur via split_part(), valide :
--     - existence de la clé search_path dans proconfig
--     - valeur non vide (search_path='' = équivalent au défaut de session)
--     - absence de 'public' (substitution d'objet possible)
--     - absence de '$user' (résolution dynamique = non déterministe)

CREATE OR REPLACE VIEW meta.v_introspection_security AS
WITH sp_extract AS (
    SELECT
        oid,
        proname,
        prosecdef,
        -- Extraire la valeur brute : 'search_path=identity, pg_catalog'
        (SELECT split_part(cfg, '=', 2)
         FROM   unnest(proconfig) AS cfg
         WHERE  cfg LIKE 'search_path=%'
         LIMIT  1) AS sp_value
    FROM pg_proc
    WHERE prokind = 'p'   -- Procédures (CALL) uniquement, pas les fonctions
)
SELECT
    oid              AS proc_id,
    proname          AS proc_name,
    prosecdef        AS is_security_definer,
    -- Chemin sécurisé : présent, non vide, sans schéma à résolution dangereuse
    (
        sp_value IS NOT NULL
        AND  sp_value  <> ''
        AND  sp_value  NOT LIKE '%public%'
        AND  sp_value  NOT LIKE '%$user%'
    )                AS has_secured_path,
    sp_value         AS search_path_value   -- Valeur brute pour diagnostic
FROM sp_extract;


-- ==============================================================================
-- 4. MATRICE DE CONFORMITÉ ÉTENDUE (Extended Containment Security Matrix)
-- ==============================================================================
-- Croise le registre d'intention et le dictionnaire de données en temps réel.
-- Chaque colonne de type boolean est une alerte autonome : TRUE = dérive.
--
-- ALERTES :
--
-- component_not_found_alert (NOUVEAU v2)
--   to_regclass() retourne NULL si la table n'existe pas physiquement.
--   Utile dans un workflow migration : l'intention est déclarée avant la
--   création de la table — l'alerte passe automatiquement à FALSE une fois
--   le DDL appliqué.
--
-- density_drift_alert
--   Détecte un padding structurel non anticipé (ordre de colonnes sous-optimal,
--   type plus large que prévu) ou une croissance des données varlena (avg_width
--   en hausse après ANALYZE).
--   NOTA : si ANALYZE n'a pas été exécuté, actual_density_bytes reflète
--   uniquement les colonnes fixes + 4B par varlena (densité minimale).
--
-- missing_mutation_interface
--   Aucune procédure enregistrée, OU aucune des procédures déclarées n'est
--   résoluble via to_regprocedure() (procédure supprimée ou signature obsolète).
--
-- security_breach_alert
--   Au moins une procédure déclarée existe mais n'est plus SECURITY DEFINER
--   ou expose un search_path dangereux. Détecte les régressions post-ALTER.
--
-- JOINTURES :
--   LEFT JOIN sur v_introspection_layout : retourne NULL si table inexistante
--   (component_not_found_alert = TRUE → density_drift_alert indisponible).
--   La résolution des procédures via to_regprocedure() est lazy : une signature
--   obsolète produit NULL → non matchée dans la jointure sécurité.

CREATE OR REPLACE VIEW meta.v_extended_containment_security_matrix AS
SELECT
    ci.component_id                                              AS component_name,

    -- 0. Existence physique du composant
    (to_regclass(ci.component_id) IS NULL)                      AS component_not_found_alert,

    -- 1. Densité DOD
    ci.intent_density_bytes,
    ts.actual_density_bytes,
    ts.header_bytes_used,
    (ts.actual_density_bytes > ci.intent_density_bytes)         AS density_drift_alert,

    -- 2. Interface de mutation ECS
    (
        ci.mutation_procedures IS NULL
        OR NOT EXISTS (
            SELECT 1
            FROM   unnest(ci.mutation_procedures) AS p(sig)
            WHERE  to_regprocedure(p.sig) IS NOT NULL
        )
    )                                                           AS missing_mutation_interface,

    -- 3. Sécurité procédurale
    (
        ci.mutation_procedures IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM   unnest(ci.mutation_procedures) AS p(sig)
            JOIN   meta.v_introspection_security ps
                   ON ps.proc_id = to_regprocedure(p.sig)
            WHERE  NOT ps.is_security_definer
               OR  NOT ps.has_secured_path
        )
    )                                                           AS security_breach_alert,

    -- Colonnes de diagnostic (non-booléennes)
    ci.mutation_procedures,
    ci.immutable_keys,
    ci.rls_guard_bitmask,

    -- 4. Flag d'exemption bloat (v2.1)
    ci.exempt_bloat_check,

    -- ── Nouvelles colonnes de diagnostic v2.2 ────────────────────────────────

    -- 5. Positive drift (Proposition 2 — recadrage correct)
    --    Quantifie les octets gagnés quand actual < intent.
    --    Interprétation : ANALYZE a mesuré des données plus compactes que
    --    l'estimation pre-ANALYZE (ex: varlena courtes inline, NULLs fréquents).
    --    N'affecte PAS density_drift_alert (unidirectionnel : actual > intent).
    --    NULL si la table n'existe pas physiquement (component_not_found_alert).
    CASE
        WHEN ts.actual_density_bytes IS NULL          THEN NULL
        WHEN ts.actual_density_bytes < ci.intent_density_bytes
        THEN (ci.intent_density_bytes - ts.actual_density_bytes)::smallint
        ELSE 0::smallint
    END                                                         AS positive_drift_bytes,

    -- 6. Structural padding (Proposition 3 — Waste Management)
    --    padding_bytes = actual_density_bytes - raw_data_bytes.
    --    = alignement intra-tuple + tail MAXALIGN, en octets.
    --    Tout padding >= 8B sur une table fixe signale un layout sous-optimal.
    --    Sur une table varlena post-ANALYZE, la valeur peut légitimement dépasser
    --    8B (tail MAXALIGN après une colonne de grande avg_width).
    --    Voir padding_category dans v_master_health_audit pour la catégorisation.
    (ts.actual_density_bytes - ts.raw_data_bytes)               AS padding_bytes,

    -- 7. DOD efficiency ratio (Proposition 1 — Cache Multiplier)
    --    = naive_density_bytes / intent_density_bytes.
    --    Interprétation : 1.25 → le layout DOD est 25% plus dense que le layout naïf
    --    (25% de tuples supplémentaires par page = 25% de I/O en moins sur seq scan).
    --    NULL si naive_density_bytes non renseigné dans meta.containment_intent.
    --    À renseigner via f_generate_dod_template sur la liste de colonnes pré-DOD.
    CASE
        WHEN ci.naive_density_bytes IS NOT NULL AND ci.intent_density_bytes > 0
        THEN (ci.naive_density_bytes::numeric / ci.intent_density_bytes)::numeric(4, 2)
        ELSE NULL
    END                                                         AS dod_efficiency_ratio,

    -- Exposition des valeurs brutes pour diagnostic
    ts.raw_data_bytes

FROM       meta.containment_intent          ci
LEFT JOIN  meta.v_introspection_layout      ts
           ON ts.component_id = to_regclass(ci.component_id)::oid;

