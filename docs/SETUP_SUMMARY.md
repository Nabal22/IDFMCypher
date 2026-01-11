# Résumé de la Configuration - Projet Cypher 5 vs 25

## ✅ Statut Actuel

### Données
- ✅ **Dataset nettoyé** : 107,230 vols (1-7 janvier 2015)
- ✅ **Aéroports** : 312 aéroports US avec coordonnées GPS
- ✅ **Compagnies** : 14 compagnies aériennes
- ✅ **Correction des données** : 3 aéroports avec coordonnées manquantes corrigées (ECP, PBG, UST)

### PostgreSQL
- ✅ **Base de données créée** : `flights_db`
- ✅ **Tables créées** : `airlines`, `airports`, `flights`
- ✅ **Vues créées** : `flights_detailed`, `airport_stats`, `airline_stats`
- ✅ **Index créés** : 12 index pour optimisation
- ✅ **Données importées** : 107,230 vols + 312 aéroports + 14 compagnies
- ✅ **Taille totale** : ~28 MB

### Neo4j
- 🔄 **Prêt pour import**
- 📄 Scripts d'import créés (`import_neo4j.cypher`, `scripts/import_to_neo4j.py`)
- 📄 Documentation complète (`IMPORT_INSTRUCTIONS.md`)

## 📁 Fichiers Créés

### Scripts d'Import

1. **`import_postgresql.sql`** (7.5 KB)
   - Création des tables PostgreSQL
   - Import via `\COPY`
   - Création des index et vues
   - Requêtes de validation

2. **`import_neo4j.cypher`** (3.3 KB)
   - Import des nœuds (Airport, Airline)
   - Import des relations (FLIGHT)
   - Contraintes et index
   - Requêtes de vérification

3. **`scripts/import_to_postgresql.py`** (10 KB)
   - Import automatisé via psycopg2
   - Gestion des batches (1000 vols)
   - Progress tracking
   - Création automatique de la base

4. **`scripts/import_to_neo4j.py`** (9.3 KB)
   - Import automatisé via driver Neo4j
   - Gestion des batches
   - Statistiques en temps réel

### Documentation

5. **`POSTGRESQL_INSTRUCTIONS.md`** (8.5 KB)
   - Guide d'installation PostgreSQL
   - 3 méthodes d'import
   - Schéma complet de la base
   - Requêtes exemples (WITH RECURSIVE)
   - Comparaison PostgreSQL vs Neo4j
   - Troubleshooting

6. **`IMPORT_INSTRUCTIONS.md`** (4.5 KB)
   - Instructions d'import Neo4j
   - Configuration requise
   - Troubleshooting Neo4j

7. **`QUICKSTART.md`** (5.6 KB)
   - Checklist de démarrage rapide
   - Exemples de requêtes intéressantes
   - Roadmap du projet

8. **`DATA_MODEL.md`** (8.9 KB)
   - Schéma du graphe (diagramme ASCII)
   - Détail des propriétés
   - Patterns de requêtes courants
   - Considérations de performance

9. **`SETUP_SUMMARY.md`** (ce fichier)
   - Résumé de tout ce qui a été fait

### Requêtes de Validation

10. **`queries/00_validation.cypher`** (6.3 KB)
    - 40+ requêtes de validation Neo4j
    - Statistiques, analyses, tests

11. **`queries/00_validation.sql`** (8.7 KB)
    - 50+ requêtes de validation PostgreSQL
    - Incluant WITH RECURSIVE pour chemins

## 🗄️ Modèle de Données

### PostgreSQL (Relationnel)

```
airlines (14 rows)
├─ iata_code (PK)
└─ name

airports (312 rows)
├─ iata_code (PK)
├─ name, city, state, country
└─ latitude, longitude

flights (107,230 rows)
├─ id (PK, SERIAL)
├─ source (FK → airports)
├─ target (FK → airports)
├─ airline (FK → airlines)
├─ departure_ts, arrival_ts
├─ distance, delay
└─ constraints: source ≠ target, distance > 0
```

### Neo4j (Graphe)

```
(:Airport) - 312 nœuds
├─ iata_code (unique)
├─ name, city, state, country
└─ latitude, longitude

(:Airline) - 14 nœuds
├─ iata_code (unique)
└─ name

[:FLIGHT] - 107,230 relations
├─ airline, airline_name
├─ departure_ts, arrival_ts (datetime)
├─ distance (integer)
└─ delay (float)
```

## 📊 Statistiques du Dataset

### Top 5 Hubs (par nombre total de vols)

| Code | Ville | État | Vols |
|------|-------|------|------|
| ATL | Atlanta | GA | 13,296 |
| DFW | Dallas-Fort Worth | TX | 10,221 |
| ORD | Chicago | IL | 10,141 |
| DEN | Denver | CO | 8,269 |
| LAX | Los Angeles | CA | 8,170 |

### Top 5 Compagnies (par nombre de vols)

| Code | Nom | Vols | Retard Moyen |
|------|-----|------|--------------|
| WN | Southwest Airlines | 23,061 | 21.2 min |
| DL | Delta Air Lines | 14,471 | 10.5 min |
| EV | Atlantic Southeast | 11,459 | 21.6 min |
| OO | Skywest Airlines | 11,021 | 20.5 min |
| AA | American Airlines | 10,087 | 23.2 min |

### Distribution Temporelle

