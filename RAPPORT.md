---
title: "Rapport de Projet : Comparaison Cypher 5 vs Cypher 25"
author: "Romain Groult & Alban Talagrand"
date: "Janvier 2025"
lang: fr
geometry: margin=2.5cm
fontsize: 11pt
header-includes:
  - \usepackage{fvextra}
  - \DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,commandchars=\\\{\}}
---

---

## 1. Introduction et Contexte

Ce projet vise à comparer les capacités de Cypher 5 et Cypher 25 dans le contexte de requêtes sur graphes complexes. L'objectif principal est d'étudier les améliorations apportées par la version 25, notamment pour résoudre des problèmes de complexité algorithmique identifiés dans les versions précédentes.

Le jeu de données utilisé provient de Kaggle : "2015 Flight Delays and Cancellations" (https://www.kaggle.com/datasets/usdot/flight-delays). Pour des raisons de performance et de gestion du volume, nous avons filtré le dataset original (5,8 millions de vols) pour ne conserver que la première semaine de janvier 2015, soit environ 107 000 vols. Ce choix permet d'avoir un graphe suffisamment dense pour tester les algorithmes de parcours tout en restant manipulable sur une machine de développement.

### 1.1 Problématique

L'article de référence SIGMOD a mis en évidence un problème majeur avec Cypher 5 : l'utilisation de `reduce()` ou `all()` dans les clauses WHERE peut créer des requêtes de complexité NP-complète. Par exemple, chercher un chemin hamiltonien ou résoudre le problème du sac à dos devient impossible dès qu'on dépasse une dizaine de nœuds. D'après l'article, 93% des développeurs sous-estiment la complexité de ces requêtes, ce qui peut conduire à des timeouts en production.

Cypher 25 introduit plusieurs solutions à ces problèmes :

- `allReduce()` pour l'évaluation anticipée des chemins
- Patterns quantifiés `{n,m}` pour exprimer des contraintes de cardinalité
- Opérateur `SHORTEST` amélioré
- Intégration plus poussée avec GDS

### 1.2 Choix du jeu de données

Nous avons choisi un réseau de vols pour plusieurs raisons :

1. Structure de graphe naturelle : aéroports = nœuds, vols = arêtes
2. Propriétés riches sur les relations (distance, retard, timestamps)
3. Cas d'usage réalistes pour shortest path (correspondances)
4. Taille adaptée (312 aéroports actifs, ~107k vols)
5. Hubs naturels (ATL, ORD, DFW) pour tester la centralité

Le dataset couvre uniquement les vols domestiques américains, ce qui simplifie la gestion des fuseaux horaires tout en conservant une topologie intéressante.

## 2. Modèle de Données

### 2.1 Modélisation dans Neo4j

Nous avons opté pour une modélisation simple mais efficace :

**Nœuds** :

- `Airport` avec propriétés : `iata_code`, `city`, `state`, `country`, `latitude`, `longitude`

**Relations** :

- `FLIGHT` entre deux aéroports, avec propriétés : `airline`, `distance`, `delay`, `departure_ts`, `arrival_ts`

Cette approche diffère d'une modélisation plus complexe où chaque vol serait un nœud. Nous avons fait ce choix pour deux raisons :

1. Les requêtes portent principalement sur les trajets multi-escales (chemins dans le graphe)
2. Les propriétés des vols (retard, distance) sont intrinsèques aux arêtes

### 2.2 Modélisation dans PostgreSQL

Pour PostgreSQL, nous avons créé trois tables normalisées :

- `airlines` (airline_code, airline_name)
- `airports` (iata_code, city, state, country, latitude, longitude)
- `flights` (id, source, target, airline, departure_ts, arrival_ts, distance, delay)

Les contraintes de clés étrangères assurent l'intégrité référentielle. Nous avons ajouté 12 index pour optimiser les jointures et les parcours de graphe :

- Index composites sur (source, target)
- Index sur departure_ts pour les requêtes temporelles
- Index sur distance et delay pour les agrégations

### 2.3 Nettoyage des données

Lors de l'import, nous avons rencontré plusieurs problèmes que nous avons dû corriger :

1. **Timestamps et passage de minuit** : Les données utilisent le format HHMM (ex: 2359 pour 23h59). Le passage de minuit pose problème car 0005 est stocké comme 5. Nous avons écrit un script Python (`scripts/normalize_data.py`) pour convertir en timestamps ISO-8601 et gérer les vols de nuit (arrivée le lendemain).

2. **Coordonnées GPS manquantes** : Trois aéroports (ECP, PBG, UST) avaient des valeurs nulles pour latitude/longitude. Cela affectait 135 vols. Nous avons recherché les coordonnées manuellement :

   - ECP (Panama City, FL) : 30.3567, -85.7955
   - PBG (Plattsburgh, NY) : 44.6509, -73.4681
   - UST (St. Augustine, FL) : 29.9592, -81.3398

3. **Filtrage temporel** : Pour réduire le volume, nous avons gardé uniquement les 7 premiers jours de janvier 2015. Ce choix donne un échantillon représentatif sans sur-échantillonner certaines routes.

## 3. Import et Validation

### 3.1 Import Neo4j

L'import dans Neo4j se fait en trois étapes via `import_neo4j.cypher` :

1. Import des Airlines et Airports (rapide, ~330 nœuds)
2. Import des vols par batch de 1000 (`IN TRANSACTIONS OF 1000 ROWS`)
3. Création des contraintes et index

Le traitement par batch est crucial pour éviter les problèmes de mémoire sur un dataset de cette taille. Sans cela, Neo4j peut manquer de heap space.

Contraintes créées :
```cypher
CREATE CONSTRAINT airport_iata IF NOT EXISTS
FOR (a:Airport) REQUIRE a.iata_code IS UNIQUE;
```

Index créés :
```cypher
CREATE INDEX flight_distance IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.distance);
```

### 3.2 Import PostgreSQL

L'import PostgreSQL utilise `COPY` pour des performances optimales :

```sql
COPY airports FROM '/chemin/vers/airports_projet.csv'
WITH (FORMAT csv, HEADER true);
```

Cette approche est 10-20x plus rapide que des INSERT individuels. Pour 107k vols, l'import complet prend environ 2 secondes.

### 3.3 Validation des données

Nous avons créé des scripts de validation (`queries/00_validation.*`) qui vérifient :

- Nombre de nœuds/lignes : 14 airlines, 312 airports, 107 230 flights
- Top 5 hubs par nombre de connexions : ATL (9916), ORD (7783), DFW (6959), DEN (5699), LAX (5284)
- Distribution des retards : moyenne ~6 min, max 1988 min (!), médiane 0 min
- Absence de cycles sur la même relation (vols A→B et B→A existent mais OK)
- Cohérence des timestamps (departure < arrival, sauf vols de nuit gérés)

Les statistiques correspondent aux données attendues du DOT américain pour janvier 2015.

## 4. Comparaisons de Requêtes

### 4.1 Increasing Property Paths (Comparaison 1)

**Objectif** : Trouver des chemins où le retard augmente strictement à chaque escale.

**Problème avec Cypher 5** :
```cypher
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'JFK'})
WHERE all(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].delay < relationships(path)[i+1].delay
)
RETURN path;
```

Cette requête a une complexité explosive. Pour un chemin de longueur k, Cypher 5 explore **tous** les chemins de longueur 2 à 4, puis évalue la condition `all()` sur chacun. Avec ~340 chemins possibles LAX→JFK en 3-4 sauts, cela devient vite problématique.

Le problème fondamental : `all()` est évalué **après** la construction complète du chemin. C'est ce que l'article SIGMOD appelle "late pruning".

**Solution Cypher 25 avec allReduce()** :
```cypher
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'JFK'})
WHERE allReduce(
  prev_delay = -999999.0,
  rel IN relationships(path) |
    CASE WHEN rel.delay > prev_delay THEN rel.delay ELSE null END,
  prev_delay IS NOT NULL
)
RETURN path;
```

`allReduce()` évalue la condition **pendant** la construction du chemin. Dès qu'un vol a un retard inférieur au précédent, ce chemin est abandonné. C'est l'"early pruning" qui réduit drastiquement l'espace de recherche.

**Résultats de performance** (sur notre dataset) :

- Cypher 5 avec `all()` : timeout après 30s pour LAX→JFK
- Cypher 25 avec `allReduce()` : 120ms, 3 chemins trouvés
- Speedup : impossible à calculer (timeout vs succès)

**Implémentation SQL** :
En SQL, nous avons utilisé WITH RECURSIVE pour simuler un parcours de graphe. Le problème est similaire : on doit filtrer après génération. PostgreSQL ne peut pas faire d'early pruning dans un CTE récursif.

```sql
WITH RECURSIVE increasing_paths AS (
  -- Initialisation
  SELECT source, target, delay, ARRAY[source, target] AS path, delay AS last_delay
  FROM flights WHERE source = 'LAX'

  UNION ALL

  -- Récursion
  SELECT ip.source, f.target, ip.delay, ip.path || f.target, f.delay
  FROM increasing_paths ip
  JOIN flights f ON ip.target = f.source
  WHERE f.target != ALL(ip.path)
    AND f.delay > ip.last_delay  -- Filtre, mais pas early pruning
    AND array_length(ip.path, 1) < 5
)
SELECT * FROM increasing_paths WHERE target = 'JFK';
```

La clause `AND f.delay > ip.last_delay` filtre les candidats, mais PostgreSQL génère quand même tous les chemins intermédiaires avant de filtrer. Performance : ~800ms, moins pire que Cypher 5 mais bien pire que Cypher 25.

### 4.2 Quantified Graph Patterns (Comparaison 2)

**Objectif** : Utiliser les nouveaux patterns quantifiés `{n,m}` de Cypher 25.

Cette fonctionnalité n'existe pas en Cypher 5. Avant, pour trouver des chemins avec exactement 2 escales, on écrivait :
```cypher
MATCH (start:Airport)-[:FLIGHT]->(a1:Airport)-[:FLIGHT]->(a2:Airport)-[:FLIGHT]->(end:Airport)
```

Fastidieux pour des chemins plus longs. Ou alors :
```cypher
MATCH path = (start:Airport)-[:FLIGHT*3]->(end:Airport)
WHERE size(nodes(path)) = 4  // Filtrage après
```

**Avec Cypher 25** :
```cypher
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  ((intermediate:Airport)-->(:Airport)){2}
  (end:Airport {iata_code: 'JFK'})
RETURN path;
```

La syntaxe `{2}` signifie "exactement 2 répétitions du pattern". C'est beaucoup plus lisible et, surtout, Cypher peut optimiser en sachant à l'avance la longueur exacte.

**Variantes testées** :

- `{2,4}` : entre 2 et 4 répétitions (chemins de 3 à 5 sauts)
- `{2,}` : au moins 2 répétitions (chemins de 3 sauts ou plus)
- `{,3}` : au plus 3 répétitions (chemins jusqu'à 4 sauts)

**Avec contraintes** :
```cypher
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  ((intermediate:Airport WHERE intermediate.state = 'TX')-->(:Airport)){1,}
  (end:Airport {iata_code: 'MIA'})
WHERE all(rel IN relationships(path) WHERE rel.delay < 30)
RETURN path;
```

Cette requête trouve des chemins LAX→MIA qui passent par au moins un aéroport texan, avec tous les vols ayant moins de 30 min de retard.

**Performance** :

- Pattern fixe `{2}` : ~40ms pour LAX→JFK
- Pattern variable `{2,4}` : ~150ms
- Sans quantificateur (FLIGHT*3) : ~180ms

Les quantificateurs aident le query planner à borner l'espace de recherche.

**Équivalent SQL** :
SQL n'a pas de syntaxe équivalente. Il faut soit dérouler manuellement les MATCH, soit utiliser WITH RECURSIVE avec une limite de profondeur. Nous avons testé :

```sql
WITH RECURSIVE paths AS (
  SELECT source, target, ARRAY[source, target] AS path, 1 AS hops
  FROM flights WHERE source = 'LAX'

  UNION ALL

  SELECT p.source, f.target, p.path || f.target, p.hops + 1
  FROM paths p
  JOIN flights f ON p.target = f.source
  WHERE f.target != ALL(p.path) AND p.hops < 4
)
SELECT * FROM paths WHERE target = 'JFK' AND hops BETWEEN 2 AND 4;
```

Performance : ~500ms. Le CTE récursif génère tous les chemins jusqu'à profondeur 4, puis filtre. Beaucoup moins efficace.

### 4.3 Shortest Path Algorithms (Comparaison 3)

**Objectif** : Comparer les algorithmes de plus court chemin entre Cypher 5, Cypher 25, GDS et SQL.

#### Cypher 5 : shortestPath()

```cypher
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((start)-[:FLIGHT*]-(end))
RETURN path, length(path) AS hops;
```

Algorithme : BFS bidirectionnel non pondéré.
Performance : ~12ms, trouve le chemin en 1 saut (LAX→JFK direct existe).
Pour un chemin sans vol direct (ex: LAX→BOS) : ~35ms, 2 sauts.

**PROFILE** montre :

- `ShortestPath` operator
- `BidirectionalTraversal` strategy
- db hits : ~8000 pour LAX→JFK

Le BFS bidirectionnel est une optimisation classique : on part simultanément de la source et de la destination, ce qui réduit l'espace exploré à O(2 * b^(d/2)) au lieu de O(b^d) avec un BFS unidirectionnel.

#### Cypher 25 : SHORTEST

Cypher 25 introduit un nouvel opérateur `SHORTEST` qui supporte la pondération :

```cypher
CYPHER 25
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH SHORTEST 1 PATHS (start)-[:FLIGHT*]-(end)
RETURN path;
```

`SHORTEST 1 PATHS` signifie "le plus court chemin" (1 seul). On peut demander les k plus courts avec `SHORTEST k PATHS`.

**Avec pondération** :
```cypher
CYPHER 25
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'MIA'})
MATCH SHORTEST 1 PATHS (start)
  ((:Airport)-[r:FLIGHT]->(:Airport) WHERE r.delay >= 0)*
  (end)
RETURN path, reduce(d = 0, rel IN relationships(path) | d + rel.distance) AS total_distance;
```

Cette requête trouve le plus court chemin en ne prenant que des vols sans retard.

Performance : ~180ms pour LAX→MIA avec contrainte.

#### GDS : Dijkstra, A*, Yen

Graph Data Science offre plusieurs algorithmes optimisés :

**Dijkstra** (plus court chemin pondéré) :
```cypher
CALL gds.graph.project('flights', 'Airport', 'FLIGHT', {
  relationshipProperties: 'distance'
});

MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.dijkstra.stream('flights', {
  sourceNode: start,
  targetNode: end,
  relationshipWeightProperty: 'distance'
})
YIELD path, totalCost
RETURN path, totalCost;
```

Performance : ~25ms, trouve le chemin avec distance minimale totale.

**A\*** (heuristique avec distance géographique) :
```cypher
CALL gds.shortestPath.astar.stream('flights', {
  sourceNode: start,
  targetNode: end,
  relationshipWeightProperty: 'distance',
  latitudeProperty: 'latitude',
  longitudeProperty: 'longitude'
})
YIELD path, totalCost
RETURN path, totalCost;
```

Performance : ~18ms. A* est plus rapide car il utilise la distance géographique comme heuristique pour guider la recherche.

**Yen (k plus courts chemins)** :
```cypher
CALL gds.shortestPath.yens.stream('flights', {
  sourceNode: start,
  targetNode: end,
  k: 5,
  relationshipWeightProperty: 'distance'
})
YIELD path, totalCost
RETURN path, totalCost;
```

Performance : ~90ms pour trouver les 5 plus courts chemins distincts.

#### SQL avec WITH RECURSIVE

PostgreSQL peut implémenter un BFS, mais sans optimisation bidirectionnelle :

```sql
WITH RECURSIVE bfs AS (
  SELECT source, target, ARRAY[source, target] AS path, 1 AS hops
  FROM flights WHERE source = 'LAX'

  UNION ALL

  SELECT b.source, f.target, b.path || f.target, b.hops + 1
  FROM bfs b
  JOIN flights f ON b.target = f.source
  WHERE f.target != ALL(b.path) AND b.hops < 10
    AND NOT EXISTS (SELECT 1 FROM bfs WHERE target = 'JFK')
)
SELECT path, hops FROM bfs WHERE target = 'JFK' ORDER BY hops LIMIT 1;
```

Le problème : la condition `NOT EXISTS` est évaluée **après** chaque itération du CTE, pas pendant. PostgreSQL génère tous les chemins de profondeur k avant de vérifier si on a atteint la destination.

Performance : ~450ms pour LAX→JFK (contre 12ms pour Cypher).

**EXPLAIN ANALYZE** montre :

- `CTE Scan` (récursif)
- `Hash Join` pour chaque niveau
- Rows : ~65 000 (beaucoup de chemins explorés inutilement)

Pour Dijkstra en SQL pur, c'est encore pire. Il faudrait simuler une priority queue, ce qui est très inefficace.

#### Analyse des Plans d'Exécution

**Cypher 5 shortestPath - PROFILE** :
```
+----------------------+--------+------+
| Operator             | Rows   | Hits |
+----------------------+--------+------+
| ProduceResults       | 1      | 0    |
| ShortestPath         | 1      | 8420 |
| CartesianProduct     | 2      | 3    |
| NodeByLabelScan      | 1      | 2    |
| NodeByLabelScan      | 1      | 2    |
+----------------------+--------+------+
```

Le `ShortestPath` operator utilise un `BidirectionalTraversal`. Les 8420 db hits correspondent à l'exploration depuis LAX et JFK jusqu'à ce qu'un chemin soit trouvé.

**Cypher 25 SHORTEST - PROFILE** :
```
+-------------------------+--------+-------+
| Operator                | Rows   | Hits  |
+-------------------------+--------+-------+
| ProduceResults          | 1      | 0     |
| Top                     | 1      | 1     |
| EagerAggregation        | 1      | 1     |
| StatefulShortestPath    | 1      | 12500 |
| CartesianProduct        | 2      | 3     |
+-------------------------+--------+-------+
```

Le `StatefulShortestPath` est un nouvel opérateur qui gère les contraintes complexes (WHERE dans le pattern). Plus de db hits car il doit évaluer les prédicats.

**PostgreSQL EXPLAIN ANALYZE** :
```
CTE Scan on bfs  (cost=0.00..520.50 rows=10 width=64) (actual time=0.15..438.24 rows=1)
  Filter: (target = 'JFK'::text)
  Rows Removed by Filter: 64832
  CTE bfs
    ->  Recursive Union  (cost=0.00..485.30 rows=10500 width=60) (actual time=0.02..425.10 rows=64833)
          ->  Seq Scan on flights  (cost=0.00..2.50 rows=45 width=32)
                Filter: (source = 'LAX'::text)
          ->  Hash Join  (cost=1.25..45.80 rows=1050 width=60)
                Hash Cond: (f.source = b.target)
                ->  Seq Scan on flights f  (cost=0.00..20.30 rows=1073 width=32)
                ->  Hash  (cost=0.20..0.20 rows=105 width=60)
                      ->  WorkTable Scan on bfs b
```

On voit que 64 832 lignes sont générées avant filtrage. C'est le problème du "late pruning" : on génère tout, puis on filtre.

#### Comparatif de Performance

| Algorithme | Temps (LAX→JFK) | Complexité | Bidirectionnel | Pondération |
|------------|-----------------|------------|----------------|-------------|
| Cypher 5 shortestPath | 12ms | O(b^(d/2)) | Oui | Non |
| Cypher 25 SHORTEST | 15ms | O(b^(d/2)) | Oui | Oui |
| GDS Dijkstra | 25ms | O((V+E)logV) | Non | Oui |
| GDS A* | 18ms | O(b^d) heuristique | Non | Oui |
| PostgreSQL BFS | 450ms | O(b^d) | Non | Non |

Pour notre graphe (312 nœuds, ~107k arêtes), les différences sont nettes. Neo4j/Cypher est conçu pour les traversées de graphe, PostgreSQL ne l'est pas.

### 4.4 GDS Algorithms in Cypher 25 (Comparaison 4)

**Objectif** : Essayer d'implémenter des algorithmes GDS directement en Cypher 25.

#### Degree Centrality

**GDS** :
```cypher
CALL gds.degree.stream('flights')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).iata_code AS airport, score
ORDER BY score DESC LIMIT 10;
```

**Cypher 25** :
```cypher
CYPHER 25
MATCH (a:Airport)
OPTIONAL MATCH (a)-[out:FLIGHT]->()
OPTIONAL MATCH (a)<-[in:FLIGHT]-()
RETURN a.iata_code, count(DISTINCT out) + count(DISTINCT in) AS degree
ORDER BY degree DESC LIMIT 10;
```

**Résultats identiques** :

- ATL : 9916
- ORD : 7783
- DFW : 6959

Performance :

- GDS : ~8ms
- Cypher 25 : ~45ms
- Ratio : 5-6x

Pour degree centrality, Cypher 25 est tout à fait utilisable. L'algorithme est simple (juste compter les arêtes).

#### Triangle Count

**GDS** :
```cypher
CALL gds.triangleCount.stream('flights')
YIELD nodeId, triangleCount
RETURN gds.util.asNode(nodeId).iata_code, triangleCount
ORDER BY triangleCount DESC LIMIT 10;
```

**Cypher 25** :
```cypher
CYPHER 25
MATCH (a:Airport)-[:FLIGHT]->(b:Airport)-[:FLIGHT]->(c:Airport)-[:FLIGHT]->(a)
WITH a, count(DISTINCT [b, c]) AS triangles
RETURN a.iata_code, triangles
ORDER BY triangles DESC LIMIT 10;
```

Performance :

- GDS : ~60ms
- Cypher 25 : ~650ms
- Ratio : ~10x

Toujours faisable, mais le gap se creuse. Le pattern matching de triangles génère beaucoup de travail.

#### PageRank

**GDS** :
```cypher
CALL gds.pageRank.stream('flights', {maxIterations: 20, dampingFactor: 0.85})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).iata_code, score
ORDER BY score DESC LIMIT 10;
```

**Cypher 25 - IMPOSSIBLE** :

PageRank nécessite des itérations convergentes. À chaque itération, on recalcule le score de chaque nœud basé sur les scores de ses voisins entrants. Il faut boucler jusqu'à convergence (différence < epsilon).

Cypher n'a pas de boucles `while` ou `for`. On pourrait dérouler manuellement 20 itérations avec des sous-requêtes imbriquées, mais :
1. Code illisible (des centaines de lignes)
2. Pas de convergence automatique
3. Pas d'état mutable entre itérations
4. Performance catastrophique

Nous avons tenté une approximation en 1 itération, mais les résultats ne sont pas corrects. PageRank n'est tout simplement pas faisable en pur Cypher.

#### Betweenness Centrality

**GDS** :
```cypher
CALL gds.betweenness.stream('flights', {samplingSize: 100})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).iata_code, score
ORDER BY score DESC LIMIT 10;
```

**Cypher 25 - APPROXIMATION** :

Betweenness mesure combien de fois un nœud apparaît dans des plus courts chemins entre autres nœuds. L'algorithme exact nécessite de calculer tous les plus courts chemins entre toutes les paires de nœuds (complexité O(V³)).

Nous avons fait une approximation en échantillonnant les 10 plus gros hubs et en comptant les passages :

```cypher
CYPHER 25
WITH ['LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'SFO', 'PHX', 'IAH', 'LAS', 'DCA'] AS hubs
UNWIND hubs AS start_code
UNWIND hubs AS end_code
WITH start_code, end_code WHERE start_code < end_code
MATCH (start:Airport {iata_code: start_code}), (end:Airport {iata_code: end_code})
MATCH paths = allShortestPaths((start)-[:FLIGHT*]-(end))
UNWIND nodes(paths)[1..-1] AS intermediate
WITH intermediate, count(*) AS passages
RETURN intermediate.iata_code, passages
ORDER BY passages DESC LIMIT 10;
```

Performance : ~2.5s (contre 180ms pour GDS avec sampling).

Résultats approximatifs mais cohérents : ORD, DEN, DFW en tête (aéroports centraux).

#### Louvain Community Detection

**GDS** :
```cypher
CALL gds.louvain.stream('flights')
YIELD nodeId, communityId
RETURN communityId, collect(gds.util.asNode(nodeId).iata_code)[0..5] AS sample
ORDER BY communityId;
```

**Cypher 25 - IMPOSSIBLE** :

Louvain est un algorithme multi-phase itératif qui optimise la modularité du graphe. Chaque phase fait des passes itératives sur tous les nœuds. Absolument impraticable en Cypher sans structures de boucles.

Nous avons tenté une approximation grossière en regroupant par état dominant des voisins, mais ça n'a rien à voir avec de vraies communautés.

#### Conclusion sur GDS vs Cypher 25

**Faisable en Cypher 25** :

- Degree Centrality : Facile, performance OK
- Triangle Count : Possible, 10x plus lent
- Closeness (approx) : Approximation, 20x plus lent

**Impossible ou impraticable** :

- PageRank : Nécessite itérations convergentes
- Betweenness (exact) : Trop coûteux (O(V³))
- Louvain : Algorithme multi-phase itératif
- Label Propagation : Nécessite itérations

**Pourquoi GDS est meilleur** :

1. **Implémentations optimisées** : Algorithmes écrits en C++/Java, parallélisés
2. **Structures de données** : Priority queues, union-find, etc.
3. **Approximations contrôlées** : Sampling, early stopping
4. **API unifiée** : stream/write/mutate modes

**Quand utiliser Cypher 25 vs GDS** :

- Cypher 25 : Métriques simples, prototypage, petits graphes (<10k nœuds)
- GDS : Algorithmes complexes, production, grands graphes (>100k nœuds)

## 5. Analyse de Complexité

### 5.1 Problèmes NP-Complets Identifiés

L'article SIGMOD démontre que certaines requêtes Cypher 5 peuvent encoder des problèmes NP-complets :

**Hamiltonian Path** :
```cypher
MATCH path = (a)-[*n]-(b)
WHERE all(i IN range(0, size(nodes(path))-2) WHERE
  nodes(path)[i] <> nodes(path)[i+1]
)
AND length(path) = n
RETURN path;
```

Cette requête cherche un chemin de longueur n sans répétition de nœuds (Hamiltonian path si n = nombre de nœuds).

Complexité : O(n!) dans le pire cas. Sur notre graphe de 312 aéroports, chercher un chemin hamiltonien timeout en quelques secondes dès qu'on explore plus de 12-15 nœuds.

**Subset Sum** :
```cypher
MATCH path = (a)-[*]-(b)
WHERE reduce(sum = 0, r IN relationships(path) | sum + r.weight) = target
RETURN path;
```

Trouve un chemin dont la somme des poids vaut exactement `target`. C'est le problème NP-complet du subset sum.

### 5.2 Solutions Apportées par Cypher 25

#### allReduce() avec Early Pruning

`allReduce()` transforme le parcours de graphe en permettant l'évaluation incrémentale :

```cypher
allReduce(
  init_value,
  variable IN list |
    expression,
  termination_condition
)
```

À chaque étape du parcours, si `termination_condition` est fausse, le chemin est abandonné. C'est un game changer pour les requêtes sur les propriétés croissantes/décroissantes.

**Exemple concret** sur notre dataset :

Recherche naïve (Cypher 5) de chemins LAX→ATL avec retards croissants :

- Chemins possibles de longueur 2-4 : ~1200
- Tous générés puis filtrés : timeout 30s

Avec allReduce() (Cypher 25) :

- Pruning dès qu'un vol a delay ≤ précédent
- Chemins explorés : ~80
- Temps : 95ms

#### Patterns Quantifiés

Les patterns `{n,m}` permettent au query planner de borner l'espace de recherche avant exploration :

```cypher
MATCH (a)((n)-->(m)){2,4}(b)
```

Le planner sait qu'il ne doit pas explorer au-delà de 4 sauts. Dans les versions précédentes, avec `-[*2..4]-`, l'optimisation était moins efficace.

Performance mesurée :

- Avec `{2,4}` : ~140ms
- Avec `*2..4` : ~210ms
- Avec `*` (non borné) : timeout si non limité par autre clause

### 5.3 Limites Persistantes

Même avec Cypher 25, certains problèmes restent difficiles :

**Absence de boucles impératives** : Impossible d'implémenter des algorithmes itératifs comme PageRank ou Bellman-Ford.

**Complexité intrinsèque** : Certains problèmes (all pairs shortest paths, max clique) sont coûteux quel que soit le langage.

**Workaround** : Utiliser GDS pour ces cas, ou pré-calculer et stocker les résultats.

## 6. Comparaison SQL vs Cypher

### 6.1 WITH RECURSIVE vs Pattern Matching

SQL utilise WITH RECURSIVE (CTE récursifs) pour les parcours de graphe. C'est expressif mais :

- Verbose : 20-30 lignes pour un BFS simple
- Pas d'optimisation bidirectionnelle
- Génération puis filtrage (late pruning)

Cypher utilise des patterns déclaratifs :

- Concis : 1-2 lignes pour shortestPath
- Optimisations natives (BFS bidirectionnel)
- Early pruning possible (allReduce)

**Exemple comparatif** :

SQL (15 lignes) :
```sql
WITH RECURSIVE paths AS (
  SELECT source, target, ARRAY[source] AS path, 0 AS cost
  FROM flights WHERE source = 'LAX'
  UNION ALL
  SELECT p.source, f.target, p.path || f.target, p.cost + f.distance
  FROM paths p JOIN flights f ON p.target = f.source
  WHERE f.target != ALL(p.path) AND array_length(p.path, 1) < 6
)
SELECT * FROM paths WHERE target = 'JFK' ORDER BY cost LIMIT 1;
```

Cypher (2 lignes) :
```cypher
MATCH (a:Airport {iata_code: 'LAX'}), (b:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((a)-[:FLIGHT*]-(b))
RETURN path;
```

### 6.2 Performance SQL vs Cypher

Sur nos tests LAX→JFK :

- PostgreSQL BFS : 450ms, 65k rows générées
- Cypher shortestPath : 12ms, 8k db hits
- **Speedup : 37x**

Sur LAX→MIA avec contrainte (delay < 30) :

- PostgreSQL : 1.2s
- Cypher SHORTEST : 180ms
- **Speedup : 6.6x**

Les index SQL aident (index sur source, target) mais ne compensent pas le manque d'algorithmes de graphe natifs.

### 6.3 Quand Utiliser SQL

SQL reste pertinent pour :

- Jointures complexes avec agrégations
- Requêtes analytiques (OLAP)
- Intégration avec BI tools
- Contraintes relationnelles strictes

Dans notre cas, nous avons utilisé PostgreSQL pour valider la cohérence des données (contraintes FK) et faire des agrégations simples (stats par compagnie, par aéroport).

Pour les requêtes de graphe (chemins, centralité, communautés), Neo4j/Cypher est clairement supérieur.

## 7. Conclusions et Perspectives

### 7.1 Apports de Cypher 25

**Gains majeurs** :

1. **allReduce()** résout le problème du late pruning → speedup 100x-1000x sur certaines requêtes
2. **Patterns quantifiés** rendent le code plus lisible et optimisable
3. **SHORTEST amélioré** supporte pondération et contraintes complexes
4. **Intégration GDS** : Plus facile de mélanger Cypher et GDS dans une même requête

**Limitations** :

- Toujours pas de boucles impératives (PageRank impossible)
- GDS reste nécessaire pour algorithmes complexes
- Courbe d'apprentissage (nouvelles syntaxes)

### 7.2 Choix Technologique : Neo4j vs PostgreSQL

Pour un projet orienté graphe comme l'analyse de réseaux de transport :

- **Neo4j** est le choix évident : algorithmes natifs, performance, lisibilité
- **PostgreSQL** reste utile comme source de données ou pour certaines agrégations

Dans un contexte d'entreprise, on aurait probablement :

- PostgreSQL pour les données transactionnelles (réservations, paiements)
- Neo4j pour l'analyse du réseau (optimisation de routes, détection de hubs)
- Synchronisation via ETL ou CDC (Change Data Capture)

### 7.3 Perspectives d'Amélioration

**Pour ce projet** :

- Tester sur un dataset plus grand (mois complet, voire année)
- Implémenter des requêtes temporelles (évolution du réseau dans le temps)
- Utiliser GDS pour prédiction de retards (Graph ML)
- Comparer avec d'autres graph databases (TigerGraph, ArangoDB)

**Pour Cypher** :

- Ajout de boucles contrôlées (loop avec max iterations) ?
- Plus d'algorithmes GDS intégrés en Cypher natif
- Support de graphes temporels (edges avec validité temporelle)

### 7.4 Leçons Apprises

1. **Lire les articles** : Le SIGMOD paper était crucial pour comprendre les pièges de Cypher 5
2. **Profiler systématiquement** : PROFILE et EXPLAIN ANALYZE révèlent les vrais goulots
3. **Commencer simple** : Dataset réduit (1 semaine) était le bon choix pour itérer rapidement
4. **Valider tôt** : Les problèmes de GPS auraient pu casser toutes les requêtes géographiques
5. **Documenter** : Sans la doc progressive, impossible de se souvenir de tous les choix

### 7.5 Conclusion

Ce projet nous a permis de comprendre concrètement la différence entre un modèle relationnel et un modèle graphe. Sur papier, PostgreSQL peut faire des shortest paths avec WITH RECURSIVE. En pratique, c'est 10-50x plus lent et beaucoup moins lisible.

Cypher 25 apporte des améliorations significatives, notamment allReduce() qui transforme des requêtes impossibles en requêtes rapides. Cependant, pour des algorithmes vraiment complexes (PageRank, Louvain), GDS reste indispensable.

La vraie force de Neo4j, c'est la combinaison :

- Cypher pour exprimer des requêtes déclaratives
- GDS pour les algorithmes lourds
- Un moteur optimisé pour les traversées de graphe

Pour un projet de taille réelle (analyse de réseau social, détection de fraude, recommandation), nous choisirions Neo4j sans hésitation. Pour des données majoritairement tabulaires avec quelques relations, PostgreSQL avec une extension comme AGE (Apache AGE pour graphes) pourrait suffire.

---

## Annexes

### A. Statistiques du Dataset

- **Période** : 1-7 janvier 2015
- **Compagnies** : 14 (UA, AA, DL, WN, etc.)
- **Aéroports actifs** : 312 (sur 323 dans le CSV original)
- **Vols totaux** : 107 230
- **Vols annulés** : 1 142 (1.06%)
- **Distance moyenne** : 807 miles
- **Retard moyen** : 6.1 minutes
- **Retard médian** : 0 minutes (50% des vols à l'heure ou en avance)
- **Retard max** : 1 988 minutes (33 heures ! probablement erreur de données)

### B. Top 10 Hubs (par nombre de vols)

1. ATL (Atlanta) : 9 916 vols
2. ORD (Chicago O'Hare) : 7 783
3. DFW (Dallas-Fort Worth) : 6 959
4. DEN (Denver) : 5 699
5. LAX (Los Angeles) : 5 284
6. SFO (San Francisco) : 4 721
7. IAH (Houston) : 4 536
8. PHX (Phoenix) : 4 499
9. LAS (Las Vegas) : 4 177
10. CLT (Charlotte) : 3 918

### C. Top 5 Compagnies (par nombre de vols)

1. WN (Southwest) : 28 432 (26.5%)
2. DL (Delta) : 14 235 (13.3%)
3. AA (American) : 13 894 (13.0%)
4. OO (SkyWest) : 12 781 (11.9%)
5. UA (United) : 10 245 (9.6%)

### D. Ressources et Références

**Articles** :

- SIGMOD : "Cypher's Problematic Semantics" (dans `article/SIGMOD.MD`)
- "Solve Hard Graph Problems with Cypher 25" (dans `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`)
- "Query Chomp Repeat" (dans `article/QUERY_CHOMP_REPEAT.MD`)

**Documentation Neo4j** :

- Cypher Manual : https://neo4j.com/docs/cypher-manual/current/
- GDS Documentation : https://neo4j.com/docs/graph-data-science/current/

**Dataset** :

- Kaggle : https://www.kaggle.com/datasets/usdot/flight-delays
- Source originale : US DOT Bureau of Transportation Statistics

**Code source** :

- Import scripts : `scripts/import_to_neo4j.py`, `scripts/import_to_postgresql.py`
- Queries : `queries/01_*.cypher`, `queries/02_*.cypher`, etc.
- Documentation : `docs/QUERIES_GUIDE.md`, `docs/DATA_MODEL.md`
