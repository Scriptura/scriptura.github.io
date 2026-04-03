-- ==============================================================================
-- 06_commerce/02_systems.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : triggers commerce (immuabilité, modified_at, BRIN, audit)
--           · procédures commerce · vue commerce.v_product · vue commerce.v_transaction
--
-- Triggers cross-domaine déployés ici (fonctions définies en 02_identity) :
--   transaction_modified_at             → identity.fn_update_modified_at()
--   transaction_deny_created_at_update  → identity.fn_deny_created_at_update()
--   transaction_core_deny_id_update     → identity.fn_deny_entity_id_update()
--
-- Triggers d'audit (fonction identity.fn_dml_audit définie en 02_identity) :
--   audit_commerce_transaction_core
--   audit_commerce_transaction_item
--   audit_commerce_transaction_payment
--
-- SECURITY DEFINER + SET search_path appliqués en 08_dcl/02_secdef.sql
-- ==============================================================================


-- ==============================================================================
-- SECTION 7 suite : IMMUTABILITÉ transaction_item (ADR-030)
-- ==============================================================================

-- unit_price_snapshot_cents est un enregistrement d'audit financier — immuable
-- après INSERT, même par marius_admin. La seule opération légitime sur une ligne
-- existante est la suppression (annulation de commande).
CREATE FUNCTION commerce.fn_deny_transaction_item_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'transaction_item is immutable after INSERT: modify quantity by deleting and re-inserting the line'
    USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER transaction_item_immutable
BEFORE UPDATE ON commerce.transaction_item
FOR EACH ROW EXECUTE FUNCTION commerce.fn_deny_transaction_item_update();


-- ==============================================================================
-- SECTION 10 : TRIGGERS — tables commerce
-- ==============================================================================

-- TRANSACTION CORE : modified_at sur changement de statut
CREATE TRIGGER transaction_modified_at
BEFORE UPDATE ON commerce.transaction_core
FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION identity.fn_update_modified_at();

-- BRIN IMMUTABILITY — commerce.transaction_core.created_at
CREATE TRIGGER transaction_deny_created_at_update
BEFORE UPDATE ON commerce.transaction_core
FOR EACH ROW WHEN (OLD.created_at IS DISTINCT FROM NEW.created_at)
EXECUTE FUNCTION identity.fn_deny_created_at_update();

-- IMMUABILITÉ id (spine de transaction — ADR-001)
-- Réutilise fn_deny_entity_id_update() : même sémantique (clé de spine immuable).
CREATE TRIGGER transaction_core_deny_id_update
BEFORE UPDATE ON commerce.transaction_core
FOR EACH ROW WHEN (OLD.id IS DISTINCT FROM NEW.id)
EXECUTE FUNCTION identity.fn_deny_entity_id_update();

-- AUDIT — shadow write detection (ADR-001 rev.)
-- Fonction identity.fn_dml_audit() définie en 02_identity/02_systems.sql.
CREATE TRIGGER audit_commerce_transaction_core
AFTER INSERT OR UPDATE OR DELETE ON commerce.transaction_core
FOR EACH ROW EXECUTE FUNCTION identity.fn_dml_audit();

CREATE TRIGGER audit_commerce_transaction_item
AFTER INSERT OR UPDATE OR DELETE ON commerce.transaction_item
FOR EACH ROW EXECUTE FUNCTION identity.fn_dml_audit();

CREATE TRIGGER audit_commerce_transaction_payment
AFTER INSERT OR UPDATE OR DELETE ON commerce.transaction_payment
FOR EACH ROW EXECUTE FUNCTION identity.fn_dml_audit();


-- ==============================================================================
-- SECTION 11 : PROCÉDURES commerce
-- ==============================================================================

