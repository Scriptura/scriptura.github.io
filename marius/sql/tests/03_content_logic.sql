-- ==============================================================================
-- 03_content_logic.sql
-- Tests fonctionnels : domaine Content
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre : atomicité de create_document, snapshot complet de save_revision
--          (ADR-024), cycle de vie éditorial (publish_document), construction
--          des chemins ltree dans create_comment (ADR-007), rejet des
--          parentés inter-documents.
--
-- Exécution : psql -U postgres -d marius -f 03_content_logic.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(17);


-- ============================================================
-- DONNÉES DE TEST
-- ============================================================

CREATE TEMP TABLE _ids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

-- Auteur
DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'author_cnt',
    '$argon2id$v=19$m=65536$cnt_test',
    'author-cnt',
    7, 'fr_FR',
    v_id
  );
  INSERT INTO _ids VALUES ('author_id', v_id);
END;
$$;

-- Document 1 : article complet avec alt_headline et description
DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_document(
    (SELECT val FROM _ids WHERE key = 'author_id'),
    'Article de test',           -- p_name
    'article-de-test',           -- p_slug
    0,                           -- p_doc_type = article
    0,                           -- p_status = brouillon
    'Corps initial de larticle', -- p_content
    'Description initiale',      -- p_description
    'Chapô initial',             -- p_alt_headline
    v_id
  );
  INSERT INTO _ids VALUES ('doc1_id', v_id);
END;
$$;

-- Document 2 : minimal, pour le test de parenté inter-documents
DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_document(
    (SELECT val FROM _ids WHERE key = 'author_id'),
    'Article bis', 'article-bis',
    0, 0, NULL, NULL, NULL,
    v_id
  );
  INSERT INTO _ids VALUES ('doc2_id', v_id);
END;
$$;

-- Commentaire racine sur le document 1
DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_comment(
    (SELECT val FROM _ids WHERE key = 'doc1_id'),
    (SELECT val FROM _ids WHERE key = 'author_id'),
    'Commentaire racine',
    NULL,   -- pas de parent
    1,      -- status = approuvé
    v_id
  );
  INSERT INTO _ids VALUES ('cmt1_id', v_id);
END;
$$;

-- Commentaire réponse (enfant du commentaire racine)
DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_comment(
    (SELECT val FROM _ids WHERE key = 'doc1_id'),
    (SELECT val FROM _ids WHERE key = 'author_id'),
    'Réponse au commentaire racine',
    (SELECT val FROM _ids WHERE key = 'cmt1_id'),
    1,
    v_id
  );
  INSERT INTO _ids VALUES ('cmt2_id', v_id);
END;
$$;


-- ============================================================
-- create_document : atomicité des composants ECS
--
-- La procédure crée quatre objets atomiquement :
--   content.document  → spine documentaire
--   content.core      → status, dates, auteur (hot path)
--   content.identity  → titre, slug, description (listing path)
--   content.revision  → snapshot initial (révision n°1)
-- ============================================================

SELECT ok(
  EXISTS (SELECT 1 FROM content.document WHERE id = (SELECT val FROM _ids WHERE key = 'doc1_id')),
  'create_document : content.document créé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM content.core WHERE document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')),
  'create_document : content.core créé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM content.identity WHERE document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')),
  'create_document : content.identity créé'
);


-- ============================================================
-- Snapshot initial de create_document (ADR-024)
--
-- La révision n°1 est insérée dans create_document. Elle doit capturer
-- l'intégralité des champs éditoriaux, y compris alternative_headline et
-- description — ajoutés suite à l'audit ADR-024 (manquants dans la version
-- précédente, ce qui rendait l'historique silencieusement incomplet).
-- ============================================================

SELECT is(
  (SELECT snapshot_headline FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 1),
  'Article de test',
  'Révision initiale : snapshot_headline = ''Article de test'''
);

SELECT is(
  (SELECT snapshot_alternative_headline FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 1),
  'Chapô initial',
  'Révision initiale : snapshot_alternative_headline capturé (ADR-024)'
);

SELECT is(
  (SELECT snapshot_description FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 1),
  'Description initiale',
  'Révision initiale : snapshot_description capturé (ADR-024)'
);

SELECT is(
  (SELECT snapshot_body FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 1),
  'Corps initial de larticle',
  'Révision initiale : snapshot_body capturé'
);


-- ============================================================
-- publish_document : transition d'état brouillon → publié
-- ============================================================

CALL content.publish_document((SELECT val FROM _ids WHERE key = 'doc1_id'));

