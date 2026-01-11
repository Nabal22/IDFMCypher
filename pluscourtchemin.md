# Analyse des Algorithmes de Plus Courts Chemins dans Neo4j

Je vais te préparer une analyse complète comparant Cypher 5, Cypher 25 et GDS pour les algorithmes de plus courts chemins sur ton graphe de vols.

## 1. Requêtes en Cypher 5 (Neo4j 4.x)

### Plus court chemin non pondéré (BFS)

```cypher
// Cypher 5 - BFS avec pattern de chemin variable
// Trouve le chemin avec le moins d'escales entre deux aéroports
MATCH path = (start:Airport {iata_code: 'LAX'})-[:FLIGHT*1..5]->(end:Airport {iata_code: 'JFK'})
RETURN path, length(path) AS hops
ORDER BY hops ASC
LIMIT 1
```

```cypher
// Cypher 5 - Tous les chemins de longueur minimale (non pondéré)
MATCH path = (start:Airport {iata_code: 'LAX'})-[:FLIGHT*1..5]->(end:Airport {iata_code: 'JFK'})
WITH path, length(path) AS hops
ORDER BY hops ASC
WITH collect(path) AS paths, min(hops) AS minHops
UNWIND paths AS p
WITH p WHERE length(p) = minHops
RETURN p, length(p) AS hops
```

### Plus court chemin pondéré (par distance)

```cypher
// Cypher 5 - Chemin de distance minimale
// Attention: cette approche énumère TOUS les chemins (très coûteux)
MATCH path = (start:Airport {iata_code: 'LAX'})-[:FLIGHT*1..4]->(end:Airport {iata_code: 'JFK'})
WITH path, reduce(totalDist = 0, f IN relationships(path) | totalDist + f.distance) AS totalDistance
RETURN path, totalDistance
ORDER BY totalDistance ASC
LIMIT 1
```

```cypher
// Cypher 5 - Chemin minimisant le délai total
MATCH path = (start:Airport {iata_code: 'LAX'})-[:FLIGHT*1..4]->(end:Airport {iata_code: 'JFK'})
WITH path, reduce(totalDelay = 0.0, f IN relationships(path) | totalDelay + coalesce(f.delay, 0.0)) AS totalDelay
RETURN path, totalDelay
ORDER BY totalDelay ASC
LIMIT 1
```

## 2. Requêtes en Cypher 25 (Neo4j 5.x)

### Nouvelles fonctionnalités Graph Pattern Matching (GPM)

```cypher
// Cypher 25 - Syntaxe QPP (Quantified Path Patterns)
// Plus court chemin non pondéré avec nouvelle syntaxe
MATCH path = (start:Airport {iata_code: 'LAX'})
             (()-[:FLIGHT]->())+
             (end:Airport {iata_code: 'JFK'})
RETURN path, length(path) AS hops
ORDER BY hops ASC
LIMIT 1
```

```cypher
// Cypher 25 - Chemin le plus court avec contrainte de longueur
MATCH path = (start:Airport {iata_code: 'LAX'})
             (()-[:FLIGHT]->()) {1,5}
             (end:Airport {iata_code: 'JFK'})
RETURN path, length(path) AS hops
ORDER BY hops ASC
LIMIT 1
```

### Plus court chemin pondéré en Cypher 25

```cypher
// Cypher 25 - Distance minimale avec reduce
MATCH path = (start:Airport {iata_code: 'LAX'})
             (()-[f:FLIGHT]->()) {1,4}
             (end:Airport {iata_code: 'JFK'})
WITH path, reduce(d = 0, r IN relationships(path) | d + r.distance) AS totalDistance
RETURN path, totalDistance, length(path) AS hops
ORDER BY totalDistance ASC
LIMIT 1
```

```cypher
// Cypher 25 - Utilisation de list comprehension pour le poids
MATCH path = (start:Airport {iata_code: 'LAX'})
             (()-[:FLIGHT]->()) {1,4}
             (end:Airport {iata_code: 'JFK'})
WITH path, 
     reduce(dist = 0, r IN relationships(path) | dist + r.distance) AS totalDistance,
     [r IN relationships(path) | r.distance] AS distances
RETURN [n IN nodes(path) | n.iata_code] AS route,
       distances,
       totalDistance,
       length(path) AS numberOfFlights
ORDER BY totalDistance ASC
LIMIT 5
```

### Chemin avec contraintes temporelles (spécifique à ton modèle)

