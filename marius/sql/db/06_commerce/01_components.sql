-- ==============================================================================
-- 06_commerce/01_components.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : composants du domaine commerce
--
-- FK cross-schéma RETIRÉES (→ 07_cross_fk/01_constraints.sql) :
--   commerce.product_core.media_id           → content.media_core(id)   ON DELETE SET NULL
--   commerce.transaction_core.client_entity_id → identity.entity(id)    [pas de ON DELETE]
--   commerce.transaction_core.seller_entity_id → org.entity(id)         [pas de ON DELETE]
--   commerce.transaction_payment.billing_place_id  → geo.place_core(id) ON DELETE SET NULL
--   commerce.transaction_delivery.shipping_place_id → geo.place_core(id) ON DELETE SET NULL
--
-- FK intra-domaine conservées inline :
--   product_identity.product_id  → product_core(id)      CASCADE
--   product_content.product_id   → product_core(id)      CASCADE
--   transaction_price.transaction_id    → transaction_core(id)  CASCADE
--   transaction_payment.transaction_id  → transaction_core(id)  CASCADE
--   transaction_delivery.transaction_id → transaction_core(id)  CASCADE
--   transaction_item.transaction_id     → transaction_core(id)  CASCADE
--   transaction_item.product_id         → product_core(id)      [sans ON DELETE]
-- ==============================================================================

-- ==============================================================================
-- SECTION 7 : COMPOSANTS COMMERCE
-- ==============================================================================

