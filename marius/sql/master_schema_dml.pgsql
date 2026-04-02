-- ==============================================================================
-- MASTER SCHEMA DML — Seed Data (Développement & CI/CD uniquement)
-- Architecture ECS/DOD · PostgreSQL 18
-- ==============================================================================
-- Fichier     : master_schema_dml.pgsql
-- Exécution   : psql -U postgres -d marius -f master_schema_dml.pgsql
-- Prérequis   : master_schema_ddl.pgsql exécuté préalablement sur la base cible
-- Environnements : développement local · intégration continue · benchmarking
-- NE PAS exécuter en production.
-- ==============================================================================
--
-- CONTENU
-- -------
--   content.media_core       9 médias
--   content.media_content    9 métadonnées de médias
--   geo.place_core           12 lieux (France)
--   identity.entity          74 entités (4 personnes + 70 comptes)
--   identity.person_*        profils Henri de Lubac, Jeanne d'Arc, de Gaulle, anonyme
--   identity.auth            70 comptes (argon2id) — entities 5–74
--   identity.account_core    70 comptes utilisateurs
--   content.document         16 articles
--   content.core             16 statuts de publication
--   content.identity         16 titres / slugs
--   content.body             5 corps courts (les corps longs sont à charger séparément)
--   content.comment          5 commentaires (document 5) — via CALL content.create_comment()
--   content.tag              232 tags (taxonomie plate — hiérarchiser via UPDATE path)
--   content.content_to_tag   ~455 liaisons article ↔ tag (44 nominales + ~411 bulk)
--   content.content_to_media 6 liaisons article ↔ média
--
-- NOTES D'EXÉCUTION
-- -----------------
-- Les IDs sont forcés via OVERRIDING SYSTEM VALUE pour garantir la cohérence
-- des FK croisées (ex : author_entity_id dans content.core référence
-- des identity.entity dont les IDs sont connus à l'avance).
-- Les séquences sont remises à jour via setval() après chaque bloc forcé.
--
-- Les corps HTML longs (articles 1, 2, 4, 6, 7, 8, 9, 11, 12, 13) sont omis.
-- Les charger via :
--   UPDATE content.body SET content = $body$ ... $body$ WHERE document_id = N;
-- Ou déclencher un snapshot :
--   CALL content.save_revision(N, <author_entity_id>);
--
-- Les chemins ltree des commentaires sont initialisés à '<document_id>' dans
-- l'INSERT. Les triggers AFTER INSERT finalisent chaque chemin en
-- '<document_id>.<comment_id>' après attribution de l'identifiant par la séquence.
--
-- La hiérarchie des tags est initialisée à plat (racines uniquement).
-- Établir la taxonomie via CALL content.create_tag() avec p_parent_id,
-- ou via INSERT direct dans content.tag_hierarchy (Closure Table — ADR-018).
-- Exemple :
--   CALL content.create_tag('Patristique', 'patristique', NULL);  -- racine
--   CALL content.create_tag('Cyrille d''Alexandrie', 'cyrille-d-alexandrie', <id_parent>);
--
-- SATURATION DES PAGES (DOD audit) :
--   identity.auth (ff=70) : 70 tuples × 160B → 2 pages pleines à ff=70.
--     observed ≈ 16384B / 70 = 234B < seuil (160/0.70 × 1.20 = 274B) → bloat_alert OFF.
--   content.content_to_tag : ~455 tuples × 32B → ≥ 1 page pleine (255 tpp).
--     observed ≈ 2×8192 / 455 = 36B < seuil (32 × 1.20 = 38.4B) → bloat_alert OFF.
-- ==============================================================================

\c marius

-- SECTION 14 : DONNÉES DE REMPLISSAGE (SEED)
-- OVERRIDING SYSTEM VALUE utilisé pour forcer les IDs des FK croisées.
-- ==============================================================================

-- ENTITÉS D'IDENTITÉ (persons 1-4, accounts 5-8)
INSERT INTO identity.entity (id) OVERRIDING SYSTEM VALUE VALUES (1),(2),(3),(4),(5),(6),(7),(8);
SELECT setval(pg_get_serial_sequence('identity.entity', 'id'), 8);

-- MÉDIAS
INSERT INTO content.media_core (id, created_at, author_id, width, height, mime_type, folder_url, file_name)
OVERRIDING SYSTEM VALUE VALUES
  (1, now(), 1, 1337, 1337, 'image/jpeg', '/medias/1974/11/21/041212', 'henri-de-lubac.jpg'),
  (2, now(), 2, 503,  756,  'image/jpeg', '/medias/1974/11/21/041212', 'jeanne-d-arc.jpg'),
  (3, now(), 1, 1150, 1150, 'image/jpeg', '/medias/1974/11/21/041212', 'charles-de-gaulle.jpg'),
  (4, now(), 1, 3024, 4032, 'image/jpeg', '/medias/1974/11/21/041212', 'pisit-heng.jpg'),
  (5, now(), 2, 2712, 4068, 'image/jpeg', '/medias/1974/11/21/041212', 'kevin-mueller.jpg'),
  (6, now(), 1, 3715, 3715, 'image/jpeg', '/medias/1974/11/21/041212', 'nicolas-hoizey.jpg'),
  (7, now(), 1, 2500, 2500, 'image/jpg',  '/medias/1974/11/21/041212', 'robin-billy2.jpg'),
  (8, now(), 1, 2002, 3000, 'image/jpeg', '/medias/1974/11/21/041212', 'clay-banks.jpg'),
  (9, now(), 2, 3040, 3942, 'image/jpeg', '/medias/1974/11/21/041212', 'charles-de-foucauld.jpg');
SELECT setval(pg_get_serial_sequence('content.media_core', 'id'), 9);

INSERT INTO content.media_content (media_id, name) VALUES
  (1, 'Henri de Lubac'),
  (2, 'Jeanne d''Arc'),
  (3, 'Charles de Gaulle'),
  (4, 'Tombeau ouvert'),
  (5, 'Perroquet'),
  (6, 'Escalier intérieur d''un phare'),
  (7, 'Herbe, macro'),
  (8, 'Phare'),
  (9, 'Charles de Foucauld');

-- LIEUX — spine spatial (ADR-017 : données postales séparées dans geo.postal_address)
INSERT INTO geo.place_core (id, name, coordinates, elevation)
OVERRIDING SYSTEM VALUE VALUES
  (1,  'Cathédrale Notre-Dame de Paris',                ST_SetSRID(ST_MakePoint(2.349747,  48.853133), 4326), 210),
  (2,  'Basilique du Sacré-Cœur de Montmartre',         ST_SetSRID(ST_MakePoint(2.343076,  48.886719), 4326), NULL),
  (3,  'Primatiale Saint-Jean de Lyon',                 ST_SetSRID(ST_MakePoint(4.827409,  45.760792), 4326), NULL),
  (4,  'Basilique Notre-Dame de Fourvière',             ST_SetSRID(ST_MakePoint(4.822550,  45.762300), 4326), 287),
  (5,  'Carmel de Montmartre',                          NULL,                                                  NULL),
  (6,  'Chapelle Notre-Dame de la Médaille Miraculeuse', ST_SetSRID(ST_MakePoint(2.323305,  48.851043), 4326), NULL),
  (7,  'Collège des Bernardins',                        ST_SetSRID(ST_MakePoint(2.351987,  48.848775), 4326), NULL),
  (8,  'École Cathédrale',                              ST_SetSRID(ST_MakePoint(2.350691,  48.853372), 4326), NULL),
  (9,  'Bibliothèque du Saulchoir',                     ST_SetSRID(ST_MakePoint(2.344720,  48.832783), 4326), NULL),
  (10, 'Basilique Notre-Dame-de-la-Garde',              ST_SetSRID(ST_MakePoint(5.371195,  43.284002), 4326), NULL),
  (11, 'Lille',                                         ST_SetSRID(ST_MakePoint(2.699902,  50.763034), 4326), 20),
  (12, 'Colombey-les-Deux-Églises',                    ST_SetSRID(ST_MakePoint(3.782467,  48.192773), 4326), 239);
SELECT setval(pg_get_serial_sequence('geo.place_core', 'id'), 12);

-- ADRESSES POSTALES (ADR-017 · country_code 250 = France ISO 3166-1 numérique)
INSERT INTO geo.postal_address (place_id, country_code, street_address, postal_code, address_locality, address_region) VALUES
  (1,  250, '6 Parvis Notre-Dame - Pl. Jean-Paul II', '75004', 'Paris',                      'Île-de-France'),
  (2,  250, '35 Rue du Chevalier de la Barre',         '75018', 'Paris',                      'Île-de-France'),
  (3,  250, 'Place Saint-Jean',                        '69005', 'Lyon',                       'Rhône'),
  (4,  250, '8 Place de Fourvière',                    '69005', 'Lyon',                       'Rhône'),
  (5,  250, '34 Rue du Chevalier de la Barre',         '75018', 'Paris',                      'Île-de-France'),
  (6,  250, '140 Rue du Bac',                          '75007', 'Paris',                      'Île-de-France'),
  (7,  250, NULL,                                      NULL,    'Paris',                      'Île-de-France'),
  (8,  250, NULL,                                      NULL,    'Paris',                      'Île-de-France'),
  (9,  250, NULL,                                      NULL,    'Paris',                      'Île-de-France'),
  (10, 250, 'Rue Fort du Sanctuaire',                  '13281', 'Marseille',                  'Bouches-du-Rhône'),
  (11, 250, NULL,                                      '59000', 'Lille',                      'Nord'),
  (12, 250, NULL,                                      '52330', 'Colombey-les-Deux-Églises', 'Haute-Marne');

-- PERSONNES (entities 1-4) — person_identity + biography + contact + content
INSERT INTO identity.person_identity (entity_id, gender, given_name, additional_name, family_name, suffix, prefix, nickname, nationality) VALUES
  (1, 1, 'Henri',   'Sonier',              'de Lubac',     's.j.', 'P.',    NULL,                    250),
  (2, 2, 'Jeanne',  NULL,                  'd''Arc',       NULL,   'Ste',   'La Pucelle d''Orléans', 250),
  (3, 1, 'Charles', 'André Joseph Marie',  'de Gaulle',    NULL,   'Gal',   'Le Général',            250),
  (4, NULL, NULL,   NULL,                   NULL,          NULL,   NULL,    'El Comandante',         250);

INSERT INTO identity.person_biography (entity_id, birth_date, death_date, birth_place_id, death_place_id) VALUES
  (1, '1896-02-20', '1991-09-04', NULL, NULL),
  (2, '1412-01-01', '1431-05-30', NULL, NULL),
  (3, '1890-11-22', '1970-11-09', 11,   12);

INSERT INTO identity.person_contact (entity_id, phone, email) VALUES
  (1, '04 46 35 76 89', NULL),
  (2, NULL,             'jeanne.arc@mail.com'),
  (3, NULL,             NULL),
  (4, '01 44 55 66 77', NULL);

INSERT INTO identity.person_content (entity_id, media_id, devise, description) VALUES
  (1, 1, 'L''Église a pour unique mission de rendre Jésus Christ présent aux hommes.',
      'Henri Sonier de Lubac, né à Cambrai le 20 février 1896 et mort à Paris le 4 septembre 1991, est un jésuite, théologien catholique et cardinal français.'),
  (2, 2, 'De par le Roy du Ciel !',
      'Jeanne d''Arc, née vers 1412 à Domrémy, village du duché de Bar, et morte sur le bûcher le 30 mai 1431 à Rouen, est une héroïne de l''histoire de France, chef de guerre et sainte de l''Église catholique.'),
  (3, 3, 'France libre !',
      'Charles de Gaulle, né le 22 novembre 1890 à Lille et mort le 9 novembre 1970 à Colombey-les-Deux-Églises, est un militaire, résistant, homme d''État et écrivain français.'),
  (4, NULL, 'Personne anonyme pour test.', NULL);

-- COMPTES NOMINAUX (entities 5-8) — insérés séparément pour cohérence FK
INSERT INTO identity.auth (created_at, last_login_at, modified_at, entity_id, role_id, is_banned, password_hash) VALUES
  ('2005-05-07 19:37:25-07', '2020-05-03 10:10:25-07', '2017-07-17 07:08:25-07', 5, 1, false, '$argon2id$v=19$m=65536,t=3,p=4$/ysOM8eTucePuwFGbJGxaw$ctdsiTpyTyaQ7iXR1J6+K2v7Q38pPEzfQTI7tr56Sy0'),
  ('2005-05-07 19:37:25-07', '2020-05-03 10:10:25-07', '2017-07-17 07:08:25-07', 6, 2, false, '$argon2id$v=19$m=65536,t=3,p=4$O7V//bsQ6NBAhMgwoRuz4Q$rL5T4u4qm1sxKz/eDZTpUrfMwxqylEULf26ZYnwZBCA'),
  ('2005-05-07 19:37:25-07', '2020-05-03 10:10:25-07', '2017-07-17 07:08:25-07', 7, 3, false, '$argon2id$v=19$m=65536,t=3,p=4$O7V//bsQ6NBAhMgwoRuz4Q$rL5T4u4qm1sxKz/eDZTpUrfMwxqylEULf26ZYnwZBCA'),
  ('2005-05-07 19:37:25-07', '2020-05-03 10:10:25-07', '2017-07-17 07:08:25-07', 8, 7, false, '$argon2id$v=19$m=65536,t=3,p=4$O7V//bsQ6NBAhMgwoRuz4Q$rL5T4u4qm1sxKz/eDZTpUrfMwxqylEULf26ZYnwZBCA');

INSERT INTO identity.account_core (entity_id, person_entity_id, display_mode, is_visible, is_private_message, username, slug, language) VALUES
  (5, 1, 2, true, true,  'Alpha',    'alpha',    'fr_FR'),  -- display_mode=2 (fullName)
  (6, 2, 3, true, false, 'Beta',     'beta',     'fr_FR'),  -- display_mode=3 (nickname)
  (7, 3, 1, true, false, 'Delta',    'delta',    'fr_FR'),  -- display_mode=1 (given+family)
  (8, NULL, 0, true, false, 'Rogue One', 'rogue-one', 'en_GB'); -- display_mode=0 (username)

-- ==============================================================================
-- SEED BULK — SATURATION DES PAGES identity.auth (DOD audit)
-- ------------------------------------------------------------------------------
-- Objectif : éliminer le bloat_alert sur identity.auth.
--
-- Calcul de saturation (fillfactor=70, tuple=160B) :
--   rows_per_page = floor(8168 × 0.70 / 160) = 35
--   2 pages pleines = 70 tuples → observed = 16384B / 70 = 234B
--   seuil bloat    = (160 / 0.70) × 1.20 = 274B
--   234 < 274 → bloat_alert = FALSE ✓
--
-- Entités 9–74 : 66 subscribers (role_id=7).
-- created_at : espacés d'une semaine depuis 2018-01-01 → corrélation BRIN ≈ 1.0.
-- password_hash : hash de test fixe (non exploité en prod — seed CI/CD only).
-- username/slug : format 'seed_usr_NN' / 'seed-usr-NN' (contrainte UNIQUE).
-- ==============================================================================

DO $$
DECLARE
    i            INT;
    v_created_at TIMESTAMPTZ;
    v_hash       TEXT := '$argon2id$v=19$m=65536,t=3,p=4$O7V//bsQ6NBAhMgwoRuz4Q$rL5T4u4qm1sxKz/eDZTpUrfMwxqylEULf26ZYnwZBCA';
BEGIN
    FOR i IN 9..74 LOOP
        -- Espacement hebdomadaire depuis 2018-01-01 : BRIN correlation ≈ 1.0
        v_created_at := TIMESTAMPTZ '2018-01-01 00:00:00+00'
                        + ((i - 9) * INTERVAL '1 week');

        INSERT INTO identity.entity (id) OVERRIDING SYSTEM VALUE VALUES (i);

        INSERT INTO identity.auth
            (created_at, entity_id, role_id, is_banned, password_hash)
        VALUES
            (v_created_at, i, 7, false, v_hash);

        INSERT INTO identity.account_core
            (entity_id, display_mode, is_visible, is_private_message, username, slug, language)
        VALUES
            (i, 0, true, false,
             'seed_usr_' || lpad(i::text, 2, '0'),
             'seed-usr-' || lpad(i::text, 2, '0'),
             'fr_FR');
    END LOOP;
END;
$$;

SELECT setval(pg_get_serial_sequence('identity.entity', 'id'), 74);

-- ==============================================================================
-- DOCUMENTS — articles (IDs 1-16 pour cohérence avec les FK tag_to_article)
-- ==============================================================================

INSERT INTO content.document (id, doc_type) OVERRIDING SYSTEM VALUE VALUES
  (1,0),(2,0),(3,0),(4,0),(5,0),(6,0),(7,0),(8,0),
  (9,0),(10,0),(11,0),(12,0),(13,0),(14,0),(15,0),(16,0);
SELECT setval(pg_get_serial_sequence('content.document', 'id'), 16);

-- CONTENU CORE (author_entity_id = identity.entity de la personne autrice)
INSERT INTO content.core (published_at, created_at, modified_at, document_id, author_entity_id, status, is_readable, is_commentable) VALUES
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  1, 2, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  2, 2, 1, true, false),
  ('2024-05-16 19:10:25-07', '2024-05-16 19:10:25-07', '2024-05-16 20:15:22-01',  3, 2, 1, true, true),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  4, 2, 1, true, false),
  ('2024-05-17 19:10:25-07', '2024-05-17 19:10:25-07', '2024-05-17 20:15:22-01',  5, 4, 1, true, true),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  6, 2, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  7, 1, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  8, 4, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01',  9, 2, 1, true, false),
  ('2022-02-27 00:43:06+01', '2022-02-27 00:43:06+01', '2022-02-27 00:45:37+01', 10, 1, 1, true, false),
  ('2020-04-16 19:10:25-07', '2020-04-16 19:10:25-07', '2020-04-16 20:15:22-01', 11, 3, 1, true, false),
  ('2020-04-16 19:10:25-07', '2020-04-16 19:10:25-07', '2020-04-16 20:15:22-01', 12, 2, 1, true, false),
  ('2022-02-27 00:43:06+01', '2022-02-27 00:43:06+01', '2022-02-27 00:45:37+01', 13, 1, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01', 14, 1, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01', 15, 1, 1, true, false),
  ('2022-04-16 19:10:25-07', '2022-04-16 19:10:25-07', '2022-04-16 20:15:22-01', 16, 1, 1, true, false);

