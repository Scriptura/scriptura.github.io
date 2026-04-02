-- ==============================================================================
-- META-DATA — Manifeste des Invariants (Source of Truth Architectural)
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Format v2.1 : exempt_bloat_check BOOLEAN (v2.1), mutation_procedures TEXT[] (N:1),
--               component_id TEXT, immutable_keys name[]
-- Aligné sur meta_registry.sql v2.1 (to_regprocedure() + TEXT[] array + exempt flag)
--
-- Correctifs v2.1 :
--   - identity.person_identity : intent 72 → 80B
--       Header MAXALIGN(23 + ceil(10/8)) = 32B (null bitmap 2B pour 10 cols).
--       Après ANALYZE sur seed réaliste, avg_width varlena ~5-6B/colonne.
--       Simulation : 32 + 4 + 2 + 2 + 7×5.7 ≈ 80B → MAXALIGN(80) = 80B.
--       La valeur 72B était correcte pre-ANALYZE (varlena = 4B fallback) mais
--       sous-estimait les données réelles → density_drift_alert faux positif permanent.
--
--   - identity.person_biography : intent 44 → 48B
--       La valeur 44B = header(24B) + 5×INT4(20B) = 44B brut SANS tail padding.
--       MAXALIGN(44) = 48B. Le tuple padded réel est 48B → drift inévitable à 44B.
--       Layout : 5 cols, ≥1 nullable → bitmap 1B → MAXALIGN(24B) header.
--       Correction structurelle (tail MAXALIGN omis dans la déclaration initiale).
--
--   - identity.role : exempt_bloat_check = true
--       Table de configuration structurelle : 7 lignes, REVOKE INSERT/UPDATE/DELETE
--       en production, mutations_procedures = NULL (données immuables).
--       pg_relation_size / n_live_tup >> intent_density à 7 tuples (fraction de page).
--       Le bloat physique est inévitable et inoffensif : la sentinelle ne peut pas
--       le distinguer d'un vrai bloat sans ce flag. L'exemption n'affecte pas
--       v_performance_sentinel (qui continue de reporter les densités brutes) ni
--       density_drift_alert.
-- ==============================================================================

BEGIN;

-- Nettoyage du registre pour éviter les doublons lors des ré-exécutions
TRUNCATE meta.containment_intent;

-- ------------------------------------------------------------------------------
-- INSERTION DES INVARIANTS PAR DOMAINE
-- Format mutation_procedures : TEXT[] — signatures canoniques PostgreSQL
-- (character varying, not varchar ; integer, not int — requis par to_regprocedure)
-- Format exempt_bloat_check : BOOLEAN — false par défaut (DEFAULT), true pour
-- les tables de configuration structurelle à cardinalité fixe immuable.
-- ------------------------------------------------------------------------------

INSERT INTO meta.containment_intent
(component_id, intent_density_bytes, rls_guard_bitmask, mutation_procedures, immutable_keys, exempt_bloat_check)
VALUES

-- [ DOMAINE IDENTITY ]
-- ADR-008 & ADR-015 : Focus HOT et Auth Bitmask
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
    false
),
(
    'identity.person_identity',
    -- v2.1 : 72 → 80B
    -- Header 32B (10 cols, null bitmap 2B, MAXALIGN) + 4B(entity_id) + 2B(gender)
    -- + 2B(nationality) + 7×varlena × avg~5.7B ≈ 80B → MAXALIGN(80) = 80B.
    -- 72B était le calcul pre-ANALYZE (varlena=4B fallback) → faux positif permanent.
    80,
    256,
    ARRAY[
        'identity.create_person(integer,character varying,character varying,smallint,smallint)'
    ],
    ARRAY['entity_id'::name],
    false
),
(
    'identity.person_biography',
    -- v2.1 : 44 → 48B
    -- Header 24B (5 cols, null bitmap 1B, MAXALIGN(24)) + 5×INT4(20B) = 44B brut.
    -- MAXALIGN(44) = 48B — tail padding MAXALIGN omis dans la déclaration initiale.
    -- Le tuple padded réel est 48B → density_drift_alert inévitable à 44B.
    48,
    256,
    NULL, -- Géré via anonymize_person (pas de procédure dédiée — write par marius_admin)
    ARRAY['entity_id'::name],
    false
),
(
    'identity.role',
    49,
    NULL,
    NULL, -- Données de configuration structurelle — immuables en production
    NULL,
    -- exempt_bloat_check = true : table de configuration structurelle.
    -- 7 lignes × ~49B ≈ 343B → fraction d'une page 8kB.
    -- pg_relation_size / n_live_tup >> intent_density * 1.20 de façon permanente.
    -- REVOKE INSERT/UPDATE/DELETE FROM PUBLIC en production (master_schema_ddl.pgsql).
    -- Le bloat est inévitable et inoffensif : la sentinelle ne peut pas le
    -- distinguer d'un vrai bloat sans ce flag.
    true
),

-- [ DOMAINE CONTENT ]
-- ADR-003 & ADR-007 : Densité maximale (tuples/page) et scellement
(
    'content.document',
    32,
    NULL,
    ARRAY[
        'content.create_document(integer,character varying,character varying,smallint,smallint,text,character varying,character varying)'
    ],
    ARRAY['entity_id'::name],
    false
),
(
    'content.core',
    72,
    NULL,
    ARRAY[
        'content.create_document(integer,character varying,character varying,smallint,smallint,text,character varying,character varying)',
        'content.publish_document(integer)'
    ],
    ARRAY['document_id'::name, 'created_at'::name],
    false
),
(
    'content.content_to_tag',
    32,
    NULL,
    NULL,
    ARRAY['document_id'::name, 'tag_id'::name],
    false
),

-- [ DOMAINE COMMERCE ]
-- ADR-024 & ADR-026 : Intégrité financière et snapshotting
(
    'commerce.product_core',
    48,
    2,
    ARRAY[
        'commerce.create_product(character varying,character varying,bigint,integer,character varying)',
        'commerce.create_transaction_item(integer,integer,integer)'
    ],
    ARRAY['id'::name],
    false
),
(
    'commerce.transaction_core',
    56,
    NULL,
    ARRAY[
        'commerce.create_transaction(integer,integer,smallint,smallint,text)'
    ],
    ARRAY['client_entity_id'::name, 'created_at'::name],
    false
),

-- [ DOMAINE ORGANISATION & GEO ]
-- ADR-011 : Hiérarchies denses
(
    'org.org_hierarchy',
    40,
    128,
    ARRAY[
        'org.create_organization(character varying,character varying,smallint,integer,integer)',
        'org.add_organization_to_hierarchy(integer,integer)'
    ],
    ARRAY['entity_id'::name],
    false
),
(
    'geo.place_core',
    96,
    NULL,
    ARRAY[
        'geo.create_place(character varying,smallint,smallint,double precision,double precision,smallint,character varying,character varying,character varying,character varying)'
    ],
    ARRAY['entity_id'::name],
    false
);

COMMIT;

-- ------------------------------------------------------------------------------
-- VÉRIFICATION IMMÉDIATE DU DRIFT
-- ------------------------------------------------------------------------------
-- Affiche les composants qui ne respectent pas le contrat dès l'initialisation.
SELECT
    component_name,
    intent_density_bytes,
    actual_density_bytes,
    (actual_density_bytes - intent_density_bytes) AS padding_overhead,
    density_drift_alert,
    exempt_bloat_check
FROM meta.v_extended_containment_security_matrix
ORDER BY density_drift_alert DESC, component_name;
