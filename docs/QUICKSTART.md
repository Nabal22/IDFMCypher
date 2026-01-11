# Guide de Démarrage Rapide

## 📋 Checklist de Mise en Route

### 1. Vérifier les Données
```bash
# Depuis la racine du projet
ls -lh import/
# Devrait afficher:
# - airlines.csv (359 bytes, 14 compagnies)
# - airports_projet.csv (~23 KB, 313 aéroports)
# - flights_projet.csv (~6.5 MB, 107,230 vols)
```

### 2. Préparer Neo4j

1. Télécharger Neo4j Desktop : https://neo4j.com/download/
2. Créer une nouvelle base de données
3. Démarrer la base de données
4. Copier les fichiers CSV dans le répertoire d'import :
   ```bash
   # Trouver le chemin d'import
   # Dans Neo4j Browser, exécuter:
   CALL dbms.listConfig() YIELD name, value
   WHERE name = 'dbms.directories.import'
   RETURN value;

   # Puis copier les fichiers
   cp import/*.csv <chemin_retourné>/
   ```

### 3. Importer les Données

#### Via Neo4j Browser (Simple)
1. Ouvrir http://localhost:7474
2. Se connecter (neo4j / your_password)
3. Copier-coller le contenu de `import_neo4j.cypher` section par section
4. Vérifier après chaque section

### 4. Préparer PostgreSQL

```bash
# 1. Créer la base de données
createdb flights_db

# 2. Exécuter le script d'import (tables + données + index)
psql -U user -d flights_db -f import_postgresql.sql

# Lancer l'import
cd scripts
python import_to_neo4j.py
```