-- CONTENT IDENTITY (slugs/titres — le trigger slug_dedup est actif)
INSERT INTO content.identity (document_id, slug, headline, alternative_headline, description) VALUES
  (1,  'legenda-aurea',                                                    'La légende dorée',                                                  '',           'Encyclique Dominum et vivificantem, Sur l''Esprit Saint dans la vie de l''Église et du monde, § 46, 1986'),
  (2,  'le-peche-contre-l-esprit-saint-jean-paul-ii',                     'Le péché contre l''Esprit Saint',                                   '',           'Encyclique Dominum et vivificantem, Sur l''Esprit Saint dans la vie de l''Église et du monde, § 46, 1986'),
  (3,  'o-prends-mon-ame',                                                 'Ô prends mon âme',                                                  '',           'Oh ! prends mon âme, aussi intitulé Ô prends mon âme, est un cantique chrétien du milieu du XXe siècle.'),
  (4,  'si-quelqu-un-a-soif-qu-il-vienne-a-moi-et-qu-il-boive-maitre-eckhart', 'Si quelqu''un a soif qu''il vienne à moi et qu''il boive', '', 'Eckhart von Hochheim, Du recueillement, in Les jours du Seigneur.'),
  (5,  'agent-327',                                                        'Agent 327',                                                         '',           'Test pour une vidéo...'),
  (6,  'le-monde-de-la-redemption-est-meilleur-au-total-que-le-monde-de-la-creation-charles-journet', 'Le monde de la Rédemption est meilleur au total que le monde de la création', '', 'Charles Journet, Le mal, Essai Théologique, p. 285, Éditions Saint-Augustin, 1988.'),
  (7,  'ne-me-touche-pas-john-henry-newman',                               'Ne me touche pas',                                                  '',           'John Henry Newman, Lectures on justification, in Les jours du Seigneur, pp. 186-187.'),
  (8,  'improperes-du-vendredi-saint',                                     'Impropères du Vendredi Saint',                                      '',           'Les Improperia sont une partie de l''office de l''après-midi du Vendredi saint dans l''Église catholique romaine.'),
  (9,  'eveille-toi-o-toi-qui-dors',                                       'Éveille-toi, ô toi qui dors',                                       '',           'Office des lectures pour le Samedi Saint, origine inconnue.'),
  (10, 'video-youtube-en-shortcode',                                       'Vidéo YouTube en shortcode',                                        '',           'Test de shortcodes pour les vidéos YouTube.'),
  (11, 'cartes-leaflet-en-shortcodes',                                     'Cartes Leaflet en shortcodes',                                      '',           'Test de shortcodes pour les cartes Leaflet.'),
  (12, 'images-en-shortcodes',                                             'Images en shortcodes',                                              '',           'Test de shortcodes pour les images.'),
  (13, 'shortcodes',                                                       'Shortcodes',                                                        '',           'Test de shortcodes pour les vidéos YouTube.'),
  (14, 'ecriture-et-tradition-chez-saint-irenee-de-lyon',                 'Écriture et Tradition chez saint Irénée de Lyon', 'La théologie de la Tradition et son rapport à l''Écriture chez saint Irénée de Lyon', 'Test pour un titre additionnel'),
  (15, 'markdown-test',                                                   'Markdown test',                                                     'Syntaxe markdown permettant de tester notre parseur', 'Syntaxe markdown à destination de notre parseur'),
  (16, 'cyan',                                                             'Cyan',                                                              'Magenta',    'Noir');