```cypher
// Cypher 25 - Chemin réalisable temporellement
// Chaque vol doit partir après l'arrivée du précédent
MATCH path = (start:Airport {iata_code: 'LAX'})-[f1:FLIGHT]->(mid1:Airport)
             -[f2:FLIGHT]->(end:Airport {iata_code: 'JFK'})
WHERE f2.departure_ts > f1.arrival_ts
WITH path, 
     reduce(d = 0, r IN relationships(path) | d + r.distance) AS totalDistance
RETURN path, totalDistance
ORDER BY totalDistance ASC
LIMIT 5
```

## 3. Graph Data Science (GDS)

### Création de la projection du graphe

```cypher
// Suppression d'une projection existante (si nécessaire)
CALL gds.graph.drop('flights-graph', false) YIELD graphName;

// Projection native du graphe pour GDS
CALL gds.graph.project(
    'flights-graph',
    'Airport',
    {
        FLIGHT: {
            type: 'FLIGHT',
            orientation: 'NATURAL',
            properties: {
                distance: {
                    property: 'distance',
                    defaultValue: 0
                },
                delay: {
                    property: 'delay',
                    defaultValue: 0.0
                }
            }
        }
    }
) YIELD graphName, nodeCount, relationshipCount;
```

### Dijkstra - Plus court chemin pondéré

```cypher
// GDS Dijkstra - Chemin de distance minimale
MATCH (source:Airport {iata_code: 'LAX'})
MATCH (target:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.dijkstra.stream('flights-graph', {
    sourceNode: source,
    targetNode: target,
    relationshipWeightProperty: 'distance'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
    gds.util.asNode(sourceNode).iata_code AS sourceAirport,
    gds.util.asNode(targetNode).iata_code AS targetAirport,
    totalCost AS totalDistance,
    [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
    costs AS cumulativeDistances,
    size(nodeIds) - 1 AS numberOfFlights
```

```cypher
// GDS Dijkstra - Minimiser le délai total
MATCH (source:Airport {iata_code: 'LAX'})
MATCH (target:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.dijkstra.stream('flights-graph', {
    sourceNode: source,
    targetNode: target,
    relationshipWeightProperty: 'delay'
})
YIELD sourceNode, targetNode, totalCost, nodeIds, costs
RETURN
    [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
    totalCost AS totalDelay,
    size(nodeIds) - 1 AS numberOfFlights
```

### A* (A-Star) - Plus court chemin avec heuristique

```cypher
// GDS A* - Utilise les coordonnées géographiques comme heuristique
MATCH (source:Airport {iata_code: 'LAX'})
MATCH (target:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.astar.stream('flights-graph', {
    sourceNode: source,
    targetNode: target,
    relationshipWeightProperty: 'distance',
    latitudeProperty: 'latitude',
    longitudeProperty: 'longitude'
})
YIELD sourceNode, targetNode, totalCost, nodeIds, costs
RETURN
    [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
    totalCost AS totalDistance,
    costs AS cumulativeDistances
```

### BFS - Plus court chemin non pondéré

```cypher
// GDS BFS - Nombre minimum d'escales
MATCH (source:Airport {iata_code: 'LAX'})
MATCH (target:Airport {iata_code: 'JFK'})
CALL gds.bfs.stream('flights-graph', {
    sourceNode: source,
    targetNodes: [target]
})
YIELD sourceNode, targetNode, nodeIds, path
RETURN
    [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
    size(nodeIds) - 1 AS numberOfFlights
```

### Yens K-Shortest Paths - K meilleurs chemins

```cypher
// GDS Yen's K-Shortest Paths - Trouver les 5 meilleurs itinéraires
MATCH (source:Airport {iata_code: 'LAX'})
MATCH (target:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.yens.stream('flights-graph', {
    sourceNode: source,
    targetNode: target,
    relationshipWeightProperty: 'distance',
    k: 5
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs
RETURN
    index + 1 AS rank,
    [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
    totalCost AS totalDistance,
    size(nodeIds) - 1 AS numberOfFlights
ORDER BY rank
```

### Single Source Shortest Path (SSSP) - Depuis une source vers tous

