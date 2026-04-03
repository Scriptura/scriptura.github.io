-- ==============================================================================
-- 07_cross_fk/01_constraints.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : 17 contraintes FK inter-schémas via ALTER TABLE ADD CONSTRAINT
--
-- Toutes les tables source et cible existent physiquement à ce stade
-- (étapes 02 à 06 chargées). Le résultat dans pg_catalog est identique
-- à une déclaration inline dans le CREATE TABLE (pg_constraint ne distingue
-- pas les deux formes).
--
-- Convention de nommage : fk_{table_source}_{colonne}
-- Ordre : identity → org → content → commerce
--   (suit la topologie du DAG pour lisibilité — l'ordre ALTER TABLE est
--    sans contrainte d'exécution à ce stade)
-- ==============================================================================

-- ── IDENTITY → CONTENT ────────────────────────────────────────────────────────
-- Cycle identity.account_core ↔ content.media_core résolu ici.

-- #1 : identity.account_core.media_id → content.media_core
ALTER TABLE identity.account_core
    ADD CONSTRAINT fk_account_core_media
    FOREIGN KEY (media_id) REFERENCES content.media_core(id)
    ON DELETE SET NULL;

-- #5 : identity.person_content.media_id → content.media_core
ALTER TABLE identity.person_content
    ADD CONSTRAINT fk_person_content_media
    FOREIGN KEY (media_id) REFERENCES content.media_core(id)
    ON DELETE SET NULL;


-- ── IDENTITY → GEO ────────────────────────────────────────────────────────────

-- #2 : identity.person_contact.place_id → geo.place_core
ALTER TABLE identity.person_contact
    ADD CONSTRAINT fk_person_contact_place
    FOREIGN KEY (place_id) REFERENCES geo.place_core(id)
    ON DELETE SET NULL;

-- #3 : identity.person_biography.birth_place_id → geo.place_core
ALTER TABLE identity.person_biography
    ADD CONSTRAINT fk_person_biography_birth_place
    FOREIGN KEY (birth_place_id) REFERENCES geo.place_core(id)
    ON DELETE SET NULL;

-- #4 : identity.person_biography.death_place_id → geo.place_core
ALTER TABLE identity.person_biography
    ADD CONSTRAINT fk_person_biography_death_place
    FOREIGN KEY (death_place_id) REFERENCES geo.place_core(id)
    ON DELETE SET NULL;


-- ── ORG → GEO / IDENTITY / CONTENT ───────────────────────────────────────────

-- #6 : org.org_core.place_id → geo.place_core
ALTER TABLE org.org_core
    ADD CONSTRAINT fk_org_core_place
    FOREIGN KEY (place_id) REFERENCES geo.place_core(id)
    ON DELETE SET NULL;

-- #7 : org.org_core.contact_entity_id → identity.entity
ALTER TABLE org.org_core
    ADD CONSTRAINT fk_org_core_contact_entity
    FOREIGN KEY (contact_entity_id) REFERENCES identity.entity(id)
    ON DELETE SET NULL;

-- #8 : org.org_core.media_id → content.media_core
ALTER TABLE org.org_core
    ADD CONSTRAINT fk_org_core_media
    FOREIGN KEY (media_id) REFERENCES content.media_core(id)
    ON DELETE SET NULL;


-- ── CONTENT → IDENTITY ────────────────────────────────────────────────────────
-- Ferme le cycle : content.media_core ← identity.entity
-- (content.media_core ne référence pas identity — c'est identity qui référence content.
--  Mais content.media_core.author_id → identity.entity est ici la FK sortante de content.)

-- #9 : content.media_core.author_id → identity.entity
ALTER TABLE content.media_core
    ADD CONSTRAINT fk_media_core_author
    FOREIGN KEY (author_id) REFERENCES identity.entity(id)
    ON DELETE SET NULL;

-- #10 : content.core.author_entity_id → identity.entity
ALTER TABLE content.core
    ADD CONSTRAINT fk_content_core_author
    FOREIGN KEY (author_entity_id) REFERENCES identity.entity(id)
    ON DELETE SET NULL;

-- #11 : content.revision.author_entity_id → identity.entity
ALTER TABLE content.revision
    ADD CONSTRAINT fk_revision_author
    FOREIGN KEY (author_entity_id) REFERENCES identity.entity(id)
    ON DELETE SET NULL;

-- #12 : content.comment.account_entity_id → identity.entity
ALTER TABLE content.comment
    ADD CONSTRAINT fk_comment_account
    FOREIGN KEY (account_entity_id) REFERENCES identity.entity(id)
    ON DELETE SET NULL;


-- ── COMMERCE → CONTENT / IDENTITY / ORG / GEO ────────────────────────────────

-- #13 : commerce.product_core.media_id → content.media_core
ALTER TABLE commerce.product_core
    ADD CONSTRAINT fk_product_core_media
    FOREIGN KEY (media_id) REFERENCES content.media_core(id)
    ON DELETE SET NULL;

-- #14 : commerce.transaction_core.client_entity_id → identity.entity
-- Pas de ON DELETE : l'intégrité comptable interdit la suppression d'une entité
-- référencée par une transaction (ADR-026). La suppression doit passer par
-- identity.anonymize_person() qui préserve le spine.
ALTER TABLE commerce.transaction_core
    ADD CONSTRAINT fk_transaction_core_client
    FOREIGN KEY (client_entity_id) REFERENCES identity.entity(id);

-- #15 : commerce.transaction_core.seller_entity_id → org.entity
-- Même invariant comptable : pas de ON DELETE.
ALTER TABLE commerce.transaction_core
    ADD CONSTRAINT fk_transaction_core_seller
    FOREIGN KEY (seller_entity_id) REFERENCES org.entity(id);

-- #16 : commerce.transaction_payment.billing_place_id → geo.place_core
ALTER TABLE commerce.transaction_payment
    ADD CONSTRAINT fk_transaction_payment_billing_place
    FOREIGN KEY (billing_place_id) REFERENCES geo.place_core(id)
    ON DELETE SET NULL;

-- #17 : commerce.transaction_delivery.shipping_place_id → geo.place_core
ALTER TABLE commerce.transaction_delivery
    ADD CONSTRAINT fk_transaction_delivery_shipping_place
    FOREIGN KEY (shipping_place_id) REFERENCES geo.place_core(id)
    ON DELETE SET NULL;
