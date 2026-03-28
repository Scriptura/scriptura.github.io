-- ==============================================================================
-- META-REGISTRY — Extended Containment Security Matrix (Schema-as-Data)
-- Architecture ECS/DOD · PostgreSQL 18
--
-- Objectif : Détection Ahead-Of-Time (AOT) des dérives (Drift) structurelles
-- et sécuritaires entre l'intention architecturale et le dictionnaire de données.
--
-- Dépendances : pg_catalog pur (aucune extension requise).
-- ==============================================================================

CREATE SCHEMA IF NOT EXISTS meta;

-- ==============================================================================
-- 1. TABLE D'INTENTION (Source of Truth)
-- ==============================================================================
-- Stocke les invariants déclaratifs pour chaque composant ECS.
-- regclass / regprocedure : Types OID dynamiques. Garantissent l'intégrité
-- référentielle interne (le renommage d'une table met à jour l'OID nativement,
-- la suppression lève une erreur de dépendance).

CREATE TABLE meta.containment_intent (
    component_id           regclass NOT NULL PRIMARY KEY,
    intent_density_bytes   SMALLINT NOT NULL,  -- Plafond physique toléré (padding inclus)
    rls_guard_bitmask      INT      NULL,      -- Masque binaire d'accès attendu (INT4 pass-by-value)
    mutation_procedure     regprocedure NULL,  -- Point d'entrée exclusif d'écriture
    immutable_keys         name[]   NULL,      -- Colonnes scellées post-INSERT (ex: entity_id)
    
    CONSTRAINT intent_density_positive CHECK (intent_density_bytes > 0)
);

-- Seed de démonstration basé sur les ADR (ex: ADR-026, ADR-016)
INSERT INTO meta.containment_intent 
    (component_id, intent_density_bytes, rls_guard_bitmask, mutation_procedure, immutable_keys)
VALUES 
    ('commerce.transaction_item'::regclass, 20, NULL, 'commerce.create_transaction_item(integer, integer, integer)'::regprocedure, ARRAY['unit_price_snapshot_cents'::name]),
    ('identity.auth'::regclass, 160, NULL, 'identity.create_account(varchar, varchar, varchar, smallint, varchar)'::regprocedure, ARRAY['entity_id'::name, 'created_at'::name]),
    ('content.core'::regclass, 72, 32768, 'content.publish_document(integer)'::regprocedure, ARRAY['created_at'::name])
ON CONFLICT DO NOTHING;


-- ==============================================================================
-- 2. VUE INTROSPECTION (Scanner de Layout DOD)
-- ==============================================================================
-- Calcule la densité réelle d'un tuple physique en simulant l'alignement matériel.
-- attalign : Contrainte d'alignement CPU (c=1B, s=2B, i=4B, d=8B). Un offset
-- non aligné déclenche l'insertion de padding invisible par le moteur.

CREATE OR REPLACE VIEW meta.v_introspection_layout AS
WITH RECURSIVE
cols AS (
    SELECT
        attrelid,
        attnum,
        attname,
        -- Résolution de la taille. -1 = varlena (donnée de taille variable).
        -- En DOD, on évalue l'empreinte de base du tuple (header varlena = 4B).
        CASE WHEN attlen = -1 THEN 4 ELSE attlen END AS effective_len,
        CASE attalign
            WHEN 'c' THEN 1
            WHEN 's' THEN 2
            WHEN 'i' THEN 4
            WHEN 'd' THEN 8
            ELSE 4
        END AS align_bytes,
        ROW_NUMBER() OVER (PARTITION BY attrelid ORDER BY attnum) as seq
    FROM pg_attribute
    WHERE attnum > 0 AND NOT attisdropped
),
layout_calc (attrelid, seq, attname, offset_bytes, len_bytes, align_bytes) AS (
    -- Cas de base : Offset initial = Heap Tuple Header (24B = 23B + MAXALIGN)
    -- Note : Ignore l'expansion du null bitmap pour l'analyse nominale.
    SELECT
        attrelid,
        seq,
        attname,
        24::int AS offset_bytes, 
        effective_len,
        align_bytes
    FROM cols WHERE seq = 1
    
    UNION ALL
    
    -- Récursion : Offset courant = (Offset précédent + Taille précédente) + Padding d'alignement
    SELECT
        c.attrelid,
        c.seq,
        c.attname,
        (l.offset_bytes + l.len_bytes + 
        (c.align_bytes - ((l.offset_bytes + l.len_bytes) % c.align_bytes)) % c.align_bytes)::int,
        c.effective_len,
        c.align_bytes
    FROM cols c
    JOIN layout_calc l ON c.attrelid = l.attrelid AND c.seq = l.seq + 1
)
SELECT 
    attrelid AS component_id,
    -- Taille finale : Offset de la dernière colonne + sa taille, le tout réaligné sur MAXALIGN (8B)
    ((MAX(offset_bytes + len_bytes) + 7) / 8 * 8)::smallint AS actual_density_bytes
FROM layout_calc
GROUP BY attrelid;


-- ==============================================================================
-- 3. VUE INTROSPECTION SÉCURITÉ (Scanner procédural AOT)
-- ==============================================================================
-- Valide l'encapsulation SECURITY DEFINER (prosecdef) et la protection du
-- search_path (proconfig) pour prévenir l'escalade de privilèges via substitution.

CREATE OR REPLACE VIEW meta.v_introspection_security AS
SELECT
    oid AS proc_id,
    prosecdef AS is_security_definer,
    COALESCE(array_to_string(proconfig, ',') LIKE '%search_path=%', false) AS has_secured_path
FROM pg_proc;


-- ==============================================================================
-- 4. MATRICE DE CONFORMITÉ (Extended Containment Security Matrix)
-- ==============================================================================
-- Croise l'intention (Registry) et le dictionnaire de données pour lever 
-- les alertes structurelles.

CREATE OR REPLACE VIEW meta.v_extended_containment_security_matrix AS
SELECT
    ci.component_id::text AS component_name,
    ci.intent_density_bytes,
    ts.actual_density_bytes,
    
    -- Alerte DOD : Dérive du layout mémoire (ordre sous-optimal, padding indésirable)
    (ts.actual_density_bytes > ci.intent_density_bytes) AS density_drift_alert,
    
    -- Alerte AOT/ECS : Composant orphelin sans procédure de mutation dédiée
    CASE 
        WHEN ci.mutation_procedure IS NULL THEN true
        WHEN ps.proc_id IS NULL THEN true
        ELSE false
    END AS missing_mutation_interface,
    
    -- Alerte Sécurité : Procédure existante mais vulnérable (pas de SECDEF ou search_path ouvert)
    CASE
        WHEN ps.proc_id IS NOT NULL AND (NOT ps.is_security_definer OR NOT ps.has_secured_path) THEN true
        ELSE false
    END AS security_breach_alert

FROM meta.containment_intent ci
LEFT JOIN meta.v_introspection_layout ts ON ts.component_id = ci.component_id
LEFT JOIN meta.v_introspection_security ps ON ps.proc_id = ci.mutation_procedure;
