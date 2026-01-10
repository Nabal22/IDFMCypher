# Documentation GTFS - Île-de-France Mobilités

Référence complète pour les données IDFM au format GTFS (General Transit Feed Specification). Ces données représentent les horaires et informations géographiques des réseaux de transport en commun de la région Île-de-France.

## Vue d'ensemble des fichiers

| Fichier | Taille | Records | Description |
|---------|--------|---------|-------------|
| `stop_times.csv` | 796 MB | ~15M | **VOLUMINEUX** - Horaires à chaque arrêt |
| `trips.csv` | 33.7 MB | ~500K | Trajets individuels |
| `transfers.csv` | 6.2 MB | ~200K | Correspondances entre arrêts |
| `stops.csv` | 3.5 MB | ~50K | Arrêts et stations |
| `pathways.csv` | 359 KB | ~10K | Chemins piétons en station |
| `routes.csv` | 79 KB | ~2K | Lignes de transport |
| `calendar.csv` | 38 KB | - | Calendriers de service |
| `calendar_dates.csv` | 32 KB | - | Exceptions calendaires |
| `agency.csv` | 7 KB | 2 | RATP, Aérobus |
| **`stop_times_subset.csv`** | 30 MB | ~394K | **Subset métro** |
| **`trips_subset.csv`** | 6 MB | ~15K | **Subset métro** |

---

## ⚠️ Fichiers Subset - Cohérence des Données

En raison de la taille des fichiers originaux (796 MB + 33.7 MB), des versions réduites sont générées :

### Pourquoi générer les subsets ?

