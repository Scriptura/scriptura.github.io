-- ==============================================================================
-- 05_tag_hierarchy.sql
-- Tests fonctionnels : Closure Table — domaine Content · taxonomie des tags
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre : atomicité de create_tag (spine + self-ref + héritage ancêtres),
--          profondeur maximale (depth ≤ 4), rejet si depth dépassé,
--          navigation de sous-arbre via tag_hierarchy, v_tag_tree breadcrumb.
--
-- Exécution : psql -U postgres -d marius -f tests/05_tag_hierarchy.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(10);


-- ============================================================
-- DONNÉES DE TEST — hiérarchie à 4 niveaux
--
--   Racine (L0)
--     └── Enfant L1
--           └── Enfant L2
--                 └── Enfant L3
--                       └── Feuille L4 (profondeur max)
-- ============================================================

CREATE TEMP TABLE _tids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_tag('Racine Test',    'racine-test',    NULL, v_id);
  INSERT INTO _tids VALUES ('L0', v_id);

  CALL content.create_tag('Enfant L1',      'enfant-l1',
    (SELECT val FROM _tids WHERE key = 'L0'), v_id);
  INSERT INTO _tids VALUES ('L1', v_id);

  CALL content.create_tag('Enfant L2',      'enfant-l2',
    (SELECT val FROM _tids WHERE key = 'L1'), v_id);
  INSERT INTO _tids VALUES ('L2', v_id);

  CALL content.create_tag('Enfant L3',      'enfant-l3',
    (SELECT val FROM _tids WHERE key = 'L2'), v_id);
  INSERT INTO _tids VALUES ('L3', v_id);

  CALL content.create_tag('Feuille L4',     'feuille-l4',
    (SELECT val FROM _tids WHERE key = 'L3'), v_id);
  INSERT INTO _tids VALUES ('L4', v_id);
END;
$$;


-- ============================================================
-- TEST 1 — create_tag : self-reference obligatoire
-- ============================================================
SELECT ok(
  EXISTS (
    SELECT 1 FROM content.tag_hierarchy
    WHERE  ancestor_id = (SELECT val FROM _tids WHERE key = 'L0')
      AND  descendant_id = (SELECT val FROM _tids WHERE key = 'L0')
      AND  depth = 0
  ),
  'create_tag : self-reference (depth=0) insérée pour la racine'
);


-- ============================================================
-- TEST 2 — Nombre de lignes hiérarchiques pour la feuille L4
-- Feuille L4 doit avoir 5 ancêtres : L0, L1, L2, L3, L4(self)
-- ============================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM content.tag_hierarchy
   WHERE  descendant_id = (SELECT val FROM _tids WHERE key = 'L4')),
  5,
  'create_tag L4 : 5 lignes dans tag_hierarchy (L0→L4, L1→L4, L2→L4, L3→L4, self)'
);


-- ============================================================
-- TEST 3 — Profondeur de la feuille L4 = 4
-- ============================================================
SELECT is(
  (SELECT depth FROM content.tag_hierarchy
   WHERE  ancestor_id   = (SELECT val FROM _tids WHERE key = 'L0')
     AND  descendant_id = (SELECT val FROM _tids WHERE key = 'L4')),
  4::SMALLINT,
  'Profondeur L0→L4 = 4'
);


-- ============================================================
-- TEST 4 — Parent immédiat de L4 = L3
-- ============================================================
SELECT is(
  (SELECT ancestor_id FROM content.tag_hierarchy
   WHERE  descendant_id = (SELECT val FROM _tids WHERE key = 'L4')
     AND  depth = 1),
  (SELECT val FROM _tids WHERE key = 'L3'),
  'Parent immédiat de L4 = L3 (depth=1)'
);


-- ============================================================
-- TEST 5 — Rejet d'un tag à profondeur 5 (depth > 4 interdit)
-- ============================================================
SELECT throws_ok(
  format(
    $$CALL content.create_tag('Trop profond', 'trop-profond', %s)$$,
    (SELECT val FROM _tids WHERE key = 'L4')
  ),
  '23514',  -- check_violation : depth BETWEEN 0 AND 4
  NULL,
  'create_tag au-delà de depth=4 : CHECK violation 23514 (ADR-018)'
);


-- ============================================================
-- TEST 6 — Navigation de sous-arbre depuis L1
-- Descendants de L1 : L1(self), L2, L3, L4 → 4 lignes
-- ============================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM content.tag_hierarchy
   WHERE  ancestor_id = (SELECT val FROM _tids WHERE key = 'L1')),
  4,
  'Sous-arbre L1 : 4 descendants (L1 self + L2 + L3 + L4)'
);


-- ============================================================
-- TEST 7 — Descendants directs uniquement (depth=1)
-- Seul L2 est enfant direct de L1
-- ============================================================
SELECT is(
  (SELECT COUNT(*)::INT FROM content.tag_hierarchy
   WHERE  ancestor_id = (SELECT val FROM _tids WHERE key = 'L1') AND depth = 1),
  1,
  'Enfants directs de L1 (depth=1) : 1 seul (L2)'
);


-- ============================================================
-- TEST 8 — v_tag_tree : depth correct pour L4
-- ============================================================
SELECT is(
  (SELECT depth FROM content.v_tag_tree
   WHERE  identifier = (SELECT val FROM _tids WHERE key = 'L4')),
  4,
  'v_tag_tree : depth de L4 = 4'
);


-- ============================================================
-- TEST 9 — v_tag_tree : parent_id de L2 = L1
-- ============================================================
SELECT is(
  (SELECT parent_id FROM content.v_tag_tree
   WHERE  identifier = (SELECT val FROM _tids WHERE key = 'L2')),
  (SELECT val FROM _tids WHERE key = 'L1'),
  'v_tag_tree : parent_id de L2 = L1'
);


-- ============================================================
-- TEST 10 — v_tag_tree : breadcrumb de L4 contient 4 segments
-- "Racine Test > Enfant L1 > Enfant L2 > Enfant L3"
-- ============================================================
SELECT is(
  (SELECT breadcrumb FROM content.v_tag_tree
   WHERE  identifier = (SELECT val FROM _tids WHERE key = 'L4')),
  'Racine Test > Enfant L1 > Enfant L2 > Enfant L3',
  'v_tag_tree : breadcrumb de L4 = ''Racine Test > Enfant L1 > Enfant L2 > Enfant L3'''
);


SELECT * FROM finish();
ROLLBACK;
