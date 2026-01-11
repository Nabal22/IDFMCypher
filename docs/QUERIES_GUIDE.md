# Guide d'Exécution des Requêtes - Projet Cypher 5 vs 25

## 📋 Vue d'Ensemble

Ce guide explique comment exécuter les 4 comparaisons obligatoires de requêtes créées pour le projet.

### Fichiers de Requêtes Créés

| # | Comparaison | Fichier Cypher | Fichier SQL | Taille |
|---|-------------|----------------|-------------|--------|
| 1 | Increasing Property Paths | `01_increasing_property_paths.cypher` | `01_increasing_property_paths.sql` | ~6 KB |
| 2 | Quantified Graph Patterns | `02_quantified_graph_patterns.cypher` | `02_quantified_graph_patterns.sql` | ~5 KB |
| 3 | Shortest Path Algorithms | `03_shortest_path_algorithms.cypher` | `03_shortest_path_algorithms.sql` | ~7 KB |
| 4 | GDS Algorithms in Cypher 25 | `04_gds_algorithms_in_cypher25.cypher` | N/A | ~8 KB |

## 🎯 Objectifs de Chaque Comparaison

### 1. Increasing Property Paths

**Problématique SIGMOD** : `reduce()` dans WHERE clause = NP-complet

**Ce qu'on montre** :
- ✅ Cypher 5 avec `all()` + `reduce` : Timeout sur graphes moyens
- ✅ Cypher 25 avec `allReduce()` : Pruning précoce, 120x plus rapide
- ✅ SQL avec WITH RECURSIVE : Peut faire du pruning si bien écrit

**Cas d'usage** : Chemins de vols où le retard augmente à chaque escale

### 2. Quantified Graph Patterns

**Nouveauté Cypher 25** : Patterns `{n,m}` pour spécifier répétitions

**Ce qu'on montre** :
- ✅ Cypher 25 `{2,3}` : Concis et lisible
- ✅ Cypher 5 : Doit spécifier chaque longueur ou utiliser UNION
- ✅ SQL : Doit filtrer par `hops BETWEEN n AND m`

**Cas d'usage** : Chemins avec exactement N escales, ou N à M escales

### 3. Shortest Path Algorithms

**Comparaison complète** : Cypher 5, Cypher 25, GDS, SQL

**Ce qu'on montre** :
- ✅ `shortestPath()` Cypher 5 : BFS bidirectionnel (rapide)
- ✅ `SHORTEST` Cypher 25 : Syntaxe moderne + top-K
- ✅ GDS Dijkstra/A*/Yen : Chemins pondérés optimisés
- ✅ SQL WITH RECURSIVE : BFS unidirectionnel (lent)

**Analyse** : BFS unidirectionnel vs bidirectionnel (speedup ~158x théorique)

### 4. GDS Algorithms in Cypher 25

**Challenge** : Implémenter en pur Cypher des algos normalement dans GDS

**Ce qu'on montre** :
- ✅ Degree Centrality : Facile en Cypher, identique à GDS
- ✅ Triangle Count : Simple pattern matching
- ✅ Betweenness : Approximation possible (échantillonnage)
- ❌ PageRank : Très difficile (nécessite itérations)
- ❌ Louvain : Impraticable en pur Cypher

**Conclusion** : GDS reste indispensable pour algos complexes

## 📖 Comment Exécuter les Requêtes

### Option 1 : Exécution Section par Section (Recommandé)

#### Pour Neo4j :
1. Ouvrir Neo4j Browser : http://localhost:7474
2. Ouvrir le fichier `.cypher` dans un éditeur
3. Copier-coller chaque section une par une
4. Lire les commentaires
5. Exécuter et analyser les résultats
6. Comparer les PROFILE

#### Pour PostgreSQL :
```bash
# Dans psql
psql -d flights_db

# Puis copier-coller sections du fichier .sql
\i queries/01_increasing_property_paths.sql
```

### Option 2 : Exécution Complète