1. **Volumétrie** : Les fichiers complets sont difficiles à traiter (30 min d'import, problèmes mémoire Neo4j)
2. **Cohérence relationnelle** : Les deux fichiers sont filtrés ensemble pour garantir l'intégrité référentielle
   - Chaque `trip_id` dans `stop_times_subset.csv` existe dans `trips_subset.csv`
   - Aucun trajet orphelin (trip sans horaires)
   - Aucun horaire orphelin (stop_time sans trip)
   - Essentiel pour PostgreSQL (clés étrangères) ET Neo4j (relations valides)

### Génération des subsets

```bash
# Default : lignes 3, 7, 14, 11
./generate_subset_files.sh

# Personnaliser les lignes
METRO_LINES="11" ./generate_subset_files.sh
METRO_LINES="1 4 6 14" ./generate_subset_files.sh
```

**Stratégie de filtrage** (optimisé awk, 10-20 secondes) :
1. Extraction des `route_id` pour les lignes de métro spécifiées (route_type=1)
2. Extraction des `trip_id` associés → `trips_subset.csv`
3. Extraction des `stop_times` correspondants → `stop_times_subset.csv`

### Utilisation recommandée

- **PostgreSQL** : Peut utiliser fichiers complets OU subsets (performances suffisantes)
- **Neo4j** : DOIT utiliser subsets (évite problèmes mémoire)
- **Important** : Utiliser les subsets pour TOUTES les bases si on les utilise (cohérence PostgreSQL ↔ Neo4j)

---

## Description détaillée des fichiers

### 1. agency.csv (6,7 Ko)
Informations sur les agences de transport exploitant les lignes.

**Colonnes** :
- `agency_id` : Identifiant unique de l'agence
- `agency_name` : Nom de l'agence (ex: RATP, Aérobus)
- `agency_url` : Site web de l'agence
- `agency_timezone` : Fuseau horaire (Europe/Paris)
- `agency_fare_url` : URL pour les informations tarifaires

**Exemple** : Identifier quel opérateur gère une ligne de transport donnée.

---

### 2. routes.csv (79,3 Ko)
Lignes de transport (bus, métro, RER, tramway).

**Colonnes** :
- `route_id` : Identifiant unique de la ligne
- `agency_id` : Agence exploitant la ligne
- `route_short_name` : Nom court (numéro de ligne)
- `route_long_name` : Nom complet de la ligne
- `route_type` : Type de transport (0=tram, 1=métro, 2=train, 3=bus, etc.)
- `route_color` : Couleur de la ligne en hexadécimal
- `route_text_color` : Couleur du texte

**Exemple** : Afficher toutes les lignes de métro avec leurs couleurs officielles.

---

### 3. trips.csv (33,7 Mo)
Trajets individuels effectués sur une ligne.

**Colonnes** :
- `route_id` : Référence à la ligne
- `service_id` : Référence au calendrier
- `trip_id` : Identifiant unique du trajet
- `trip_headsign` : Destination affichée
- `trip_short_name` : Nom court du trajet
- `direction_id` : Direction (0 ou 1)
- `wheelchair_accessible` : Accessibilité PMR (0=inconnu, 1=accessible, 2=non accessible)
- `bikes_allowed` : Vélos autorisés (0=inconnu, 1=oui, 2=non)

**Exemple** : Lister tous les trajets d'une ligne de métro vers une destination donnée.

---

### 4. stop_times.csv (796,5 Mo) ⚠️ VOLUMINEUX
Horaires détaillés de passage à chaque arrêt pour chaque trajet.

**Colonnes** :
- `trip_id` : Référence au trajet
- `arrival_time` : Heure d'arrivée (format HH:MM:SS, peut dépasser 24h)
- `departure_time` : Heure de départ
- `stop_id` : Référence à l'arrêt
- `stop_sequence` : Ordre de l'arrêt dans le trajet
- `stop_headsign` : Indication de direction
- `pickup_type` : Type de montée (0=régulier, 1=non disponible)
- `drop_off_type` : Type de descente
- `timepoint` : 1 si horaire exact, 0 si approximatif

**Exemple** : Obtenir tous les horaires de passage d'un bus à un arrêt spécifique.

**Note** : Fichier trop volumineux, utiliser `stop_times_subset.csv` généré par le script.

---

### 5. stops.csv (3,5 Mo)
Liste de tous les arrêts, stations et points d'accès.

**Colonnes** :
- `stop_id` : Identifiant unique de l'arrêt
- `stop_code` : Code visible par les usagers
- `stop_name` : Nom de l'arrêt
- `stop_lat` : Latitude (WGS84)
- `stop_lon` : Longitude (WGS84)
- `wheelchair_boarding` : Accessibilité PMR (0=inconnu, 1=accessible, 2=non accessible)
- `stop_timezone` : Fuseau horaire
- `location_type` : Type (0=arrêt, 1=station, 2=entrée/sortie, etc.)
- `parent_station` : Station parente si applicable
- `level_id` : Niveau (étage)

**Exemple** : Trouver tous les arrêts accessibles en fauteuil roulant dans un rayon de 500m.

---

### 6. transfers.csv (6,2 Mo)
Correspondances possibles entre arrêts et temps de correspondance.

**Colonnes** :
- `from_stop_id` : Arrêt de départ
- `to_stop_id` : Arrêt d'arrivée
- `transfer_type` : Type de correspondance
  - 0 = Point de correspondance recommandé
  - 1 = Point de correspondance chronométré
  - 2 = Temps de correspondance minimum requis
  - 3 = Correspondance impossible
- `min_transfer_time` : Temps minimum de correspondance en secondes

**Exemple** : Calculer si une correspondance est faisable en 3 minutes.

---

### 7. pathways.csv (359,7 Ko)
Chemins piétons au sein des stations (passages, escaliers, ascenseurs).

**Colonnes** :
- `pathway_id` : Identifiant unique du chemin
- `from_stop_id` : Point de départ
- `to_stop_id` : Point d'arrivée
- `pathway_mode` : Type de chemin (1 = passage piéton, 2 = escalier, etc.)
- `is_bidirectional` : 1 si bidirectionnel, 0 sinon
- `length` : Longueur en mètres
- `traversal_time` : Temps de traversée en secondes

**Exemple** : Calculer le temps de correspondance entre deux quais dans une station.

---

### 8. calendar.csv (37,6 Ko)
Définit les périodes de service régulières (jours de la semaine où un service fonctionne).

**Colonnes** :
- `service_id` : Identifiant unique du calendrier de service
- `monday`, `tuesday`, `wednesday`, etc. : 1 si le service fonctionne ce jour, 0 sinon
- `start_date` : Date de début du service (format YYYYMMDD)
- `end_date` : Date de fin du service

**Exemple** : Déterminer si un bus circule un mardi spécifique.

---

### 9. calendar_dates.csv (31,9 Ko)
Exceptions aux calendriers réguliers (jours fériés, grèves, modifications ponctuelles).

**Colonnes** :
- `service_id` : Référence au calendrier concerné
- `date` : Date de l'exception (format YYYYMMDD)
- `exception_type` :
  - 1 = Service ajouté ce jour
  - 2 = Service supprimé ce jour

**Exemple** : Savoir qu'une ligne ne circule pas le 1er mai (jour férié).

---

## Relations entre les fichiers

```
agency.csv
    ↓
routes.csv (lignes exploitées par les agences)
    ↓
trips.csv (trajets sur ces lignes)
    ↓
stop_times.csv (horaires détaillés pour chaque trajet)
    ↓
stops.csv (arrêts desservis)
    ↓
transfers.csv (correspondances entre arrêts)
    ↓
pathways.csv (chemins au sein des stations)

calendar.csv + calendar_dates.csv → Déterminent quand les trajets fonctionnent
```

---

## Champs importants pour le projet

### Propriétés numériques pour les arêtes du graphe
- `min_transfer_time` (transfers.csv) - Durée de correspondance en secondes
- `traversal_time` (pathways.csv) - Temps de marche en secondes
- `length` (pathways.csv) - Distance en mètres
- `arrival_time`, `departure_time` (stop_times.csv) - Horodatages
- **Dérivée** : `travel_time` = arrival suivant - departure actuel

### Filtrage
- `wheelchair_boarding` (stops.csv) : 0=inconnu, 1=accessible, 2=non accessible
- `wheelchair_accessible` (trips.csv) : 0=inconnu, 1=accessible, 2=non accessible
- `route_type` (routes.csv) : 0=tram, 1=métro, 2=train, 3=bus
- `transfer_type` (transfers.csv) : 0=recommandé, 1=chronométré, 2=min requis, 3=impossible

### Localisation
- `stop_lat`, `stop_lon` (stops.csv) - Coordonnées WGS84
- `location_type` (stops.csv) : 0=arrêt, 1=station, 2=entrée

---

## Exemples de requêtes

### PostgreSQL

```sql
-- Arrêts sur une ligne
SELECT DISTINCT s.stop_name
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
WHERE t.route_id = '100110';  -- RER A

-- Temps de trajet entre arrêts consécutifs
SELECT st1.stop_id as from_stop, st2.stop_id as to_stop,
       st2.arrival_time - st1.departure_time as travel_time
FROM stop_times st1
JOIN stop_times st2 ON st1.trip_id = st2.trip_id
  AND st2.stop_sequence = st1.stop_sequence + 1;
```

### Neo4j

```cypher
// Arrêts sur une ligne
MATCH (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route {route_id: '100110'})
RETURN DISTINCT s.stop_name;

// Correspondances depuis un arrêt
MATCH (s:Stop {stop_name: 'Châtelet'})-[t:TRANSFER]->(dest:Stop)
RETURN dest.stop_name, t.min_transfer_time
ORDER BY t.min_transfer_time;
```

---

## Stratégies de subsetting

### Par type de route
```sql
-- Métro uniquement (route_type = 1)
WHERE route_type = 1

-- Bus uniquement (route_type = 3)
WHERE route_type = 3
```

### Par zone géographique
```sql
-- Centre de Paris (bornes approximatives)
WHERE stop_lat BETWEEN 48.8 AND 48.9
  AND stop_lon BETWEEN 2.3 AND 2.4
```

### Par fenêtre horaire
```sql
-- Heure de pointe matinale
WHERE departure_time BETWEEN '07:00:00' AND '09:00:00'
```

---

## Notes sur la qualité des données

- Les horaires peuvent dépasser 24:00:00 (ex: 25:30:00 pour 1h30 du matin le jour suivant)
- Certains arrêts ont un `parent_station` (entrées → station)
- Tous les transfers n'ont pas de `min_transfer_time` (peut être NULL)
- `stop_code` est visible par l'usager, `stop_id` est interne

---

## Informations pratiques

- **Période de validité** : 27 décembre 2025 au 28 janvier 2026
- **Version** : 20251231_200102
- **Producteur** : ITO World
- **Opérateurs** : RATP, Aérobus
- **Fuseau horaire** : Europe/Paris

---

## Ressources

- Spécification GTFS complète : https://gtfs.org/
- Portail Île-de-France Mobilités : https://www.iledefrance-mobilites.fr
- API et données : https://app.idf-mobilites.fr/gtfs
