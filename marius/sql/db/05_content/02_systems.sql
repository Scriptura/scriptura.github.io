-- ==============================================================================
-- 05_content/02_systems.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : fonctions content · triggers (BRIN immuabilité, modified_at, slug,
--           révision, entity_id) · procédures content · vues content
--
-- Triggers cross-domaine déployés ici (fonctions définies en 02_identity) :
--   content_core_modified_at          → identity.fn_update_modified_at()
--   media_core_modified_at            → identity.fn_update_modified_at()
--   core_deny_created_at_update       → identity.fn_deny_created_at_update()
--   core_deny_document_id_update      → identity.fn_deny_entity_id_update()
--
-- SECURITY DEFINER + SET search_path appliqués en 08_dcl/02_secdef.sql
-- ==============================================================================


-- ==============================================================================
-- SECTION 9 : FONCTION content.fn_revision_num
-- ==============================================================================

-- Numérotation automatique des révisions (BEFORE INSERT)
-- Calcule COALESCE(MAX(revision_num), 0) + 1 pour le document courant.
-- Le sentinel DEFAULT 0 est écrasé par ce trigger avant que le CHECK
-- revision_num > 0 ne soit évalué (les CHECK s'appliquent après les triggers
-- BEFORE dans PostgreSQL).
CREATE FUNCTION content.fn_revision_num()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  SELECT COALESCE(MAX(revision_num), 0) + 1
  INTO   NEW.revision_num
  FROM   content.revision
  WHERE  document_id = NEW.document_id;
  RETURN NEW;
END;
$$;


-- ==============================================================================
-- SECTION 10 : TRIGGERS — tables content
-- ==============================================================================

-- CONTENT.CORE : modified_at sur changements de statut/visibilité
-- WHEN clause : évite les déclenchements sur les UPDATE de colonnes non listées.
CREATE TRIGGER content_core_modified_at
BEFORE UPDATE ON content.core
FOR EACH ROW WHEN (
  OLD.status         IS DISTINCT FROM NEW.status         OR
  OLD.is_readable    IS DISTINCT FROM NEW.is_readable    OR
  OLD.is_commentable IS DISTINCT FROM NEW.is_commentable
) EXECUTE FUNCTION identity.fn_update_modified_at();

-- CONTENT.IDENTITY : déduplication de slug
CREATE TRIGGER content_identity_slug_dedup
BEFORE INSERT OR UPDATE OF slug ON content.identity
FOR EACH ROW EXECUTE FUNCTION public.fn_slug_deduplicate();

-- CONTENT.REVISION : numérotation automatique
CREATE TRIGGER content_revision_num
BEFORE INSERT ON content.revision
FOR EACH ROW EXECUTE FUNCTION content.fn_revision_num();

-- CONTENT.MEDIA_CORE : modified_at sur changements descriptifs uniquement
-- Ne se déclenche pas sur created_at (invariant BRIN).
CREATE TRIGGER media_core_modified_at
BEFORE UPDATE ON content.media_core
FOR EACH ROW WHEN (
  OLD.mime_type  IS DISTINCT FROM NEW.mime_type  OR
  OLD.folder_url IS DISTINCT FROM NEW.folder_url OR
  OLD.file_name  IS DISTINCT FROM NEW.file_name  OR
  OLD.width      IS DISTINCT FROM NEW.width      OR
  OLD.height     IS DISTINCT FROM NEW.height
) EXECUTE FUNCTION identity.fn_update_modified_at();

-- BRIN IMMUTABILITY — content.core.created_at
CREATE TRIGGER core_deny_created_at_update
BEFORE UPDATE ON content.core
FOR EACH ROW WHEN (OLD.created_at IS DISTINCT FROM NEW.created_at)
EXECUTE FUNCTION identity.fn_deny_created_at_update();

-- IMMUABILITÉ document_id (ECS spine key — ADR-001)
-- Réutilise fn_deny_entity_id_update() : sémantique identique (spine FK immuable).
CREATE TRIGGER core_deny_document_id_update
BEFORE UPDATE ON content.core
FOR EACH ROW WHEN (OLD.document_id IS DISTINCT FROM NEW.document_id)
EXECUTE FUNCTION identity.fn_deny_entity_id_update();


-- ==============================================================================
-- SECTION 11 : PROCÉDURES content
-- ==============================================================================

