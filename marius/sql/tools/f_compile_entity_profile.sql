-- ==============================================================================
-- meta.f_compile_entity_profile
-- Architecture ECS/DOD · PostgreSQL 18 · Projet Marius
--
-- Compilateur AOT : genere et execute dynamiquement meta.v_entity_profile.
-- Le catalogue pg_catalog n'est interroge qu'une seule fois, a la compilation.
-- La vue resultante est un UNION ALL pur, sans acces catalogue au runtime.
--
-- Algorithme :
--   1. Itere sur meta.containment_intent (composants enregistres, resolus via
--      to_regclass).
--   2. Pour chaque composant, detecte la colonne de liaison (spine FK) avec
--      priorite : entity_id > document_id > id.
--      Guard pour 'id' : verifie l'existence d'un pg_constraint contype='f'
--      sur cette colonne -- exclut les PK autogeneres (ex: commerce.product_core).
--   3. Composants sans spine FK detecte : ignores silencieusement.
--   4. Assemble le DDL : UNION ALL des SELECT spine_id, spine_type, component_name,
--      suivi d'un GROUP BY spine_id, spine_type.
--   5. EXECUTE le DDL (CREATE OR REPLACE VIEW).
--   6. Retourne le DDL compile (inspecter avant deploiement, loggable, auditee).
--
-- Note sur spine_type :
--   Le UNION ALL melange les sequences de spines distinctes (identity.entity,
--   content.document, ...). Un spine_id=7 peut designer simultanement une entite
--   et un document -- les namespaces sont disjoints. La colonne spine_type
--   ('entity_id', 'document_id', 'id') disambigue la cle composite.
--
-- Usage :
--   SELECT meta.f_compile_entity_profile();   -- compile + execute
--   \gset                                      -- puis inspecter la vue :
--   SELECT * FROM meta.v_entity_profile WHERE spine_id = 1;
-- ==============================================================================

CREATE OR REPLACE FUNCTION meta.f_compile_entity_profile()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'meta', 'pg_catalog'
AS $$
DECLARE
    v_union_parts  TEXT    := '';
    v_sep          TEXT    := '';
    v_ddl          TEXT;
    v_spine_col    TEXT;
    r              RECORD;
BEGIN
    -- ---- 1. Iteration sur les composants enregistres et resolus ---------------
    FOR r IN
        SELECT ci.component_id,
               to_regclass(ci.component_id)::oid AS reloid
          FROM meta.containment_intent ci
         WHERE to_regclass(ci.component_id) IS NOT NULL
         ORDER BY ci.component_id          -- ordre deterministe -> DDL reproductible
    LOOP
        -- ---- 2. Detection de la colonne spine FK (priorite stricte) -----------
        -- Priorite : entity_id(1) > document_id(2) > id(3).
        -- Pour 'id' : guard pg_constraint -- la colonne doit etre contrainte par
        -- une FK (contype='f') sur ce composant. Cela exclut les PK autogeneres
        -- (GENERATED ALWAYS AS IDENTITY sans FK sortante) comme product_core.id.
        SELECT candidates.col
          INTO v_spine_col
          FROM (VALUES ('entity_id', 1), ('document_id', 2), ('id', 3))
               AS candidates(col, prio)
         WHERE EXISTS (
                   SELECT 1
                     FROM pg_attribute a
                    WHERE a.attrelid  = r.reloid
                      AND a.attname   = candidates.col
                      AND a.attnum    > 0
                      AND NOT a.attisdropped
               )
           AND (
                   -- entity_id et document_id : presence suffit (convention FK du projet)
                   candidates.col <> 'id'
                   OR
                   -- 'id' : verification pg_constraint -- FK obligatoire
                   EXISTS (
                       SELECT 1
                         FROM pg_constraint  c
                         JOIN pg_attribute   ca ON ca.attrelid = c.conrelid
                                                AND ca.attnum  = ANY(c.conkey)
                        WHERE c.conrelid  = r.reloid
                          AND c.contype   = 'f'
                          AND ca.attname  = 'id'
                   )
               )
         ORDER BY prio
         LIMIT 1;

        -- Aucune spine FK : composant ignore (transaction_item, tag_hierarchy, etc.)
        IF v_spine_col IS NULL THEN
            CONTINUE;
        END IF;

        -- ---- 3. Assemblage du bras UNION ALL ----------------------------------
        v_union_parts := v_union_parts
            || v_sep
            || format(
                   '    SELECT %I AS spine_id, %L AS spine_type, %L AS component_name'
                   ' FROM %s',
                   v_spine_col,
                   v_spine_col,   -- spine_type = nom de la colonne source
                   r.component_id,
                   r.component_id
               );
        v_sep      := E'\n    UNION ALL\n';
        v_spine_col := NULL;
    END LOOP;

    -- ---- Guard : aucun composant eligible ------------------------------------
    IF v_union_parts = '' THEN
        RAISE EXCEPTION
            'f_compile_entity_profile: aucun composant eligible trouve dans '
            'meta.containment_intent. Aucune colonne entity_id / document_id / '
            'id (FK) n''a ete detectee sur les composants enregistres.';
    END IF;

    -- ---- 4. Assemblage DDL complet -------------------------------------------
    v_ddl :=
        'CREATE OR REPLACE VIEW meta.v_entity_profile AS'              || E'\n'
        'SELECT'                                                        || E'\n'
        '    spine_id,'                                                 || E'\n'
        '    spine_type,'                                               || E'\n'
        '    array_agg(component_name ORDER BY component_name)'
        ' AS active_components'                                         || E'\n'
        'FROM ('                                                        || E'\n'
        || v_union_parts                                                || E'\n'
        || ') AS raw_components'                                        || E'\n'
        'GROUP BY spine_id, spine_type';

    -- ---- 5. Execution --------------------------------------------------------
    EXECUTE v_ddl;

    -- ---- 6. Retour du DDL compile (auditabilite AOT) -------------------------
    RETURN v_ddl;
END;
$$;

COMMENT ON FUNCTION meta.f_compile_entity_profile() IS
    'Compilateur AOT : genere et execute meta.v_entity_profile. '
    'Detecte les colonnes spine FK (entity_id > document_id > id+FK-guard) '
    'sur les composants enregistres dans meta.containment_intent. '
    'Retourne le DDL compile pour inspection et audit. '
    'ADR-001 / ADR-013 -- meta_registry v2.';

-- ---- DCL : verrouillage des privileges d''execution -------------------------
-- La fonction execute un CREATE OR REPLACE VIEW sous SECURITY DEFINER (postgres).
-- PUBLIC ne doit pas pouvoir recompiler le profil depuis un contexte applicatif.
REVOKE ALL     ON FUNCTION meta.f_compile_entity_profile() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION meta.f_compile_entity_profile() TO marius_admin;