SELECT is(
  (SELECT status FROM content.core
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')),
  1::SMALLINT,
  'publish_document : status = 1 (publié)'
);

SELECT ok(
  (SELECT published_at FROM content.core
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')) IS NOT NULL,
  'publish_document : published_at renseigné'
);


-- ============================================================
-- save_revision : snapshot complet après modification (ADR-024)
--
-- On met à jour les colonnes de content.identity et content.body directement
-- (as postgres, owner des tables), puis on appelle save_revision.
-- La révision n°2 doit refléter les nouvelles valeurs pour les champs modifiés.
-- snapshot_headline n'est pas touché → doit rester identique à la révision n°1.
-- ============================================================

UPDATE content.identity
SET    alternative_headline = 'Chapô v2',
       description          = 'Description v2'
WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id');

UPDATE content.body
SET    content = 'Corps remanié version 2'
WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id');

CALL content.save_revision(
  (SELECT val FROM _ids WHERE key = 'doc1_id'),
  (SELECT val FROM _ids WHERE key = 'author_id')
);

SELECT is(
  (SELECT snapshot_headline FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 2),
  'Article de test',
  'save_revision n°2 : snapshot_headline inchangé (titre non modifié)'
);

SELECT is(
  (SELECT snapshot_alternative_headline FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 2),
  'Chapô v2',
  'save_revision n°2 : snapshot_alternative_headline = ''Chapô v2'' (ADR-024)'
);

SELECT is(
  (SELECT snapshot_description FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 2),
  'Description v2',
  'save_revision n°2 : snapshot_description = ''Description v2'' (ADR-024)'
);

SELECT is(
  (SELECT snapshot_body FROM content.revision
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc1_id')
     AND  revision_num = 2),
  'Corps remanié version 2',
  'save_revision n°2 : snapshot_body mis à jour'
);


-- ============================================================
-- create_comment : construction des chemins ltree (ADR-007)
--
-- La procédure alloue l'id via nextval() AVANT l'INSERT, construit le chemin
-- en mémoire PL/pgSQL, puis effectue un INSERT unique avec OVERRIDING SYSTEM
-- VALUE. Zéro dead tuple structurel (pas de trigger AFTER + UPDATE).
--
-- Format attendu :
--   Racine : <document_id>.<comment_id>
--   Réponse : <document_id>.<parent_comment_id>.<child_comment_id>
-- ============================================================

SELECT is(
  (SELECT path::text FROM content.comment
   WHERE  id = (SELECT val FROM _ids WHERE key = 'cmt1_id')),
  (SELECT val FROM _ids WHERE key = 'doc1_id')::text
    || '.' ||
  (SELECT val FROM _ids WHERE key = 'cmt1_id')::text,
  'create_comment racine : chemin ltree = <doc_id>.<cmt_id>'
);

SELECT is(
  (SELECT path::text FROM content.comment
   WHERE  id = (SELECT val FROM _ids WHERE key = 'cmt2_id')),
  (SELECT val FROM _ids WHERE key = 'doc1_id')::text
    || '.' ||
  (SELECT val FROM _ids WHERE key = 'cmt1_id')::text
    || '.' ||
  (SELECT val FROM _ids WHERE key = 'cmt2_id')::text,
  'create_comment réponse : chemin ltree = <doc_id>.<parent_id>.<cmt_id>'
);


-- ============================================================
-- create_comment : rejet d'une parenté inter-documents
--
-- Si parent_id appartient à un document différent de document_id, la procédure
-- doit lever une exception (ERRCODE foreign_key_violation = 23503).
-- Sans cette garde, un chemin ltree incohérent serait inséré silencieusement.
-- ============================================================

SELECT throws_ok(
  format(
    'CALL content.create_comment(%s, %s, ''Commentaire parasite'', %s, 1)',
    (SELECT val FROM _ids WHERE key = 'doc2_id'),    -- document 2
    (SELECT val FROM _ids WHERE key = 'author_id'),
    (SELECT val FROM _ids WHERE key = 'cmt1_id')     -- parent dans document 1
  ),
  '23503',
  NULL,
  'create_comment : parent_id appartenant à un autre document → exception 23503'
);


-- ============================================================
-- create_comment : statut par défaut
-- ============================================================

SELECT is(
  (SELECT status FROM content.comment
   WHERE  id = (SELECT val FROM _ids WHERE key = 'cmt1_id')),
  1::SMALLINT,
  'create_comment : status = 1 (approuvé) par défaut'
);


SELECT * FROM finish();
ROLLBACK;
