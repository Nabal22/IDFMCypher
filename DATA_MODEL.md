# Modèle de Données - Flight Network Graph

## Vue d'Ensemble

Le graphe représente un réseau de vols aériens avec :
- **Nœuds** : Aéroports et Compagnies aériennes
- **Relations** : Vols entre aéroports

## Schéma du Graphe

```
┌─────────────────────────────────────────────────────────────────┐
│                    MODÈLE DE GRAPHE                              │
└─────────────────────────────────────────────────────────────────┘

    ┌──────────────┐                           ┌──────────────┐
    │   :Airport   │                           │   :Airline   │
    ├──────────────┤                           ├──────────────┤
    │ iata_code    │                           │ iata_code    │
    │ name         │                           │ name         │
    │ city         │                           └──────────────┘
    │ state        │
    │ country      │
    │ latitude     │
    │ longitude    │
    └──────┬───────┘
           │
           │ [:FLIGHT]
           │ ┌────────────────────┐
           │ │ airline            │
           │ │ airline_name       │
           ├─┤ departure_ts       │
           │ │ arrival_ts         │
           │ │ distance           │
           │ │ delay              │
           │ └────────────────────┘
           │
           ▼
    ┌──────────────┐
    │   :Airport   │
    └──────────────┘
```

## Détail des Nœuds

### Label: `Airport`

Représente un aéroport dans le réseau.

| Propriété    | Type    | Description                          | Exemple        |
|--------------|---------|--------------------------------------|----------------|
| `iata_code`  | String  | Code IATA unique (3 lettres)         | "LAX"          |
| `name`       | String  | Nom complet de l'aéroport            | "Los Angeles International Airport" |
| `city`       | String  | Ville                                | "Los Angeles"  |
| `state`      | String  | État (US)                            | "CA"           |
| `country`    | String  | Pays                                 | "USA"          |
| `latitude`   | Float   | Latitude GPS                         | 33.9416        |
| `longitude`  | Float   | Longitude GPS                        | -118.4085      |

**Contraintes :**
- `iata_code` : UNIQUE

**Index :**
- `city`
- `state`

### Label: `Airline`

Représente une compagnie aérienne.

| Propriété    | Type    | Description                          | Exemple        |
|--------------|---------|--------------------------------------|----------------|
| `iata_code`  | String  | Code IATA unique (2 lettres)         | "AA"           |
| `name`       | String  | Nom de la compagnie                  | "American Airlines Inc." |

**Contraintes :**
- `iata_code` : UNIQUE

## Détail des Relations

### Type: `FLIGHT`

Représente un vol entre deux aéroports.

| Propriété      | Type     | Description                          | Exemple        |
|----------------|----------|--------------------------------------|----------------|
| `airline`      | String   | Code IATA de la compagnie            | "AA"           |
| `airline_name` | String   | Nom de la compagnie (dénormalisé)    | "American Airlines Inc." |
| `departure_ts` | DateTime | Timestamp de départ (ISO 8601)       | 2015-01-01T08:00:00 |
| `arrival_ts`   | DateTime | Timestamp d'arrivée (ISO 8601)       | 2015-01-01T11:30:00 |
| `distance`     | Integer  | Distance du vol en miles             | 2475           |
| `delay`        | Float    | Retard au départ en minutes (peut être négatif) | 15.0 |

**Index :**
- `departure_ts`
- `arrival_ts`
- `delay`
- `distance`

## Statistiques du Dataset

### Noeuds
- **Airports** : 313
- **Airlines** : 14

### Relations
- **Flights** : 107,230

### Période
- **Du** : 1er janvier 2015, 00:00
- **Au** : 7 janvier 2015, 23:59

## Requêtes de Schéma

### Afficher le schéma complet
```cypher
CALL db.schema.visualization();
```

### Lister les contraintes
```cypher
SHOW CONSTRAINTS;
```

### Lister les index
```cypher
SHOW INDEXES;
```

### Compter les labels
```cypher
CALL db.labels() YIELD label
CALL apoc.cypher.run('MATCH (n:' + label + ') RETURN count(n) as count', {})
YIELD value
RETURN label, value.count as count;
```

## Patterns de Requêtes Courants

### 1. Vol Direct
```cypher
MATCH (origin:Airport)-[f:FLIGHT]->(dest:Airport)
WHERE origin.iata_code = 'LAX' AND dest.iata_code = 'JFK'
RETURN f;
```

### 2. Vols avec 1 Escale
```cypher
MATCH path = (origin:Airport)-[:FLIGHT]->(hub:Airport)-[:FLIGHT]->(dest:Airport)
WHERE origin.iata_code = 'LAX' AND dest.iata_code = 'JFK'
RETURN path
LIMIT 10;
```

