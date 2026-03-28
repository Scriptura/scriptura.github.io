-- ==============================================================================
-- 08_rgpd_audit.sql
-- Tests invariants RGPD et gardes bitwise — Audit 4
-- pgTAP test suite — Projet Marius · PostgreSQL 18 · ECS/DOD
--
-- Couvre :
--   A — Gardes bitwise : create_account (escalade rôle), create_person
--   B — Intégrité anonymize_person : couverture complète des FK PII
--   C — Jointure orpheline : anonymized_at non-NULL → données nominatives purgées
--   D — Préservation intégrité financière : entity physique conservée après anonymisation
--
-- Exécution : psql -U postgres -d marius -f 08_rgpd_audit.sql
-- ==============================================================================

\set ON_ERROR_STOP 1

BEGIN;

SELECT plan(16);


-- ============================================================
-- DONNÉES DE TEST
-- ============================================================

CREATE TEMP TABLE _ids (key TEXT PRIMARY KEY, val INT) ON COMMIT DROP;

-- Compte subscriber (rôle standard)
DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'rgpd_subscriber', '$argon2id$v=19$m=65536$rgpd',
    'rgpd-subscriber', 7, 'fr_FR', v_id
  );
  INSERT INTO _ids VALUES ('sub_id', v_id);
END;
$$;

-- Compte à anonymiser (avec données nominatives complètes)
DO $$
DECLARE v_id INT;
BEGIN
  CALL identity.create_account(
    'rgpd_target', '$argon2id$v=19$m=65536$target',
    'rgpd-target', 7, 'fr_FR', v_id
  );
  INSERT INTO _ids VALUES ('target_id', v_id);
END;
$$;

-- Organisation vendeur (pour la transaction)
DO $$
DECLARE v_id INT;
BEGIN
  CALL org.create_organization('Vendeur RGPD', 'vendeur-rgpd', 'company', NULL, NULL, v_id);
  INSERT INTO _ids VALUES ('org_id', v_id);
END;
$$;

-- Insérer des données nominatives dans person_identity pour la cible
INSERT INTO identity.person_identity (entity_id, given_name, family_name, gender, nationality)
VALUES (
  (SELECT val FROM _ids WHERE key = 'target_id'),
  'Jean', 'Dupont', 1, 250
);

-- Insérer des données de contact
INSERT INTO identity.person_contact (entity_id, email, phone)
VALUES (
  (SELECT val FROM _ids WHERE key = 'target_id'),
  'jean.dupont@example.com', '+33612345678'
);

-- Créer un document dont la cible est auteur
DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_document(
    (SELECT val FROM _ids WHERE key = 'target_id'),
    'Article de Jean Dupont', 'article-jean-dupont',
    0, 1, 'Contenu de larticle', NULL, NULL, v_id
  );
  INSERT INTO _ids VALUES ('doc_id', v_id);
END;
$$;

-- Créer un commentaire de la cible
DO $$
DECLARE v_id INT;
BEGIN
  CALL content.create_comment(
    (SELECT val FROM _ids WHERE key = 'doc_id'),
    (SELECT val FROM _ids WHERE key = 'target_id'),
    'Commentaire de Jean Dupont',
    NULL, 1, v_id
  );
  INSERT INTO _ids VALUES ('cmt_id', v_id);
END;
$$;

-- Créer une transaction financière de la cible
DO $$
DECLARE v_id INT;
BEGIN
  CALL commerce.create_transaction(
    (SELECT val FROM _ids WHERE key = 'target_id'),
    (SELECT val FROM _ids WHERE key = 'org_id'),
    978, 0, NULL, v_id
  );
  INSERT INTO _ids VALUES ('txn_id', v_id);
END;
$$;


-- ============================================================
-- A — GARDES BITWISE (Audit 4)
-- ============================================================

-- A.1 : create_account — un subscriber ne peut pas s'attribuer administrator
SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'sub_id'), true);
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL identity.create_account('hack_admin','$argon2id$v=19$m=65536$h','hack-admin',1,'fr_FR')$$,
  '42501', NULL,
  'create_account : subscriber rejeté pour role_id=1 (administrator) — Audit 4'
);

SELECT throws_ok(
  $$CALL identity.create_account('hack_editor','$argon2id$v=19$m=65536$h','hack-editor',3,'fr_FR')$$,
  '42501', NULL,
  'create_account : subscriber rejeté pour role_id=3 (editor) — Audit 4'
);

RESET ROLE;

-- A.2 : create_account role_id=7 (subscriber) toujours autorisé sans manage_users
SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'sub_id'), true);
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT lives_ok(
  $$
  DO $$inner$$
  DECLARE v INT;
  BEGIN
    CALL identity.create_account('self_reg','$argon2id$v=19$m=65536$s','self-reg',7,'fr_FR',v);
  END;
  $$inner$$
  $$,
  'create_account : subscriber peut créer un compte subscriber (role_id=7) sans manage_users — Audit 4'
);

RESET ROLE;

-- A.3 : create_person — subscriber rejeté
SELECT set_config('marius.user_id',
  (SELECT val::text FROM _ids WHERE key = 'sub_id'), true);
SELECT set_config('marius.auth_bits', '16384', true);
SET LOCAL ROLE marius_user;