-- PRODUCT CORE — prix et stock (HAUTE fréquence) · fillfactor=80 pour HOT updates
-- Layout (ADR-006 + ADR-026) :
--   price_cents INT8 (offset 0, 8B) · id INT4 (8) · stock INT4 (12) · media_id INT4 (16)
--   · is_available BOOL (20, 1B) · 3B pad (21-23)
-- HOT path : UPDATE stock → non indexé → HOT-eligible.
-- FK cross-schéma RETIRÉE :
--   media_id → content.media_core(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE commerce.product_core (
  price_cents   INT8     NULL                  CHECK (price_cents >= 0),
  id            INT      GENERATED ALWAYS AS IDENTITY,
  stock         INT      NOT NULL DEFAULT 0    CHECK (stock >= 0),
  media_id      INT      NULL,
  is_available  BOOLEAN  NOT NULL DEFAULT true,
  PRIMARY KEY (id)
  -- FOREIGN KEY (media_id) REFERENCES content.media_core(id) ON DELETE SET NULL → 07_cross_fk
) WITH (fillfactor = 80);

-- Catalogue publié : partial index sur produits disponibles.
CREATE INDEX product_core_catalog ON commerce.product_core (price_cents)
  WHERE is_available = true;


-- PRODUCT IDENTITY — noms et référencement
CREATE TABLE commerce.product_identity (
  product_id  INT           NOT NULL,
  name        VARCHAR(64)   NOT NULL,
  slug        VARCHAR(64)   NOT NULL,
  isbn_ean    VARCHAR(13)   NULL,
  PRIMARY KEY (product_id),
  UNIQUE (slug),
  UNIQUE (isbn_ean),
  FOREIGN KEY (product_id) REFERENCES commerce.product_core(id) ON DELETE CASCADE,
  CONSTRAINT isbn_ean_format CHECK (isbn_ean IS NULL OR isbn_ean ~ '^[0-9]{13}$'),
  CONSTRAINT slug_format     CHECK (slug ~ '^[a-z0-9-]+$')
);


-- PRODUCT CONTENT — TOAST systématique
CREATE TABLE commerce.product_content (
  product_id   INT           NOT NULL,
  description  TEXT          NULL,
  tags         VARCHAR(255)  NULL,
  PRIMARY KEY (product_id),
  FOREIGN KEY (product_id) REFERENCES commerce.product_core(id) ON DELETE CASCADE
) WITH (toast_tuple_target = 128);


-- TRANSACTION CORE — spine de commande (ADR-016)
-- Layout (ADR-006) :
--   2×TIMESTAMPTZ (offset 0, 16B) · id INT4 (16) · client_entity_id INT4 (20)
--   · seller_entity_id INT4 (24) · status SMALLINT (28) · 2×BOOL (30-31) | TEXT
-- FK cross-schéma RETIRÉES :
--   client_entity_id → identity.entity(id) (→ 07_cross_fk)
--   seller_entity_id → org.entity(id)      (→ 07_cross_fk)
CREATE TABLE commerce.transaction_core (
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  modified_at         TIMESTAMPTZ   NULL,
  id                  INT           GENERATED ALWAYS AS IDENTITY,
  client_entity_id    INT           NOT NULL,
  seller_entity_id    INT           NOT NULL,
  status              SMALLINT      NOT NULL DEFAULT 0,
  is_gift             BOOLEAN       NOT NULL DEFAULT false,
  is_recurring        BOOLEAN       NOT NULL DEFAULT false,
  description         TEXT          NULL,
  PRIMARY KEY (id),
  -- FOREIGN KEY (client_entity_id)  REFERENCES identity.entity(id) → 07_cross_fk
  -- FOREIGN KEY (seller_entity_id)  REFERENCES org.entity(id)      → 07_cross_fk
  CONSTRAINT status_range CHECK (status IN (0, 1, 2, 3, 9))
);

CREATE INDEX transaction_core_pending ON commerce.transaction_core (client_entity_id, created_at DESC)
  WHERE status = 0;
CREATE INDEX transaction_created_brin ON commerce.transaction_core USING brin (created_at)
  WITH (pages_per_range = 128);


-- TRANSACTION PRICE — PriceSpecification (ADR-016)
-- Layout (ADR-006 + ADR-026) :
--   3×INT8 (offset 0, 24B) · transaction_id INT4 (24) · tax_rate_bp INT4 (28)
--   · currency_code SMALLINT (32) · is_tax_included BOOL (34) · 1B pad (35)
CREATE TABLE commerce.transaction_price (
  shipping_cents   INT8      NOT NULL DEFAULT 0  CHECK (shipping_cents  >= 0),
  discount_cents   INT8      NOT NULL DEFAULT 0  CHECK (discount_cents  >= 0),
  tax_cents        INT8      NOT NULL DEFAULT 0  CHECK (tax_cents       >= 0),
  transaction_id   INT       NOT NULL,
  tax_rate_bp      INT4      NOT NULL DEFAULT 0  CHECK (tax_rate_bp     >= 0),
  currency_code    SMALLINT  NOT NULL DEFAULT 978,
  is_tax_included  BOOLEAN   NOT NULL DEFAULT false,
  PRIMARY KEY (transaction_id),
  FOREIGN KEY (transaction_id) REFERENCES commerce.transaction_core(id) ON DELETE CASCADE,
  CONSTRAINT currency_code_range CHECK (currency_code BETWEEN 1 AND 999)
);


-- TRANSACTION PAYMENT — PaymentChargeSpecification (ADR-016)
-- Layout (ADR-006) :
--   paid_at TIMESTAMPTZ (offset 0, 8B) · transaction_id INT4 (8)
--   · billing_place_id INT4 (12) · payment_status SMALLINT (16) · 2B pad (18) | varlena
-- FK cross-schéma RETIRÉE :
--   billing_place_id → geo.place_core(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE commerce.transaction_payment (
  paid_at             TIMESTAMPTZ   NULL,
  transaction_id      INT           NOT NULL,
  billing_place_id    INT           NULL,
  payment_status      SMALLINT      NOT NULL DEFAULT 0,
  invoice_number      VARCHAR(64)   NULL,
  payment_method      VARCHAR(32)   NULL,
  provider_reference  VARCHAR(255)  NULL,
  PRIMARY KEY (transaction_id),
  UNIQUE (invoice_number),
  FOREIGN KEY (transaction_id) REFERENCES commerce.transaction_core(id) ON DELETE CASCADE,
  -- FOREIGN KEY (billing_place_id) REFERENCES geo.place_core(id) ON DELETE SET NULL → 07_cross_fk
  CONSTRAINT payment_status_range CHECK (payment_status IN (0, 1, 2, 3, 9))
);


-- TRANSACTION DELIVERY — ParcelDelivery (ADR-016)
-- Layout (ADR-006) :
--   3×TIMESTAMPTZ (offset 0, 24B) · transaction_id INT4 (24)
--   · shipping_place_id INT4 (28) · delivery_status SMALLINT (32) · 2B pad (34) | varlena
-- FK cross-schéma RETIRÉE :
--   shipping_place_id → geo.place_core(id) ON DELETE SET NULL (→ 07_cross_fk)
CREATE TABLE commerce.transaction_delivery (
  shipped_at          TIMESTAMPTZ   NULL,
  estimated_at        TIMESTAMPTZ   NULL,
  delivered_at        TIMESTAMPTZ   NULL,
  transaction_id      INT           NOT NULL,
  shipping_place_id   INT           NULL,
  delivery_status     SMALLINT      NOT NULL DEFAULT 0,
  carrier             VARCHAR(64)   NULL,
  tracking_number     VARCHAR(255)  NULL,
  PRIMARY KEY (transaction_id),
  FOREIGN KEY (transaction_id)    REFERENCES commerce.transaction_core(id) ON DELETE CASCADE,
  -- FOREIGN KEY (shipping_place_id) REFERENCES geo.place_core(id) ON DELETE SET NULL → 07_cross_fk
  CONSTRAINT delivery_status_range CHECK (delivery_status IN (0, 1, 2, 3, 4, 9))
);


-- TRANSACTION ITEM — résolution 1NF · snapshot prix immuable (ADR-026 + ADR-030)
-- Layout (ADR-006) :
--   unit_price_snapshot_cents INT8 (offset 0, 8B) · transaction_id INT4 (8)
--   · product_id INT4 (12) · quantity INT4 (16)
-- Tuple 48 B → ~170 tuples/page
-- unit_price_snapshot_cents : immuable après INSERT (trigger dans 02_systems.sql).
CREATE TABLE commerce.transaction_item (
  unit_price_snapshot_cents  INT8  NOT NULL  CHECK (unit_price_snapshot_cents >= 0),
  transaction_id             INT   NOT NULL,
  product_id                 INT   NOT NULL,
  quantity                   INT   NOT NULL DEFAULT 1  CHECK (quantity > 0),
  PRIMARY KEY (transaction_id, product_id),
  FOREIGN KEY (transaction_id) REFERENCES commerce.transaction_core(id) ON UPDATE CASCADE ON DELETE CASCADE,
  FOREIGN KEY (product_id)     REFERENCES commerce.product_core(id)
);

CREATE INDEX transaction_item_product ON commerce.transaction_item (product_id);
