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
--   geo.place_core           12 lieux (France)
--   identity.entity          8 entités (4 personnes + 4 comptes)
--   identity.person_*        profils Henri de Lubac, Jeanne d'Arc, de Gaulle, anonyme
--   identity.auth            4 comptes (argon2id)
--   identity.account_core    4 comptes utilisateurs
--   content.document         16 articles
--   content.core             16 statuts de publication
--   content.identity         16 titres / slugs
--   content.body             5 corps courts (les corps longs sont à charger séparément)
--   content.comment          5 commentaires (document 5) — via CALL content.create_comment()
--   content.tag              232 tags (taxonomie plate — hiérarchiser via UPDATE path)
--   content.content_to_tag   16 liaisons article ↔ tag
--   content.media_core       9 médias
--   content.media_content    9 métadonnées de médias
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
-- La hiérarchie des tags (path ltree) est initialisée à plat (racines uniquement).
-- Établir la taxonomie via :
--   UPDATE content.tag SET path = 'theologie.patristique', parent_id = <id_parent>
--   WHERE slug = 'cyrille-d-alexandrie';
-- ==============================================================================

\c marius

-- SECTION 14 : DONNÉES DE REMPLISSAGE (SEED)
-- Traduction fidèle de logicalDataModel.pgsql vers le modèle ECS.
-- OVERRIDING SYSTEM VALUE utilisé pour forcer les IDs des FK croisées.
-- ==============================================================================

-- ENTITÉS D'IDENTITÉ (persons 1-4, accounts 5-8)
INSERT INTO identity.entity (id) OVERRIDING SYSTEM VALUE VALUES (1),(2),(3),(4),(5),(6),(7),(8);
SELECT setval(pg_get_serial_sequence('identity.entity', 'id'), 8);

-- LIEUX — spine spatial (ADR-024 : données postales séparées dans geo.postal_address)
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

-- ADRESSES POSTALES (ADR-024 · country_code 250 = France ISO 3166-1 numérique)
INSERT INTO geo.postal_address (place_id, country_code, street,                            postal_code, locality,                      region) VALUES
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
  (1, 1, 'Henri',   'Sonier',              'de Lubac',     's.j.', 'P.',    NULL,                    'FR'),
  (2, 2, 'Jeanne',  NULL,                  'd''Arc',       NULL,   'Ste',   'La Pucelle d''Orléans', 'FR'),
  (3, 1, 'Charles', 'André Joseph Marie',  'de Gaulle',    NULL,   'Gal',   'Le Général',            'FR'),
  (4, NULL, NULL,   NULL,                   NULL,          NULL,   NULL,    'El Comandante',         'FR');

INSERT INTO identity.person_biography (entity_id, birth_date, death_date, birth_place_id, death_place_id) VALUES
  (1, '1896-02-20', '1991-09-04', NULL, NULL),
  (2, '1412-01-01', '1431-05-30', NULL, NULL),
  (3, '1890-11-22', '1970-11-09', 11,   12);

INSERT INTO identity.person_contact (entity_id, phone, email) VALUES
  (1, '04 46 35 76 89', NULL),
  (2, NULL,             'jeanne.arc@mail.com'),
  (4, '01 44 55 66 77', NULL);

INSERT INTO identity.person_content (entity_id, media_id, devise, description) VALUES
  (1, 1, 'L''Église a pour unique mission de rendre Jésus Christ présent aux hommes.',
      'Henri Sonier de Lubac, né à Cambrai le 20 février 1896 et mort à Paris le 4 septembre 1991, est un jésuite, théologien catholique et cardinal français.'),
  (2, 2, 'De par le Roy du Ciel !',
      'Jeanne d''Arc, née vers 1412 à Domrémy, village du duché de Bar, et morte sur le bûcher le 30 mai 1431 à Rouen, est une héroïne de l''histoire de France, chef de guerre et sainte de l''Église catholique.'),
  (3, 3, 'France libre !',
      'Charles de Gaulle, né le 22 novembre 1890 à Lille et mort le 9 novembre 1970 à Colombey-les-Deux-Églises, est un militaire, résistant, homme d''État et écrivain français.'),
  (4, NULL, 'Personne anonyme pour test.', NULL);