-- Création d'un document (spine + core + identity + body optionnel + 1re révision)
-- Gardes d'autorisation (ADR-001 rev.) :
--   create_contents (bit 1, valeur 2) requis.
--   p_author_id doit correspondre à rls_user_id() sauf si edit_others_contents (32768).
CREATE PROCEDURE content.create_document(
  p_author_id     INT,
  p_name          VARCHAR(255),
  p_slug          VARCHAR(255),
  OUT p_document_id INT,
  p_doc_type      SMALLINT      DEFAULT 0,
  p_status        SMALLINT      DEFAULT 0,
  p_content       TEXT          DEFAULT NULL,
  p_description   VARCHAR(1000) DEFAULT NULL,
  p_alt_headline  VARCHAR(255)  DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 2) <> 2 THEN
      RAISE EXCEPTION 'insufficient_privilege: create_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF p_author_id <> identity.rls_user_id()
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: cannot create document attributed to another author'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  INSERT INTO content.document (doc_type) VALUES (p_doc_type) RETURNING id INTO p_document_id;
  INSERT INTO content.core (document_id, author_entity_id, status, published_at, created_at)
  VALUES (p_document_id, p_author_id, p_status,
          CASE WHEN p_status = 1 THEN now() ELSE NULL END, now());
  INSERT INTO content.identity (document_id, slug, headline, alternative_headline, description)
  VALUES (p_document_id, p_slug, p_name, p_alt_headline, p_description);
  IF p_content IS NOT NULL THEN
    INSERT INTO content.body (document_id, content) VALUES (p_document_id, p_content);
  END IF;
  -- revision_num omis : délégué au trigger fn_revision_num() (BEFORE INSERT).
  INSERT INTO content.revision (
    document_id, author_entity_id,
    snapshot_headline, snapshot_slug, snapshot_alternative_headline,
    snapshot_description, snapshot_body
  )
  VALUES (p_document_id, p_author_id, p_name, p_slug, p_alt_headline, p_description, p_content);
END;
$$;

-- Publication d'un document (brouillon/archivé → publié)
-- Garde : publish_contents (bit 4, valeur 16) requis.
CREATE PROCEDURE content.publish_document(p_document_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 16) <> 16 THEN
    RAISE EXCEPTION 'insufficient_privilege: publish_contents required'
      USING ERRCODE = '42501';
  END IF;
  UPDATE content.core
  SET status = 1, published_at = COALESCE(published_at, now())
  WHERE document_id = p_document_id AND status IN (0, 2);
END;
$$;

-- Snapshot éditorial avant modification
-- Capture content.identity + content.body (ADR-024).
-- Garde : edit_contents (4) ou edit_others_contents (32768) + ownership check.
CREATE PROCEDURE content.save_revision(p_document_id INT, p_author_id INT)
LANGUAGE plpgsql AS $$
DECLARE
  v_headline    VARCHAR(255);
  v_slug        VARCHAR(255);
  v_alt         VARCHAR(255);
  v_description VARCHAR(1000);
  v_body        TEXT;
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id
        AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot save revision for another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  SELECT i.headline, i.slug, i.alternative_headline, i.description, b.content
  INTO   v_headline, v_slug, v_alt, v_description, v_body
  FROM   content.identity i
  LEFT JOIN content.body b ON b.document_id = i.document_id
  WHERE  i.document_id = p_document_id FOR SHARE;
  INSERT INTO content.revision (
    document_id, author_entity_id,
    snapshot_headline, snapshot_slug, snapshot_alternative_headline,
    snapshot_description, snapshot_body
  )
  VALUES (p_document_id, p_author_id, v_headline, v_slug, v_alt, v_description, v_body);
END;
$$;

-- Création d'un tag et insertion dans la Closure Table (ADR-018)
-- Garde : manage_tags (bit 11, valeur 2048) requis.
CREATE PROCEDURE content.create_tag(
  p_name      VARCHAR(64),
  p_slug      VARCHAR(64),
  OUT p_tag_id INT,
  p_parent_id INT DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 2048) <> 2048 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_tags required'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO content.tag (slug, name) VALUES (p_slug, p_name) RETURNING id INTO p_tag_id;
  -- Self-reference obligatoire (depth = 0)
  INSERT INTO content.tag_hierarchy (ancestor_id, descendant_id, depth)
  VALUES (p_tag_id, p_tag_id, 0);
  IF p_parent_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM content.tag_hierarchy
                   WHERE ancestor_id = p_parent_id AND descendant_id = p_parent_id) THEN
      RAISE EXCEPTION 'Tag parent introuvable dans la Closure Table (id=%)', p_parent_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    INSERT INTO content.tag_hierarchy (ancestor_id, descendant_id, depth)
    SELECT th.ancestor_id, p_tag_id, th.depth + 1
    FROM   content.tag_hierarchy th
    WHERE  th.descendant_id = p_parent_id;
    -- CHECK depth BETWEEN 0 AND 4 rejette automatiquement si depth + 1 > 4.
  END IF;
END;
$$;

