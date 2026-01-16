# Fiche de Préparation Oral - FlightCypher

## Présentation Générale (1-2 min)

**Sujet** : Comparaison des performances entre Cypher 5 et Cypher 25 sur des données réelles de vols américains

**Auteurs** : Romain Groult & Alban Talagrand

**Contexte** : Analyse des nouvelles fonctionnalités de Cypher 25 (langage de requête Neo4j) et leur impact sur les performances pour les requêtes de chemins

**Dataset** :
- Source : Kaggle "2015 Flight Delays and Cancellations" (US DoT)
- Période : 1-7 janvier 2015 (première semaine)
- Volume : 107 230 vols, 313 aéroports, 14 compagnies aériennes

---

## Structure du Projet

### Choix des Données

**Pourquoi les vols et pas les transports franciliens (IDFM) ?**
- IDFM trop orienté relationnel : 4 tables intermédiaires pour relier deux stations
- Vols américains : structure naturellement orientée graphe
- Relations directes entre aéroports = arêtes avec propriétés

### Modèle de Graphe Neo4j

**Nœuds** :
- `Airport` (313) : code IATA, nom, ville, état, coordonnées GPS
- `Airline` (14) : code IATA, nom compagnie

**Relations** :
- `FLIGHT` (107 230) avec propriétés :
  - `departure_ts` / `arrival_ts` (timestamps)
  - `distance` (miles)
  - `delay` (minutes, peut être négatif)
  - `airline` (code compagnie)

**Point clé** : Chaque vol = 1 relation unique identifiée par timestamp
→ Évite le problème des multi-edges (ANC→SEA 23h54 ≠ ANC→SEA 08h30)

### Contraintes et Index

- Unicité codes IATA
- Index sur `departure_ts`, `distance`, `delay`

---

## 5 Comparaisons Principales

### 1. Chemins avec Propriété Croissante ⭐

**Problème** : Trouver LAX → JFK où le retard augmente à chaque escale

**Cypher 5** :
```cypher
MATCH path = (start)-[:FLIGHT*2..4]->(end)
WHERE NOT EXISTS { ... }
```
- Stratégie : Génère TOUS les chemins (319 631), filtre après
- Temps : ~1,5 seconde
- DB Hits : 16 340 381

**Cypher 25** :
```cypher
MATCH path = (start)(()-[f:FLIGHT]->(:Airport)){2,4}(end)
WHERE allReduce(prev_delay = -999999.0, rel IN f | ...)
```
- Stratégie : Filtre PENDANT la traversée (opérateur Trail)
- Temps : ~3,5 ms
- DB Hits : 39 904

**Gain** : 1,5s → 3,5ms = **99,8% plus rapide** ! 🚀

**Pourquoi ?** Plan d'exécution différent :
- Cypher 5 : `VarLengthExpand` + `Apply+Anti` (filtre tardif)
- Cypher 25 : `Repeat(Into,Trail)` avec pruning inline

---

### 2. Quantified Graph Patterns

**Problème** : N escales exactes sans repasser par le même aéroport

**Cypher 5** : Verbeux et rigide
```cypher
MATCH path = (start)-[:FLIGHT]->(hub1)-[:FLIGHT]->(hub2)-[:FLIGHT]->(end)
WHERE start <> hub1 AND start <> hub2 AND start <> end
  AND hub1 <> hub2 AND hub1 <> end
  AND hub2 <> end
```
→ 7 lignes, 6 comparaisons pour 3 escales

**Cypher 25** : Concis et flexible
```cypher
MATCH path = (start)(()-[:FLIGHT]->(:Airport)){3}(end)
WHERE allReduce(seen = [], n IN nodes(path) | ...)
```
→ 1 ligne pour le pattern

**Avantage** : Maintenabilité. Changer 3 escales en 2-4 = changer `{3}` en `{2,4}` vs réécrire tout le pattern

---

### 3. Plus Courts Chemins Pondérés ⚠️

**Problème** : JFK → DAY en minimisant la distance

**Cypher 5 `shortestPath()`** :
- Route : JFK → ATL → DAY (1192 miles)
- Temps : 15 ms
- **Problème** : Minimise le nombre de sauts, PAS la distance

**Cypher 5/25 pondéré** :
```cypher
MATCH path = (start)-[:FLIGHT*1..3]->(end)
WITH path, reduce(dist = 0, r in relationships(path) | dist + r.distance) AS total_distance
ORDER BY total_distance LIMIT 1
```
- Route optimale : JFK → BWI → DAY (590 miles)
- Temps : 293 ms pour 2 sauts, **137 secondes pour 3 sauts**
- **Explosion combinatoire** : timeout à 4 sauts

**GDS Dijkstra** :
```cypher
CALL gds.shortestPath.dijkstra.stream(...)
```
- Route : JFK → BWI → DAY (590 miles, optimal garanti)
- Temps : **37 ms**, scalable

**Conclusion** : Pour chemins pondérés, **GDS obligatoire**. Cypher pur n'a pas les structures optimisées (priority queue)

---

### 4. Implémentation GDS en Cypher 25

**Question** : Peut-on reproduire les algorithmes GDS en Cypher pur ?

**Degree Centrality** : Oui, performances similaires
**Triangle Count** : Oui, compétitif (attention : diviser par 3 !)