-- COMPTES (entities 5-8)
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

-- DOCUMENTS — articles (IDs 1-16 pour cohérence avec les FK tag_to_article)
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
-- Le contenu complet est préservé fidèlement depuis logicalDataModel.pgsql.
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
-- et la construction correcte des chemins ltree (ADR-012).
-- L'argument OUT p_comment_id est ignoré ici (variable anonyme $_).
DO $$
DECLARE _id INT;
BEGIN
  CALL content.create_comment(5, 6, 'Un petit commentaire. Un.',    NULL, 1, _id);
  CALL content.create_comment(5, 7, 'Un petit commentaire. Deux.',  NULL, 1, _id);
  CALL content.create_comment(5, 8, 'Un petit commentaire. Trois.', NULL, 1, _id);
  CALL content.create_comment(5, 5, 'Un petit commentaire. Quatre.',NULL, 1, _id);
  CALL content.create_comment(5, 6, 'Un petit commentaire. Cinq.',  NULL, 1, _id);
END;
$$;

-- TAGS (flat, tous en racine — hiérarchie établie via UPDATE path ultérieurement)
-- path = replace(slug, '-', '_')::ltree
INSERT INTO content.tag (id, path, slug, name) OVERRIDING SYSTEM VALUE VALUES
  (1,  'sur_le_monde_invisible',           'sur-le-monde-invisible',           'Sur le monde invisible'),
  (2,  'parole_du_magistere',              'parole-du-magistere',              'Parole du magistère'),
  (3,  'prieres_chretiennes',              'prieres-chretiennes',              'Prières chrétiennes'),
  (4,  'symboles_de_la_foi',               'symboles-de-la-foi',               'Symboles de la foi'),
  (5,  'cartes',                           'cartes',                           'Cartes'),
  (6,  'sur_la_sainte_mere_de_dieu',       'sur-la-sainte-mere-de-dieu',       'Sur la sainte Mère de Dieu'),
  (7,  'anthropologie',                    'anthropologie',                    'Anthropologie'),
  (8,  'jean_paul_ii',                     'jean-paul-ii',                     'Jean-Paul II'),
  (9,  'sur_eglise',                       'sur-eglise',                       'Sur l''Église'),
  (10, 'la_revelation_divine',             'la-revelation-divine',             'La Révélation divine'),
  (11, 'metaphysique',                     'metaphysique',                     'Métaphysique'),
  (12, 'leon_le_grand',                    'leon-le-grand',                    'Léon le Grand'),
  (13, 'morale',                           'morale',                           'Morale'),
  (14, 'figures_de_eglise',               'figures-de-eglise',               'Figures de l''Église'),
  (15, 'symbolique_chretienne',            'symbolique-chretienne',            'Symbolique chrétienne'),
  (16, 'atelier',                          'atelier',                          'L''atelier'),
  (17, 'sur_le_pere',                      'sur-le-pere',                      'Sur le Père'),
  (18, 'sur_le_fils',                      'sur-le-fils',                      'Sur le Fils'),
  (19, 'sur_esprit_saint',                 'sur-esprit-saint',                 'Sur l''Esprit Saint'),
  (20, 'paroles_des_peres',               'paroles-des-peres',               'Paroles des Pères'),
  (21, 'ecriture_tradition',               'ecriture-tradition',               'Écriture & Tradition'),
  (22, 'saint_augustin',                   'saint-augustin',                   'Saint Augustin'),
  (23, 'peche',                            'peche',                            'Le péché'),
  (24, 'bible',                            'bible',                            'Bible'),
  (25, 'bede_le_venerable',               'bede-le-venerable',               'Bède le vénérable'),
  (26, 'saint_paul',                       'saint-paul',                       'Saint Paul'),
  (27, 'filioque',                         'filioque',                         'Filioque'),
  (28, 'freres_de_jesus',                  'freres-de-jesus',                  'Frères de Jésus'),
  (29, 'saint_irenee',                     'saint-irenee',                     'Saint Irénée'),
  (30, 'anges',                            'anges',                            'Anges'),
  (31, 'enfer',                            'enfer',                            'L''Enfer'),
  (32, 'eusebe_de_cesaree',               'eusebe-de-cesaree',               'Eusèbe de Césarée'),
  (33, 'presentation_du_seigneur',         'presentation-du-seigneur',         'Présentation du Seigneur'),
  (34, 'hilaire_de_poitiers',              'hilaire-de-poitiers',              'Hilaire de Poitiers'),
  (35, 'saint_benoit',                     'saint-benoit',                     'Saint Benoît'),
  (36, 'thomas_d_aquin',                   'thomas-d-aquin',                   'Thomas d''Aquin'),
  (37, 'gethsemani',                       'gethsemani',                       'Gethsémani'),
  (38, 'droit_canon',                      'droit-canon',                      'Droit canon'),
  (39, 'incarnation_du_verbe',             'incarnation-du-verbe',             'Incarnation du Verbe'),
  (40, 'sacrements',                       'sacrements',                       'Sacrements'),
  (41, 'tria_munera',                      'tria-munera',                      'Tria munera'),
  (42, 'videos',                           'videos',                           'Videos'),
  (43, 'bapteme_du_seigneur',              'bapteme-du-seigneur',              'Baptême du Seigneur'),
  (44, 'litanies',                         'litanies',                         'Litanies'),
  (45, 'jean_chrysostome',                 'jean-chrysostome',                 'Jean Chrysostome'),
  (46, 'saint_etienne',                    'saint-etienne',                    'Saint Etienne'),
  (47, 'saint_joseph',                     'saint-joseph',                     'Saint Joseph'),
  (48, 'jean_de_damas',                    'jean-de-damas',                    'Jean de Damas'),
  (49, 'pierre_chrysologue',               'pierre-chrysologue',               'Pierre Chrysologue'),
  (50, 'ambroise_de_milan',               'ambroise-de-milan',               'Ambroise de Milan'),
  (51, 'concile_vatican_ii',              'concile-vatican-ii',              'Concile Vatican II'),
  (52, 'joseph_marie_verlinde',            'joseph-marie-verlinde',            'Joseph-Marie Verlinde'),
  (53, 'origene',                          'origene',                          'Origène'),
  (54, 'cyprien_de_carthage',             'cyprien-de-carthage',             'Cyprien de Carthage'),
  (55, 'succession_apostolique',           'succession-apostolique',           'Succession apostolique'),
  (56, 'pierre_le_venerable',             'pierre-le-venerable',             'Pierre le Vénérable'),
  (57, 'inspiration_et_assistance',        'inspiration-et-assistance',        'Inspiration et assistance'),
  (58, 'theologie_de_la_femme',           'theologie-de-la-femme',           'Théologie de la femme'),
  (59, 'annonciation',                     'annonciation',                     'Annonciation'),
  (60, 'immaculee_conception',             'immaculee-conception',             'Immaculée Conception'),
  (61, 'catherine_de_genes',              'catherine-de-genes',              'Catherine de Gênes'),
  (62, 'catherine_de_sienne',             'catherine-de-sienne',             'Catherine de Sienne'),
  (63, 'saint_bonaventure',               'saint-bonaventure',               'Saint Bonaventure'),
  (64, 'saint_bernard',                   'saint-bernard',                   'Saint Bernard'),
  (65, 'le_mal',                          'le-mal',                          'Le mal'),
  (66, 'benoit_xvi',                      'benoit-xvi',                      'Benoît XVI'),
  (67, 'john_henry_newman',               'john-henry-newman',               'John Henry Newman'),
  (68, 'encycliques',                     'encycliques',                     'Encycliques'),
  (69, 'assomption',                      'assomption',                      'Assomption'),
  (70, 'therese_de_lisieux',              'therese-de-lisieux',              'Thérèse de Lisieux'),
  (71, 'signe_de_jonas',                  'signe-de-jonas',                  'Signe de Jonas'),
  (72, 'romanos_le_melode',               'romanos-le-melode',               'Romanos le Mélode'),
  (73, 'julienne_de_norwich',             'julienne-de-norwich',             'Julienne de Norwich'),
  (74, 'ephrem_le_syrien',               'ephrem-le-syrien',               'Éphrem le Syrien'),
  (75, 'isaac_le_syrien',                'isaac-le-syrien',                'Isaac le Syrien'),
  (76, 'germain_de_constantinople',       'germain-de-constantinople',       'Germain de Constantinople'),
  (77, 'jean_de_la_croix',               'jean-de-la-croix',               'Jean de la Croix'),
  (78, 'isaac_de_letoile',               'isaac-de-letoile',               'Isaac de l''Étoile'),
  (79, 'jean_vanier',                    'jean-vanier',                    'Jean Vanier'),
  (80, 'mere_teresa',                    'mere-teresa',                    'Mère Teresa'),
  (81, 'maxime_de_turin',               'maxime-de-turin',               'Maxime de Turin'),
  (82, 'gregoire_le_grand',             'gregoire-le-grand',             'Grégoire le Grand'),
  (83, 'paul_vi',                        'paul-vi',                        'Paul VI'),
  (84, 'cyrille_de_jerusalem',           'cyrille-de-jerusalem',           'Cyrille de Jérusalem'),
  (85, 'alphonse_marie_de_liguori',     'alphonse-marie-de-liguori',     'Alphonse-Marie de Liguori'),
  (86, 'cyrille_d_alexandrie',           'cyrille-d-alexandrie',           'Cyrille d''Alexandrie'),
  (87, 'gertrude_d_helfta',              'gertrude-d-helfta',              'Gertrude d''Helfta'),
  (88, 'jean_xxiii',                     'jean-xxiii',                     'Jean XXIII'),
  (89, 'guerric_d_igny',                 'guerric-d-igny',                 'Guerric d''Igny'),
  (90, 'baudouin_de_ford',              'baudouin-de-ford',              'Baudouin de Ford'),
  (91, 'therese_d_avila',               'therese-d-avila',               'Thérèse d''Avila'),
  (92, 'clement_d_alexandrie',          'clement-d-alexandrie',          'Clément d''Alexandrie'),
  (93, 'basile_de_seleucie',            'basile-de-seleucie',            'Basile de Séleucie'),
  (94, 'gregoire_de_nazianze',          'gregoire-de-nazianze',          'Grégoire de Nazianze'),
  (95, 'laurent_de_brindisi',           'laurent-de-brindisi',           'Laurent de Brindisi'),
  (96, 'edith_stein',                   'edith-stein',                   'Édith Stein'),
  (97, 'basile_de_cesaree',             'basile-de-cesaree',             'Basile de Césarée'),
  (98, 'charles_de_foucauld',           'charles-de-foucauld',           'Charles de Foucauld'),
  (99, 'maxime_le_confesseur',          'maxime-le-confesseur',          'Maxime le Confesseur'),
 (100, 'saint_francois',               'saint-francois',               'Saint François'),
 (101, 'isidore_de_seville',            'isidore-de-seville',            'Isidore de Séville'),
 (102, 'guillaume_d_auvergne',          'guillaume-d-auvergne',          'Guillaume d''Auvergne'),
 (103, 'jean_guitton',                  'jean-guitton',                  'Jean Guitton'),
 (104, 'gregoire_de_nysse',             'gregoire-de-nysse',             'Grégoire de Nysse'),
 (105, 'tertullien',                    'tertullien',                    'Tertullien'),
 (106, 'frederic_ozanam',               'frederic-ozanam',               'Frédéric Ozanam'),
 (107, 'islam',                         'islam',                         'Islam'),
 (108, 'histoire_de_vatican_ii',        'histoire-de-vatican-ii',        'Histoire de Vatican II'),
 (109, 'saint_thomas_apotre',           'saint-thomas-apotre',           'Saint Thomas apôtre'),
 (110, 'symeon_le_nouveau_theologien',  'symeon-le-nouveau-theologien',  'Syméon le Nouveau Théologien'),
 (111, 'charles_peguy',                 'charles-peguy',                 'Charles Peguy'),
 (112, 'jean_le_baptiste',              'jean-le-baptiste',              'Jean le Baptiste'),
 (113, 'irenee_de_lyon',               'irenee-de-lyon',               'Irénée de Lyon'),
 (114, 'corps_et_liturgie',             'corps-et-liturgie',             'Corps et liturgie'),
 (115, 'jean_tauler',                   'jean-tauler',                   'Jean Tauler'),
 (116, 'guigues_ii_le_chartreux',      'guigues-ii-le-chartreux',      'Guigues II le Chartreux'),
 (117, 'guillaume_de_saint_thierry',    'guillaume-de-saint-thierry',    'Guillaume de Saint-Thierry'),
 (118, 'apologetique',                  'apologetique',                  'Apologétique'),
 (119, 'vertus',                        'vertus',                        'Vertus'),
 (120, 'avent',                         'avent',                         'Avent'),
 (121, 'liturgie',                      'liturgie',                      'Liturgie'),
 (122, 'naissance_de_la_vierge_marie',  'naissance-de-la-vierge-marie',  'Naissance de la Vierge Marie'),
 (123, 'presentation_de_la_vierge_marie_au_temple', 'presentation-de-la-vierge-marie-au-temple', 'Présentation de la Vierge Marie au Temple'),
 (124, 'christ_roi',                    'christ-roi',                    'Christ Roi'),
 (125, 'le_martyre',                    'le-martyre',                    'Le martyre'),
 (126, 'saint_andre_apotre',            'saint-andre-apotre',            'Saint André apôtre'),
 (127, 'andre_de_crete',               'andre-de-crete',               'André de Crète'),
 (128, 'aelred_de_rievaulx',           'aelred-de-rievaulx',           'Ælred de Rievaulx'),
 (129, 'epiphanie',                     'epiphanie',                     'Épiphanie'),
 (130, 'francois_de_sales',             'francois-de-sales',             'François de Sales'),
 (131, 'macaire_le_grand',             'macaire-le-grand',             'Macaire le Grand'),
 (132, 'josemaria_escriva',             'josemaria-escriva',             'Josemaría Escrivá'),
 (133, 'hymnes',                        'hymnes',                        'Hymnes'),
 (134, 'henri_de_lubac',               'henri-de-lubac',               'Henri de Lubac'),
 (135, 'eucharistie',                   'eucharistie',                   'Eucharistie'),
 (136, 'lettre_aux_hebreux',            'lettre-aux-hebreux',            'Lettre aux Hébreux'),
 (137, 'evangile_selon_saint_jean',     'evangile-selon-saint-jean',     'Évangile selon saint Jean'),
 (138, 'premiere_lettre_de_saint_jean', 'premiere-lettre-de-saint-jean', 'Première lettre de saint Jean'),
 (139, 'gender_theory',                 'gender-theory',                 'Gender theory'),
 (140, 'noces_de_cana',                'noces-de-cana',                'Noces de Cana'),
 (141, 'jean_miguel_garrigues',         'jean-miguel-garrigues',         'Jean-Miguel Garrigues'),
 (142, 'mariage',                       'mariage',                       'Mariage'),
 (143, 'richard_bauckham',             'richard-bauckham',             'Richard Bauckham'),
 (144, 'careme',                        'careme',                        'Carême'),
 (145, 'lourdes',                       'lourdes',                       'Lourdes'),
 (146, 'la_croix_glorieuse',            'la-croix-glorieuse',            'La Croix Glorieuse'),
 (147, 'transfiguration',               'transfiguration',               'Transfiguration'),
 (148, 'theologie_du_corps',            'theologie-du-corps',            'Théologie du corps'),
 (149, 'tentations_du_seigneur',        'tentations-du-seigneur',        'Tentations du Seigneur'),
 (150, 'bible_crampon',                 'bible-crampon',                 'Bible Crampon'),
 (151, 'serpent_de_bronze',             'serpent-de-bronze',             'Serpent de bronze'),
 (152, 'francois_ier',                  'francois-ier',                  'Pape François'),
 (153, 'marie_eugene_de_l_enfant_jesus','marie-eugene-de-l-enfant-jesus','Marie-Eugène de l''Enfant Jésus'),
 (154, 'la_redaction',                  'la-redaction',                  'La Rédaction'),
 (155, 'jeanne_jugan',                  'jeanne-jugan',                  'Jeanne Jugan'),
 (156, 'rameaux',                       'rameaux',                       'Rameaux'),
 (157, 'resurrection_du_seigneur',      'resurrection-du-seigneur',      'Résurrection du Seigneur'),
 (158, 'bonaventure_de_bagnoregio',     'bonaventure-de-bagnoregio',     'Bonaventure de Bagnoregio'),
 (159, 'meliton_de_sardes',             'meliton-de-sardes',             'Méliton de Sardes'),
 (160, 'cesaire_d_arles',              'cesaire-d-arles',              'Césaire d''Arles'),
 (161, 'claude_la_colombiere',          'claude-la-colombiere',          'Claude La Colombière'),
 (162, 'grignon_de_montfort',           'grignon-de-montfort',           'Grignon de Montfort'),
 (163, 'thomas_becket',                 'thomas-becket',                 'Thomas Becket'),
 (164, 'saint_colomban',               'saint-colomban',               'Saint Colomban'),
 (165, 'imperfection_du_monde',         'imperfection-du-monde',         'De l''imperfection du monde'),
 (166, 'aphraate_le_perse',             'aphraate-le-perse',             'Aphraate le Perse'),
 (167, 'toussaint',                     'toussaint',                     'Toussaint'),
 (168, 'communion_des_saints',          'communion-des-saints',          'Communion des saints'),
 (169, 'saints_innocents',             'saints-innocents',             'Saints Innocents'),
 (170, 'charles_borromee',             'charles-borromee',             'Charles Borromée'),
 (171, 'francois_xavier',               'francois-xavier',               'François Xavier'),
 (172, 'vincent_de_paul',              'vincent-de-paul',              'Vincent de Paul'),
 (173, 'epiphane_de_salamine',          'epiphane-de-salamine',          'Épiphane de Salamine'),
 (174, 'magnificat',                    'magnificat',                    'Magnificat'),
 (175, 'manuscrits_anciens',           'manuscrits-anciens',           'Manuscrits anciens'),
 (176, 'ascension',                     'ascension',                     'Ascension'),
 (177, 'la_sainte_trinite',             'la-sainte-trinite',             'La Sainte Trinité'),
 (178, 'la_garde_du_coeur',             'la-garde-du-coeur',             'La garde du cœur'),
 (179, 'du_repentir',                   'du-repentir',                   'Du repentir'),
 (180, 'pierre_damien',                 'pierre-damien',                 'Pierre Damien'),
 (181, 'anselme_de_canterbury',         'anselme-de-canterbury',         'Anselme de Canterbury'),
 (182, 'coeur_de_jesus',               'coeur-de-jesus',               'Cœur de Jésus'),
 (183, 'jerome',                        'jerome',                        'Jérôme'),
 (184, 'saint_jerome',                  'saint-jerome',                  'Saint Jérôme'),
 (185, 'jean_duns_scot',               'jean-duns-scot',               'Jean Duns Scot'),
 (186, 'jean_pierre_batut',             'jean-pierre-batut',             'Jean-Pierre Batut'),
 (187, 'jean_marie_lustiger',           'jean-marie-lustiger',           'Jean-Marie Lustiger'),
 (188, 'dessein_de_dieu',              'dessein-de-dieu',              'Dessein de Dieu'),
 (189, 'proclus_de_constantinople',     'proclus-de-constantinople',     'Proclus de Constantinople'),
 (190, 'sammaritaine',                  'sammaritaine',                  'Sammaritaine'),
 (191, 'passion_du_christ',             'passion-du-christ',             'Passion du Christ'),
 (192, 'francois_varillon',             'francois-varillon',             'François Varillon'),
 (193, 'liberte_de_l_homme',           'liberte-de-l-homme',           'Liberté de l''homme'),
 (194, 'apophtegmes',                   'apophtegmes',                   'Apophtegmes'),
 (195, 'les_7_dons_de_l_esprit_saint',  'les-7-dons-de-l-esprit-saint',  'Les 7 dons de l''Esprit Saint'),
 (196, 'c_s_lewis',                     'c-s-lewis',                     'C. S. Lewis'),
 (197, 'de_la_temporalite',             'de-la-temporalite',             'De la temporalité'),
 (198, 'charles_journet',               'charles-journet',               'Charles Journet'),
 (199, 'le_purgatoire',                 'le-purgatoire',                 'Le purgatoire'),
 (200, 'bapteme',                       'bapteme',                       'Baptême'),
 (201, 'vepres',                        'vepres',                        'Vêpres'),
 (202, 'liturgie_des_heures',           'liturgie-des-heures',           'Liturgie des heures'),
 (203, 'theodore_de_mopsueste',         'theodore-de-mopsueste',         'Théodore de Mopsueste'),
 (204, 'pierre_de_berulle',             'pierre-de-berulle',             'Pierre de Bérulle'),
 (205, 'elie_ayroulet',                'elie-ayroulet',                'Élie Ayroulet'),
 (206, 'andre_gouzes',                  'andre-gouzes',                  'André Gouzes'),
 (207, 'chants_de_communion',           'chants-de-communion',           'Chants de communion'),
 (208, 'raban_maure',                   'raban-maure',                   'Raban Maure'),
 (209, 'beatus',                        'beatus',                        'Beatus'),
 (210, 'les_deux_cites',               'les-deux-cites',               'Les deux cités'),
 (211, 'saint_pierre',                  'saint-pierre',                  'Saint Pierre'),
 (212, 'notre_dame_des_douleurs',       'notre-dame-des-douleurs',       'Notre-Dame des Douleurs'),
 (213, 'sur_le_monde_de_ce_temps',     'sur-le-monde-de-ce-temps',     'Sur le monde de ce temps'),
 (214, 'post_format_gallery',           'post-format-gallery',           'post-format-gallery'),
 (215, 'simone_weil',                   'simone-weil',                   'Simone Weil'),
 (216, 'jeanne_d_arc',                  'jeanne-darc',                   'Jeanne d''Arc'),
 (217, 'serviteur',                     'serviteur',                     'Serviteur'),
 (218, 'maitre_eckhart',               'maitre-eckhart',               'Maître Eckhart'),
 (219, 'fenelon',                       'fenelon',                       'Fénelon'),
 (220, 'nuits_spirituelles',            'nuits-spirituelles',            'Nuits spirituelles'),
 (221, 'charismes_et_ministeres',       'charismes-et-ministeres',       'Charismes et ministères'),
 (222, 'louis_bouyer',                  'louis-bouyer',                  'Louis Bouyer'),
 (223, 'paques',                        'paques',                        'Pâques'),
 (224, 'triduum_pascal',               'triduum-pascal',               'Triduum pascal'),
 (225, 'arbre_de_vie',                  'arbre-de-vie',                  'Arbre de vie'),
 (226, 'demons',                        'demons',                        'Démons'),
 (227, 'aline_lizotte',                'aline-lizotte',                'Aline Lizotte'),
 (228, 'filiation',                     'filiation',                     'Filiation'),
 (229, 'dysmas_de_lassus',              'dysmas-de-lassus',              'Dysmas de Lassus'),
 (230, 'chastete',                      'chastete',                      'Chasteté'),
 (231, 'visitation_de_la_vierge_marie', 'visitation-de-la-vierge-marie', 'Visitation de la Vierge Marie'),
 (232, 'testimonia',                    'testimonia',                    'Testimonia');
SELECT setval(pg_get_serial_sequence('content.tag', 'id'), 232);

-- LIAISONS Article ↔ Tag (content_to_tag)
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

-- LIAISONS Article ↔ Média
INSERT INTO content.content_to_media (content_id, media_id, position) VALUES
  (1, 1, 0),
  (1, 2, 1),
  (1, 7, 2),
  (2, 2, 0),
  (3, 3, 0),
  (4, 8, 0);


-- ==============================================================================
-- FIN DU MASTER SCHEMA
-- ==============================================================================

-- ==============================================================================
-- FIN DU DML — master_schema_dml.pgsql
-- ==============================================================================
