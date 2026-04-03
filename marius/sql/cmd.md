# Commandes d'installation sur Ubuntu

```sql
# DDL, initialisation de la base de données
# À lancer depuis la racine du dossier 'db'
sudo -u postgres psql -p 5433 -d postgres -f master_init.sql
```

```sql
# On injecte des données de test dans la base 'marius' déjà créée
sudo -u postgres psql -p 5433 -d marius -f master_schema_dml.pgsql
```

```sql
# Recalibrage des stats PG
# PostgreSQL a besoin de "compter" les lignes physiquement pour mettre à jour ses statistiques.
sudo -u postgres psql -p 5433 -d marius -c "ANALYZE;"
```

```sql
# Audit de sécurité
# Lecture de l'état de santé DOD/ECS
sudo -u postgres psql -p 5433 -d marius -c "SELECT * FROM meta.v_master_health_audit;"
```