```cypher
// GDS Delta-Stepping SSSP - Tous les chemins depuis LAX
MATCH (source:Airport {iata_code: 'LAX'})
CALL gds.allShortestPaths.delta.stream('flights-graph', {
    sourceNode: source,
    relationshipWeightProperty: 'distance',
    delta: 100  // Paramètre de bucket pour Delta-Stepping
})
YIELD sourceNode, targetNode, totalCost, nodeIds
WITH gds.util.asNode(targetNode) AS target, totalCost, nodeIds
WHERE target.iata_code IN ['JFK', 'ORD', 'DFW', 'MIA', 'SEA']
RETURN
    target.iata_code AS destination,
    totalCost AS totalDistance,
    [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route
ORDER BY totalDistance
```

## 4. Analyse des Plans d'Exécution

### Requête pour voir le plan d'exécution

```cypher
// Utiliser EXPLAIN ou PROFILE pour voir le plan
PROFILE
MATCH path = (start:Airport {iata_code: 'LAX'})-[:FLIGHT*1..4]->(end:Airport {iata_code: 'JFK'})
WITH path, length(path) AS hops
RETURN path, hops
ORDER BY hops ASC
LIMIT 1
```

```cypher
// Plan pour Cypher 25 QPP
PROFILE
MATCH path = (start:Airport {iata_code: 'LAX'})
             (()-[:FLIGHT]->()) {1,4}
             (end:Airport {iata_code: 'JFK'})
RETURN path, length(path) AS hops
ORDER BY hops ASC
LIMIT 1
```

---

## 5. Analyse Comparative et Algorithmes Utilisés

### Tableau Comparatif

| Aspect | Cypher 5 | Cypher 25 | GDS |
|--------|----------|-----------|-----|
| **Algorithme non pondéré** | BFS implicite (énumération) | BFS implicite (QPP optimisé) | BFS explicite |
| **Algorithme pondéré** | Énumération exhaustive | Énumération exhaustive | Dijkstra, A*, Delta-Stepping |
| **Complexité non pondéré** | O(V + E) pour BFS | O(V + E) optimisé | O(V + E) |
| **Complexité pondéré** | O(paths) - exponentiel | O(paths) - exponentiel | O((V + E) log V) pour Dijkstra |
| **Bidirectionnel** | Non | Limité | Oui (optionnel) |
| **K meilleurs chemins** | Manuel | Manuel | Yen's natif |
| **Heuristique** | Non | Non | A* avec lat/long |

### Algorithmes dans les Plans Neo4j

**BFS Unidirectionnel :**
- Explore le graphe niveau par niveau depuis la source
- Garantit le chemin le plus court en nombre d'arêtes
- Complexité : O(V + E)
- Utilisé par défaut pour `*..n` patterns

**BFS Bidirectionnel :**
- Explore simultanément depuis source ET destination
- Se rencontre au milieu
- Complexité : O(b^(d/2)) vs O(b^d) pour unidirectionnel
- **Avantage majeur** : Réduit exponentiellement l'espace de recherche
- Neo4j l'utilise pour `shortestPath()` - mais tu ne peux pas l'utiliser ici

**VarExpand (Variable Length Expand) :**
- Utilisé pour les patterns `-[:REL*1..n]->`
- Implémente un DFS ou BFS selon le contexte
- Peut être coûteux car énumère potentiellement tous les chemins

### Différence BFS Unidirectionnel vs Bidirectionnel

```
BFS Unidirectionnel:
Source ──────────────────────────────► Target
   └── Explore tout l'espace jusqu'à trouver target
   
Branching factor b = 10, depth d = 6
Noeuds explorés ≈ 10^6 = 1,000,000

BFS Bidirectionnel:
Source ──────► ◄────── Target
   └── Se rencontrent au milieu (depth d/2)
   
Noeuds explorés ≈ 2 × 10^3 = 2,000
Gain: 500x moins de noeuds !
```

**Dans ton graphe de vols :**
- Chaque aéroport hub (ATL, LAX, ORD) peut avoir 100+ connexions
- Un chemin de 4 escales pourrait explorer 100^4 = 100M chemins en unidirectionnel
- Bidirectionnel : 2 × 100^2 = 20,000 chemins seulement

### Recommandations pour ton Projet

1. **Pour chemins non pondérés simples** : Cypher 25 QPP est le plus lisible
2. **Pour chemins pondérés en production** : GDS Dijkstra obligatoire
3. **Pour ton réseau aérien avec coordonnées** : GDS A* est optimal
4. **Pour trouver des alternatives** : GDS Yen's K-Shortest Paths

Tu veux que je te prépare un fichier avec toutes ces requêtes prêtes à exécuter ?