-- Liaison tag → document (idempotent)
-- Gardes : edit_contents (4) ou edit_others_contents (32768) + ownership.
CREATE PROCEDURE content.add_tag_to_document(p_document_id INT, p_tag_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot tag another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  INSERT INTO content.content_to_tag (content_id, tag_id)
  VALUES (p_document_id, p_tag_id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- Déliaison tag → document (idempotent)
CREATE PROCEDURE content.remove_tag_from_document(p_document_id INT, p_tag_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot untag another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  DELETE FROM content.content_to_tag
  WHERE content_id = p_document_id AND tag_id = p_tag_id;
END;
$$;

-- Insertion d'un commentaire avec construction du chemin ltree (ADR-007)
-- nextval() préalable → path construit en mémoire → INSERT unique, zéro dead tuple.
-- Gardes : create_comments (bit 5, valeur 32) + ownership (p_account_entity_id = rls_user_id()).
CREATE PROCEDURE content.create_comment(
  p_document_id       INT,
  p_account_entity_id INT,
  p_content           TEXT,
  OUT p_comment_id    INT,
  p_parent_id         INT      DEFAULT NULL,
  p_status            SMALLINT DEFAULT 1
)
LANGUAGE plpgsql AS $$
DECLARE
  v_seq_name    TEXT;
  v_parent_path public.ltree;
  v_path        public.ltree;
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 32) <> 32 THEN
      RAISE EXCEPTION 'insufficient_privilege: create_comments required'
        USING ERRCODE = '42501';
    END IF;
    IF p_account_entity_id <> identity.rls_user_id() THEN
      RAISE EXCEPTION 'insufficient_privilege: cannot post comment attributed to another account'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  SELECT pg_get_serial_sequence('content.comment', 'id') INTO v_seq_name;
  p_comment_id := nextval(v_seq_name);
  IF p_parent_id IS NULL THEN
    v_path := public.text2ltree(p_document_id::text || '.' || p_comment_id::text);
  ELSE
    SELECT path INTO v_parent_path
    FROM   content.comment
    WHERE  id = p_parent_id AND document_id = p_document_id
    FOR SHARE;
    IF v_parent_path IS NULL THEN
      RAISE EXCEPTION
        'Commentaire parent introuvable ou appartenant à un autre document (parent_id=%, document_id=%)',
        p_parent_id, p_document_id
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    v_path := v_parent_path || public.text2ltree(p_comment_id::text);
  END IF;
  INSERT INTO content.comment (
    created_at, modified_at,
    document_id, account_entity_id, parent_id,
    id, status, path, content
  )
  OVERRIDING SYSTEM VALUE
  VALUES (
    now(), NULL,
    p_document_id, p_account_entity_id, p_parent_id,
    p_comment_id, p_status, v_path, p_content
  );
END;
$$;

-- Création atomique d'un média (media_core + media_content optionnel)
-- Garde : upload_files (8192).
CREATE PROCEDURE content.create_media(
  p_author_id        INT,
  OUT p_media_id     INT,
  p_mime_type        VARCHAR(255)  DEFAULT NULL,
  p_folder_url       VARCHAR(255)  DEFAULT NULL,
  p_file_name        VARCHAR(255)  DEFAULT NULL,
  p_width            INT           DEFAULT NULL,
  p_height           INT           DEFAULT NULL,
  p_name             VARCHAR(255)  DEFAULT NULL,
  p_description      VARCHAR(255)  DEFAULT NULL,
  p_copyright_notice VARCHAR(255)  DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 8192) <> 8192 THEN
      RAISE EXCEPTION 'insufficient_privilege: upload_files required to create a media'
        USING ERRCODE = '42501';
    END IF;
    IF p_author_id <> identity.rls_user_id()
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: cannot create media attributed to another author'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  INSERT INTO content.media_core (author_id, mime_type, folder_url, file_name, width, height)
  VALUES (p_author_id, p_mime_type, p_folder_url, p_file_name, p_width, p_height)
  RETURNING id INTO p_media_id;
  IF p_name IS NOT NULL OR p_description IS NOT NULL OR p_copyright_notice IS NOT NULL THEN
    INSERT INTO content.media_content (media_id, name, description, copyright_notice)
    VALUES (p_media_id, p_name, p_description, p_copyright_notice);
  END IF;
END;
$$;

-- Liaison document ↔ média
-- Garde : edit_contents (4) ou edit_others_contents (32768) + ownership.
CREATE PROCEDURE content.add_media_to_document(
  p_document_id INT, p_media_id INT, p_position SMALLINT DEFAULT 0
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot add media to another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  INSERT INTO content.content_to_media (content_id, media_id, position)
  VALUES (p_document_id, p_media_id, p_position)
  ON CONFLICT (content_id, media_id) DO UPDATE SET position = EXCLUDED.position;
END;
$$;

-- Déliaison document ↔ média
CREATE PROCEDURE content.remove_media_from_document(p_document_id INT, p_media_id INT)
LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1 THEN
    IF (identity.rls_auth_bits() & 4) <> 4
       AND (identity.rls_auth_bits() & 32768) <> 32768 THEN
      RAISE EXCEPTION 'insufficient_privilege: edit_contents or edit_others_contents required'
        USING ERRCODE = '42501';
    END IF;
    IF (identity.rls_auth_bits() & 32768) <> 32768 THEN
      PERFORM 1 FROM content.core
      WHERE document_id = p_document_id AND author_entity_id = identity.rls_user_id();
      IF NOT FOUND THEN
        RAISE EXCEPTION 'insufficient_privilege: cannot remove media from another author''s document'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  DELETE FROM content.content_to_media WHERE content_id = p_document_id AND media_id = p_media_id;
END;
$$;


-- ==============================================================================
-- SECTION 12 : VUES content
-- ==============================================================================

-- v_article_list — hot path listing (zéro TOAST, zéro agrégat)
-- WHERE GUC : mécanisme de contrôle d'accès primaire (ADR-003 invariant 2 révisé).
-- Comportement anonyme (GUC absent) : seul status=1 passe (comportement public préservé).
CREATE VIEW content.v_article_list AS
SELECT
  d.id                     AS identifier,
  ci.headline,
  ci.slug,
  ci.alternative_headline,
  ci.description,
  co.published_at,
  co.author_entity_id      AS author_id,
  co.status
FROM        content.document  d
JOIN        content.core      co ON co.document_id = d.id
JOIN        content.identity  ci ON ci.document_id = d.id
WHERE (
  co.status = 1
  OR (identity.rls_auth_bits() & 16)    = 16
  OR (identity.rls_auth_bits() & 32768) = 32768
  OR co.author_entity_id = identity.rls_user_id()
);

-- v_article — schema.org/Article (page complète avec TOAST + agrégats)
CREATE VIEW content.v_article AS
SELECT
  d.id                     AS identifier,
  d.doc_type,
  ci.headline,
  ci.slug,
  ci.alternative_headline,
  ci.description,
  co.status,
  co.is_readable,
  co.is_commentable,
  co.published_at,
  co.created_at,
  co.modified_at,
  co.author_entity_id      AS author_id,
  b.content                AS article_body,
  (SELECT json_agg(json_build_object(
    'id', t.id, 'name', t.name, 'slug', t.slug
  ) ORDER BY t.name)
   FROM content.content_to_tag ct JOIN content.tag t ON t.id = ct.tag_id
   WHERE ct.content_id = d.id)  AS keywords,
  (SELECT json_agg(json_build_object(
    'id', m.id, 'name', mc.name,
    'url', m.folder_url || '/' || m.file_name,
    'mime_type', m.mime_type, 'width', m.width,
    'height', m.height, 'position', ctm.position
  ) ORDER BY ctm.position)
   FROM  content.content_to_media ctm
   JOIN  content.media_core       m   ON m.id       = ctm.media_id
   LEFT JOIN content.media_content mc ON mc.media_id = m.id
   WHERE ctm.content_id = d.id)  AS images
FROM        content.document  d
JOIN        content.core      co ON co.document_id = d.id
JOIN        content.identity  ci ON ci.document_id = d.id
LEFT JOIN   content.body      b  ON b.document_id  = d.id
WHERE (
  co.status = 1
  OR (identity.rls_auth_bits() & 16)    = 16
  OR (identity.rls_auth_bits() & 32768) = 32768
  OR co.author_entity_id = identity.rls_user_id()
);

-- v_tag_tree — taxonomie avec Closure Table (ADR-018)
CREATE VIEW content.v_tag_tree AS
SELECT
  t.id         AS identifier,
  t.name,
  t.slug,
  COALESCE((
    SELECT MAX(th.depth) FROM content.tag_hierarchy th
    WHERE  th.descendant_id = t.id AND th.ancestor_id <> t.id
  ), 0)        AS depth,
  (SELECT th_p.ancestor_id FROM content.tag_hierarchy th_p
   WHERE  th_p.descendant_id = t.id AND th_p.depth = 1
   LIMIT  1)   AS parent_id,
  (SELECT string_agg(a.name, ' > ' ORDER BY th_a.depth DESC)
   FROM   content.tag_hierarchy th_a
   JOIN   content.tag           a  ON a.id = th_a.ancestor_id
   WHERE  th_a.descendant_id = t.id AND th_a.depth > 0) AS breadcrumb,
  (SELECT COUNT(*) FROM content.content_to_tag ct
   JOIN   content.core co ON co.document_id = ct.content_id
   WHERE  ct.tag_id = t.id AND co.status = 1) AS article_count
FROM content.tag t;
