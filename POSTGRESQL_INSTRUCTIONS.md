# Instructions d'Import PostgreSQL

## Préparation

### 1. Installer PostgreSQL

#### Mac (Homebrew)
```bash
brew install postgresql@14
brew services start postgresql@14
```

#### Linux (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

#### Windows
Télécharger depuis : https://www.postgresql.org/download/windows/

### 2. Vérifier l'Installation

```bash
# Vérifier que PostgreSQL tourne
pg_isready

# Version installée
psql --version
```

## Import des Données

### Méthode 1 : Via Script SQL (Recommandé)

```bash
# 1. Créer la base de données
createdb flights_db

# 2. Exécuter le script d'import
psql -d flights_db -f import_postgresql.sql

# 3. Vérifier l'import
psql -d flights_db -c "SELECT COUNT(*) FROM flights;"
```

### Méthode 2 : Via Python

```bash
# 1. Installer psycopg2
pip install psycopg2-binary

# 2. Modifier le mot de passe dans le script
nano scripts/import_to_postgresql.py
# Changer: DB_CONFIG['password'] = 'your_password'

# 3. Exécuter l'import
cd scripts
python import_to_postgresql.py
```

### Méthode 3 : Pas à Pas (PostgreSQL Interactive)

```bash
# Se connecter à PostgreSQL
psql

# Créer la base
CREATE DATABASE flights_db;

# Se connecter à la base
\c flights_db

# Exécuter le script
\i import_postgresql.sql
```

## Résultats Attendus

Après l'import :

- **14 compagnies** aériennes
- **312 aéroports**
- **107,230 vols**

### Vérification Rapide

```sql
-- Statistiques générales
SELECT 'Airlines' AS table_name, COUNT(*) AS count FROM airlines
UNION ALL
SELECT 'Airports', COUNT(*) FROM airports
UNION ALL
SELECT 'Flights', COUNT(*) FROM flights;

-- Top 5 des hubs
SELECT
    iata_code,
    city,
    total_flights
FROM airport_stats
ORDER BY total_flights DESC
LIMIT 5;

-- Compagnies avec le plus de vols
SELECT * FROM airline_stats
ORDER BY total_flights DESC;
```

## Schéma de la Base de Données

### Tables

#### `airlines`
```sql
CREATE TABLE airlines (
    iata_code VARCHAR(2) PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);
```

#### `airports`
```sql
CREATE TABLE airports (
    iata_code VARCHAR(3) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL,
    country VARCHAR(50) NOT NULL,
    latitude DECIMAL(10, 6) NOT NULL,
    longitude DECIMAL(10, 6) NOT NULL
);
```

#### `flights`
```sql
CREATE TABLE flights (
    id SERIAL PRIMARY KEY,
    source VARCHAR(3) NOT NULL REFERENCES airports(iata_code),
    target VARCHAR(3) NOT NULL REFERENCES airports(iata_code),
    airline VARCHAR(2) NOT NULL REFERENCES airlines(iata_code),
    departure_ts TIMESTAMP NOT NULL,
    arrival_ts TIMESTAMP NOT NULL,
    distance INTEGER NOT NULL,
    delay DECIMAL(10, 2),
    CONSTRAINT chk_different_airports CHECK (source != target),
    CONSTRAINT chk_positive_distance CHECK (distance > 0)
);
```

### Vues

#### `flights_detailed`
Vue avec toutes les informations des vols (jointures effectuées).

```sql
SELECT * FROM flights_detailed LIMIT 10;
```

#### `airport_stats`
Statistiques par aéroport (départs, arrivées, retards moyens).

```sql
SELECT * FROM airport_stats
ORDER BY total_flights DESC
LIMIT 10;
```

#### `airline_stats`
Statistiques par compagnie (vols, retards, distances).

```sql
SELECT * FROM airline_stats
ORDER BY total_flights DESC;
```

## Index Créés

Pour optimiser les performances :

- `idx_airports_city` : Recherche par ville
- `idx_airports_state` : Recherche par état
- `idx_airports_location` : Recherche géographique (latitude, longitude)
- `idx_flights_source` : Recherche par aéroport de départ
- `idx_flights_target` : Recherche par aéroport d'arrivée
- `idx_flights_airline` : Recherche par compagnie
- `idx_flights_departure_ts` : Recherche par horaire de départ
- `idx_flights_arrival_ts` : Recherche par horaire d'arrivée
- `idx_flights_delay` : Recherche par retard
- `idx_flights_distance` : Recherche par distance
- `idx_flights_source_target` : Recherche de routes
- `idx_flights_departure_date` : Recherche par date

## Requêtes Utiles

