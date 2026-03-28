-- ==============================================================================
-- META-DATA — Manifeste des Invariants (Source of Truth Architectural)
-- Architecture ECS/DOD · Projet Marius
-- ==============================================================================

BEGIN;

-- Nettoyage du registre pour éviter les doublons lors des ré-exécutions
TRUNCATE meta.containment_intent;

-- ------------------------------------------------------------------------------
-- INSERTION DES INVARIANTS PAR DOMAINE
-- ------------------------------------------------------------------------------

INSERT INTO meta.containment_intent 
(component_id, intent_density_bytes, rls_guard_bitmask, mutation_procedure, immutable_keys)
VALUES 

-- [ DOMAINE IDENTITY ]
-- ADR-008 & ADR-015 : Focus HOT et Auth Bitmask
(
    'identity.auth'::regclass, 
    155, 
    1, 
    'identity.record_login(integer)'::regprocedure, 
    ARRAY['entity_id']::name[]
),
(
    'identity.person_identity'::regclass, 
    74, 
    256, 
    'identity.create_person(integer,text,text,text,date)'::regprocedure, 
    ARRAY['entity_id']::name[]
),
(
    'identity.person_biography'::regclass, 
    44, 
    256, 
    NULL, -- Géré via create_person (composition)
    ARRAY['entity_id']::name[]
),
(
    'identity.role'::regclass, 
    49, 
    NULL, 
    NULL, 
    NULL
),

-- [ DOMAINE CONTENT ]
-- ADR-003 & ADR-007 : Densité maximale (tuples/page) et scellement
(
    'content.document'::regclass, 
    32, 
    NULL, 
    'content.create_document(integer,text,text,integer)'::regprocedure, 
    ARRAY['entity_id']::name[]
),
(
    'content.core'::regclass, 
    64, 
    NULL, 
    'content.publish_document(integer,integer)'::regprocedure, 
    ARRAY['document_id']::name[]
),
(
    'content.content_to_tag'::regclass, 
    32, 
    NULL, 
    NULL, 
    ARRAY['document_id', 'tag_id']::name[]
),

-- [ DOMAINE COMMERCE ]
-- ADR-024 & ADR-026 : Intégrité financière et snapshotting
(
    'commerce.product_core'::regclass, 
    80, 
    2, 
    'commerce.create_product(text,text,int8,int4)'::regprocedure, 
    ARRAY['product_id']::name[]
),
(
    'commerce.transaction_core'::regclass, 
    56, 
    NULL, 
    'commerce.create_transaction(integer)'::regprocedure, 
    ARRAY['client_entity_id']::name[]
),

-- [ DOMAINE ORGANISATION & GEO ]
-- ADR-011 : Hiérarchies denses
(
    'org.org_hierarchy'::regclass, 
    40, 
    128, 
    'org.create_organization(text,text,integer)'::regprocedure, 
    ARRAY['entity_id']::name[]
),
(
    'geo.place_core'::regclass, 
    96, 
    NULL, 
    'geo.create_place(text,text,geometry,integer)'::regprocedure, 
    ARRAY['entity_id']::name[]
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
