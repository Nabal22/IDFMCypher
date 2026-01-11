# Projet : Comparaison Cypher 5 vs Cypher 25

Projet de Master en bases de données comparant les performances et l'expressivité des langages de requêtes Cypher 5, Cypher 25 et SQL sur un dataset de vols aériens.

## 📊 Dataset

**US Flight Delays 2015** (source : Kaggle / US DOT)
- 📅 Période : 1-7 janvier 2015 (première semaine)
- ✈️ Vols : 107,230
- 🏢 Aéroports : 312 (US)
- 🛫 Compagnies : 14

## 🎯 Objectifs

1. Comparer Cypher 5 vs Cypher 25 (problèmes NP-complets)
2. Analyser les patterns problématiques identifiés dans SIGMOD
3. Comparer performances graphe (Neo4j) vs relationnel (PostgreSQL)
4. Étudier 6 cas d'usage obligatoires
5. Documenter les plans d'exécution et optimisations

## 🚀 Démarrage Rapide

### 1. PostgreSQL (✅ Déjà fait)

```bash
# La base est déjà créée et peuplée
psql -d flights_db

# Vérifier
\dt  # Voir les tables
\dv  # Voir les vues
SELECT COUNT(*) FROM flights;  # 107230

# Requêtes de validation
\i queries/00_validation.sql
```

### 2. Neo4j (🔄 À faire)

Voir `IMPORT_INSTRUCTIONS.md` ou `QUICKSTART.md`

```bash
# Méthode rapide : Neo4j Browser
# 1. Copier les CSV dans le répertoire Neo4j import/
# 2. Exécuter import_neo4j.cypher

# Méthode alternative : Python
python scripts/import_to_neo4j.py
```

## 📁 Structure du Projet

```
IDFMCypher/
├── source/                   # Données brutes Kaggle
│   ├── flights.csv          # Dataset complet (5M+ lignes)
│   ├── airports.csv         # 323 aéroports
│   └── airlines.csv         # 14 compagnies
│
├── import/                   # Données nettoyées
│   ├── flights_projet.csv   # 107,230 vols (1-7 jan 2015)
│   ├── airports_projet.csv  # 312 aéroports utilisés
│   └── airlines.csv         # 14 compagnies
│
├── scripts/                  # Scripts de traitement
│   ├── normalize_data.py    # Nettoyage et filtrage
│   ├── import_to_postgresql.py
│   └── import_to_neo4j.py
│
├── queries/                  # Requêtes de validation
│   ├── 00_validation.sql    # PostgreSQL
│   └── 00_validation.cypher # Neo4j
│
├── article/                  # Articles de référence
│   ├── SIGMOD.MD           # Synthèse problèmes NP
│   ├── SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD
│   └── QUERY_CHOMP_REPEAT.MD
│
├── import_postgresql.sql     # Script d'import PostgreSQL
├── import_neo4j.cypher      # Script d'import Neo4j
│
├── CLAUDE.MD                # Instructions pour Claude Code
├── CONSIGNES.MD             # Consignes du projet
├── RAPPORT.md               # Rapport (à rédiger)
│
└── Documentation/
    ├── QUICKSTART.md        # Guide de démarrage
    ├── IMPORT_INSTRUCTIONS.md      # Import Neo4j
    ├── POSTGRESQL_INSTRUCTIONS.md  # Import PostgreSQL
    ├── DATA_MODEL.md        # Modèle de données détaillé
    └── SETUP_SUMMARY.md     # Résumé complet
```

## 🗄️ Modèle de Données

### PostgreSQL (Relationnel)

```sql
airlines (14)  ──┐
                 │
airports (312) ──┼── flights (107,230)
                 │
                 └── avec FK constraints
```

### Neo4j (Graphe)

```
(:Airport)-[:FLIGHT {
  airline, departure_ts, arrival_ts,
  distance, delay
}]->(:Airport)

(:Airline)
```

## 📚 Documentation

| Fichier | Description | Taille |
|---------|-------------|--------|
| `QUICKSTART.md` | Guide de démarrage rapide | 5.6 KB |
| `POSTGRESQL_INSTRUCTIONS.md` | Guide PostgreSQL complet | 8.3 KB |
| `IMPORT_INSTRUCTIONS.md` | Guide import Neo4j | 4.5 KB |
| `DATA_MODEL.md` | Schéma et patterns | 8.9 KB |
| `SETUP_SUMMARY.md` | Résumé de la config | 8.5 KB |

## 🎓 Les 6 Comparaisons Obligatoires

### 1. Increasing Property Paths
- **Cypher 5** : `NOT EXISTS` + `reduce` (problématique)
- **Cypher 25** : `allReduce()` (optimisé)
- **SQL** : `WITH RECURSIVE` + conditions

**Cas d'usage** : Trouver des chemins de vols où le retard augmente à chaque escale

