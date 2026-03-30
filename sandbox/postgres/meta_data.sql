-- ==============================================================================
-- META-DATA — Manifeste des Invariants (Source of Truth Architectural)
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Format v2 : mutation_procedures TEXT[] (N:1), component_id TEXT, immutable_keys name[]
-- Aligné sur meta_registry.sql v2 (to_regprocedure() + TEXT[] array)
-- ==============================================================================

BEGIN;

-- Nettoyage du registre pour éviter les doublons lors des ré-exécutions
TRUNCATE meta.containment_intent;

-- ------------------------------------------------------------------------------
-- INSERTION DES INVARIANTS PAR DOMAINE
-- Format mutation_procedures : TEXT[] — signatures canoniques PostgreSQL
-- (character varying, not varchar ; integer, not int — requis par to_regprocedure)
-- ------------------------------------------------------------------------------

INSERT INTO meta.containment_intent
(component_id, intent_density_bytes, rls_guard_bitmask, mutation_procedures, immutable_keys)
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
    ARRAY['entity_id'::name, 'created_at'::name]
),
(
    'identity.person_identity',
    72,
    256,
    ARRAY[
        'identity.create_person(integer,character varying,character varying,smallint,smallint)'
    ],
    ARRAY['entity_id'::name]
),
(
    'identity.person_biography',
    44,
    256,
    NULL, -- Géré via anonymize_person (pas de procédure dédiée — write par marius_admin)
    ARRAY['entity_id'::name]
),
(
    'identity.role',
    49,
    NULL,
    NULL, -- Données de configuration structurelle — immuables en production
    NULL
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
    ARRAY['entity_id'::name]
),
(
    'content.core',
    72,
    NULL,
    ARRAY[
        'content.create_document(integer,character varying,character varying,smallint,smallint,text,character varying,character varying)',
        'content.publish_document(integer)'
    ],
    ARRAY['document_id'::name, 'created_at'::name]
),
(
    'content.content_to_tag',
    32,
    NULL,
    NULL,
    ARRAY['document_id'::name, 'tag_id'::name]
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
    ARRAY['id'::name]
),
(
    'commerce.transaction_core',
    56,
    NULL,
    ARRAY[
        'commerce.create_transaction(integer,integer,smallint,smallint,text)'
    ],
    ARRAY['client_entity_id'::name, 'created_at'::name]
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
    ARRAY['entity_id'::name]
),
(
    'geo.place_core',
    96,
    NULL,
    ARRAY[
        'geo.create_place(character varying,smallint,smallint,double precision,double precision,smallint,character varying,character varying,character varying,character varying)'
    ],
    ARRAY['entity_id'::name]
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
    density_drift_alert
FROM meta.v_extended_containment_security_matrix
ORDER BY density_drift_alert DESC, component_name;
