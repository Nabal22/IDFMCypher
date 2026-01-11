# Modèle de Données - Flight Network Graph

## Vue d'Ensemble

Le graphe représente un réseau de vols aériens avec :
- **Nœuds** : Aéroports et Compagnies aériennes
- **Relations** : Vols entre aéroports

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

## PostgreSQL (Relationnel)

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

## Statistiques du Dataset

### Noeuds
- **Airports** : 313
- **Airlines** : 14

### Relations
- **Flights** : 107,230

### Période
- **Du** : 1er janvier 2015, 00:00
- **Au** : 7 janvier 2015, 23:59