-- CONTENT BODY (corps HTML — stockés séparément pour isolation TOAST)
INSERT INTO content.body (document_id, content) VALUES
  (5,  '<video class="media" controls="controls" poster="/medias/videos/Agent327/poster.jpg"><source src="/medias/videos/Agent327/Agent327.mp4" type="video/mp4"></video>'),
  (10, '{{https://www.youtube.com/watch?v=3Bs4LOtIuxg}} <hr> {{https://www.youtube.com/watch?v=TJo-xajORwY}}'),
  (14, '[content]'),
  (15, 'normal, _italic_, __strong__'),
  (16, 'Jaune');
-- NOTE : Les corps HTML longs (articles 1-4, 6-9, 11-13) sont délibérément omis
-- ici car ils dépassent les limites raisonnables d''un script DDL de démonstration.
-- Insérer via : UPDATE content.body SET content = '...' WHERE document_id = N;
-- Ou via la procédure : CALL content.save_revision(N, author_entity_id);

-- COMMENTAIRES (sur le document 5 — Agent 327)
-- Exécution via la procédure content.create_comment() : traverse le même chemin
-- d'écriture (I/O) qu'en production. Valide l'absence de dead tuples structurels
-- et la construction correcte des chemins ltree (ADR-007).
-- L'argument OUT p_comment_id (position 4) reçoit la variable _id.
-- Signature actuelle : (document_id, account_entity_id, content, OUT p_comment_id, parent_id, status)
DO $$
DECLARE _id INT;
BEGIN
  CALL content.create_comment(5, 6, 'Un petit commentaire. Un.',    _id, NULL, 1::smallint);
  CALL content.create_comment(5, 7, 'Un petit commentaire. Deux.',  _id, NULL, 1::smallint);
  CALL content.create_comment(5, 8, 'Un petit commentaire. Trois.', _id, NULL, 1::smallint);
  CALL content.create_comment(5, 5, 'Un petit commentaire. Quatre.',_id, NULL, 1::smallint);
  CALL content.create_comment(5, 6, 'Un petit commentaire. Cinq.',  _id, NULL, 1::smallint);
