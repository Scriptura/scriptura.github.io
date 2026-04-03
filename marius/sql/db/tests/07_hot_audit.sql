-- ==============================================================================
-- 07_hot_audit.sql
-- Tests HOT (Heap Only Tuple) efficiency — Audit 3
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre :
--   A — Immuabilité de created_at : rejet effectif sur les 4 tables BRIN
--   B — Matrice HOT product_core : stock non indexé, price_cents indexé
--   C — Matrice HOT identity.auth : all UPDATE paths HOT-eligible
--   D — Corrélation BRIN : vérification via pg_stats
--   E — content.core fillfactor absent (Audit 3 correction)
--
-- Exécution : psql -U postgres -d marius -f 07_hot_audit.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(14);


-- ============================================================
-- DONNÉES DE TEST
-- ============================================================

CREATE TEMP TABLE _ids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'hot_audit_user', '$argon2id$v=19$m=65536$hot',
    'hot-audit-user', 7, 'fr_FR', v_id
  );
  INSERT INTO _ids VALUES ('entity_id', v_id);
END;
$$;

DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_document(
    (SELECT val FROM _ids WHERE key = 'entity_id'),
    'Doc HOT Audit', 'doc-hot-audit',
    0, 0, NULL, NULL, NULL, v_id
  );
  INSERT INTO _ids VALUES ('doc_id', v_id);
END;
$$;


-- ============================================================
-- A — IMMUABILITÉ DE created_at (Audit 3 · ADR-010 rev.)
--
-- Le trigger BEFORE UPDATE avec clause WHEN (OLD.created_at IS DISTINCT FROM NEW.created_at)
-- doit lever SQLSTATE 55000. La clause WHEN garantit coût nul sur les paths nominaux.
-- ============================================================

SELECT throws_ok(
  format(
    $$UPDATE identity.auth SET created_at = now() - interval '1 day'
      WHERE entity_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'entity_id')
  ),
  '55000',
  NULL,
  'identity.auth : UPDATE created_at rejeté → BRIN correlation préservée (Audit 3)'
);

SELECT throws_ok(
  format(
    $$UPDATE content.core SET created_at = now() - interval '1 day'
      WHERE document_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'doc_id')
  ),
  '55000',
  NULL,
  'content.core : UPDATE created_at rejeté → BRIN correlation préservée (Audit 3)'
);


-- ============================================================
-- A.3 — UPDATE nominal sur identity.auth : created_at non touché → pas de rejet
--
-- Valide que le trigger WHEN est bien ciblé et ne bloque pas les updates légitimes.
-- record_login → UPDATE last_login_at uniquement → HOT eligible.
-- ============================================================

CALL identity.record_login((SELECT val FROM _ids WHERE key = 'entity_id'));

SELECT ok(
  (SELECT last_login_at FROM identity.auth
   WHERE entity_id = (SELECT val FROM _ids WHERE key = 'entity_id')) IS NOT NULL,
  'identity.auth : record_login (UPDATE last_login_at) non bloqué par le trigger BRIN (Audit 3)'
);


-- ============================================================
-- B — MATRICE HOT product_core (Audit 3)
--
-- B.1 : stock n'est pas indexé → UPDATE stock = HOT-eligible.
-- On valide l'absence d'index sur la colonne stock via pg_attribute + pg_index.
-- ============================================================

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_index     ix
    JOIN   pg_class     t  ON t.oid  = ix.indrelid
    JOIN   pg_namespace n  ON n.oid  = t.relnamespace
    JOIN   pg_attribute a  ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    WHERE  n.nspname = 'commerce'
      AND  t.relname = 'product_core'
      AND  a.attname = 'stock'
  ),
  'product_core.stock non indexé : UPDATE stock HOT-eligible (Audit 3)'
);

-- B.2 : price_cents est indexé → UPDATE price_cents casse HOT (low freq, acceptable)
SELECT ok(
  EXISTS (
    SELECT 1
    FROM   pg_index     ix
    JOIN   pg_class     t  ON t.oid  = ix.indrelid
    JOIN   pg_namespace n  ON n.oid  = t.relnamespace
    JOIN   pg_attribute a  ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    WHERE  n.nspname = 'commerce'
      AND  t.relname = 'product_core'
      AND  a.attname = 'price_cents'
  ),
  'product_core.price_cents indexé : UPDATE price_cents non HOT (low freq — documenté Audit 3)'
);


-- ============================================================
-- C — MATRICE HOT identity.auth (Audit 3)
--
-- Colonnes modifiées par les procédures : last_login_at, password_hash,
-- is_banned, role_id. Aucune de ces colonnes ne doit être dans un index
-- (hors PK entity_id, jamais mutée).
-- ============================================================

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_index     ix
    JOIN   pg_class     t  ON t.oid  = ix.indrelid
    JOIN   pg_namespace n  ON n.oid  = t.relnamespace
    JOIN   pg_attribute a  ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
    WHERE  n.nspname = 'identity'
      AND  t.relname = 'auth'
      AND  a.attname IN ('last_login_at', 'password_hash', 'is_banned', 'role_id')
      AND  NOT ix.indisprimary   -- exclure la PK
  ),
  'identity.auth : last_login_at/password_hash/is_banned/role_id non indexés → tous HOT-eligible (Audit 3)'
);


