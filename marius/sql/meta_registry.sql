-- ==============================================================================
-- META-REGISTRY v2.2 — Extended Containment Security Matrix (ECSM)
-- Architecture ECS/DOD · PostgreSQL 18
--
-- Objectif : Détection AOT (Ahead-Of-Time) des dérives structurelles et
-- sécuritaires entre l'intention architecturale (ADR) et le dictionnaire de
-- données réel (pg_catalog + pg_stats).
--
-- Corrections v2 par rapport à v1 (Gemini) :
--   1. Null bitmap dynamique : header = f(n_cols), pas 24B fixe
--   2. Densité varlena : pg_stats.avg_width (données réelles), pas 4B fixe
--   3. Performance : filtrage pg_attribute sur les OIDs enregistrés uniquement
--   4. component_id TEXT : permet la pré-déclaration avant création physique
--   5. mutation_procedures TEXT[] : modèle N:1 (plusieurs procédures par composant)
--   6. search_path robuste : extraction et validation de la valeur, pas juste
--      la présence de la clé
--   7. prokind = 'p' : filtrage sur les procédures uniquement
--   8. Nouvelle alerte : component_not_found_alert
--
-- v2.1 — Ajout exempt_bloat_check :
--   9. exempt_bloat_check BOOLEAN : neutralise le scoring bloat dans
--      v_master_health_audit pour les tables de configuration structurelle.
--
-- v2.2 — Métriques architecturales (intégration propositions Gemini) :
--  10. naive_density_bytes SMALLINT NULL : densité pre-DOD (pré-optimisation),
--      source du dod_efficiency_ratio. À renseigner via f_generate_dod_template.
--  11. raw_data_bytes dans v_introspection_layout : header + SUM(col_sizes) sans
--      padding, base de calcul du padding_bytes structurel.
--  12. positive_drift_bytes dans ECSM : octets gagnés si actual < intent
--      (ANALYZE plus précis que l'estimation pre-ANALYZE, pas un artefact PG18).
--  13. padding_bytes dans ECSM : waste structurel = actual - raw_data.
--  14. dod_efficiency_ratio dans ECSM : naive / intent (ratio de densité DOD vs naïf).
--  15. padding_category dans v_master_health_audit : OPTIMAL / WARNING / INVESTIGATE.
--
-- Dépendances : pg_catalog, pg_stats (ANALYZE requis pour densité précise).
-- Exécution  : psql -U postgres -d marius -f meta_registry.sql
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS meta;


-- ==============================================================================
-- 1. REGISTRE D'INTENTION (Source of Truth architecturale)
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
-- naive_density_bytes SMALLINT NULL (v2.2 — Proposition 1 Cache Multiplier) :
--   Taille du tuple padded si les colonnes étaient dans leur ordre naturel pré-DOD
--   (non optimisé), produite par f_generate_dod_template sur la liste originale.
--   NULL = non renseigné (métrique optionnelle, aucun effet sur les alertes).
--   Le ratio dod_efficiency_ratio = naive / intent est exposé dans
--   v_extended_containment_security_matrix comme KPI architectural.
--   Pour les tables conçues d'emblée en ordre DOD, calculer rétrospectivement en
--   passant les colonnes dans l'ordre fonctionnel (alphabétique ou déclaratif)
--   à f_generate_dod_template. Contrainte naive >= intent : par définition, le
--   layout optimisé est ≤ au layout naïf (un tuple DOD ne peut être plus grand).

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
--
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


-- ==============================================================================
-- 2. SCANNER DE LAYOUT DOD (Introspection physique)
-- ==============================================================================
-- Calcule la taille réelle d'un tuple padded en simulant l'alignement CPU.
--
-- CORRECTIONS v2 :
--
-- A — Header dynamique avec null bitmap
--   PostgreSQL alloue un null bitmap si au moins une colonne est nullable.
--   Sa taille : ceil(n_cols / 8) octets. Le header complet :
--     header_bytes = MAXALIGN(23 + ceil(n_cols / 8))
--                  = ((23 + ceil(n_cols/8) + 7) / 8) * 8
--   Exemples :
--     7 cols  → bitmap 1B → brut 24B → MAXALIGN 24B (coïncide avec v1)
--     9 cols  → bitmap 2B → brut 25B → MAXALIGN 32B (v1 sous-estimait 8B)
--     17 cols → bitmap 3B → brut 26B → MAXALIGN 32B (v1 sous-estimait 8B)
--
-- B — Densité varlena via pg_stats.avg_width
--   v1 utilisait effective_len=4 pour toute varlena (header seul, données ignorées).
--   Résultat : actual_density_bytes = densité minimale théorique (sans données),
--   density_drift_alert toujours FALSE pour les tables à varlena.
--   v2 utilise avg_width de pg_stats, qui reflète la longueur moyenne constatée
--   après ANALYZE — header varlena inclus. Fallback à 4B si ANALYZE non exécuté.
--   PRÉCONDITION : ANALYZE doit avoir été exécuté sur les tables auditées.
--
-- C — Filtrage sur les OIDs enregistrés (performance)
--   v1 scannait l'intégralité de pg_attribute (O(total_cols)).
--   v2 filtre sur les OIDs des composants enregistrés (O(composants × cols)).
--   Le filtre ANY(ARRAY(...)) permet au planner d'utiliser
--   l'index pg_attribute_relid_attnum_index de pg_catalog.

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


-- ==============================================================================
-- 5. SEED — Manifeste des composants du projet Marius
-- ==============================================================================
-- intent_density_bytes : taille du tuple padded calculée avec header dynamique
-- et densité varlena réelle (STORAGE MAIN sur les colonnes courtes).
-- Valeurs vérifiées par simulation arithmétique (Audit 3 — buffer simulation).
--
-- Légende des mutation_procedures :
--   Signatures au format to_regprocedure() : types PostgreSQL canoniques
--   (character varying et non varchar, integer et non int, etc.)
-- ==============================================================================

INSERT INTO meta.containment_intent
    (component_id, intent_density_bytes, rls_guard_bitmask, mutation_procedures, immutable_keys, exempt_bloat_check, naive_density_bytes)
VALUES

-- ── identity.auth ────────────────────────────────────────────────────────────
-- Layout : 3×TSTZ + INT4 + INT2 + BOOL + 1B slot + VARCHAR(inline ~101B)
-- Header : 7 cols, 2 nullable → bitmap 1B → 24B (MAXALIGN absorbe)
-- Tuple padded : 160B @ ff=70% → 34 tpp
-- STORAGE MAIN sur password_hash : argon2id pseudo-aléatoire, PGLZ ratio ≈ 1.0
-- naive_density_bytes : NULL — table conçue d'emblée en ordre DOD.
--   Pré-DOD hypothétique (ordre fonctionnel) : entity_id(4B) first, puis TSTZ ×3,
--   role_id, is_banned, password_hash → padding 4B entre entity_id et 1er TSTZ.
--   Exécuter f_generate_dod_template avec cet ordre pour obtenir la valeur exacte.
(
    'identity.auth',
    160,
    NULL,   -- Pas de RLS sur auth (accès via v_auth uniquement, REVOKE SELECT)
    ARRAY[
        'identity.create_account(character varying,character varying,character varying,smallint,character varying)',
        'identity.record_login(integer)',
        'identity.anonymize_person(integer)'
    ],
    ARRAY['entity_id'::name, 'created_at'::name],
    false,
    NULL    -- naive_density_bytes : à renseigner via f_generate_dod_template
),

-- ── content.core ─────────────────────────────────────────────────────────────
-- Layout : 3×TSTZ + 2×INT4 + INT2 + 3×BOOL
-- Header : 9 cols, 3 nullable → bitmap 2B → brut 25B → MAXALIGN 32B
-- Tuple padded : 72B @ ff=100% → 107 tpp
-- fillfactor absent (Audit 3 : tous les UPDATE touchent des colonnes indexées)
(
    'content.core',
    72,
    32768,  -- edit_others_contents (bit 15) : accès éditorial global
    ARRAY[
        'content.create_document(integer,character varying,character varying,smallint,smallint,text,character varying,character varying)',
        'content.publish_document(integer)'
    ],
    ARRAY['document_id'::name, 'created_at'::name],
    false,
    NULL    -- naive_density_bytes : à renseigner via f_generate_dod_template
),

-- ── commerce.transaction_item ────────────────────────────────────────────────
-- Layout : INT8 + 3×INT4 — zéro varlena, zéro nullable
-- Header : 4 cols, 0 nullable → pas de bitmap → 23B → MAXALIGN 24B
-- Tuple padded : 48B → 170 tpp (immutabilité trigger ADR-030)
-- NOTA : intent_density_bytes = 48B (tuple padded complet).
--   La v1 déclarait 20B (taille des données brutes sans header) → faux positif.
(
    'commerce.transaction_item',
    48,
    NULL,   -- Pas de RLS (INSERT uniquement via create_transaction_item)
    ARRAY[
        'commerce.create_transaction_item(integer,integer,integer)'
    ],
    ARRAY['unit_price_snapshot_cents'::name, 'transaction_id'::name, 'product_id'::name],
    false,
    NULL    -- naive_density_bytes : layout entièrement fixe, ordre DOD = ordre naturel
),

-- ── commerce.product_core ────────────────────────────────────────────────────
-- Layout : INT8 + 3×INT4 + BOOL
-- Header : 5 cols, 2 nullable → bitmap 1B → 24B
-- Tuple padded : 48B @ ff=80% → 125 tpp
-- HOT : stock (non indexé) → HOT-eligible sur create_transaction_item
(
    'commerce.product_core',
    48,
    262144, -- manage_commerce (bit 18) : gestion catalogue
    ARRAY[
        'commerce.create_product(character varying,character varying,bigint,integer,character varying)',
        'commerce.create_transaction_item(integer,integer,integer)'
    ],
    ARRAY['id'::name],
    false,
    NULL    -- naive_density_bytes : à renseigner via f_generate_dod_template
),

-- ── commerce.transaction_price ───────────────────────────────────────────────
-- Layout : 3×INT8 + 2×INT4 + INT2 + BOOL
-- Header : 7 cols, 0 nullable → pas de bitmap → 23B → MAXALIGN 24B
-- Tuple padded : 64B → 127 tpp
(
    'commerce.transaction_price',
    64,
    262144,
    ARRAY[
        'commerce.create_transaction(integer,integer,smallint,smallint,text)'
    ],
    ARRAY['transaction_id'::name],
    false,
    NULL    -- naive_density_bytes : à renseigner via f_generate_dod_template
),

-- ── content.tag_hierarchy ────────────────────────────────────────────────────
-- Layout : 2×INT4 + INT2 — zéro varlena, zéro nullable
-- Header : 3 cols, 0 nullable → pas de bitmap → 23B → MAXALIGN 24B
-- Tuple padded : 40B → 185 tpp (Closure Table : INSERT-only, jamais UPDATE)
-- NOTA : la v1 documentait "12B → 682 tpp" — erreur : 12B = données brutes
--   sans header. Avec header 24B : 34B brut → 40B padded, 8168/44=185 tpp.
(
    'content.tag_hierarchy',
    40,
    2048,   -- manage_tags (bit 11)
    ARRAY[
        'content.create_tag(character varying,character varying,integer)'
    ],
    ARRAY['ancestor_id'::name, 'descendant_id'::name, 'depth'::name],
    false,
    NULL    -- naive_density_bytes : layout fixe, DOD = ordre naturel (INT2 en dernier déjà)
)

ON CONFLICT DO NOTHING;