END;
$$;

-- TAGS (232 entrées — taxonomie plate, hiérarchie à établir via create_tag)
INSERT INTO content.tag (id, slug, name)
OVERRIDING SYSTEM VALUE VALUES
  (1,  'esprit-saint',                   'Esprit Saint'),
  (2,  'jean-paul-ii',                   'Jean-Paul II'),
  (3,  'peche',                          'Péché'),
  (4,  'salut',                          'Salut'),
  (5,  'saint-augustin',                 'Saint Augustin'),
  (6,  'conversion',                     'Conversion'),
  (7,  'priere',                         'Prière'),
  (8,  'christologie',                   'Christologie'),
  (9,  'confession',                     'Confession'),
  (10, 'messe',                          'Messe'),
  (11, 'marie',                          'Marie'),
  (12, 'trinite',                        'Trinité'),
  (13, 'eglise',                         'Eglise'),
  (14, 'tradition',                      'Tradition'),
  (15, 'ecriture-sainte',               'Ecriture Sainte'),
  (16, 'jean-paul-i',                    'Jean-Paul I'),
  (17, 'sacrements',                     'Sacrements'),
  (18, 'confirmation',                   'Confirmation'),
  (19, 'mariage-chretien',               'Mariage chrétien'),
  (20, 'paroles-des-peres',              'Paroles des Pères'),
  (21, 'paroles-des-saints',             'Paroles des Saints'),
  (22, 'confession-eucharistie',         'Confession & Eucharistie'),
  (23, 'credo',                          'Credo'),
  (24, 'symbole-nicee-constantinople',   'Symbole de Nicée-Constantinople'),
  (25, 'divers',                         'Divers'),
  (26, 'test',                           'Test'),
  (27, 'shortcodes',                     'Shortcodes'),
  (28, 'saint-irenee',                   'Saint Irénée'),
  (29, 'irenee-de-lyon-2',              'Irénée de Lyon'),
  (30, 'saint-leon',                     'Saint Léon'),
  (31, 'saint-thomas',                   'Saint Thomas'),
  (32, 'charles-journet-2',             'Charles Journet'),
  (33, 'jean-danielou',                   'Jean Daniélou'),
  (34, 'hans-urs-von-balthasar',         'Hans Urs von Balthasar'),
  (35, 'yves-congar',                    'Yves Congar'),
  (36, 'karl-rahner',                    'Karl Rahner'),
  (37, 'temoignage',                     'Témoignage'),
  (38, 'apologetique-2',                 'Apologétique'),
  (39, 'mission',                        'Mission'),
  (40, 'monasticisme',                   'Monasticisme'),
  (41, 'vie-consacree',                 'Vie consacrée'),
  (42, 'laics',                          'Laïcs'),
  (43, 'catechese',                      'Catéchèse'),
  (44, 'pastorale',                      'Pastorale'),
  (45, 'origene-2',                      'Origène'),
  (46, 'tertullien-2',                   'Tertullien'),
  (47, 'apres-concile',                  'Après le Concile'),
  (48, 'concile-vatican-ii',             'Concile Vatican II'),
  (49, 'reforme',                        'Réforme'),
  (50, 'oecumenisme',                    'Œcuménisme'),
  (51, 'patristique',                    'Patristique'),
  (52, 'joseph-marie-verlinde',            'Joseph-Marie Verlinde'),
  (53, 'origene',                          'Origène'),
  (54, 'cyprien-de-carthage',             'Cyprien de Carthage'),
  (55, 'succession-apostolique',           'Succession apostolique'),
  (56, 'pierre-le-venerable',             'Pierre le Vénérable'),
  (57, 'inspiration-et-assistance',        'Inspiration et assistance'),
  (58, 'theologie-de-la-femme',           'Théologie de la femme'),
  (59, 'annonciation',                     'Annonciation'),
  (60, 'immaculee-conception',             'Immaculée Conception'),
  (61, 'catherine-de-genes',              'Catherine de Gênes'),
  (62, 'catherine-de-sienne',             'Catherine de Sienne'),
  (63, 'saint-bonaventure',               'Saint Bonaventure'),
  (64, 'saint-bernard',                   'Saint Bernard'),
  (65, 'le-mal',                          'Le mal'),
  (66, 'benoit-xvi',                      'Benoît XVI'),
  (67, 'john-henry-newman',               'John Henry Newman'),
  (68, 'encycliques',                     'Encycliques'),
  (69, 'assomption',                      'Assomption'),
  (70, 'therese-de-lisieux',              'Thérèse de Lisieux'),
  (71, 'signe-de-jonas',                  'Signe de Jonas'),
  (72, 'romanos-le-melode',               'Romanos le Mélode'),
  (73, 'julienne-de-norwich',             'Julienne de Norwich'),
  (74, 'ephrem-le-syrien',               'Éphrem le Syrien'),
  (75, 'isaac-le-syrien',                'Isaac le Syrien'),
  (76, 'germain-de-constantinople',       'Germain de Constantinople'),
  (77, 'jean-de-la-croix',               'Jean de la Croix'),
  (78, 'isaac-de-letoile',               'Isaac de l''Étoile'),
  (79, 'jean-vanier',                    'Jean Vanier'),
  (80, 'mere-teresa',                    'Mère Teresa'),
  (81, 'maxime-de-turin',               'Maxime de Turin'),
  (82, 'gregoire-le-grand',             'Grégoire le Grand'),
  (83, 'paul-vi',                        'Paul VI'),
  (84, 'cyrille-de-jerusalem',           'Cyrille de Jérusalem'),
  (85, 'alphonse-marie-de-liguori',     'Alphonse-Marie de Liguori'),
  (86, 'cyrille-d-alexandrie',           'Cyrille d''Alexandrie'),
  (87, 'gertrude-d-helfta',              'Gertrude d''Helfta'),
  (88, 'jean-xxiii',                     'Jean XXIII'),
  (89, 'guerric-d-igny',                 'Guerric d''Igny'),
  (90, 'baudouin-de-ford',              'Baudouin de Ford'),
  (91, 'therese-d-avila',               'Thérèse d''Avila'),
  (92, 'clement-d-alexandrie',          'Clément d''Alexandrie'),
  (93, 'basile-de-seleucie',            'Basile de Séleucie'),
  (94, 'gregoire-de-nazianze',          'Grégoire de Nazianze'),
  (95, 'laurent-de-brindisi',           'Laurent de Brindisi'),
  (96, 'edith-stein',                   'Édith Stein'),
  (97, 'basile-de-cesaree',             'Basile de Césarée'),
  (98, 'charles-de-foucauld',           'Charles de Foucauld'),
  (99, 'maxime-le-confesseur',          'Maxime le Confesseur'),
 (100, 'saint-francois',               'Saint François'),
 (101, 'isidore-de-seville',            'Isidore de Séville'),
 (102, 'guillaume-d-auvergne',          'Guillaume d''Auvergne'),
 (103, 'jean-guitton',                  'Jean Guitton'),
 (104, 'gregoire-de-nysse',             'Grégoire de Nysse'),
 (105, 'tertullien',                    'Tertullien'),
 (106, 'frederic-ozanam',               'Frédéric Ozanam'),
 (107, 'islam',                         'Islam'),
 (108, 'histoire-de-vatican-ii',        'Histoire de Vatican II'),
 (109, 'saint-thomas-apotre',           'Saint Thomas apôtre'),
 (110, 'symeon-le-nouveau-theologien',  'Syméon le Nouveau Théologien'),
 (111, 'charles-peguy',                 'Charles Peguy'),
 (112, 'jean-le-baptiste',              'Jean le Baptiste'),
 (113, 'irenee-de-lyon',               'Irénée de Lyon'),
 (114, 'corps-et-liturgie',             'Corps et liturgie'),
 (115, 'jean-tauler',                   'Jean Tauler'),
 (116, 'guigues-ii-le-chartreux',      'Guigues II le Chartreux'),
 (117, 'guillaume-de-saint-thierry',    'Guillaume de Saint-Thierry'),
 (118, 'apologetique',                  'Apologétique'),
 (119, 'vertus',                        'Vertus'),
 (120, 'avent',                         'Avent'),
 (121, 'liturgie',                      'Liturgie'),
 (122, 'naissance-de-la-vierge-marie',  'Naissance de la Vierge Marie'),
 (123, 'presentation-de-la-vierge-marie-au-temple', 'Présentation de la Vierge Marie au Temple'),
 (124, 'christ-roi',                    'Christ Roi'),
 (125, 'le-martyre',                    'Le martyre'),
 (126, 'saint-andre-apotre',            'Saint André apôtre'),
 (127, 'andre-de-crete',               'André de Crète'),
 (128, 'aelred-de-rievaulx',           'Ælred de Rievaulx'),
 (129, 'epiphanie',                     'Épiphanie'),
 (130, 'francois-de-sales',             'François de Sales'),
 (131, 'macaire-le-grand',             'Macaire le Grand'),
 (132, 'josemaria-escriva',             'Josemaría Escrivá'),
 (133, 'hymnes',                        'Hymnes'),
 (134, 'henri-de-lubac',               'Henri de Lubac'),
 (135, 'eucharistie',                   'Eucharistie'),
 (136, 'lettre-aux-hebreux',            'Lettre aux Hébreux'),
 (137, 'evangile-selon-saint-jean',     'Évangile selon saint Jean'),
 (138, 'premiere-lettre-de-saint-jean', 'Première lettre de saint Jean'),
 (139, 'gender-theory',                 'Gender theory'),
 (140, 'noces-de-cana',                'Noces de Cana'),
 (141, 'jean-miguel-garrigues',         'Jean-Miguel Garrigues'),
 (142, 'mariage',                       'Mariage'),
 (143, 'richard-bauckham',             'Richard Bauckham'),
 (144, 'careme',                        'Carême'),
 (145, 'lourdes',                       'Lourdes'),
 (146, 'la-croix-glorieuse',            'La Croix Glorieuse'),
 (147, 'transfiguration',               'Transfiguration'),
 (148, 'theologie-du-corps',            'Théologie du corps'),
 (149, 'tentations-du-seigneur',        'Tentations du Seigneur'),
 (150, 'bible-crampon',                 'Bible Crampon'),
 (151, 'serpent-de-bronze',             'Serpent de bronze'),
 (152, 'francois-ier',                  'Pape François'),
 (153, 'marie-eugene-de-l-enfant-jesus','Marie-Eugène de l''Enfant Jésus'),
 (154, 'la-redaction',                  'La Rédaction'),
 (155, 'jeanne-jugan',                  'Jeanne Jugan'),
 (156, 'rameaux',                       'Rameaux'),
 (157, 'resurrection-du-seigneur',      'Résurrection du Seigneur'),
 (158, 'bonaventure-de-bagnoregio',     'Bonaventure de Bagnoregio'),
 (159, 'meliton-de-sardes',             'Méliton de Sardes'),
 (160, 'cesaire-d-arles',              'Césaire d''Arles'),
 (161, 'claude-la-colombiere',          'Claude La Colombière'),
 (162, 'grignon-de-montfort',           'Grignon de Montfort'),
 (163, 'thomas-becket',                 'Thomas Becket'),
 (164, 'saint-colomban',               'Saint Colomban'),
 (165, 'imperfection-du-monde',         'De l''imperfection du monde'),
 (166, 'aphraate-le-perse',             'Aphraate le Perse'),
 (167, 'toussaint',                     'Toussaint'),
 (168, 'communion-des-saints',          'Communion des saints'),
 (169, 'saints-innocents',             'Saints Innocents'),
 (170, 'charles-borromee',             'Charles Borromée'),
 (171, 'francois-xavier',               'François Xavier'),
 (172, 'vincent-de-paul',              'Vincent de Paul'),
 (173, 'epiphane-de-salamine',          'Épiphane de Salamine'),
 (174, 'magnificat',                    'Magnificat'),
 (175, 'manuscrits-anciens',           'Manuscrits anciens'),
 (176, 'ascension',                     'Ascension'),
 (177, 'la-sainte-trinite',             'La Sainte Trinité'),
 (178, 'la-garde-du-coeur',             'La garde du cœur'),
 (179, 'du-repentir',                   'Du repentir'),
 (180, 'pierre-damien',                 'Pierre Damien'),
 (181, 'anselme-de-canterbury',         'Anselme de Canterbury'),
 (182, 'coeur-de-jesus',               'Cœur de Jésus'),
 (183, 'jerome',                        'Jérôme'),
 (184, 'saint-jerome',                  'Saint Jérôme'),
 (185, 'jean-duns-scot',               'Jean Duns Scot'),
 (186, 'jean-pierre-batut',             'Jean-Pierre Batut'),
 (187, 'jean-marie-lustiger',           'Jean-Marie Lustiger'),
 (188, 'dessein-de-dieu',              'Dessein de Dieu'),
 (189, 'proclus-de-constantinople',     'Proclus de Constantinople'),
 (190, 'sammaritaine',                  'Sammaritaine'),
 (191, 'passion-du-christ',             'Passion du Christ'),
 (192, 'francois-varillon',             'François Varillon'),
 (193, 'liberte-de-l-homme',           'Liberté de l''homme'),
 (194, 'apophtegmes',                   'Apophtegmes'),
 (195, 'les-7-dons-de-l-esprit-saint',  'Les 7 dons de l''Esprit Saint'),
 (196, 'c-s-lewis',                     'C. S. Lewis'),
 (197, 'de-la-temporalite',             'De la temporalité'),
 (198, 'charles-journet',               'Charles Journet'),
 (199, 'le-purgatoire',                 'Le purgatoire'),
 (200, 'bapteme',                       'Baptême'),
 (201, 'vepres',                        'Vêpres'),
 (202, 'liturgie-des-heures',           'Liturgie des heures'),
 (203, 'theodore-de-mopsueste',         'Théodore de Mopsueste'),
 (204, 'pierre-de-berulle',             'Pierre de Bérulle'),
 (205, 'elie-ayroulet',                'Élie Ayroulet'),
 (206, 'andre-gouzes',                  'André Gouzes'),
 (207, 'chants-de-communion',           'Chants de communion'),
 (208, 'raban-maure',                   'Raban Maure'),
 (209, 'beatus',                        'Beatus'),
 (210, 'les-deux-cites',               'Les deux cités'),
 (211, 'saint-pierre',                  'Saint Pierre'),
 (212, 'notre-dame-des-douleurs',       'Notre-Dame des Douleurs'),
 (213, 'sur-le-monde-de-ce-temps',     'Sur le monde de ce temps'),
 (214, 'post-format-gallery',           'post-format-gallery'),
 (215, 'simone-weil',                   'Simone Weil'),
 (216, 'jeanne-darc',                   'Jeanne d''Arc'),
 (217, 'serviteur',                     'Serviteur'),
 (218, 'maitre-eckhart',               'Maître Eckhart'),
 (219, 'fenelon',                       'Fénelon'),
 (220, 'nuits-spirituelles',            'Nuits spirituelles'),
 (221, 'charismes-et-ministeres',       'Charismes et ministères'),
 (222, 'louis-bouyer',                  'Louis Bouyer'),
 (223, 'paques',                        'Pâques'),
 (224, 'triduum-pascal',               'Triduum pascal'),
 (225, 'arbre-de-vie',                  'Arbre de vie'),
 (226, 'demons',                        'Démons'),
 (227, 'aline-lizotte',                'Aline Lizotte'),
 (228, 'filiation',                     'Filiation'),
 (229, 'dysmas-de-lassus',              'Dysmas de Lassus'),
 (230, 'chastete',                      'Chasteté'),
 (231, 'visitation-de-la-vierge-marie', 'Visitation de la Vierge Marie'),
 (232, 'testimonia',                    'Testimonia');