**Limite** : Algorithmes simples seulement. Pour Dijkstra, PageRank, Betweenness → GDS indispensable

---

### 5. Contraintes Temporelles

**Problème** : LAX → JFK avec minimum 45min de correspondance entre vols

**Cypher 25** :
```cypher
WHERE allReduce(
  prev_arrival = datetime('2015-01-01T00:00:00'),
  rel IN f |
    CASE
      WHEN duration.between(prev_arrival, rel.departure_ts).minutes >= 45
      THEN rel.arrival_ts
      ELSE null
    END,
  prev_arrival IS NOT NULL
)
```

**Avantage** : `allReduce()` accumule l'état (heure d'arrivée précédente) et filtre en une seule passe

---

## Comparaison avec SQL

**SQL récursif** (WITH RECURSIVE) :
- 44 lignes vs 10 pour Cypher 25
- Verbeux, logique métier noyée dans la syntaxe
- Gestion manuelle des timestamps
- Performances comparables à Cypher 5 (pas d'équivalent à `allReduce()`)

**Verdict** : SQL pas adapté aux path queries complexes

---

## Points Clés à Retenir

### Apports de Cypher 25

1. **`allReduce()`** : Filtre incrémental pendant la traversée
   - Évite l'explosion combinatoire
   - Accumule un état (delay, timestamp, nœuds visités)

2. **Quantified Patterns** `{n,m}` :
   - Code plus concis et maintenable
   - Flexibilité pour changer la profondeur

3. **Opérateur Trail** : Pruning inline dans le plan d'exécution

### Limites

1. **Chemins pondérés** : Cypher pur timeout au-delà de 2-3 sauts → GDS obligatoire

2. **Dataset limité** : 1 semaine = max 2-3 escales testables

3. **REPEATABLE ELEMENTS** : Non testé (pas pertinent pour vols uniques)

### Résultats Principaux

| Métrique | Cypher 5 | Cypher 25 | Amélioration |
|----------|----------|-----------|--------------|
| Temps | 1500 ms | 3,5 ms | **99,8%** |
| DB Hits | 16,3M | 39,9k | **99,7%** |
| Rows | 320k | 9,3k | **97,1%** |

---

## Démonstration Possible

### Requête à Montrer en Live (si demandé)

**01_increasing_property_paths.cypher** (Cypher 25) :
```cypher
MATCH path = (start:Airport {iata_code: 'LAX'})
  ((:Airport)-[f:FLIGHT]->(:Airport)){2,4}
  (end:Airport {iata_code: 'JFK'})
WHERE allReduce(
  prev_delay = -999999.0,
  rel IN f |
    CASE
      WHEN rel.delay > prev_delay THEN rel.delay
      ELSE null
    END,
  prev_delay IS NOT NULL
)
RETURN path LIMIT 50;
```

**Point à souligner** : Le `CASE ... ELSE null` arrête la propagation si la condition échoue

---

## Questions Anticipées

### "Pourquoi pas un dataset plus grand ?"
- Volume raisonnable pour tests locaux
- 107k vols suffisants pour observer l'explosion combinatoire
- Focus sur la comparaison qualitative des approches

### "Quelle est l'utilisation concrète ?"
- Optimisation d'itinéraires multi-vols
- Détection d'anomalies (retards croissants = problème opérationnel)
- Analyse de résilience du réseau aérien

### "Cypher 25 est-il toujours meilleur ?"
- Non ! Pour chemins pondérés, GDS >> Cypher 25
- Pour algorithmes simples (degree, triangles), gain marginal
- **Domaine optimal** : path queries avec contraintes accumulatives

### "Pourquoi Neo4j plutôt que PostgreSQL ?"
- SQL pas conçu pour path queries (WITH RECURSIVE verbeux)
- Neo4j natif pour traversées de graphes
- Index adaptés aux relations (pas aux jointures)

---

## Structure Recommandée de l'Oral

1. **Introduction** (30s)
   - Problématique : Cypher 5 vs 25 sur données réelles
   - Dataset : vols américains janvier 2015

2. **Modélisation** (1 min)
   - Pourquoi ce dataset (vs IDFM)
   - Structure du graphe

3. **Comparaisons** (3-4 min)
   - **Focus sur #1** (chemins croissants) : résultat le plus spectaculaire
   - Mentionner #2 (patterns quantifiés) et #5 (contraintes temporelles)
   - **Aborder #3** (limites de Cypher pur pour chemins pondérés)

4. **Résultats** (1 min)
   - Tableau comparatif
   - Conclusion : quand utiliser quoi

5. **Limites et Extensions** (30s)
   - Dataset limité, pas de pgRouting testé

6. **Questions** (reste du temps)

---

## Vocabulaire Technique à Maîtriser

- **VarLengthExpand** : Opérateur Cypher 5 qui génère tous les chemins d'une longueur variable
- **Trail** : Opérateur Cypher 25 qui filtre pendant la traversée
- **allReduce()** : Fonction Cypher 25 pour accumuler un état incrémentalement
- **GDS (Graph Data Science)** : Bibliothèque Neo4j pour algorithmes avancés
- **DB Hits** : Nombre d'accès à la base (métrique de performance Neo4j)
- **Quantified Patterns** : Syntaxe `{n,m}` pour répétitions de patterns
- **Explosion combinatoire** : Croissance exponentielle du nombre de chemins