### 3. Vols avec Escales (Longueur Variable)
```cypher
MATCH path = (origin:Airport)-[:FLIGHT*1..3]->(dest:Airport)
WHERE origin.iata_code = 'LAX' AND dest.iata_code = 'JFK'
RETURN path
LIMIT 10;
```

### 4. Plus Court Chemin (Distance)
```cypher
MATCH (origin:Airport {iata_code: 'LAX'})
MATCH (dest:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((origin)-[:FLIGHT*]->(dest))
RETURN path;
```

### 5. Chemins avec Contrainte de Temps (Correspondances Valides)
```cypher
// Cypher 25 : vérifier que chaque correspondance a au moins 30 min
MATCH path = (origin:Airport {iata_code: 'LAX'})
  -[:FLIGHT*1..3]->(dest:Airport {iata_code: 'JFK'})
WHERE allReduce(valid = true, i IN range(0, size(relationships(path))-2) |
  valid AND
  relationships(path)[i].arrival_ts + duration({minutes: 30})
    <= relationships(path)[i+1].departure_ts
)
RETURN path
LIMIT 10;
```

### 6. Analyse de Hub (Degré des Nœuds)
```cypher
MATCH (a:Airport)
OPTIONAL MATCH (a)-[out:FLIGHT]->()
OPTIONAL MATCH (a)<-[in:FLIGHT]-()
RETURN
  a.iata_code,
  a.city,
  count(DISTINCT out) as out_degree,
  count(DISTINCT in) as in_degree,
  count(DISTINCT out) + count(DISTINCT in) as total_degree
ORDER BY total_degree DESC
LIMIT 10;
```

## Propriétés Calculées Utiles

### Durée du Vol
```cypher
MATCH ()-[f:FLIGHT]->()
RETURN
  f.departure_ts,
  f.arrival_ts,
  duration.between(f.departure_ts, f.arrival_ts) as flight_duration;
```

### Distance Haversine (si besoin de recalculer)
```cypher
MATCH (a1:Airport)-[f:FLIGHT]->(a2:Airport)
RETURN
  f.distance as reported_distance,
  point.distance(
    point({latitude: a1.latitude, longitude: a1.longitude}),
    point({latitude: a2.latitude, longitude: a2.longitude})
  ) / 1609.34 as calculated_distance_miles;
```

### Vitesse Moyenne du Vol
```cypher
MATCH ()-[f:FLIGHT]->()
WITH f, duration.between(f.departure_ts, f.arrival_ts).minutes as duration_min
WHERE duration_min > 0
RETURN
  f.distance,
  duration_min,
  (f.distance * 60.0) / duration_min as avg_speed_mph
LIMIT 10;
```

## Considérations de Performance

### Utiliser les Index
Les requêtes suivantes bénéficient des index existants :

```cypher
// ✅ Utilise l'index sur iata_code
MATCH (a:Airport {iata_code: 'LAX'})

// ✅ Utilise l'index sur departure_ts
MATCH ()-[f:FLIGHT]->()
WHERE f.departure_ts >= datetime('2015-01-01T00:00:00')
  AND f.departure_ts < datetime('2015-01-02T00:00:00')

// ✅ Utilise l'index sur delay
MATCH ()-[f:FLIGHT]->()
WHERE f.delay > 30
```

### Éviter les Scans Complets
```cypher
// ❌ Mauvais : scan complet
MATCH (a:Airport)
WHERE a.name CONTAINS 'International'

// ✅ Mieux : utiliser l'index city si possible
MATCH (a:Airport {city: 'Los Angeles'})
```

## Évolutions Possibles du Modèle

### Option 1 : Relation vers Airline
Actuellement, l'airline est dénormalisée dans la relation FLIGHT.
On pourrait la normaliser :

```cypher
(Airport)-[:FLIGHT {departure_ts, arrival_ts, distance, delay}]->(Airport)
(Flight)-[:OPERATED_BY]->(Airline)
```

**Avantages :** Normalisation, pas de duplication
**Inconvénients :** Requêtes plus complexes, 2 relations à traverser

### Option 2 : Nœud Flight
Transformer la relation en nœud :

```cypher
(Airport)-[:DEPARTS_FROM]->(Flight)-[:ARRIVES_AT]->(Airport)
(Flight)-[:OPERATED_BY]->(Airline)
```

**Avantages :** Plus flexible pour ajouter des propriétés ou relations
**Inconvénients :** Modèle plus complexe, plus de nœuds

### Option 3 : Ajout de Nœuds Temporels
Pour des requêtes temporelles complexes :

```cypher
(Airport)-[:FLIGHT]->(Airport)
(Flight)-[:ON_DATE]->(Date)
(Flight)-[:AT_HOUR]->(Hour)
```

**Avantages :** Requêtes temporelles très rapides
**Inconvénients :** Beaucoup plus de nœuds et relations

**→ Pour ce projet, le modèle actuel (simple) est optimal**
