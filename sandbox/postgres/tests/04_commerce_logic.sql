-- ==============================================================================
-- 04_commerce_logic.sql
-- Tests fonctionnels : domaine Commerce
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre : atomicité de create_transaction (ADR-016), décrémentation atomique
--          du stock (ADR-024 FOR UPDATE), immutabilité du snapshot de prix
--          en centimes (ADR-026), rejet de la sur-vente (CHECK stock_positive),
--          agrégation correcte dans v_transaction (subtotal + total avec taxes).
--          ADR-030 : gardes ownership/statut create_transaction(_item), trigger immutabilité.
--
-- Exécution : psql -U postgres -d marius -f tests/04_commerce_logic.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(17);


-- ============================================================
-- DONNÉES DE TEST
-- ============================================================

CREATE TEMP TABLE _ids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

-- Client
DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'buyer_cmt', '$argon2id$v=19$m=65536$com_test',
    'buyer-cmt', 7, 'fr_FR', v_id
  );
  INSERT INTO _ids VALUES ('client_id', v_id);
END;
$$;

-- Organisation vendeur
DO $$
DECLARE v_id INT;
BEGIN
  CALL org.create_organization('Org Vendeur Test', 'org-vendeur-test', 'company', NULL, NULL, v_id);
  INSERT INTO _ids VALUES ('org_id', v_id);
END;
$$;

-- Produit — prix initial : 29,99 € = 2999 centimes, stock = 5
WITH ins AS (
  INSERT INTO commerce.product_core (price_cents, stock, is_available)
  VALUES (2999, 5, true) RETURNING id
)
INSERT INTO _ids SELECT 'product_id', id FROM ins;

INSERT INTO commerce.product_identity (product_id, name, slug)
VALUES ((SELECT val FROM _ids WHERE key = 'product_id'), 'Produit de test', 'produit-de-test');

-- Transaction créée via la procédure (ADR-016)
DO $$
DECLARE v_id INT;
BEGIN
  CALL commerce.create_transaction(
    (SELECT val FROM _ids WHERE key = 'client_id'),
    (SELECT val FROM _ids WHERE key = 'org_id'),
    978,   -- EUR
    0,     -- pending
    NULL,  -- description
    v_id
  );
  INSERT INTO _ids VALUES ('txn_id', v_id);
END;
$$;


-- ============================================================
-- TEST 1–3 — create_transaction : atomicité des quatre composants (ADR-016)
-- ============================================================

SELECT ok(
  EXISTS (SELECT 1 FROM commerce.transaction_core WHERE id = (SELECT val FROM _ids WHERE key = 'txn_id')),
  'create_transaction : transaction_core créé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM commerce.transaction_price WHERE transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id')),
  'create_transaction : transaction_price initialisé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM commerce.transaction_payment WHERE transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id')),
  'create_transaction : transaction_payment initialisé'
);