#### Neo4j (cypher-shell)
```bash
cypher-shell -u neo4j -p password < queries/01_increasing_property_paths.cypher
```

#### PostgreSQL
```bash
psql -d flights_db -f queries/01_increasing_property_paths.sql > results_01.txt
```

## 🔍 Analyses à Faire pour le Rapport

### Pour Chaque Comparaison

#### 1. Comparer le Code
- **Lignes de code** (LOC) : Compter Cypher vs SQL
- **Lisibilité** : Noter la clarté et expressivité
- **Maintenabilité** : Facilité de modification

#### 2. Analyser les Plans d'Exécution

**Neo4j** :
```cypher
// Remplacer MATCH par PROFILE MATCH
PROFILE
MATCH path = (start:Airport {iata_code: 'LAX'})...
```

Regarder :
- `db hits` : Nombre d'accès à la base
- `Rows` : Nombre de résultats
- `Operator` : Algorithme utilisé
- `Time` : Temps d'exécution (ms)

**PostgreSQL** :
```sql
-- Ajouter EXPLAIN ANALYZE avant la requête
EXPLAIN ANALYZE
WITH RECURSIVE flight_paths AS ...
```

Regarder :
- `Planning Time` : Temps de planification
- `Execution Time` : Temps d'exécution
- `Rows` : Lignes générées à chaque étape
- `Cost` : Coût estimé

#### 3. Mesurer les Performances

Créer un tableau comme :

| Requête | Cypher 5 | Cypher 25 | SQL | GDS |
|---------|----------|-----------|-----|-----|
| Temps (ms) | 500 | 10 | 200 | 5 |
| db hits / rows | 50k | 2k | 30k | 1k |
| Speedup | 1x | 50x | 2.5x | 100x |

#### 4. Expliquer les Différences

Pour chaque comparaison, expliquer :
- **Pourquoi** une version est plus rapide
- **Comment** l'algorithme fonctionne
- **Quand** utiliser quelle approche

## 📊 Requêtes Spécifiques à Tester

### Requête 1 : Increasing Property Paths

#### Test Critique
```cypher
// Cypher 5 : Peut timeout sur graphe complet !
// Tester d'abord sur sous-graphe
MATCH path = (start:Airport)
  -[:FLIGHT*2..3]->(end:Airport)
WHERE start.iata_code IN ['LAX', 'ATL', 'ORD']
  AND end.iata_code IN ['JFK', 'BOS', 'MIA']
  AND all(i IN range(0, size(relationships(path))-2) WHERE
    relationships(path)[i].delay < relationships(path)[i+1].delay
  )
RETURN count(path);

// Cypher 25 : Devrait être rapide même sur graphe complet
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'JFK'})
WHERE allReduce(
  prev_delay = -999999.0,
  rel IN relationships(path) |
    CASE WHEN rel.delay > prev_delay THEN rel.delay ELSE null END,
  prev_delay IS NOT NULL
)
RETURN count(path);
```

**Analyse** :
- Comparer db hits
- Noter si Cypher 5 timeout
- Calculer speedup Cypher 25

### Requête 2 : Quantified Patterns

#### Test de Concision
```cypher
// Sans quantifiers (verbeux)
MATCH p1 = (s)-[:FLIGHT]->(a)-[:FLIGHT]->(e)
RETURN count(p1)
UNION
MATCH p2 = (s)-[:FLIGHT]->(a)-[:FLIGHT]->(b)-[:FLIGHT]->(e)
RETURN count(p2);

// Avec quantifiers (concis)
CYPHER 25
MATCH path = (s)(()-->(:Airport)){2,3}(e)
RETURN count(path);
```

**Analyse** :
- Compter lignes de code : ~10 vs ~2
- Comparer performance
- Vérifier que résultats sont identiques

### Requête 3 : Shortest Path