### Chemins avec WITH RECURSIVE

Trouver tous les chemins possibles entre deux aéroports :

```sql
WITH RECURSIVE flight_paths AS (
    -- Vols directs depuis LAX
    SELECT
        source, target,
        ARRAY[source, target] as path,
        1 as hops,
        distance as total_distance
    FROM flights
    WHERE source = 'LAX'

    UNION ALL

    -- Ajouter des vols
    SELECT
        fp.source,
        f.target,
        fp.path || f.target,
        fp.hops + 1,
        fp.total_distance + f.distance
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path)
        AND fp.hops < 3
)
SELECT * FROM flight_paths
WHERE target = 'JFK'
ORDER BY hops, total_distance
LIMIT 10;
```

### Analyse des Retards

```sql
-- Retard moyen par jour de la semaine
SELECT
    EXTRACT(DOW FROM departure_ts) as day_of_week,
    CASE EXTRACT(DOW FROM departure_ts)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_name,
    COUNT(*) as flights,
    AVG(delay) as avg_delay
FROM flights
GROUP BY day_of_week
ORDER BY day_of_week;
```

### Analyse Géographique

```sql
-- Vols les plus longs (distance réelle calculée)
SELECT
    f.source,
    f.target,
    f.distance as reported_distance,
    ROUND(
        111.045 * DEGREES(ACOS(
            LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(src.latitude))
                * COS(RADIANS(dst.latitude))
                * COS(RADIANS(src.longitude - dst.longitude))
                + SIN(RADIANS(src.latitude))
                * SIN(RADIANS(dst.latitude))
            ))
        )) * 0.621371
    ) as calculated_distance_miles
FROM flights f
JOIN airports src ON f.source = src.iata_code
JOIN airports dst ON f.target = dst.iata_code
ORDER BY calculated_distance_miles DESC
LIMIT 10;
```

## Troubleshooting

### Erreur : "database does not exist"

```bash
createdb flights_db
```

### Erreur : "COPY: could not open file"

Le fichier CSV doit être accessible depuis le serveur PostgreSQL.

**Solution 1** : Utiliser un chemin absolu
```sql
\COPY airlines FROM '/absolute/path/to/import/airlines.csv' WITH (FORMAT csv, HEADER true);
```

**Solution 2** : Exécuter depuis le bon répertoire
```bash
cd /Users/albantalagrand/Dev/Master/BDD/IDFMCypher
psql -d flights_db -f import_postgresql.sql
```

### Erreur : "permission denied for database"

```bash
# Donner les droits à votre utilisateur
psql -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE flights_db TO your_username;"
```

### Import très lent

```bash
# Augmenter les paramètres de performance dans postgresql.conf
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 256MB

# Redémarrer PostgreSQL
brew services restart postgresql@14
```

### Voir les requêtes en cours

```sql
SELECT
    pid,
    now() - query_start as duration,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;
```

### Analyser les performances d'une requête

```sql
EXPLAIN ANALYZE
SELECT * FROM flights
WHERE source = 'LAX' AND target = 'JFK';
```

## Comparaison avec Neo4j

### Avantages PostgreSQL
- ✅ Requêtes SQL standard (portable)
- ✅ Transactions ACID robustes
- ✅ Vues matérialisées
- ✅ WITH RECURSIVE pour les chemins
- ✅ Excellent pour les agrégations

### Avantages Neo4j
- ✅ Requêtes de graphe plus expressives
- ✅ Pattern matching naturel
- ✅ Algorithmes de graphe intégrés (GDS)
- ✅ Visualisation du graphe
- ✅ Meilleures performances pour les chemins complexes

### Quand utiliser quoi ?

| Cas d'usage | PostgreSQL | Neo4j |
|-------------|-----------|-------|
| Statistiques agrégées | ✅ Excellent | ⚠️ Bon |
| Chemins simples (1-2 sauts) | ✅ Bon | ✅ Excellent |
| Chemins complexes (3+ sauts) | ⚠️ Avec RECURSIVE | ✅ Natif |
| Requêtes relationnelles | ✅ Natif | ⚠️ Possible |
| Algorithmes de graphe | ❌ Manuel | ✅ GDS library |
| Transactions complexes | ✅ Excellent | ✅ Bon |

## Prochaines Étapes

1. ✅ Données importées dans PostgreSQL
2. 🔄 Créer des requêtes SQL équivalentes aux Cypher
3. 🔄 Comparer les performances (WITH RECURSIVE vs Cypher)
4. 🔄 Analyser les plans d'exécution (EXPLAIN vs PROFILE)
5. 🔄 Documenter les différences dans le rapport