SELECT ok(
  EXISTS (SELECT 1 FROM commerce.transaction_delivery WHERE transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id')),
  'create_transaction : transaction_delivery initialisé'
);


-- ============================================================
-- TEST 4 — currency_code par défaut : 978 (EUR) (ADR-016)
-- ============================================================

SELECT is(
  (SELECT currency_code FROM commerce.transaction_price
   WHERE  transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id')),
  978::SMALLINT,
  'create_transaction : currency_code = 978 (EUR) par défaut (ADR-016)'
);


-- ============================================================
-- TEST 5 — Ajout d'une ligne de commande et décrémentation du stock
-- ============================================================

CALL commerce.create_transaction_item(
  (SELECT val FROM _ids WHERE key = 'txn_id'),
  (SELECT val FROM _ids WHERE key = 'product_id'),
  2   -- quantité
);

SELECT is(
  (SELECT stock FROM commerce.product_core WHERE id = (SELECT val FROM _ids WHERE key = 'product_id')),
  3,
  'create_transaction_item : stock décrémenté de 5 à 3 (quantité = 2)'
);


-- ============================================================
-- TEST 6 — Snapshot du prix au moment de la commande (ADR-026)
-- ============================================================

SELECT is(
  (SELECT unit_price_snapshot_cents FROM commerce.transaction_item
   WHERE  transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id')
     AND  product_id     = (SELECT val FROM _ids WHERE key = 'product_id')),
  2999::BIGINT,
  'create_transaction_item : snapshot de prix = 2999 centimes (29,99 €)'
);


-- ============================================================
-- TEST 7 — Immutabilité du snapshot après modification du prix catalogue
-- ============================================================

UPDATE commerce.product_core
SET    price_cents = 4999
WHERE  id = (SELECT val FROM _ids WHERE key = 'product_id');

SELECT is(
  (SELECT unit_price_snapshot_cents FROM commerce.transaction_item
   WHERE  transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id')
     AND  product_id     = (SELECT val FROM _ids WHERE key = 'product_id')),
  2999::BIGINT,
  'Snapshot immuable : unit_price_snapshot_cents reste 2999 après update du prix catalogue'
);


-- ============================================================
-- TEST 8 — Rejet de la sur-vente (CHECK stock_positive)
-- stock courant = 3, tentative qty = 10 → stock cible = -7 → 23514
-- ============================================================

SELECT throws_ok(
  format(
    'CALL commerce.create_transaction_item(%s, %s, 10)',
    (SELECT val FROM _ids WHERE key = 'txn_id'),
    (SELECT val FROM _ids WHERE key = 'product_id')
  ),
  '23514',
  NULL,
  'Commande dépassant le stock (qty=10 > stock=3) : CHECK violation 23514'
);


-- ============================================================
-- TEST 9 — v_transaction : subtotalCents correct (ADR-023 + ADR-026)
-- 2 unités × 2999 = 5998 centimes
-- ============================================================

SELECT is(
  (SELECT subtotal_cents
   FROM   commerce.v_transaction
   WHERE  identifier = (SELECT val FROM _ids WHERE key = 'txn_id')),
  5998::BIGINT,
  'v_transaction.subtotal_cents = 5998 (2 × 2999 centimes)'
);


-- ============================================================
-- TEST 10 — v_transaction : totalCents avec taxes et livraison (ADR-016)
-- On fixe shipping = 500 ct, tax = 1200 ct, discount = 0
-- totalCents attendu = 5998 + 500 + 1200 - 0 = 7698
-- ============================================================

UPDATE commerce.transaction_price
SET    shipping_cents = 500,
       tax_cents      = 1200,
       discount_cents = 0
WHERE  transaction_id = (SELECT val FROM _ids WHERE key = 'txn_id');

SELECT is(
  (SELECT total_cents
   FROM   commerce.v_transaction
   WHERE  identifier = (SELECT val FROM _ids WHERE key = 'txn_id')),
  7698::BIGINT,
  'v_transaction.total_cents = 7698 (5998 subtotal + 500 ship + 1200 tax)'
);


-- ============================================================
-- TEST 11 — v_product : exposition de priceCents courant (ADR-026)
-- Prix catalogue mis à jour à 4999 ci-dessus
-- ============================================================

SELECT is(
  (SELECT price_cents
   FROM   commerce.v_product
   WHERE  identifier = (SELECT val FROM _ids WHERE key = 'product_id')),
  4999::BIGINT,
  'v_product.price_cents = 4999 (prix catalogue après mise à jour)'
);


-- ============================================================
-- TEST 12 — v_transaction : currencyCode présent (ADR-016)
-- ============================================================

SELECT is(
  (SELECT currency_code
   FROM   commerce.v_transaction
   WHERE  identifier = (SELECT val FROM _ids WHERE key = 'txn_id')),
  978::SMALLINT,
  'v_transaction.currency_code = 978 (EUR)'
);




-- ============================================================
-- TEST 13 — create_transaction : ownership guard (ADR-030)
-- Un subscriber ne peut pas créer une transaction pour un autre client.
-- ============================================================

DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'buyer_other', '$argon2id$v=19$m=65536$other',
    'buyer-other', 7, 'fr_FR', v_id
  );
  INSERT INTO _ids VALUES ('other_client_id', v_id);
END;
$$;

SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'client_id'), true);
SELECT set_config('marius.auth_bits', '16384', true);  -- subscriber
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  format(
    'CALL commerce.create_transaction(%s, %s, 978, 0, NULL)',
    (SELECT val FROM _ids WHERE key = 'other_client_id'),  -- autre client
    (SELECT val FROM _ids WHERE key = 'org_id')
  ),
  '42501', NULL,
  'create_transaction : subscriber ne peut pas créer une transaction pour un autre client (ADR-030)'
);

RESET ROLE;


-- ============================================================
-- TEST 14 — create_transaction_item : statut guard (ADR-030)
-- Impossible d'ajouter un item à une transaction confirmée (status ≠ 0).
-- ============================================================

-- Confirmer la transaction de test (status 0 → 1)
UPDATE commerce.transaction_core
SET    status = 1
WHERE  id = (SELECT val FROM _ids WHERE key = 'txn_id');

SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'client_id'), true);
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  format(
    'CALL commerce.create_transaction_item(%s, %s, 1)',
    (SELECT val FROM _ids WHERE key = 'txn_id'),
    (SELECT val FROM _ids WHERE key = 'product_id')
  ),
  '55000', NULL,
  'create_transaction_item : impossible d''ajouter un item à une transaction confirmée (ADR-030)'
);

RESET ROLE;

-- Remettre en pending pour les tests suivants
UPDATE commerce.transaction_core
SET    status = 0
WHERE  id = (SELECT val FROM _ids WHERE key = 'txn_id');


-- ============================================================
-- TEST 15 — create_transaction_item : ownership guard (ADR-030)
-- Un subscriber ne peut pas ajouter des items à la transaction d'un autre client.
-- ============================================================

SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'other_client_id'), true);  -- pas le client de txn_id
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  format(
    'CALL commerce.create_transaction_item(%s, %s, 1)',
    (SELECT val FROM _ids WHERE key = 'txn_id'),
    (SELECT val FROM _ids WHERE key = 'product_id')
  ),
  '42501', NULL,
  'create_transaction_item : subscriber ne peut pas ajouter un item à la transaction d''autrui (ADR-030)'
);

RESET ROLE;


-- ============================================================
-- TEST 16 — Trigger immutabilité de transaction_item (ADR-030)
-- unit_price_snapshot_cents ne peut pas être modifié après INSERT.
-- ============================================================

SELECT throws_ok(
  format(
    $$UPDATE commerce.transaction_item
      SET    unit_price_snapshot_cents = 9999
      WHERE  transaction_id = %s AND product_id = %s$$,
    (SELECT val FROM _ids WHERE key = 'txn_id'),
    (SELECT val FROM _ids WHERE key = 'product_id')
  ),
  '55000', NULL,
  'transaction_item : UPDATE interdit par trigger immutabilité (ADR-030)'
);

SELECT * FROM finish();
ROLLBACK;