### 2. Quantified Graph Patterns
- **Cypher 25** : `{n,m}` quantifiers
- **Cypher 5** : Simulation avec variable length
- **SQL** : Complexe

**Cas d'usage** : Chemins avec exactement 2 escales

### 3. Shortest Path Algorithms
- **Cypher 5** : `shortestPath()`
- **Cypher 25** : `SHORTEST` keyword
- **Neo4j GDS** : `gds.shortestPath.*`
- **SQL** : Dijkstra manuel

**Cas d'usage** : Plus court chemin LAX → JFK (par distance, par temps, par nombre d'escales)

### 4. GDS Algorithms in Cypher 25
- **PageRank** : Identifier les hubs majeurs
- **Betweenness** : Aéroports critiques pour la connectivité
- **Community Detection** : Régions géographiques connectées

### 5. SQL Comparisons
- **Chemins multi-sauts** : RECURSIVE vs patterns
- **Performances** : JOIN vs MATCH
- **Expressivité** : Lisibilité du code

**Cas d'usage** : Tous les chemins possibles avec max 2 escales

### 6. Execution Plans
- **BFS** : Unidirectionnel vs bidirectionnel
- **Index usage** : B-tree vs Neo4j native
- **Memory** : Consommation et optimisations

**Outils** : `EXPLAIN ANALYZE` (PostgreSQL) vs `PROFILE` (Neo4j)

## 🔬 Problèmes NP-Complets (SIGMOD)

### Le Problème
Cypher 5 utilise `reduce()` dans les `WHERE` clauses, ce qui peut créer des requêtes NP-complètes :
- **Hamiltonian path** : timeout à ≥10 nœuds
- **Subset sum** : timeout à ≥27 nœuds
- **93% des développeurs** sous-estiment le coût

### La Solution (Cypher 25)
- `allReduce()` : Optimisé pour les prédicats
- Quantified patterns : `{n,m}`
- Constructions dédiées pour patterns courants

### Sur Nos Données
Exemples concrets avec le réseau de vols :
- Chemins avec contraintes de retard
- Correspondances valides (temps minimum)
- Optimisation de routes

## 📊 Statistiques du Dataset

### Top 5 Hubs
1. **ATL** (Atlanta) : 13,296 vols
2. **DFW** (Dallas-Fort Worth) : 10,221 vols
3. **ORD** (Chicago) : 10,141 vols
4. **DEN** (Denver) : 8,269 vols
5. **LAX** (Los Angeles) : 8,170 vols

### Top 3 Compagnies
1. **Southwest** (WN) : 23,061 vols (21.2 min retard moyen)
2. **Delta** (DL) : 14,471 vols (10.5 min retard moyen)
3. **Atlantic Southeast** (EV) : 11,459 vols (21.6 min retard moyen)

### Retards
- **Retard moyen** : ~18 minutes
- **Vol le plus en retard** : +900 minutes
- **Vol le plus en avance** : -50 minutes

## 🛠️ Commandes Utiles

### PostgreSQL
```bash
# Se connecter
psql -d flights_db

# Statistiques rapides
SELECT * FROM airport_stats ORDER BY total_flights DESC LIMIT 10;
SELECT * FROM airline_stats ORDER BY total_flights DESC;

# Requêtes de validation
\i queries/00_validation.sql
```

### Neo4j
```cypher
// Statistiques rapides
MATCH (a:Airport) RETURN count(a);
MATCH ()-[f:FLIGHT]->() RETURN count(f);

// Top hubs
MATCH (a:Airport)-[f:FLIGHT]->()
RETURN a.iata_code, count(f) as flights
ORDER BY flights DESC LIMIT 10;

// Requêtes de validation
:source queries/00_validation.cypher
```

## 🎯 Prochaines Étapes

- [x] ✅ Nettoyage des données
- [x] ✅ Import PostgreSQL
- [x] ✅ Documentation complète
- [ ] 🔄 Import Neo4j
- [ ] 🔄 Requêtes Cypher 5
- [ ] 🔄 Requêtes Cypher 25
- [ ] 🔄 Comparaison SQL
- [ ] 🔄 Analyse des plans d'exécution
- [ ] 🔄 Mesures de performance
- [ ] 🔄 Rédaction du rapport

**Progression : 35%**

## 📖 Références

- **SIGMOD Article** : `article/SIGMOD.MD`
- **Cypher 25 Guide** : `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`
- **Dataset** : [Kaggle - 2015 Flight Delays](https://www.kaggle.com/datasets/usdot/flight-delays)
- **Neo4j Docs** : https://neo4j.com/docs/
- **PostgreSQL Docs** : https://www.postgresql.org/docs/

## 👨‍💻 Auteur

Projet de Master en Bases de Données
- **Dataset** : US Flight Delays 2015 (Kaggle)
- **Technologies** : PostgreSQL 14, Neo4j, Python
- **Objectif** : Comparaison Cypher 5 vs Cypher 25

---

**Note** : Voir `QUICKSTART.md` pour commencer rapidement !
