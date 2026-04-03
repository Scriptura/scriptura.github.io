-- ==============================================================================
-- 00_infra/03_schemas.sql
-- Architecture ECS/DOD · Projet Marius · PostgreSQL 18
-- Contenu : création de tous les schémas applicatifs + schéma méta AOT
-- Ordre   : doit précéder toute création de table ou de fonction qualifiée
-- ==============================================================================

CREATE SCHEMA meta;      -- registre AOT + sentinelles d'audit (chargé en 01_meta/)
CREATE SCHEMA identity;  -- acteurs, authentification, permissions
CREATE SCHEMA geo;       -- lieux, adresses postales, coordonnées spatiales
CREATE SCHEMA org;       -- organisations, hiérarchies
CREATE SCHEMA commerce;  -- produits, transactions, paiements
CREATE SCHEMA content;   -- documents, médias, taxonomie, commentaires