SELECT throws_ok(
  $$CALL identity.create_person('Paul','Martin',NULL,NULL)$$,
  '42501', NULL,
  'create_person : subscriber rejeté sans manage_users — Audit 4'
);

RESET ROLE;


-- ============================================================
-- B — INTÉGRITÉ anonymize_person : couverture complète (Audit 4)
-- On anonymise la cible et on vérifie chaque composant.
-- anonymize_person est appelée en contexte postgres (rls_user_id=-1)
-- pour simuler une opération admin légitime.
-- ============================================================

CALL identity.anonymize_person((SELECT val FROM _ids WHERE key = 'target_id'));

-- B.1 : anonymized_at renseigné
SELECT ok(
  (SELECT anonymized_at FROM identity.entity
   WHERE id = (SELECT val FROM _ids WHERE key = 'target_id')) IS NOT NULL,
  'anonymize_person : anonymized_at renseigné sur identity.entity'
);

-- B.2 : person_identity purgée
SELECT ok(
  (SELECT given_name IS NULL AND family_name IS NULL AND nationality IS NULL
   FROM   identity.person_identity
   WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'target_id')),
  'anonymize_person : person_identity — given_name/family_name/nationality = NULL'
);

-- B.3 : person_contact purgée
SELECT ok(
  (SELECT email IS NULL AND phone IS NULL
   FROM   identity.person_contact
   WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'target_id')),
  'anonymize_person : person_contact — email/phone = NULL'
);

-- B.4 : account_core neutralisée (username non-nominatif)
SELECT ok(
  (SELECT username LIKE 'user_%'
   FROM   identity.account_core
   WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'target_id')),
  'anonymize_person : account_core — username neutralisé (user_<id>)'
);

-- B.5 : auth invalidée
SELECT ok(
  (SELECT password_hash = 'ANONYMIZED' AND is_banned = true
   FROM   identity.auth
   WHERE  entity_id = (SELECT val FROM _ids WHERE key = 'target_id')),
  'anonymize_person : auth — password_hash=ANONYMIZED, is_banned=true'
);

-- B.6 (Audit 4 gap) : content.core.author_entity_id = NULL
SELECT ok(
  (SELECT author_entity_id IS NULL
   FROM   content.core
   WHERE  document_id = (SELECT val FROM _ids WHERE key = 'doc_id')),
  'anonymize_person : content.core.author_entity_id = NULL (Audit 4 — ADR-017 gap corrigé)'
);

-- B.7 (Audit 4 gap) : content.comment.account_entity_id = NULL
SELECT ok(
  (SELECT account_entity_id IS NULL
   FROM   content.comment
   WHERE  id = (SELECT val FROM _ids WHERE key = 'cmt_id')),
  'anonymize_person : content.comment.account_entity_id = NULL (Audit 4 — ADR-017 gap corrigé)'
);

-- B.8 (Audit 4 gap) : content.revision.author_entity_id = NULL
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM content.revision
    WHERE  document_id    = (SELECT val FROM _ids WHERE key = 'doc_id')
      AND  author_entity_id IS NOT NULL
  ),
  'anonymize_person : content.revision.author_entity_id = NULL (Audit 4 — ADR-017 gap corrigé)'
);


-- ============================================================
-- C — JOINTURE ORPHELINE : anonymized_at non-NULL → pas de PII résiduelle
--
-- Ce test généralise l'audit B à l'ensemble du schéma.
-- Pour toute entité marquée anonymized_at IS NOT NULL, aucune donnée
-- nominative directe (nom, email, téléphone) ne doit subsister.
-- ============================================================

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   identity.entity        e
    JOIN   identity.person_identity pi ON pi.entity_id = e.id
    WHERE  e.anonymized_at IS NOT NULL
      AND  (pi.given_name IS NOT NULL OR pi.family_name IS NOT NULL)
  ),
  'Jointure orpheline : aucune entité anonymisée avec given_name/family_name résiduel'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   identity.entity       e
    JOIN   identity.person_contact pc ON pc.entity_id = e.id
    WHERE  e.anonymized_at IS NOT NULL
      AND  (pc.email IS NOT NULL OR pc.phone IS NOT NULL)
  ),
  'Jointure orpheline : aucune entité anonymisée avec email/phone résiduel'
);


-- ============================================================
-- D — PRÉSERVATION DE L'INTÉGRITÉ FINANCIÈRE (ADR-017)
--
-- L'entité physique (spine) doit subsister après anonymisation.
-- La FK commerce.transaction_core.client_entity_id n'a pas ON DELETE CASCADE :
-- l'historique financier reste intact et traçable via l'entity_id.
-- ============================================================

SELECT ok(
  EXISTS (
    SELECT 1 FROM identity.entity
    WHERE  id            = (SELECT val FROM _ids WHERE key = 'target_id')
      AND  anonymized_at IS NOT NULL
  ),
  'Intégrité financière : identity.entity conservée après anonymisation (spine préservé)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM commerce.transaction_core
    WHERE  client_entity_id = (SELECT val FROM _ids WHERE key = 'target_id')
  ),
  'Intégrité financière : transaction_core.client_entity_id intact après anonymisation (ADR-017)'
);


SELECT * FROM finish();
ROLLBACK;