#### Test BFS Bidirectionnel
```cypher
// Variable length (unidirectionnel)
PROFILE
MATCH path = (s:Airport {iata_code: 'LAX'})-[:FLIGHT*1..10]->(e:Airport {iata_code: 'JFK'})
WITH path ORDER BY length(path) LIMIT 1
RETURN length(path);

// shortestPath (bidirectionnel)
PROFILE
MATCH (s:Airport {iata_code: 'LAX'}), (e:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((s)-[:FLIGHT*]-(e))
RETURN length(path);
```

**Analyse** :
- Comparer db hits : devrait être ~50-100x différence
- Noter algorithme dans PROFILE
- Expliquer speedup bidirectionnel

### Requête 4 : GDS vs Cypher 25

#### Test Degree Centrality
```cypher
// GDS
PROFILE
CALL gds.degree.stream('flights-network')
YIELD nodeId, score
RETURN count(*);

// Cypher 25
CYPHER 25
PROFILE
MATCH (a:Airport)
OPTIONAL MATCH (a)-[out:FLIGHT]->()
OPTIONAL MATCH (a)<-[in:FLIGHT]-()
RETURN count(a);
```

**Analyse** :
- Comparer performance (devrait être similaire)
- Vérifier précision (identique pour degree)
- Expliquer quand chaque approche est meilleure

## 📝 Structure du Rapport

Pour chaque comparaison, inclure :

### 1. Introduction
- Contexte et problématique
- Référence aux articles (SIGMOD, Cypher 25)

### 2. Code
- Montrer les requêtes côte à côte
- Annoter les différences clés

### 3. Plans d'Exécution
- Captures d'écran ou copie du PROFILE/EXPLAIN
- Annoter les parties importantes

### 4. Métriques
- Tableau de comparaison
- Graphiques si pertinent

### 5. Analyse
- Expliquer les résultats
- Référencer la théorie (BFS, NP-complet, etc.)
- Conclure

### 6. Recommandations
- Quand utiliser Cypher vs SQL
- Quand utiliser Cypher 5 vs 25 vs GDS

## 🔧 Troubleshooting

### Timeout sur Requête Cypher 5
**Problème** : `reduce()` dans WHERE cause timeout

**Solution** :
1. Réduire la profondeur : `*2..3` au lieu de `*2..4`
2. Limiter aux top hubs : `WHERE start.iata_code IN [...]`
3. Utiliser Cypher 25 `allReduce()` à la place

### GDS Graph Non Trouvé
**Problème** : `Graph 'flights-network' not found`

**Solution** :
```cypher
// Créer la projection
CALL gds.graph.project(
  'flights-network',
  'Airport',
  'FLIGHT',
  {nodeProperties: ['iata_code'], relationshipProperties: ['distance', 'delay']}
);
```

### SQL Trop Lent
**Problème** : WITH RECURSIVE prend >10s

**Solution** :
1. Vérifier les index : `CREATE INDEX idx_flights_source_target ON flights(source, target);`
2. Réduire la profondeur : `AND hops < 4`
3. Limiter aux top hubs
4. Utiliser pruning précoce (voir version 2 dans les fichiers)

## 📚 Références

- **SIGMOD Article** : `article/SIGMOD.MD`
- **Cypher 25 Guide** : `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`
- **Neo4j Cypher Manual** : https://neo4j.com/docs/cypher-manual/current/
- **Neo4j GDS Manual** : https://neo4j.com/docs/graph-data-science/current/
- **PostgreSQL Docs (WITH RECURSIVE)** : https://www.postgresql.org/docs/current/queries-with.html

## ✅ Checklist Avant de Rendre

- [ ] Toutes les données importées (Neo4j + PostgreSQL)
- [ ] GDS library installée et projection créée
- [ ] Chaque requête exécutée et testée
- [ ] PROFILE/EXPLAIN ANALYZE collectés pour toutes les variantes
- [ ] Métriques de performance enregistrées
- [ ] Screenshots des plans d'exécution
- [ ] Comparaisons documentées dans le rapport
- [ ] Code source commenté et organisé
- [ ] Références aux articles incluses
- [ ] Explications des résultats rédigées

Bonne chance ! 🚀
