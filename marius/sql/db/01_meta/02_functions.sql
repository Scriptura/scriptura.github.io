-- ==============================================================================
-- 01_meta/02_functions.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : f_generate_dod_template + f_compile_entity_profile
-- Source  : f_generate_dod_template.sql + f_compile_entity_profile.sql
-- ==============================================================================

-- ==============================================================================
-- meta.f_generate_dod_template
-- Architecture ECS/DOD · PostgreSQL 18 · Projet Marius
--
-- Génère un DDL CREATE TABLE avec tri physique DOD et calcul de gain padding.
-- Alimente la valeur intent_density_bytes pour meta.containment_intent.
--
-- Algorithme :
--   1. Parse chaque spec "col_name type_spec [clauses_colonne]".
--      - col_name  : premier token.
--      - type_spec : du second token jusqu'au premier mot-clé de contrainte
--                    (NOT NULL, DEFAULT, GENERATED, UNIQUE, PRIMARY, CHECK,
--                    REFERENCES, CONSTRAINT). Inclut modifiers (n,m) et [].
--      - clauses   : reste (DDL uniquement, ignoré pour pg_type).
--   2. Résout le type via ::regtype (aliases PG + types custom).
--   3. Lit typalign + typlen depuis pg_catalog.pg_type.
--   4. Tri DOD : typalign 'd'(8B) > 'i'(4B) > 's'(2B) > 'c'(1B) > varlena.
--   5. Simule le padding naïf (ordre input) et optimisé (ordre DOD).
--   6. Retourne : cartographie mémoire + DDL + INSERT meta.containment_intent.
--
-- Conventions :
--   - Varlena effective_len = 4 B (header toast minimum, pg_stats indisponible
--     a la generation). Reevaluer intent_density_bytes apres ANALYZE via
--     meta.v_extended_containment_security_matrix.
--   - Types tableau (text[], int4[]...) : typlen = -1 -> traites comme varlena.
--   - Header = MAXALIGN(23 + ceil(n_cols/8)) -- null bitmap dynamique (v2).
--   - intent_density_bytes = taille tuple padded complet (header inclus).
--
-- Usage :
--   SELECT meta.f_generate_dod_template(
--       'commerce.my_table',
--       ARRAY[
--           'id       int8 GENERATED ALWAYS AS IDENTITY',
--           'score    numeric(10,2) NOT NULL',
--           'active   boolean',
--           'tags     text[]',
--           'label    varchar(64)'
--       ]
--   );
-- ==============================================================================