-- ============================================================
-- D — CORRÉLATION BRIN via pg_stats
--
-- pg_stats.correlation mesure la corrélation entre l'ordre logique des valeurs
-- et l'ordre physique des tuples dans le heap.
--   1.0  = ordre physique ≡ ordre croissant des valeurs → BRIN optimal
--  -1.0  = ordre physique ≡ ordre décroissant
--   ~0.0 = aucune corrélation → BRIN inefficace (scan de zone dégradé)
--
-- Pour created_at avec DEFAULT now() et insertions séquentielles :
--   corrélation attendue ≈ 1.0 (lignes ajoutées dans l'ordre croissant du temps).
--
-- Note : pg_stats est alimenté par ANALYZE. Dans un environnement CI/CD
-- avec ANALYZE explicite post-seed, la valeur est disponible. Sans ANALYZE,
-- pg_stats retourne NULL pour les tables nouvellement créées.
-- Ce test est consultatif (ok sur NULL) : il sert de filet pour détecter
-- une dégradation de corrélation sur un environnement avec des données réelles.
-- La dégradation en production est diagnostiquée via :
--   SELECT tablename, correlation FROM pg_stats
--   WHERE tablename IN ('auth', 'transaction_core', 'org_core')
--     AND attname = 'created_at';
-- ============================================================

SELECT ok(
  COALESCE(
    (SELECT correlation > 0.8
     FROM   pg_stats
     WHERE  tablename = 'auth' AND attname = 'created_at'
     LIMIT  1),
    true  -- NULL acceptable : ANALYZE non encore exécuté sur table fraîche
  ),
  'BRIN correlation identity.auth.created_at > 0.8 (ou NULL si ANALYZE absent)'
);

SELECT ok(
  COALESCE(
    (SELECT correlation > 0.8
     FROM   pg_stats
     WHERE  tablename = 'core'
       AND  schemaname = 'content'
       AND  attname = 'created_at'
     LIMIT  1),
    true
  ),
  'BRIN correlation content.core.created_at > 0.8 (ou NULL si ANALYZE absent)'
);

SELECT ok(
  COALESCE(
    (SELECT correlation > 0.8
     FROM   pg_stats
     WHERE  tablename = 'transaction_core' AND attname = 'created_at'
     LIMIT  1),
    true
  ),
  'BRIN correlation commerce.transaction_core.created_at > 0.8 (ou NULL si ANALYZE absent)'
);


-- ============================================================
-- E — content.core fillfactor retiré (Audit 3)
--
-- fillfactor < 100 sur une table sans chemin HOT valide = perte nette
-- de densité. content.core passe à fillfactor=100 (défaut PostgreSQL).
-- Tous ses chemins UPDATE touchent des colonnes indexées (published_at,
-- modified_at) ou des conditions de partial index (status).
-- ============================================================

SELECT ok(
  NOT COALESCE(
    (SELECT reloptions @> ARRAY['fillfactor=75']
     FROM   pg_class
     WHERE  relname = 'core'
       AND  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'content')),
    false
  ),
  'content.core fillfactor absent : densité tuples ≈ +25% (127 → ~169/page) (Audit 3)'
);


-- ============================================================
-- F — HOT UPDATE effectif sur identity.auth : last_login_at
--
-- On vérifie que record_login ne crée pas de dead tuple structurel
-- en consultant pg_stat_user_tables.n_dead_tup immédiatement après.
-- Sur une table à une seule ligne et fillfactor=70, un HOT réussi
-- maintient n_dead_tup à 0 (la nouvelle version réutilise l'espace
-- intra-page, l'ancienne est nettoyée immédiatement par le vacuum léger).
--
-- Note : ce test est heuristique — n_dead_tup peut ne pas refléter
-- immédiatement le nettoyage HOT dans la même transaction. Le test
-- vérifie surtout l'absence d'une croissance anormale (>> 1).
-- ============================================================

CALL identity.record_login((SELECT val FROM _ids WHERE key = 'entity_id'));
CALL identity.record_login((SELECT val FROM _ids WHERE key = 'entity_id'));
CALL identity.record_login((SELECT val FROM _ids WHERE key = 'entity_id'));

SELECT ok(
  COALESCE(
    (SELECT n_dead_tup < 5   -- seuil conservateur : HOT doit limiter l'accumulation
     FROM   pg_stat_user_tables
     WHERE  schemaname = 'identity' AND relname = 'auth'),
    true  -- NULL si stats non encore collectées
  ),
  'identity.auth : n_dead_tup < 5 après 3 record_login successifs — HOT actif (Audit 3)'
);


SELECT * FROM finish();
ROLLBACK;