-- Création atomique d'un produit (product_core + product_identity)
-- Garde : manage_commerce (262144).
CREATE PROCEDURE commerce.create_product(
  p_name          VARCHAR(64),
  p_slug          VARCHAR(64),
  OUT p_product_id INT,
  p_price_cents   INT8         DEFAULT NULL,
  p_stock         INT          DEFAULT 0,
  p_isbn_ean      VARCHAR(13)  DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND (identity.rls_auth_bits() & 262144) <> 262144 THEN
    RAISE EXCEPTION 'insufficient_privilege: manage_commerce required to create a product'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO commerce.product_core (price_cents, stock, is_available)
  VALUES (p_price_cents, p_stock, true)
  RETURNING id INTO p_product_id;
  INSERT INTO commerce.product_identity (product_id, name, slug, isbn_ean)
  VALUES (p_product_id, p_name, p_slug, p_isbn_ean);
END;
$$;

-- Création d'une commande (transaction_core + composants ECS initialisés)
-- Les composants price, payment et delivery sont créés avec des valeurs par défaut.
-- Garde AOT : p_client_entity_id = rls_user_id() OU manage_commerce (262144).
CREATE PROCEDURE commerce.create_transaction(
  p_client_entity_id  INT,
  p_seller_entity_id  INT,
  OUT p_transaction_id INT,
  p_currency_code     SMALLINT DEFAULT 978,
  p_status            SMALLINT DEFAULT 0,
  p_description       TEXT     DEFAULT NULL
) LANGUAGE plpgsql AS $$
BEGIN
  IF identity.rls_user_id() <> -1
     AND p_client_entity_id <> identity.rls_user_id()
     AND (identity.rls_auth_bits() & 262144) <> 262144 THEN
    RAISE EXCEPTION 'insufficient_privilege: cannot create transaction for another client'
      USING ERRCODE = '42501';
  END IF;
  INSERT INTO commerce.transaction_core
    (client_entity_id, seller_entity_id, status, description)
  VALUES (p_client_entity_id, p_seller_entity_id, p_status, p_description)
  RETURNING id INTO p_transaction_id;

  -- Composant prix : devise et montants initialisés à zéro
  INSERT INTO commerce.transaction_price
    (transaction_id, currency_code, shipping_cents, discount_cents, tax_cents,
     tax_rate_bp, is_tax_included)
  VALUES (p_transaction_id, p_currency_code, 0, 0, 0, 0, false);

  -- Composant paiement : statut 0 = en attente
  INSERT INTO commerce.transaction_payment (transaction_id, payment_status)
  VALUES (p_transaction_id, 0);

  -- Composant livraison : statut 0 = en attente
  INSERT INTO commerce.transaction_delivery (transaction_id, delivery_status)
  VALUES (p_transaction_id, 0);
END;
$$;

-- Insertion d'une ligne de commande avec snapshot du prix
-- FOR UPDATE sur product_core (ADR-024) : verrou exclusif contre la sur-vente.
-- Gardes AOT :
--   1. Ownership : transaction doit appartenir à rls_user_id() OU manage_commerce.
--   2. Statut    : ajout d'items uniquement sur transaction status=0 (pending).
CREATE PROCEDURE commerce.create_transaction_item(
  p_transaction_id INT, p_product_id INT, p_quantity INT DEFAULT 1
) LANGUAGE plpgsql AS $$
DECLARE
  v_price_cents    INT8;
  v_txn_status     SMALLINT;
  v_txn_client_id  INT;
BEGIN
  SELECT status, client_entity_id
  INTO   v_txn_status, v_txn_client_id
  FROM   commerce.transaction_core
  WHERE  id = p_transaction_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transaction % introuvable', p_transaction_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF identity.rls_user_id() <> -1
     AND v_txn_client_id <> identity.rls_user_id()
     AND (identity.rls_auth_bits() & 262144) <> 262144 THEN
    RAISE EXCEPTION 'insufficient_privilege: cannot add item to another client''s transaction'
      USING ERRCODE = '42501';
  END IF;

  IF v_txn_status <> 0 THEN
    RAISE EXCEPTION 'Transaction % is not in pending state (status=%): items cannot be added',
      p_transaction_id, v_txn_status
      USING ERRCODE = '55000';
  END IF;

  SELECT price_cents INTO v_price_cents
  FROM   commerce.product_core WHERE id = p_product_id FOR UPDATE;
  IF v_price_cents IS NULL THEN
    RAISE EXCEPTION 'Produit % introuvable ou prix non défini', p_product_id;
  END IF;

  INSERT INTO commerce.transaction_item
    (unit_price_snapshot_cents, transaction_id, product_id, quantity)
  VALUES (v_price_cents, p_transaction_id, p_product_id, p_quantity);

  UPDATE commerce.product_core SET stock = stock - p_quantity WHERE id = p_product_id;
END;
$$;


-- ==============================================================================
-- SECTION 12 : VUES commerce
-- ==============================================================================

-- v_product — schema.org/Product
CREATE VIEW commerce.v_product AS
SELECT
  pc.id                    AS identifier,
  pi.name, pi.slug,
  pi.isbn_ean              AS gtin13,
  pc.price_cents,
  pc.stock,
  pc.is_available,
  pc.media_id              AS image_id,
  pco.description, pco.tags
FROM        commerce.product_core     pc
JOIN        commerce.product_identity pi  ON pi.product_id  = pc.id
LEFT JOIN   commerce.product_content  pco ON pco.product_id = pc.id;


-- v_transaction — schema.org/Order enrichi (ADR-016)
-- PUSHDOWN GARANTI : WHERE identifier = :id → WHERE tc.id = :id avant json_agg().
-- WHERE GUC : miroir de rls_transaction_select (ADR-003 invariant 2 révisé).
--   Miroir : client OU view_transactions OU manage_commerce.
CREATE VIEW commerce.v_transaction AS
SELECT
  -- Core (schema.org/Order)
  tc.id                    AS identifier,
  tc.status                AS order_status,
  tc.created_at,
  tc.modified_at,
  tc.client_entity_id      AS customer_id,
  tc.seller_entity_id      AS seller_id,
  tc.description,
  -- Price component (schema.org/PriceSpecification)
  tp.currency_code,
  tp.shipping_cents,
  tp.discount_cents,
  tp.tax_cents,
  tp.tax_rate_bp,
  tp.is_tax_included,
  -- Payment component (schema.org/PaymentChargeSpecification)
  tpay.payment_status,
  tpay.payment_method,
  tpay.invoice_number,
  tpay.paid_at,
  tpay.billing_place_id,
  -- Delivery component (schema.org/ParcelDelivery)
  tdel.delivery_status,
  tdel.shipping_place_id,
  tdel.carrier,
  tdel.tracking_number,
  tdel.shipped_at,
  tdel.estimated_at,
  tdel.delivered_at,
  -- Items aggregation
  json_agg(json_build_object(
    'product_id',            ti.product_id,
    'product_name',          pi.name,
    'quantity',              ti.quantity,
    'unit_price_cents',      ti.unit_price_snapshot_cents,
    'line_total_cents',      ti.quantity * ti.unit_price_snapshot_cents
  ) ORDER BY ti.product_id) AS ordered_items,
  SUM(ti.quantity * ti.unit_price_snapshot_cents)               AS subtotal_cents,
  SUM(ti.quantity * ti.unit_price_snapshot_cents)
    + COALESCE(tp.shipping_cents, 0)
    + COALESCE(tp.tax_cents,      0)
    - COALESCE(tp.discount_cents, 0)                            AS total_cents
FROM        commerce.transaction_core     tc
JOIN        commerce.transaction_item     ti   ON ti.transaction_id   = tc.id
JOIN        commerce.product_identity     pi   ON pi.product_id       = ti.product_id
LEFT JOIN   commerce.transaction_price    tp   ON tp.transaction_id   = tc.id
LEFT JOIN   commerce.transaction_payment  tpay ON tpay.transaction_id = tc.id
LEFT JOIN   commerce.transaction_delivery tdel ON tdel.transaction_id = tc.id
WHERE (
  tc.client_entity_id = identity.rls_user_id()
  OR (identity.rls_auth_bits() & 131072) = 131072
  OR (identity.rls_auth_bits() & 262144) = 262144
)
GROUP BY
  tc.id, tc.status, tc.created_at, tc.modified_at,
  tc.client_entity_id, tc.seller_entity_id, tc.description,
  tp.currency_code, tp.shipping_cents, tp.discount_cents,
  tp.tax_cents, tp.tax_rate_bp, tp.is_tax_included,
  tpay.payment_status, tpay.payment_method, tpay.invoice_number,
  tpay.paid_at, tpay.billing_place_id,
  tdel.delivery_status, tdel.shipping_place_id, tdel.carrier,
  tdel.tracking_number, tdel.shipped_at, tdel.estimated_at, tdel.delivered_at;