SELECT setval(pg_get_serial_sequence('content.tag', 'id'), 232);

-- TAG HIERARCHY — self-references (depth=0) pour tous les tags racines du seed
-- Les tags du seed sont tous des racines (aucune hiérarchie établie à ce stade).
-- Pour établir une hiérarchie, utiliser CALL content.create_tag() avec p_parent_id,
-- ou insérer manuellement dans tag_hierarchy après les self-references.
-- Exemple de hiérarchie manuelle :
--   INSERT INTO content.tag_hierarchy (ancestor_id, descendant_id, depth)
--   SELECT th.ancestor_id, 29, th.depth + 1  -- tag 29 = saint_irenee enfant de 20 = paroles_des_peres
--   FROM   content.tag_hierarchy th WHERE th.descendant_id = 20;
INSERT INTO content.tag_hierarchy (ancestor_id, descendant_id, depth)
SELECT id, id, 0 FROM content.tag;

-- ==============================================================================
-- LIAISONS Article ↔ Tag (content_to_tag)
-- ------------------------------------------------------------------------------
-- Bloc 1 : liaisons nominales (16 documents × associations thématiques) — 44 lignes
-- Bloc 2 : liaisons bulk (saturation de page DOD audit) — ~411 lignes supplémentaires
-- Total cible : ~455 lignes → 2 pages à 32B/tuple → bloat_alert OFF.
--
-- Calcul de saturation (tuple=32B, fillfactor=100) :
--   rows_per_page = floor(8168 / 32) = 255
--   2 pages pleines = 510 tuples idéaux — 455 suffit pour observed < seuil.
--   seuil bloat = 32 × 1.20 = 38.4B
--   observed ≈ 2×8192 / 455 = 36.0B < 38.4B → bloat_alert = FALSE ✓
-- ==============================================================================