- **Période** : 7 jours (1-7 janvier 2015)
- **Vols/jour** : ~15,318 vols en moyenne
- **Heure de pointe** : Entre 6h et 20h
- **Retard moyen global** : ~18 minutes

### Distribution Géographique

- **Vol le plus long** : ~2,500+ miles
- **Vol le plus court** : ~79 miles
- **Distance moyenne** : ~850 miles
- **États couverts** : 50 états + DC

## 🎯 Prochaines Étapes

### Phase 1 : Import Neo4j
```bash
# Copier les CSV dans le répertoire Neo4j import
# Exécuter import_neo4j.cypher
# Vérifier avec queries/00_validation.cypher
```

### Phase 2 : Création des 6 Requêtes Comparatives

#### 1. Increasing Property Paths
- **Cypher 5** : `NOT EXISTS` + `reduce`
- **Cypher 25** : `allReduce()`
- **SQL** : `WITH RECURSIVE` avec conditions

#### 2. Quantified Graph Patterns
- **Cypher 25** : Patterns quantifiés `{n,m}`
- **Cypher 5** : N/A (utiliser variable length patterns)
- **SQL** : Simulation complexe

#### 3. Shortest Path Algorithms
- **Cypher 5** : `shortestPath()`
- **Cypher 25** : `SHORTEST`
- **Neo4j GDS** : `gds.shortestPath.*`
- **SQL** : Dijkstra manuel avec RECURSIVE

#### 4. GDS Algorithms in Cypher 25
- **PageRank** : Identifier les hubs
- **Betweenness** : Aéroports critiques
- **Community Detection** : Régions connectées

#### 5. SQL Comparisons
- **Chemins multi-sauts** : RECURSIVE vs Cypher patterns
- **Agrégations** : GROUP BY vs MATCH + WITH
- **Performance** : EXPLAIN vs PROFILE

#### 6. Execution Plans
- **BFS unidirectionnel** vs **bidirectionnel**
- **Index usage** : B-tree vs Neo4j indexes
- **Memory consumption**

### Phase 3 : Rapport (RAPPORT.md)

Structure suggérée :

```markdown
# 1. Introduction
- Contexte du projet
- Objectifs : comparer Cypher 5, 25 et SQL

# 2. Modélisation
- Choix graphe vs relationnel
- Justification du modèle
- Contraintes métier

# 3. Import et Préparation
- Nettoyage des données (normalize_data.py)
- Corrections (coordonnées GPS)
- PostgreSQL : tables, index, vues
- Neo4j : nœuds, relations, contraintes

# 4. Les 6 Comparaisons Obligatoires
Pour chaque comparaison :
- Cas d'usage concret sur les vols
- Code Cypher 5 / 25 / SQL
- Execution plans (PROFILE / EXPLAIN)
- Analyse des performances
- Explication des différences

# 5. Problèmes NP-Complets (SIGMOD)
- Exemples de patterns problématiques
- Impact sur nos données
- Solutions Cypher 25

# 6. Conclusions
- Quand utiliser Cypher vs SQL
- Forces et faiblesses
- Recommandations
```

## 🔧 Commandes Utiles

### PostgreSQL

```bash
# Se connecter
psql -d flights_db

# Exécuter un fichier
psql -d flights_db -f queries/00_validation.sql

# Exporter les résultats
psql -d flights_db -c "SELECT * FROM airport_stats ORDER BY total_flights DESC LIMIT 10" -o results.txt

# Taille de la base
psql -d flights_db -c "SELECT pg_size_pretty(pg_database_size('flights_db'));"
```

### Neo4j

```bash
# Via cypher-shell
cypher-shell -u neo4j -p password

# Exécuter un fichier
cypher-shell -u neo4j -p password < import_neo4j.cypher

# Via Neo4j Browser
# http://localhost:7474
```

## 📚 Ressources Créées

- ✅ 11 fichiers de documentation
- ✅ 4 scripts d'import (2 SQL, 2 Python)
- ✅ 2 fichiers de validation (Cypher + SQL)
- ✅ 1 modèle de données complet
- ✅ Structure de projet organisée

## 🎓 Pour le Rapport

### Points Clés à Mentionner

1. **Problème NP-complet de SIGMOD**
   - `reduce` en Cypher 5 → explosion combinatoire
   - `allReduce` en Cypher 25 → optimisé
   - Exemples concrets sur chemins de vols

2. **Différences d'Expressivité**
   - Pattern matching Cypher vs JOIN SQL
   - Variable length paths natifs
   - Lisibilité et maintenance

3. **Performances**
   - Index usage (B-tree vs Neo4j)
   - Plans d'exécution (BFS strategies)
   - Memory footprint

4. **Cas d'Usage Appropriés**
   - Graphe : chemins, connexité, algorithmes
   - SQL : agrégations, transactions, reporting

### Métriques à Collecter

- ✅ Temps d'exécution (ms)
- ✅ Nombre de db hits
- ✅ Memory utilisée
- ✅ Lignes de code (complexité)
- ✅ Lisibilité (subjective mais important)

## 🚀 État d'Avancement

- [x] Nettoyage des données
- [x] Import PostgreSQL
- [x] Documentation PostgreSQL
- [ ] Import Neo4j
- [ ] Requêtes Cypher 5
- [ ] Requêtes Cypher 25
- [ ] Requêtes SQL comparatives
- [ ] Analyse des plans d'exécution
- [ ] Mesures de performance
- [ ] Rédaction du rapport

**Progression : 35% ✅**
