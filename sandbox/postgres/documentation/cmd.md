# Commandes d'installation sur Ubuntu

```
# DDL
cat master_schema_ddl.pgsql | sudo -u postgres psql -p 5433

# DML
cat master_schema_dml.pgsql | sudo -u postgres psql -p 5433 -d marius

# 1. Création du schéma et des tables du registre (Registre de base)
cat meta_registry.sql | sudo -u postgres psql -p 5433 -d marius

# 2. Injection des données du registre (Intentions de densité)
cat meta_data.sql | sudo -u postgres psql -p 5433 -d marius

# 3. Compilation des fonctions et vues de la sentinelle
cat tools/v_performance_sentinel.sql | sudo -u postgres psql -p 5433 -d marius
cat tools/v_master_health_audit.sql | sudo -u postgres psql -p 5433 -d marius

# Lancez un ANALYZE global pour recalibrer la sentinelle :
sudo -u postgres psql -p 5433 -d marius -c "ANALYZE;"

# Lancez l'audit final :
sudo -u postgres psql -p 5433 -d marius -c "SELECT * FROM meta.v_master_health_audit;"
```

