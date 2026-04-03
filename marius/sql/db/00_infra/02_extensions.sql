-- ==============================================================================
-- 00_infra/02_extensions.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : extensions PostgreSQL + fonctions utilitaires cross-schéma (public)
-- Ordre   : doit précéder toute table référençant ces extensions ou fonctions
-- ==============================================================================

-- ==============================================================================
-- EXTENSIONS
-- ==============================================================================

CREATE EXTENSION unaccent;    -- normalisation des accents (recherche texte)
CREATE EXTENSION ltree;       -- chemins matérialisés (tags, commentaires)
CREATE EXTENSION pg_trgm;     -- index trigrammes (recherche partielle sur noms)
CREATE EXTENSION postgis;     -- types et index géospatiaux (geo.place_core)


-- ==============================================================================
-- WRAPPER IMMUTABLE UNACCENT
-- ==============================================================================
-- Wrapper IMMUTABLE requis pour l'utilisation de unaccent() dans les index.
-- unaccent() n'est pas déclarée IMMUTABLE dans PostgreSQL (dépendance de dictionnaire).
-- Ce wrapper délègue à unaccent() et hérite de son comportement fonctionnel, mais
-- permet au planner de traiter l'expression comme stable entre les lignes — prérequis
-- pour toute expression d'index. Tout changement de dictionnaire unaccent nécessite
-- un REINDEX sur les index qui l'utilisent (org_identity_name_trgm, content_identity_headline_trgm).
CREATE FUNCTION public.immutable_unaccent(text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT public.unaccent($1);
$$;


-- ==============================================================================
-- DÉDUPLICATION DE SLUGS (utilitaire cross-schéma)
-- ==============================================================================
-- Fonctionne sur n'importe quelle table via TG_TABLE_SCHEMA / TG_TABLE_NAME.
-- Ignore la ligne courante (PK <> valeur courante) pour les UPDATE.
--
-- COMPORTEMENT SOUS CONCURRENCE
-- La boucle SELECT EXISTS + incrément fonctionne correctement en session unique.
-- Sous forte concurrence (deux transactions qui génèrent le même slug simultanément),
-- la contrainte UNIQUE est le vrai garde-fou : elle rejettera l'une des deux
-- insertions avec une erreur 23505 (unique_violation). Ce n'est pas un état
-- corrompu — l'erreur est propre et attrapable côté applicatif.
-- Le pattern "déduplication optimiste + UNIQUE comme filet" est acceptable pour
-- les slugs (générés depuis un titre, collisions rares). Pour un système à très
-- haute concurrence sur les titres (ex: importation de masse), préférer une
-- séquence applicationnelle avec retry explicite.
CREATE FUNCTION public.fn_slug_deduplicate()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_slug    TEXT    := NEW.slug;
  v_exists  BOOLEAN;
  v_counter INT     := 0;
  v_pk_col  TEXT;
  v_pk_val  INT;
BEGIN
  -- Détection de la colonne PK par convention de nommage
  v_pk_col := CASE TG_TABLE_NAME
    WHEN 'account_core' THEN 'entity_id'
    WHEN 'identity'     THEN 'document_id'
    ELSE 'id'
  END;

  EXECUTE format('SELECT ($1).%I', v_pk_col) INTO v_pk_val USING NEW;

  LOOP
    EXECUTE format(
      'SELECT EXISTS(SELECT 1 FROM %I.%I WHERE slug = $1 AND %I <> $2)',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_col
    ) INTO v_exists USING v_slug, COALESCE(v_pk_val, -1);
    EXIT WHEN NOT v_exists;
    v_counter := v_counter + 1;
    v_slug    := NEW.slug || '-' || v_counter;
  END LOOP;

  NEW.slug := v_slug;
  RETURN NEW;
END;
$$;
