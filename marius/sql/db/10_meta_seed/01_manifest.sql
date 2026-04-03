-- ==============================================================================
-- 10_meta_seed/01_manifest.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : manifeste des invariants AOT — TRUNCATE + INSERT meta.containment_intent
--
-- Source   : meta_data.sql v2.1 + meta_registry.sql v2.2 (fusion)
-- Format   : v2.2 — naive_density_bytes SMALLINT (optionnel)
--            exempt_bloat_check BOOLEAN
--            mutation_procedures TEXT[] (signatures to_regprocedure())
--            immutable_keys name[]
--
-- Pré-requis : toutes les tables physiques existent (étapes 02–06 chargées).
--   to_regclass() résout correctement → component_not_found_alert = FALSE.
--   La requête de vérification finale retourne des résultats fiables.
--
-- Correctifs v2.1 documentés :
--   identity.person_identity : intent 72 → 80B (varlena avg_width post-ANALYZE)
--   identity.person_biography : intent 44 → 48B (tail MAXALIGN omis v1)
--   identity.role : exempt_bloat_check = true (7 lignes, fraction de page)
-- ==============================================================================

BEGIN;

-- Nettoyage du registre pour éviter les doublons lors des ré-exécutions
TRUNCATE meta.containment_intent;

-- ==============================================================================
-- INSERTION DES INVARIANTS PAR DOMAINE
-- Format mutation_procedures : TEXT[] — signatures canoniques PostgreSQL
--   (character varying, not varchar ; integer, not int — requis par to_regprocedure)
-- ==============================================================================

INSERT INTO meta.containment_intent
    (component_id, intent_density_bytes, rls_guard_bitmask,
     mutation_procedures, immutable_keys, exempt_bloat_check, naive_density_bytes)
VALUES

-- ── DOMAINE IDENTITY ──────────────────────────────────────────────────────────

-- identity.auth — hot path, fillfactor=70, BRIN created_at
-- Layout : 3×TSTZ(24B) + entity_id INT4(4) + role_id INT2(2) + is_banned BOOL(1)
--          + 1B slot libre + password_hash varlena(~101B inline) + 3B tail pad
-- Tuple padded : 160B — 34 tpp @ ff=70%
(
    'identity.auth',
    160,
    1,
    ARRAY[
        'identity.create_account(character varying,character varying,character varying,smallint,character varying)',
        'identity.record_login(integer)',
        'identity.anonymize_person(integer)'
    ],
    ARRAY['entity_id'::name, 'created_at'::name],
    false,
    NULL
),

-- identity.person_identity — v2.1 : 72 → 80B
-- Header 32B (10 cols, null bitmap 2B, MAXALIGN) + entity_id(4) + gender(2)
-- + nationality(2) + 7×varlena × avg~5.7B ≈ 80B → MAXALIGN(80) = 80B.
(
    'identity.person_identity',
    80,
    256,
    ARRAY[
        'identity.create_person(character varying,character varying,smallint,smallint)'
    ],
    ARRAY['entity_id'::name],
    false,
    NULL
),

-- identity.person_biography — v2.1 : 44 → 48B
-- Header 24B + 5×INT4(20B) = 44B brut → MAXALIGN(44) = 48B (tail pad omis v1)
(
    'identity.person_biography',
    48,
    256,
    NULL,
    ARRAY['entity_id'::name],
    false,
    NULL
),

-- identity.role — exempt_bloat_check = true
-- Table de configuration structurelle : 7 lignes, REVOKE INSERT/UPDATE/DELETE.
-- 7 × ~49B ≈ 343B → fraction d'une page 8kB → bloat inévitable et inoffensif.
(
    'identity.role',
    49,
    NULL,
    NULL,
    NULL,
    true,
    NULL
),


-- ── DOMAINE CONTENT ───────────────────────────────────────────────────────────

-- content.document — spine : id INT4 + doc_type INT2 + 2B pad
-- Header 24B (2 cols, pas de bitmap) + 4B + 2B = 30B → MAXALIGN = 32B
(
    'content.document',
    32,
    NULL,
    ARRAY[
        'content.create_document(integer,character varying,character varying,smallint,smallint,text,character varying,character varying)'
    ],
    ARRAY['entity_id'::name],
    false,
    NULL
),

-- content.core — Layout : 3×TSTZ(24B) + doc_id INT4(4) + author INT4(4)
--                         + status INT2(2) + 3×BOOL(3B) + 1B pad
-- Header 32B (9 cols, null bitmap 2B, MAXALIGN 32B) + 38B données = 70B → MAXALIGN = 72B
(
    'content.core',
    72,
    32768,
    ARRAY[
        'content.create_document(integer,character varying,character varying,smallint,smallint,text,character varying,character varying)',
        'content.publish_document(integer)'
    ],
    ARRAY['document_id'::name, 'created_at'::name],
    false,
    NULL
),

-- content.content_to_tag — content_id INT4 + tag_id INT4
-- Header 24B (2 cols) + 8B = 32B → MAXALIGN = 32B
(
    'content.content_to_tag',
    32,
    NULL,
    NULL,
    ARRAY['document_id'::name, 'tag_id'::name],
    false,
    NULL
),