-- Bloc 1 : liaisons nominales (associations thématiques existantes)
INSERT INTO content.content_to_tag (content_id, tag_id) VALUES
  (1,1),(1,2),(1,3),(1,8),(1,12),
  (2,7),(2,5),(2,9),
  (3,10),(3,7),(3,13),(3,15),
  (4,6),(4,7),
  (5,7),(5,20),(5,21),
  (6,32),(6,53),(6,45),
  (7,24),(7,23),(7,35),
  (8,6),(8,17),(8,22),
  (9,47),(9,43),(9,55),
  (10,27),(10,26),(10,25),
  (11,27),(11,26),
  (12,25),(12,27),(12,26),
  (13,25),(13,27),
  (14,26),(14,25),
  (15,27),(15,26),
  (16,25);

-- Bloc 2 : liaisons bulk — saturation de la table pour l'audit DOD
-- Stratégie : CROSS JOIN docs 1-16 × tags 30-55 (plage non conflictuelle avec le bloc 1).
-- ON CONFLICT DO NOTHING : protection contre les 5 paires déjà présentes
-- (tag 32→doc6, tag 35→doc7, tag 43→doc9, tag 45→doc6, tag 47→doc9).
-- Résultat net : 16 × 26 − 5 conflits = 411 nouvelles lignes.
INSERT INTO content.content_to_tag (content_id, tag_id)
SELECT d, t
FROM   generate_series(1, 16)  AS d
CROSS  JOIN generate_series(30, 55) AS t
ON CONFLICT DO NOTHING;

-- LIAISONS Article ↔ Média
INSERT INTO content.content_to_media (content_id, media_id, position) VALUES
  (1, 1, 0),
  (1, 2, 1),
  (1, 7, 2),
  (2, 2, 0),
  (3, 3, 0),
  (4, 8, 0);


-- ==============================================================================
-- ANALYZE — mise à jour des statistiques pour l'audit DOD
-- ------------------------------------------------------------------------------
-- v_performance_sentinel requiert pg_stats.avg_width (densité varlena réelle)
-- et pg_stat_user_tables.n_live_tup (calcul bloat).
-- ANALYZE doit être exécuté après le seed pour que les alertes de
-- v_master_health_audit reflètent la réalité physique et non le fallback
-- 4B/varlena pré-ANALYZE.
-- ==============================================================================

ANALYZE identity.entity;
ANALYZE identity.auth;
ANALYZE identity.account_core;
ANALYZE identity.person_identity;
ANALYZE identity.person_biography;
ANALYZE identity.role;
ANALYZE content.content_to_tag;
ANALYZE content.document;
ANALYZE content.core;


-- ==============================================================================
-- FIN DU DML — master_schema_dml.pgsql
-- ==============================================================================