CREATE OR REPLACE FUNCTION meta.f_generate_dod_template(
    p_table_name  TEXT,
    p_columns     TEXT[]
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'meta', 'pg_catalog'
AS $$
DECLARE
    -- Colonnes introspeactees
    v_n              INT := array_length(p_columns, 1);
    v_names          TEXT[];    -- noms de colonnes
    v_types_ddl      TEXT[];    -- spec complete post-nom (type + clauses) -> DDL
    v_types_display  TEXT[];    -- type seul (sans clauses) -> cartographie
    v_alignments     INT[];     -- align_bytes : 1, 2, 4 ou 8
    v_lens           INT[];     -- effective_len pour simulation padding
    v_sort_keys      INT[];     -- cle de tri DOD (1=8B...4=1B, 5=varlena)

    -- Variables de parsing
    v_spec           TEXT;
    v_col_name       TEXT;
    v_rest           TEXT;      -- tout apres col_name
    v_type_full      TEXT;      -- type_spec seul (modifiers + [] inclus, sans clauses)
    v_type_lookup    TEXT;      -- type_full sans (n,m) -> pour ::regtype
    v_type_oid       OID;
    v_typlen         INT;
    v_typalign       CHAR(1);
    v_is_varlena     BOOLEAN;

    -- Simulation padding -- resultats par colonne en ordre DOD
    v_header         INT;
    v_offset         INT;
    v_pad            INT;
    v_naive_size     INT;
    v_opt_size       INT;
    v_savings        INT;
    v_col_offsets    INT[];     -- offset de debut de donnee (apres padding)
    v_col_pads       INT[];     -- octets de padding precedant la colonne
    v_col_lens_eff   INT[];     -- effective_len utilise dans la simulation

    -- Tri DOD
    v_sorted_idx     INT[];
    idx              INT;

    -- Sortie
    v_layout_map     TEXT;
    v_tail_pad       INT;
    v_ddl_cols       TEXT;
    v_sep            TEXT;
    v_result         TEXT;

    i                INT;
BEGIN
    -- ---- Guards -------------------------------------------------------------

    IF v_n IS NULL OR v_n = 0 THEN
        RAISE EXCEPTION 'DOD_TEMPLATE: p_columns est NULL ou vide';
    END IF;

    -- Point 3 : regex stricte -- pas de chiffre ni underscore en debut de segment
    IF p_table_name !~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$' THEN
        RAISE EXCEPTION
            'DOD_TEMPLATE: p_table_name "%" invalide -- format attendu : '
            'schema.table (snake_case, lettre initiale obligatoire, conforme '
            'au CHECK constraint de meta.containment_intent)',
            p_table_name;
    END IF;

    -- ---- 1. Parse + introspection pg_catalog.pg_type ------------------------

    FOR i IN 1..v_n LOOP
        v_spec := p_columns[i];

        -- col_name : premier token non-blanc
        v_col_name := trim(regexp_replace(v_spec, '^\s*(\S+)\s+.*$', '\1'));

        -- v_rest : tout ce qui suit col_name (type + eventuelles clauses)
        v_rest := trim(regexp_replace(v_spec, '^\s*\S+\s+', ''));

        -- Point 1 : isolation du type_spec
        -- Coupe v_rest au premier mot-cle de contrainte de colonne.
        -- Les types multi-tokens ("character varying") et les modifiers
        -- "varchar(10)", "numeric(10,2)", "text[]" restent dans v_type_full.
        v_type_full := trim(regexp_replace(
            v_rest,
            '\s+(NOT\s+NULL|NULL\b|DEFAULT\b|GENERATED\b|UNIQUE\b|PRIMARY\b'
            '|CHECK\b|REFERENCES\b|CONSTRAINT\b).*$',
            '',
            'ig'
        ));

        -- Pour ::regtype : supprimer les modifiers (n,m) et les suffixes []
        -- mais conserver les mots des types multi-tokens.
        v_type_lookup := trim(
            regexp_replace(
                regexp_replace(v_type_full, '\(.*?\)', '', 'g'),  -- strip (...)
                '(\[\d*\])+$', ''                                  -- strip [] suffixes
            )
        );

        -- Resolution OID -- gere aliases PG (int4, timestamptz...) et custom
        BEGIN
            v_type_oid := v_type_lookup::regtype::oid;
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION
                'DOD_TEMPLATE: type inconnu "%" (colonne "%" -- spec complete : "%"). '
                'Extension manquante ? (PostGIS, ltree...)',
                v_type_full, v_col_name, v_spec;
        END;

        SELECT pt.typlen, pt.typalign
          INTO v_typlen, v_typalign
          FROM pg_catalog.pg_type pt
         WHERE pt.oid = v_type_oid;

        -- Toujours FOUND apres regtype -- garde defensive
        IF NOT FOUND THEN
            RAISE EXCEPTION
                'DOD_TEMPLATE: OID % absent de pg_catalog.pg_type '
                '(type "%", colonne "%")',
                v_type_oid, v_type_full, v_col_name;
        END IF;

        -- typlen < 0 : varlena ou cstring -- tous traites comme varlena (fin de table)
        v_is_varlena := (v_typlen < 0);

        v_names[i]         := v_col_name;
        v_types_ddl[i]     := v_rest;        -- type + clauses -> DDL
        v_types_display[i] := v_type_full;   -- type seul      -> cartographie
        v_alignments[i]    := CASE v_typalign
                                  WHEN 'd' THEN 8
                                  WHEN 'i' THEN 4
                                  WHEN 's' THEN 2
                                  WHEN 'c' THEN 1
                                  ELSE          4   -- fallback conservateur
                              END;
        -- Varlena : 4 B (header toast minimum -- pg_stats indisponible pre-CREATE)
        v_lens[i]          := CASE WHEN v_is_varlena THEN 4 ELSE v_typlen END;
        v_sort_keys[i]     := CASE
                                  WHEN v_is_varlena     THEN 5
                                  WHEN v_typalign = 'd' THEN 1
                                  WHEN v_typalign = 'i' THEN 2
                                  WHEN v_typalign = 's' THEN 3
                                  WHEN v_typalign = 'c' THEN 4
                                  ELSE                       5
                              END;
    END LOOP;

    -- ---- 2. Header dynamique (meta_registry v2, correction A) ---------------
    -- MAXALIGN(23 B fixe + ceil(n_cols/8) B null bitmap)
    v_header := ((23 + ceil(v_n::numeric / 8))::int + 7) / 8 * 8;

    -- ---- 3. Simulation padding ordre naif (input) ---------------------------
    v_offset := v_header;
    FOR i IN 1..v_n LOOP
        v_pad    := (v_alignments[i] - (v_offset % v_alignments[i])) % v_alignments[i];
        v_offset := v_offset + v_pad + v_lens[i];
    END LOOP;
    v_naive_size := ((v_offset + 7) / 8) * 8;

    -- ---- 4. Indices tries DOD (stable : sort_key ASC, seq original ASC) -----
    WITH src AS (
        SELECT t.val, t.ordinality::int AS ord_idx
        FROM   unnest(v_sort_keys) WITH ORDINALITY AS t(val, ordinality)
    )
    SELECT array_agg(ord_idx ORDER BY val, ord_idx)
      INTO v_sorted_idx
      FROM src;

    -- ---- 5. Simulation padding ordre DOD -- capture par colonne -------------
    v_offset := v_header;
    FOR i IN 1..v_n LOOP
        idx               := v_sorted_idx[i];
        v_pad             := (v_alignments[idx] - (v_offset % v_alignments[idx]))
                             % v_alignments[idx];
        v_col_pads[i]     := v_pad;
        v_col_offsets[i]  := v_offset + v_pad;
        v_col_lens_eff[i] := v_lens[idx];
        v_offset          := v_offset + v_pad + v_lens[idx];
    END LOOP;
    v_opt_size := ((v_offset + 7) / 8) * 8;
    v_savings  := v_naive_size - v_opt_size;

    -- Padding de queue (MAXALIGN final)
    v_tail_pad := v_opt_size - (v_col_offsets[v_n] + v_col_lens_eff[v_n]);

    -- ---- 6. Point 2 : cartographie memoire par colonne (ordre DOD) ----------
    v_layout_map := '';
    FOR i IN 1..v_n LOOP
        idx          := v_sorted_idx[i];
        v_layout_map := v_layout_map || format(
            '--   %-24s (%-22s) : offset %3s B, size %2s B, padding_before %s B%s' || E'\n',
            v_names[idx],
            v_types_display[idx],
            v_col_offsets[i],
            v_col_lens_eff[i],
            v_col_pads[i],
            CASE WHEN v_sort_keys[idx] = 5
                 THEN '  [varlena -- 4 B pre-ANALYZE]'
                 ELSE ''
            END
        );
    END LOOP;
    -- Ligne de padding de queue MAXALIGN
    IF v_tail_pad > 0 THEN
        v_layout_map := v_layout_map || format(
            '--   %-24s                             : offset %3s B,            padding %s B  [MAXALIGN tail]' || E'\n',
            '(tail pad)',
            v_col_offsets[v_n] + v_col_lens_eff[v_n],
            v_tail_pad
        );
    END IF;

    -- ---- 7. Construction DDL colonnes (ordre DOD) ---------------------------
    v_ddl_cols := '';
    v_sep      := '';
    FOR i IN 1..v_n LOOP
        idx        := v_sorted_idx[i];
        v_ddl_cols := v_ddl_cols
                   || v_sep
                   || '    '
                   || rpad(v_names[idx], 28)
                   || v_types_ddl[idx];
        v_sep := E',\n';
    END LOOP;

    -- ---- 8. Assemblage de la sortie -----------------------------------------
    v_result :=
        format(
            '-- ============================================================' || E'\n'
            '-- DOD TEMPLATE : %s' || E'\n'
            '-- Generated by meta.f_generate_dod_template' || E'\n'
            '-- ------------------------------------------------------------' || E'\n'
            '-- Fixed-Length Header  : %s B' || E'\n'
            '--   (23 B base + %s B null bitmap [ceil(%s cols / 8)] -> MAXALIGN 8)' || E'\n'
            '-- ------------------------------------------------------------' || E'\n'
            '-- Layout memoire (Ordre DOD) :' || E'\n'
            '%s'
            '-- ------------------------------------------------------------' || E'\n'
            '-- Ordre naif (input)   : %s B / tuple' || E'\n'
            '-- Ordre DOD optimise   : %s B / tuple' || E'\n'
            '-- Padding economise    : %s B / tuple' || E'\n'
            '-- NOTE : varlena size = 4 B (pre-ANALYZE). Reevaluer via' || E'\n'
            '--        meta.v_extended_containment_security_matrix apres ANALYZE.' || E'\n'
            '-- ============================================================' || E'\n',
            p_table_name,
            v_header,
            ceil(v_n::numeric / 8)::int,
            v_n,
            v_layout_map,
            v_naive_size,
            v_opt_size,
            v_savings
        )
        || format(
            'CREATE TABLE %s (' || E'\n' || '%s' || E'\n' || ');' || E'\n\n',
            p_table_name,
            v_ddl_cols
        )
        || format(
            '-- Armement du registre AOT' || E'\n'
            'INSERT INTO meta.containment_intent' || E'\n'
            '    (component_id, intent_density_bytes)' || E'\n'
            'VALUES' || E'\n'
            '    (%L, %s)' || E'\n'
            'ON CONFLICT (component_id)' || E'\n'
            '    DO UPDATE SET intent_density_bytes = EXCLUDED.intent_density_bytes;' || E'\n',
            p_table_name,
            v_opt_size
        );

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION meta.f_generate_dod_template(text, text[]) IS
    'Genere un DDL CREATE TABLE avec tri physique DOD (8B->4B->2B->1B->varlena), '
    'cartographie le layout memoire (offset/size/padding par colonne), '
    'calcule le gain de padding vs ordre naif, '
    'et produit l''INSERT meta.containment_intent pre-calcule. '
    'intent_density_bytes = tuple padded complet (header + donnees + MAXALIGN final). '
    'ADR-006 / ADR-016 / ADR-030 . meta_registry v2.';

-- ---- Point 4 : DCL -- verrouillage des privileges d''execution --------------
-- SECURITY DEFINER eleve vers postgres : PUBLIC ne doit pas pouvoir declencher
-- ce generateur DDL depuis un contexte applicatif.
-- marius_user (runtime) n'a aucun cas d'usage legitime sur un generateur de schema.
-- GRANT TO marius_admin : emis en 08_dcl/01_grants.sql (role inexistant a ce stade).
REVOKE ALL ON FUNCTION meta.f_generate_dod_template(text, text[]) FROM PUBLIC;

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
-- GRANT TO marius_admin : emis en 08_dcl/01_grants.sql (role inexistant a ce stade).
REVOKE ALL ON FUNCTION meta.f_compile_entity_profile() FROM PUBLIC;
