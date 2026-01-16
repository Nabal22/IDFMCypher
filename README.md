# FlightCypher - Comparaison Cypher 5 vs Cypher 25

Projet de comparaison des performances entre Cypher 5 et Cypher 25 sur des données de vols américains (janvier 2015).

## Prérequis

- Python 3.x avec pandas
- Neo4j 5.x (avec support Cypher 25)
- PostgreSQL 13+
- Dataset Kaggle "2015 Flight Delays and Cancellations"

## Installation des données

### 1. Téléchargement du dataset

Télécharger le dataset depuis Kaggle :
https://www.kaggle.com/datasets/usdot/flight-delays

Extraire les fichiers dans le répertoire `source/` :
- `flights.csv`
- `airports.csv`
- `airlines.csv`

### 2. Nettoyage des données

Générer les fichiers nettoyés pour l'import :

```bash
cd scripts
python normalize_data.py
```

Cette commande génère dans `import/` :
- `flights_projet.csv` (107k vols, 1-7 janvier 2015)
- `airports_projet.csv` (313 aéroports)
- `airlines.csv` (14 compagnies)

## Configuration des bases de données

### Neo4j

1. Démarrer Neo4j et créer une base `flights_graph`

2. Copier les fichiers CSV dans le répertoire d'import Neo4j

3. Importer les données via Neo4j Browser en exécutant le contenu de `import_neo4j.cypher`.

### PostgreSQL

1. Créer la base de données :
```bash
createdb flights_db
```

2. Importer les données :
```bash
psql -d flights_db -f import_postgresql.sql
```

Le script utilise `\COPY` et attend les fichiers dans `import/`.

## Exécution des requêtes

### Requêtes Neo4j

Les fichiers `.cypher` dans `queries/` :

```bash
# Exemple : chemins avec propriété croissante
cat queries/01_increasing_property_paths.cypher | cypher-shell -u neo4j -p password -d flights_graph
```

Ou copier-coller dans Neo4j Browser pour voir les plans d'exécution avec `PROFILE`.

### Requêtes PostgreSQL

Les fichiers `.sql` dans `queries/` :

```bash
# Exemple : chemins avec propriété croissante
psql -d flights_db -f queries/01_increasing_property_paths.sql
```

Pour obtenir le plan d'exécution :
```sql
EXPLAIN ANALYZE [votre requête];
```

## Comparaisons disponibles

1. **01_increasing_property_paths** - Chemins avec retard croissant (Cypher 5 vs 25 vs SQL)
2. **02_quantified_graph_patterns** - Patterns quantifiés (Cypher 5 vs 25)
3. **03_shortest_path_algorithms** - Plus courts chemins pondérés (Cypher vs GDS)
4. **04_gds_algorithms_in_cypher25** - Algorithmes GDS en Cypher pur

## Résultats

Consulter le rapport complet dans `RAPPORT.pdf` pour l'analyse détaillée des performances et des différences entre les approches.
