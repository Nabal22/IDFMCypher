# Part 2: Query Development and Comparison

## Table des matières

1. [Prérequis](#prérequis)
2. [Objectifs](#objectifs)
3. [Résultats de la recherche SIGMOD](#résultats-de-la-recherche-sigmod)
4. [Cypher 25 : Solutions et nouvelles fonctionnalités](#cypher-25--solutions-et-nouvelles-fonctionnalités)
5. [Les 6 comparaisons obligatoires](#les-6-comparaisons-obligatoires)
6. [Application des patterns aux données IDFM](#application-des-patterns-aux-données-idfm)
7. [Stratégie de test et métriques](#stratégie-de-test-et-métriques)
8. [Notes d'implémentation](#notes-dimplémentation)
9. [Références](#références)

---

## Prérequis

✅ **Phase 1 complétée** : Les données doivent être chargées dans PostgreSQL ET Neo4j (voir `docs/PART1.MD`)

- **PostgreSQL** : Base relationnelle avec contraintes d'intégrité et index
- **Neo4j** : Base graphe avec modèle hybride (Stop, Trip, Route, Agency)
- **Données** : Subsets IDFM (métro) avec ~54k stops, ~15k trips, ~200k transfers

---

## Objectifs

Cette phase vise à comparer **Cypher 5 vs Cypher 25 vs SQL vs GDS** à travers :

1. **Identification des patterns problématiques** de Cypher 5 (article SIGMOD)
2. **Réécriture en Cypher 25** avec nouvelles fonctionnalités
3. **Équivalents SQL** (CTEs récursives notamment)
4. **Algorithmes GDS** (Graph Data Science)
5. **Tests sur données IDFM** de transport
6. **Analyse des plans d'exécution** et performance

---

## Résultats de la recherche SIGMOD

### Le problème fondamental

L'article **"Dangers of List Processing in Querying Property Graphs"** (SIGMOD) identifie un problème majeur dans Cypher 5 :

> **L'utilisation de `reduce` dans les clauses `WHERE` crée des requêtes NP-complètes** qui :
> - Apparaissent simples syntaxiquement
> - Sont computationnellement intractables
> - Timeout sur des graphes minuscules
> - **93% des programmeurs ne peuvent pas prédire leur performance**

### Les 6 patterns problématiques

#### 1. **Hamiltonian Path** (Chemin hamiltonien)

**Problème** : Trouver un chemin visitant tous les nœuds exactement une fois

**Requête problématique** :
```cypher
MATCH p = (start)-[*]-(end)
WHERE size(nodes(p)) = <target_count>
  AND size(nodes(p)) = size(apoc.coll.toSet(nodes(p)))
RETURN p
```

**Résultats** :
- ⏱️ Timeout à partir de **≥10 nœuds** (p=0.2 density)
- 🔴 Complexité exponentielle cachée derrière une syntaxe simple
- 📊 L'utilisation combinée de `size()` et `all()` (variantes de `reduce`) cause le problème

---

#### 2. **Subset Sum** (Somme de sous-ensemble)

**Problème** : Trouver un chemin dont la somme des propriétés d'arêtes égale une valeur cible

**Requête problématique** :
```cypher
MATCH p = (s1)-[*]-(s2)
WHERE reduce(total = 0, r IN relationships(p) | total + r.weight) = <target>
RETURN p
```

**Résultats** :
- ⏱️ Timeout à partir de **≥27 nœuds**
- 🔴 NP-complet même avec sémantique de plus court chemin
- 📊 La somme cible agit comme un prédicat qui force l'exploration exhaustive

---

#### 3. **Data-Aware Path Queries** (Chemins sensibles aux données)

**Problème** : Filtrer des chemins selon les valeurs de propriétés le long du chemin

**Exemples** :
- Chemins où les timestamps sont croissants
- Chemins où les poids alternent entre pairs/impairs
- Chemins sans arêtes consécutives de même type

**Requête problématique** :
```cypher
MATCH p = (s1)-[*]-(s2)
WHERE all(i IN range(0, size(relationships(p))-2) WHERE
  relationships(p)[i].timestamp < relationships(p)[i+1].timestamp)
RETURN p
```

**Issue** :
- Agrégation horizontale sur les éléments du chemin dans les filtres
- Force l'évaluation de TOUS les chemins avant filtrage

---

#### 4. **Horizontal Aggregation** (Agrégation horizontale)

**Problème** : Réduire/agréger sur les éléments d'un chemin dans un `WHERE`

**Exemples** :
- Compter les types de nœuds différents dans un chemin
- Calculer la moyenne des propriétés
- Vérifier des conditions sur les séquences

**Requête problématique** :
```cypher
MATCH p = (s)-[*]-(e)
WHERE reduce(count = 0, n IN nodes(p) WHERE n:Type1 | count + 1) > 5
RETURN p
```

**Issue** : Crée des espaces de recherche exponentiels

---

#### 5. **Regular Path Queries (RPQs)** avec listes

**Problème** : Patterns réguliers difficiles à exprimer sans manipulation de listes

**Exemples** :
- `(aa)*` : séquences répétées de même label
- `(ab)+c` : alternance suivie d'un label spécifique

**Requête problématique** :
```cypher
MATCH p = (s)-[*]-(e)
WHERE all(i IN range(0, size(relationships(p))-1) WHERE
  i % 2 = 0 IMPLIES type(relationships(p)[i]) = 'TYPE_A')
RETURN p
```

**Issue** : Manipulation complexe de listes requise, mieux vaut une syntaxe RPQ dédiée

---

#### 6. **Trail Semantics** combinés avec listes

**Problème** : Patterns trail (`A*BA*`) performent mal avec opérations sur listes

**Découverte clé** :
- ✅ Trail semantics **seuls** sont OK : graphes 3× plus grands, <1ms
- 🔴 Combinés avec opérations listes : effondrement des performances

**Requête problématique** :
```cypher
MATCH p = TRAIL (s)-[*]-(hub)-[*]-(e)
WHERE size([n IN nodes(p) WHERE n:SmallCave]) <= 2
RETURN p
```

**Conclusion** : Les listes, pas les trails, causent l'effondrement

---

### Comparaison SQL

L'article compare également avec PostgreSQL et DuckDB :

| Pattern | Neo4j Cypher 5 | SQL (PostgreSQL/DuckDB) | Verdict |
|---------|----------------|-------------------------|---------|
| Trail patterns (`A*BA*`) | ⏱️ Timeout | ⏱️⏱️ Timeout (pire) | **Neo4j gagne** |
| Hamiltonian path | ⏱️ Timeout ≥10 nœuds | ⏱️ Timeout ≥12 nœuds | **SQL légèrement meilleur** |
| Subset sum | ⏱️ Timeout ≥27 nœuds | ⏱️ Timeout ≥30 nœuds | **SQL légèrement meilleur** |

**Différence clé** : En SQL, il est **plus difficile d'écrire des requêtes problématiques par accident**
- Les CTEs récursives forcent une structure explicite
- Moins de "sucre syntaxique" qui cache la complexité

---

### Étude utilisateur (45 étudiants MSc)

Résultats révélateurs :
- ✅ **78%** ont correctement compris la requête Hamiltonian path
- ✅ **55%** ont pu écrire correctement la requête subset sum
- 🔴 **Seulement 7%** ont correctement estimé le seuil de timeout
- 📊 La plupart ont surestimé de **2-3 ordres de grandeur**

**Conclusion** : Les développeurs ne peuvent pas prédire la complexité de leurs propres requêtes

---

### Leçons pour la conception de langages

#### Leçon 1 : Interdire `reduce` dans les clauses `WHERE`
- ❌ La compilation devrait échouer si `reduce` apparaît dans des filtres
- ❌ S'applique même aux formes restreintes (`all`, `any`, `size`)
- ✅ Cypher 25 implémente cette restriction

#### Leçon 2 : Autoriser `reduce` dans les clauses de sortie avec restrictions
- ✅ Safe dans `RETURN`, `WITH`
- ✅ La sortie doit être une valeur scalaire ou liste de scalaires
- ❌ Pas de listes imbriquées (évite les requêtes powerset-style exponentielles)

#### Leçon 3 : Fournir des constructions spécialisées au lieu de `reduce` général
- ✅ Pour les RPQs : syntaxe de patterns dédiée (comme dans GQL/SQL/PGQ)
- ✅ Pour les chemins complexes : fonctionnalités linguistiques spécifiques
- ❌ Éviter la tentation de copier l'approche par listes de Cypher 5

---

## Cypher 25 : Solutions et nouvelles fonctionnalités

### Vue d'ensemble

Cypher 25 introduit plusieurs fonctionnalités clés pour résoudre les problèmes identifiés :

1. **`allReduce`** : Alternative sûre à `reduce` dans `WHERE`
2. **Quantified Graph Patterns** : Syntaxe pour quantifier les patterns
3. **`REPEATABLE ELEMENTS`** : Match mode permettant la répétition
4. **Trail Semantics natifs** : Support sans surcharge de listes
5. **`SHORTEST N PATHS` pondéré** : Plus courts chemins avec poids
6. **Restrictions sur `reduce`** : Interdit dans `WHERE`, permis dans `RETURN/WITH`

---

### 1. `allReduce` - Safe Path Property Checking

**Syntaxe** :
```cypher
allReduce(
    accumulator = initial_value,
    element IN collection |
    expression,
    condition
)
```

**Exemple - Chemins avec propriétés croissantes** :
```cypher
CYPHER 25
MATCH p = (s1:Stop)-[:STOP_TIME*]->(t:Trip)
WHERE allReduce(
    prev = -1,
    rel IN relationships(p) |
    rel.stop_sequence,
    prev <= rel.stop_sequence
)
RETURN p LIMIT 10
```

**Avantages** :
- ✅ Élagage pendant la traversée (pas après)
- ✅ Réduit l'espace de recherche de millions à milliers de chemins
- ✅ Permet des limites de profondeur élevées sans timeout

**Performance** : Cas d'étude Advent of Code Day 12
- Cypher 5 (2021) : **144 secondes** (avec refactoring du graphe + APOC)
- Cypher 25 (2025) : **1.2 secondes** (graphe original, pas de refactoring)
- **Speedup : 120x**

---

### 2. `REPEATABLE ELEMENTS` - Match Mode

Permet la répétition de nœuds et relations dans un même chemin.

**Cas d'usage** :

#### A. Pathfinding optimal avec contraintes

**Exemple** : Plus court chemin avec détour obligatoire (station-service)

```cypher
CYPHER 25
MATCH REPEATABLE ELEMENTS
    route = ANY SHORTEST (:Start)--{,100}(:GasStation)--{,100}(:Stop)
RETURN length(route) AS length
```

Sans `REPEATABLE ELEMENTS`, impossible d'explorer les détours (retour en arrière).

---

#### B. Covering Paths (Doctor's Rounds)

**Problème** : Un médecin doit visiter tous les services d'un étage

```cypher
CYPHER 25
LET wards = COLLECT { MATCH (n:Ward) RETURN n }
MATCH REPEATABLE ELEMENTS ALL SHORTEST
    (p = (start {id: 1})--{,11}(start)
     WHERE all(ward IN wards WHERE ward IN nodes(p)))
RETURN [n IN nodes(p) | n.id] AS route
```

**Résultat** : Trouve les chemins optimaux même si certains couloirs doivent être parcourus 2 fois.

---

#### C. Peer-to-Peer Reachability (Famille)

**Problème** : Trouver les petits-enfants partageant des grands-parents

```cypher
CYPHER 25
MATCH REPEATABLE ELEMENTS
    (kidA)-[:MOTHER|FATHER]->{2}(grandparent)<-[:MOTHER|FATHER]-{2}(kidB)
WHERE kidA < kidB
RETURN kidA.name, kidB.name, count(DISTINCT grandparent) AS shared_grandparents
```

Sans `REPEATABLE ELEMENTS`, impossible de remonter puis redescendre les mêmes relations.

---

#### D. Grammar Generation

**Problème** : Générer tous les patterns Cypher valides de forme `()-->()`

```cypher
CYPHER 25
MATCH REPEATABLE ELEMENTS p = (:Start)-->{,9}(:End)
WITH [n IN nodes(p) | n.symbol] AS letters
RETURN reduce(acc = "", l IN letters | acc + l) AS pattern
```

Génère : `()`, `()-->()`, `()<--()`, `()--()-->()`, etc.

---

### 3. Quantified Graph Patterns

Syntaxe pour spécifier des cardinalités sur les patterns.

**Exemple - Trouver les hubs (≥3 connections)** :
```cypher
CYPHER 25
MATCH (s:Stop)
WHERE EXISTS { (s)-[:TRANSFER]->(:Stop) } >= 3
RETURN s.stop_name, count { (s)-[:TRANSFER]->() } AS connections
```

**Équivalent Cypher 5 (moins clair)** :
```cypher
CYPHER 5
MATCH (s:Stop)
WITH s, count { (s)-[:TRANSFER]->() } AS cnt
WHERE cnt >= 3
RETURN s.stop_name, cnt
```

**Avantages Cypher 25** :
- Syntaxe plus expressive
- Intention plus claire
- Optimisation possible par le moteur

---

### 4. Trail Semantics Natifs

**Cypher 5** : Nécessite `DIFFERENT RELATIONSHIPS` (mode par défaut)

**Cypher 25** : Support explicite avec `TRAIL`

```cypher
CYPHER 25
MATCH (hub:Stop {stop_name: 'Châtelet'})
MATCH p = TRAIL (s1:Stop)-[:TRANSFER|STOP_TIME*]-(hub)-[:TRANSFER|STOP_TIME*]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
RETURN p LIMIT 100
```

**Performance** :
- Graphes 3× plus grands qu'en Cypher 5
- <1ms runtime
- **Condition** : Ne pas combiner avec opérations listes complexes

---

### 5. `SHORTEST N PATHS` avec pondération

```cypher
CYPHER 25
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
MATCH p = SHORTEST 5 PATHS (s)-[:TRANSFER*]-(e)
  WITH WEIGHT (r:TRANSFER | r.min_transfer_time)
RETURN p, reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) AS total_time
ORDER BY total_time
```

**Avantages** :
- Pondération native (pas besoin de GDS pour cas simples)
- Top-K shortest paths
- Syntaxe déclarative

---

## Les 6 comparaisons obligatoires

D'après `CONSIGNES.MD`, le projet doit inclure au minimum :

### 1. ✅ Increasing Property Paths (Cypher 5 vs 25 vs SQL)

**Objectif** : Chemins où une propriété d'arête est croissante

**Propriété IDFM** : `stop_sequence` (ordre des arrêts dans un trajet)

**Fichiers** : `queries/01_increasing_paths.cypher`, `queries/01_increasing_paths.sql`

#### Cypher 5 - Version problématique

```cypher
CYPHER 5
MATCH (r:Route {route_long_name: '11'})
MATCH (t:Trip)-[:BELONGS_TO]->(r)
MATCH p = (start:Stop)-[:STOP_TIME*]->(t)
WHERE NOT EXISTS {
    WITH p
    UNWIND range(0, length(p)-2) AS i
    WITH relationships(p)[i] AS r1, relationships(p)[i+1] AS r2
    WHERE r1.stop_sequence >= r2.stop_sequence
    RETURN 1
}
RETURN p LIMIT 10
```

**Problèmes** :
- `NOT EXISTS` avec itération sur range + indexation
- Force l'évaluation de TOUS les chemins avant filtrage
- Timeout attendu : >10 stops (selon SIGMOD)

---

#### Cypher 25 - Avec `allReduce`

```cypher
CYPHER 25
MATCH (r:Route {route_long_name: '11'})
MATCH (t:Trip)-[:BELONGS_TO]->(r)
MATCH p = (start:Stop)-[:STOP_TIME*]->(t)
WHERE allReduce(
    prev = -1,
    rel IN relationships(p) |
    rel.stop_sequence,
    prev <= rel.stop_sequence
)
RETURN p LIMIT 10
```

**Avantages** :
- Élagage PENDANT la traversée
- Pas d'exploration de branches mortes
- Gère des chemins plus longs

---

#### SQL - CTE Récursive

```sql
WITH RECURSIVE route_path AS (
    -- Cas de base : premier arrêt de chaque trajet
    SELECT
        st.stop_id,
        st.trip_id,
        st.stop_sequence,
        st.departure_time,
        ARRAY[st.stop_id] AS path,
        1 AS length
    FROM stop_times st
    WHERE st.stop_sequence = 0

    UNION ALL

    -- Cas récursif : arrêts suivants avec contrainte croissante
    SELECT
        st.stop_id,
        st.trip_id,
        st.stop_sequence,
        st.departure_time,
        rp.path || st.stop_id,
        rp.length + 1
    FROM route_path rp
    JOIN stop_times st
        ON rp.trip_id = st.trip_id
        AND st.stop_sequence = rp.stop_sequence + 1
    WHERE st.departure_time > rp.departure_time  -- Contrainte croissante
)
SELECT * FROM route_path
WHERE length >= 5
LIMIT 10;
```

**Avantages** :
- La contrainte est dans le `WHERE` du JOIN récursif
- Élagage naturel pendant la construction
- Performance similaire à Cypher 25

---

### 2. ✅ Quantified Graph Patterns (difficile sans cette fonctionnalité)

**Objectif** : Démontrer l'utilité des quantified patterns

**Cas d'usage IDFM** : Trouver les hubs de correspondance (≥3 transfers)

#### Cypher 25 - Quantified Pattern

```cypher
CYPHER 25
MATCH (s:Stop)
WHERE EXISTS { (s)-[:TRANSFER]->(:Stop) } >= 3
RETURN s.stop_name,
       count { (s)-[:TRANSFER]->() } AS num_transfers
ORDER BY num_transfers DESC
```

---

#### Cypher 5 - Sans quantified patterns (workaround)

```cypher
CYPHER 5
MATCH (s:Stop)
WITH s, count { (s)-[:TRANSFER]->() } AS cnt
WHERE cnt >= 3
RETURN s.stop_name, cnt
ORDER BY cnt DESC
```

**Différences** :
- Cypher 25 : Déclaratif, condition dans le `WHERE` directement
- Cypher 5 : Nécessite `WITH` intermédiaire, moins lisible

---

#### SQL - GROUP BY HAVING

```sql
SELECT
    s.stop_name,
    COUNT(DISTINCT t.to_stop_id) AS num_transfers
FROM stops s
JOIN transfers t ON s.stop_id = t.from_stop_id
GROUP BY s.stop_id, s.stop_name
HAVING COUNT(DISTINCT t.to_stop_id) >= 3
ORDER BY num_transfers DESC;
```

**Note** : SQL a toujours eu `HAVING`, donc pas de problème ici

---

### 3. ✅ Shortest Path Algorithms (Cypher 5 vs 25 vs GDS vs SQL)

**Objectif** : Comparer TOUTES les variantes de plus courts chemins

#### A. Cypher 5 - BFS non pondéré

```cypher
CYPHER 5
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
MATCH p = shortestPath((s)-[:TRANSFER*]-(e))
RETURN p, length(p) AS hops
```

**Algorithme** : BFS unidirectionnel ou bidirectionnel (selon heuristique)

---

```cypher
CYPHER 5
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
MATCH p = allShortestPaths((s)-[:TRANSFER*]-(e))
RETURN p, length(p) AS hops
```

**Retourne** : TOUS les chemins de longueur minimale

---

#### B. Cypher 25 - BFS pondéré

```cypher
CYPHER 25
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
MATCH p = SHORTEST 5 PATHS (s)-[:TRANSFER*]-(e)
  WITH WEIGHT (r:TRANSFER | r.min_transfer_time)
RETURN p,
       reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) AS total_time
ORDER BY total_time
```

**Avantages** :
- Top-K shortest paths
- Pondération native
- Retourne les K meilleurs chemins triés

---

#### C. GDS - Algorithmes spécialisés

**Fichier** : `queries/04_shortest_path_gds.cypher`

##### Dijkstra (pondéré)

```cypher
// 1. Créer projection
CALL gds.graph.project(
    'transport-weighted',
    'Stop',
    {
        TRANSFER: {
            properties: ['min_transfer_time']
        }
    }
)

// 2. Dijkstra
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
CALL gds.shortestPath.dijkstra.stream('transport-weighted', {
    sourceNode: s,
    targetNode: e,
    relationshipWeightProperty: 'min_transfer_time'
})
YIELD path, totalCost
RETURN path, totalCost
```

---

##### A* (avec heuristique géographique)

```cypher
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
CALL gds.shortestPath.astar.stream('transport-weighted', {
    sourceNode: s,
    targetNode: e,
    latitudeProperty: 'stop_lat',
    longitudeProperty: 'stop_lon',
    relationshipWeightProperty: 'min_transfer_time'
})
YIELD path, totalCost
RETURN path, totalCost
```

**Avantage A*** : Heuristique distance euclidienne réduit l'espace de recherche

---

##### Yen's K-Shortest Paths

```cypher
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
CALL gds.shortestPath.yens.stream('transport-weighted', {
    sourceNode: s,
    targetNode: e,
    k: 5,
    relationshipWeightProperty: 'min_transfer_time'
})
YIELD path, totalCost
RETURN path, totalCost
ORDER BY totalCost
```

**Retourne** : Les K meilleurs chemins (pas seulement longueur minimale)

---

##### All Pairs Shortest Path ⚠️

```cypher
CALL gds.allShortestPaths.dijkstra.stream('transport-weighted', {
    relationshipWeightProperty: 'min_transfer_time'
})
YIELD sourceNode, targetNode, totalCost, path
RETURN gds.util.asNode(sourceNode).stop_name AS from_stop,
       gds.util.asNode(targetNode).stop_name AS to_stop,
       totalCost
LIMIT 100
```

**Attention** :
- Complexité O(n²) en mémoire
- Sur 54k stops → 54k × 54k = 2.9 milliards de paires
- **Utiliser seulement sur sous-graphes**

---

#### D. SQL - CTE Récursive (approximation BFS)

```sql
WITH RECURSIVE shortest_path AS (
    -- Cas de base : départ
    SELECT
        t1.from_stop_id AS current_stop,
        t1.to_stop_id AS next_stop,
        t1.min_transfer_time AS total_time,
        ARRAY[t1.from_stop_id] AS path,
        1 AS depth
    FROM transfers t1
    JOIN stops s ON t1.from_stop_id = s.stop_id
    WHERE s.stop_name = 'Châtelet'

    UNION ALL

    -- Cas récursif : expansion
    SELECT
        sp.next_stop,
        t.to_stop_id,
        sp.total_time + t.min_transfer_time,
        sp.path || sp.next_stop,
        sp.depth + 1
    FROM shortest_path sp
    JOIN transfers t ON sp.next_stop = t.from_stop_id
    WHERE NOT (t.to_stop_id = ANY(sp.path))  -- Éviter cycles
      AND sp.depth < 10  -- Limite profondeur
)
SELECT
    sp.path || sp.next_stop AS full_path,
    sp.total_time,
    sp.depth AS hops
FROM shortest_path sp
JOIN stops s ON sp.next_stop = s.stop_id
WHERE s.stop_name = 'Nation'
ORDER BY sp.total_time
LIMIT 5;
```

**Limitations** :
- Pas de vrai Dijkstra (explore par niveaux BFS-style)
- Peut manquer le chemin optimal si profondeur limitée trop stricte
- Performance variable selon les index

---

#### Comparaison des algorithmes

| Algorithme | Complexité | Pondéré | Top-K | Heuristique | Usage |
|------------|-----------|---------|-------|-------------|-------|
| BFS (Cypher 5 `shortestPath`) | O(V+E) | ❌ | ❌ | ❌ | Chemins simples |
| BFS (Cypher 5 `allShortestPaths`) | O(V+E) | ❌ | ✅ (tous) | ❌ | Tous les plus courts |
| Cypher 25 `SHORTEST N` | O(V+E) | ✅ | ✅ | ❌ | Top-K pondérés |
| Dijkstra (GDS) | O((V+E)logV) | ✅ | ❌ | ❌ | Plus court pondéré |
| A* (GDS) | O((V+E)logV) | ✅ | ❌ | ✅ (geo) | Optimisé géo |
| Yen's K-Shortest (GDS) | O(K×V×(E+VlogV)) | ✅ | ✅ | ❌ | K meilleurs chemins |
| SQL CTE Récursive | O(V+E) par niveau | ⚠️ (approx) | ⚠️ | ❌ | Graphes simples |

---

#### Analyse des plans d'exécution

**Question clé** : BFS unidirectionnel vs bidirectionnel ?

##### BFS Unidirectionnel
```
Start → explore niveau 1 → niveau 2 → ... → Target
```
- **Espace exploré** : O(b^d) où b=branching factor, d=profondeur
- **Usage** : Quand target est proche, ou graphe peu dense

##### BFS Bidirectionnel
```
Start → niveau 1 ←
          ↓       ↑
      niveau 2   niveau 2
          ↓       ↑
          → Meet ← Target
```
- **Espace exploré** : O(2 × b^(d/2)) = O(b^(d/2)) (beaucoup plus petit!)
- **Usage** : Quand target est loin, graphe dense
- **Condition** : Les deux nœuds doivent être connus à l'avance

**Neo4j choisit automatiquement** selon :
- Distance estimée entre nœuds
- Branching factor
- Statistiques du graphe

**Comment vérifier** : Utiliser `PROFILE` et chercher :
- `BidirectionalShortestPath` operator
- `ExpandAll` directions (vers avant/arrière)

---

### 4. ✅ GDS Implementation in Cypher 25

**Objectif** : Implémenter en Cypher pur des algorithmes disponibles dans GDS

**Exemple** : Dijkstra naïf en Cypher 25

```cypher
CYPHER 25
// Version simplifiée de Dijkstra en pur Cypher
MATCH (source:Stop {stop_name: 'Châtelet'})
CALL {
    WITH source
    MATCH p = (source)-[:TRANSFER*]-(target:Stop)
    WITH target,
         reduce(cost = 0, r IN relationships(p) | cost + r.min_transfer_time) AS total_cost,
         p
    ORDER BY total_cost ASC
    LIMIT 1
    RETURN target, total_cost, p
}
RETURN target.stop_name, total_cost, p
```

**Comparaison** :

| Aspect | Cypher Natif | GDS Dijkstra |
|--------|--------------|--------------|
| **Performance** | ⏱️ Plus lent (explore tous chemins) | ✅ Optimisé (priority queue) |
| **Mémoire** | ⚠️ Stocke tous les chemins | ✅ Stocke seulement distances |
| **Simplicité** | ✅ Code Cypher pur | ❌ Nécessite projection GDS |
| **Flexibilité** | ✅ Filtres complexes faciles | ⚠️ Limité à propriétés de la projection |

**Cas d'usage Cypher natif** :
- Graphes très petits (<1000 nœuds)
- Logique métier complexe (filtres, transformations)
- Prototypage rapide

**Cas d'usage GDS** :
- Graphes larges (>10k nœuds)
- Performance critique
- Algorithmes batch (All Pairs, PageRank, etc.)

---

### 5. ✅ SQL Comparisons (CTEs récursives)

**Déjà couvert dans les sections précédentes** :
- ✅ Increasing paths : CTE récursive avec contrainte croissante
- ✅ Shortest path : CTE récursive approximation BFS

**Autre exemple** : Calcul de profondeur de hiérarchie

```sql
-- Profondeur des stations dans le réseau (via parent_station)
WITH RECURSIVE hierarchy AS (
    -- Racines (pas de parent)
    SELECT stop_id, stop_name, parent_station, 0 AS depth
    FROM stops
    WHERE parent_station IS NULL

    UNION ALL

    -- Enfants
    SELECT s.stop_id, s.stop_name, s.parent_station, h.depth + 1
    FROM stops s
    JOIN hierarchy h ON s.parent_station = h.stop_id
)
SELECT stop_name, depth
FROM hierarchy
ORDER BY depth DESC, stop_name;
```

**Quand SQL est meilleur que Cypher** :
- Agrégations complexes (GROUP BY, WINDOW functions)
- Requêtes purement tabulaires (pas de traversée de graphe)
- Compatibilité avec outils BI existants

---

### 6. ✅ Execution Plan Analysis (BFS uni vs bidirectionnel)

**Déjà couvert dans section 3.D**

**Comment analyser** :

#### Neo4j - PROFILE

```cypher
PROFILE
MATCH (s:Stop {stop_name: 'Châtelet'}), (e:Stop {stop_name: 'Nation'})
MATCH p = shortestPath((s)-[:TRANSFER*]-(e))
RETURN p
```

**Chercher dans le plan** :
- Operator : `BidirectionalShortestPath` ou `ExpandAll`
- `db hits` : nombre d'accès base
- `rows` : cardinalité estimée/réelle
- `EstimatedRows` vs `Rows` : précision des statistiques

---

#### PostgreSQL - EXPLAIN ANALYZE

```sql
EXPLAIN ANALYZE
WITH RECURSIVE shortest_path AS (
    ...
)
SELECT * FROM shortest_path;
```

**Chercher dans le plan** :
- Type de join : `Hash Join`, `Nested Loop`, `Merge Join`
- Index scans : `Index Scan` (bon) vs `Seq Scan` (mauvais pour grandes tables)
- `actual time` : temps réel d'exécution
- `rows` : nombre de lignes traitées

---

## Application des patterns aux données IDFM

### Pattern supplémentaire : Subset Sum (NP-complet)

**Problème** : Trouver des séquences de correspondances totalisant exactement N secondes

#### Cypher 5 - Version problématique

```cypher
CYPHER 5
MATCH p = (s1:Stop)-[:TRANSFER*]-(s2:Stop)
WHERE reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) = 300
RETURN p
```

**Timeout attendu** : ≥27 nœuds (selon SIGMOD)

---

#### Cypher 25 - Solution partielle (déplacer reduce)

```cypher
CYPHER 25
MATCH p = (s1:Stop)-[:TRANSFER*..5]-(s2:Stop)
WITH p, reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) AS total_time
WHERE total_time = 300
RETURN p
```

**Amélioration** :
- `reduce` dans `WITH` (pas `WHERE`)
- Limite de profondeur stricte (`*..5`)
- Toujours lent, mais termine

**Note** : Subset Sum reste NP-complet, aucune solution miracle

---

### Pattern supplémentaire : Hamiltonian-style (visiter tous les arrêts d'une ligne)

**Problème** : Trajet visitant TOUS les arrêts d'une ligne exactement une fois

#### Cypher 5 - Version problématique

```cypher
CYPHER 5
MATCH (r:Route {route_long_name: '11'})
MATCH (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r)
WITH collect(DISTINCT s) AS all_stops, count(DISTINCT s) AS target_count

MATCH p = (start:Stop)-[:STOP_TIME*]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE size(nodes(p)) = target_count
  AND size(nodes(p)) = size(apoc.coll.toSet(nodes(p)))  -- Tous distincts
RETURN p LIMIT 1
```

**Timeout attendu** : ≥10 arrêts (selon SIGMOD)

---

#### Cypher 25 - Trail Semantics

```cypher
CYPHER 25
MATCH (r:Route {route_long_name: '11'})
LET target_count = count { (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r) }

MATCH p = TRAIL (start:Stop)-[:STOP_TIME*]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE length(p) = target_count
RETURN p LIMIT 1
```

**Avantages** :
- `TRAIL` garantit pas de répétition de relations
- Plus performant que vérification manuelle avec `apoc.coll.toSet`
- Toujours NP-complet, mais exploration plus efficace

---

### Pattern supplémentaire : RPQ (Sequences régulières)

**Problème** : Trouver des séquences de même type de route (bus-bus-bus)

#### Cypher 25 - RPQ Syntax

```cypher
CYPHER 25
// Séquences de ≥3 bus consécutifs
MATCH (s1:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route {route_type: 3}){3,}
      -[:BELONGS_TO]<-(:Trip)<-[:STOP_TIME]-(s2:Stop)
RETURN s1.stop_name, s2.stop_name
```

**Syntaxe** : `{3,}` = répéter 3 fois ou plus (comme regex `{3,}`)

---

#### Cypher 5 - Workaround avec listes

```cypher
CYPHER 5
MATCH p = (s1:Stop)-[:STOP_TIME*3..10]-(s2:Stop)
WHERE all(rel IN relationships(p) WHERE
    EXISTS { (rel)-[]->(:Trip)-[:BELONGS_TO]->(:Route {route_type: 3}) }
)
RETURN s1.stop_name, s2.stop_name
```

**Problèmes** :
- Syntaxe lourde
- Performance dégradée
- Moins lisible

---

## Stratégie de test et métriques

### Phase 1 : Tests fonctionnels

#### Objectifs
- ✅ Vérifier que chaque requête s'exécute sans erreur
- ✅ Comparer résultats Cypher vs SQL (cohérence)
- ✅ Valider l'intégrité des données

#### Actions
1. Exécuter toutes les requêtes dans `queries/`
2. Pour patterns équivalents (Cypher vs SQL), comparer les résultats :
   - Même nombre de lignes ?
   - Mêmes chemins trouvés ?
   - Mêmes coûts calculés ?
3. Documenter les divergences (si any)

---

### Phase 2 : Tests de performance

#### Métriques à collecter

| Métrique | Neo4j | PostgreSQL |
|----------|-------|------------|
| **Temps d'exécution** | Timestamp début/fin | `\timing on` |
| **Plan d'exécution** | `PROFILE` | `EXPLAIN ANALYZE` |
| **Mémoire** | Java heap usage (Neo4j Desktop) | `work_mem` settings |
| **Db hits** | Dans `PROFILE` | N/A |
| **Lignes traitées** | `rows` dans plan | `rows` dans plan |
| **Algorithme utilisé** | Operator name | Join type |

---

#### Procédure de test progressif

**Pour chaque pattern problématique** :

1. **Démarrer petit** : Limiter à 1 ligne de métro (ligne 11 par exemple)
2. **Augmenter progressivement** :
   - 1 ligne → timeout ? Non → continuer
   - 2 lignes → timeout ? Non → continuer
   - Toutes lignes métro → timeout ? OUI → documenter seuil
3. **Identifier le seuil de timeout** :
   - Nombre de nœuds du graphe à ce seuil
   - Comparer avec SIGMOD (Hamiltonian ≥10, Subset Sum ≥27)

**Exemple** :
```bash
# Test ligne 11 uniquement
METRO_LINES="11" ./generate_subset_files.sh

# Charger dans Neo4j, tester requêtes, mesurer temps
# Si OK, augmenter :

METRO_LINES="11 3" ./generate_subset_files.sh
# Recharger, retester

# Répéter jusqu'à timeout
```

---


---

### Phase 3 : Analyse des plans d'exécution

#### Questions clés

##### 1. Cypher - BFS unidirectionnel vs bidirectionnel

**Expérience** :
```cypher
// Test 1 : Nœuds proches (même ligne)
PROFILE
MATCH (s:Stop {stop_name: 'République'}), (e:Stop {stop_name: 'Bastille'})
MATCH p = shortestPath((s)-[:TRANSFER*]-(e))
RETURN p

// Test 2 : Nœuds éloignés (lignes différentes)
PROFILE
MATCH (s:Stop {stop_name: 'La Défense'}), (e:Stop {stop_name: 'Château de Vincennes'})
MATCH p = shortestPath((s)-[:TRANSFER*]-(e))
RETURN p
```

**Chercher dans PROFILE** :
- Operator : `BidirectionalShortestPath` (test 2) vs `ExpandAll` (test 1) ?
- `db hits` : combien plus élevé dans test 2 ?

---

##### 2. Impact de `reduce` dans WHERE vs WITH

**Expérience** :
```cypher
// Version 1 : reduce dans WHERE (problématique)
PROFILE
MATCH p = (s:Stop)-[:TRANSFER*..5]-(e:Stop)
WHERE reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) < 600
RETURN count(p)

// Version 2 : reduce dans WITH
PROFILE
MATCH p = (s:Stop)-[:TRANSFER*..5]-(e:Stop)
WITH p, reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) AS total_time
WHERE total_time < 600
RETURN count(p)
```

**Attendre** : Version 2 devrait être plus rapide (selon SIGMOD)

**Note** : Sur Neo4j 5.x, la différence peut être minime car optimiseur moderne. L'article SIGMOD teste sur versions plus anciennes.

---

##### 3. SQL - Recursive CTE performance

**Expérience** :
```sql
-- Mesurer impact de la profondeur max
\timing on

-- Profondeur 5
WITH RECURSIVE path AS (...) WHERE depth < 5
-- Noter temps

-- Profondeur 10
WITH RECURSIVE path AS (...) WHERE depth < 10
-- Noter temps

-- Profondeur 20
WITH RECURSIVE path AS (...) WHERE depth < 20
-- Noter temps
```

**Analyser** :
- Croissance exponentielle ?
- Linéaire ?
- Impact des index sur `stop_id`, `trip_id` ?

---

##### 4. GDS vs Cypher natif

**Expérience** :
```cypher
// Dijkstra natif Cypher (approximation)
:param start => 'Châtelet'
:param end => 'Nation'
PROFILE
MATCH (s:Stop {stop_name: $start}), (e:Stop {stop_name: $end})
MATCH p = (s)-[:TRANSFER*]-(e)
WITH p, reduce(cost = 0, r IN relationships(p) | cost + r.min_transfer_time) AS total_cost
ORDER BY total_cost LIMIT 1
RETURN p, total_cost

// vs GDS Dijkstra
PROFILE
MATCH (s:Stop {stop_name: $start}), (e:Stop {stop_name: $end})
CALL gds.shortestPath.dijkstra.stream('transport-weighted', {
    sourceNode: s,
    targetNode: e,
    relationshipWeightProperty: 'min_transfer_time'
})
YIELD path, totalCost
RETURN path, totalCost
```

**Comparer** :
- Temps d'exécution
- Mémoire utilisée
- Complexité du plan

**Attendu** : GDS beaucoup plus rapide (algorithme optimisé)

---

## Notes d'implémentation

### APOC Functions

Certaines requêtes utilisent APOC (Advanced Procedures and Functions) :
- `apoc.coll.toSet` : convertir liste en ensemble (éliminer doublons)
- `apoc.coll.occurrences` : compter occurrences dans liste
- `apoc.coll.duplicates` : trouver doublons

**Installation** :
1. Neo4j Desktop → Database → Plugins → APOC
2. Restart database

**Alternatives natives** (si APOC indisponible) :
```cypher
// apoc.coll.toSet(list)
// → utiliser reduce avec accumulation conditionnelle
UNWIND list AS item
WITH DISTINCT item
RETURN collect(item) AS set_list
```

---

### GDS Plugin Installation

**Prérequis** : Nécessaire pour `04_shortest_path_gds.cypher`

**Installation** :
1. Neo4j Desktop → Database → Plugins → Graph Data Science
2. Restart database
3. Vérifier : `RETURN gds.version()`

**Versions** :
- Neo4j 5.x → GDS 2.x
- Compatibilité : vérifier [GDS compatibility matrix](https://neo4j.com/docs/graph-data-science/current/installation/)

---

### Limits et Timeouts

**Neo4j** :
```properties
# neo4j.conf
dbms.transaction.timeout=300s
dbms.memory.heap.initial_size=2G
dbms.memory.heap.max_size=4G
```

**PostgreSQL** :
```sql
-- Session level
SET statement_timeout = '300s';
SET work_mem = '256MB';

-- Vérifier
SHOW statement_timeout;
```

**Timeout progressif** :
1. Démarrer avec timeout court (30s) pour tests fonctionnels
2. Augmenter pour tests de performance (300s)
3. Pour benchmark timeout : utiliser 600s (10 min) comme limite absolue

---

### Subsets de données

**Rappel** : Le script `generate_subset_files.sh` permet de créer des subsets contrôlés

```bash
# Ligne 11 uniquement (~1.5k trips)
METRO_LINES="11" ./generate_subset_files.sh

# Lignes 3, 7, 14, 11 (default, ~15k trips)
./generate_subset_files.sh

# Toutes les lignes de métro (~50k trips)
METRO_LINES="1 2 3 3b 4 5 6 7 7b 8 9 10 11 12 13 14" ./generate_subset_files.sh
```

**Stratégie recommandée** :
- Tests fonctionnels : 1 ligne
- Tests performance initiaux : 4 lignes (default)
- Tests limites (timeout) : augmenter jusqu'à timeout
- Rapport : documenter les seuils trouvés

---

## Références

### Articles
- **SIGMOD** : `article/SIGMOD.MD` - Dangers of List Processing in Querying Property Graphs
- **Cypher 25 Case Study** : `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD` - Advent of Code Day 12, speedup 120x
- **REPEATABLE ELEMENTS** : `article/QUERY_CHOMP_REPEAT.MD` - Doctor's rounds, Pac-Man, Gas station detour

### Documentation projet
- **Part 1** : `docs/PART1.MD` - Data import strategy
- **Datasets** : `docs/DATASETS.MD` - GTFS schema reference
- **Queries** : `queries/README.md` - Implementation guide

### Documentation externe
- **Neo4j Cypher Manual** : https://neo4j.com/docs/cypher-manual/current/
- **Neo4j GDS** : https://neo4j.com/docs/graph-data-science/current/
- **PostgreSQL Recursive CTEs** : https://www.postgresql.org/docs/current/queries-with.html
- **GTFS Specification** : https://gtfs.org/

### Cours
- Cours "Bases de Données Spécialisées" - Modélisation graphe, optimisation requêtes
- Référencer dans le rapport pour justifier choix de modélisation

---

## Résumé des livrables attendus

Pour le **rapport final** (Part 3), cette phase doit fournir :

### 1. Résultats expérimentaux
- ✅ Tableau comparatif Cypher 5 vs 25 vs SQL vs GDS
- ✅ Temps d'exécution pour chaque pattern
- ✅ Seuils de timeout identifiés
- ✅ Comparaison avec benchmarks SIGMOD

### 2. Plans d'exécution
- ✅ Captures d'écran Neo4j `PROFILE`
- ✅ Captures PostgreSQL `EXPLAIN ANALYZE`
- ✅ Analyse des algorithmes utilisés (BFS uni/bidirectional, etc.)
- ✅ Comparaison db hits, mémoire, cardinalités

### 3. Analyses qualitatives
- ✅ Quels patterns sont problématiques et pourquoi ?
- ✅ Cypher 25 résout-il ces problèmes ? (théoriquement, basé sur articles)
- ✅ Dans quels cas SQL est meilleur ?
- ✅ Quand utiliser GDS vs Cypher natif ?

### 4. Code source
- ✅ Tous les fichiers `.cypher` et `.sql` dans `queries/`
- ✅ Scripts de test
- ✅ Commentaires expliquant chaque requête

### 5. Recommandations
- ✅ Meilleures pratiques Cypher (éviter `reduce` dans `WHERE`, etc.)
- ✅ Quand choisir PostgreSQL vs Neo4j
- ✅ Optimisations possibles (index, projections GDS, etc.)

---

**Prochaine étape** : Phase 3 - Exécution des tests et rédaction du rapport