-- content.tag_hierarchy — ancestor_id INT4 + descendant_id INT4 + depth INT2 + 2B pad
-- Header 24B (3 cols) + 10B = 34B → MAXALIGN = 40B
(
    'content.tag_hierarchy',
    40,
    2048,
    ARRAY[
        'content.create_tag(character varying,character varying,integer)'
    ],
    ARRAY['ancestor_id'::name, 'descendant_id'::name, 'depth'::name],
    false,
    NULL
),


-- ── DOMAINE COMMERCE ──────────────────────────────────────────────────────────

-- commerce.product_core — fillfactor=80
-- Layout : price_cents INT8(8) + id INT4(4) + stock INT4(4) + media_id INT4(4)
--          + is_available BOOL(1) + 3B pad
-- Header 24B (5 cols, bitmap 1B, MAXALIGN 24B) + 24B = 48B → MAXALIGN = 48B
(
    'commerce.product_core',
    48,
    262144,
    ARRAY[
        'commerce.create_product(character varying,character varying,bigint,integer,character varying)',
        'commerce.create_transaction_item(integer,integer,integer)'
    ],
    ARRAY['id'::name],
    false,
    NULL
),

-- commerce.transaction_core — Layout : 2×TSTZ(16B) + id INT4(4) + client INT4(4)
--                                      + seller INT4(4) + status INT2(2)
--                                      + 2×BOOL(2B) + description varlena(4B)
-- Header 32B (9 cols, bitmap 2B, MAXALIGN 32B) + 40B = 72B → arrondi à 56B sans varlena
-- Déclaration conservatrice : 56B (sans description inline) — réévaluer post-ANALYZE
(
    'commerce.transaction_core',
    56,
    NULL,
    ARRAY[
        'commerce.create_transaction(integer,integer,smallint,smallint,text)'
    ],
    ARRAY['client_entity_id'::name, 'created_at'::name],
    false,
    NULL
),

-- commerce.transaction_item — 0 varlena, 0 nullable
-- Layout : unit_price INT8(8) + transaction_id INT4(4) + product_id INT4(4) + quantity INT4(4)
-- Header 24B (4 cols, pas de bitmap) + 20B = 44B → MAXALIGN = 48B
(
    'commerce.transaction_item',
    48,
    NULL,
    ARRAY[
        'commerce.create_transaction_item(integer,integer,integer)'
    ],
    ARRAY['unit_price_snapshot_cents'::name, 'transaction_id'::name, 'product_id'::name],
    false,
    NULL
),

-- commerce.transaction_price — Layout : 3×INT8(24B) + transaction_id INT4(4)
--                                        + tax_rate_bp INT4(4) + currency_code INT2(2)
--                                        + is_tax_included BOOL(1) + 1B pad
-- Header 24B (7 cols, pas de bitmap) + 36B = 60B → MAXALIGN = 64B
(
    'commerce.transaction_price',
    64,
    262144,
    ARRAY[
        'commerce.create_transaction(integer,integer,smallint,smallint,text)'
    ],
    ARRAY['transaction_id'::name],
    false,
    NULL
),


-- ── DOMAINE ORG ───────────────────────────────────────────────────────────────

-- org.org_hierarchy — nested set
-- Layout : entity_id INT4(4) + lft INT4(4) + rgt INT4(4) + depth INT2(2) + 2B pad
-- Header 24B (4 cols, pas de bitmap) + 14B = 38B → MAXALIGN = 40B
(
    'org.org_hierarchy',
    40,
    128,
    ARRAY[
        'org.create_organization(character varying,character varying,character varying,integer,integer)',
        'org.add_organization_to_hierarchy(integer,integer)'
    ],
    ARRAY['entity_id'::name],
    false,
    NULL
),


-- ── DOMAINE GEO ───────────────────────────────────────────────────────────────

-- geo.place_core — Layout : id INT4(4) + elevation INT2(2) + type_id INT2(2)
--                           + name varlena + coordinates geometry varlena
-- Header 24B (5 cols, bitmap 1B, MAXALIGN 24B) + 8B fixe + 2×varlena(4B+4B) = 44B → MAXALIGN = 48B
-- Post-ANALYZE avec données réelles (GPS + nom ~15B) : ~96B → réévaluer
-- Déclaration conservatrice pré-ANALYZE : 48B (varlena = 4B fallback)
-- Note meta_data.sql v2.1 déclare 96B — valeur post-ANALYZE recommandée
(
    'geo.place_core',
    96,
    NULL,
    ARRAY[
        'geo.create_place(character varying,smallint,smallint,double precision,double precision,smallint,character varying,character varying,character varying,character varying)'
    ],
    ARRAY['entity_id'::name],
    false,
    NULL
);

COMMIT;

-- ==============================================================================
-- VÉRIFICATION IMMÉDIATE DU DRIFT
-- Affiche les composants qui ne respectent pas le contrat dès l'initialisation.
-- Pré-requis : ANALYZE exécuté sur les tables pour des métriques varlena fiables.
-- ==============================================================================
SELECT
    component_name,
    intent_density_bytes,
    actual_density_bytes,
    (actual_density_bytes - intent_density_bytes) AS padding_overhead,
    density_drift_alert,
    component_not_found_alert,
    exempt_bloat_check
FROM meta.v_extended_containment_security_matrix
ORDER BY density_drift_alert DESC, component_not_found_alert DESC, component_name;
