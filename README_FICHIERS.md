# Documentation des fichiers GTFS - Île-de-France Mobilités

Nous utilisons le format GTFS (General Transit Feed Specification) pour fournir des données de transport en commun pour la région Île-de-France. Ce document décrit les différents fichiers inclus dans l'export GTFS, leur contenu, et comment les utiliser.

## Format GTFS

GTFS est un format standard utilisé pour représenter les horaires et les informations géographiques des réseaux de transport en commun. Ces données permettent aux applications de planification d'itinéraires d'intégrer les informations de transport.

---
## Description des fichiers

Tous les fichiers sont dans le dossier `export/` et sont au format texte délimité par des virgules (CSV), avec une ligne d'en-tête.

## Liste des fichiers

### 1. **agency.csv** (6,7 Ko)
**Description :** Informations sur les agences de transport exploitant les lignes.

**Contenu :**
- `agency_id` : Identifiant unique de l'agence
- `agency_name` : Nom de l'agence (ex: RATP, Aérobus)
- `agency_url` : Site web de l'agence
- `agency_timezone` : Fuseau horaire (Europe/Paris)
- `agency_fare_url` : URL pour les informations tarifaires

**Exemple d'utilisation :** Identifier quel opérateur gère une ligne de transport donnée.

---

### 2. **calendar.csv** (37,6 Ko)
**Description :** Définit les périodes de service régulières (jours de la semaine où un service fonctionne).

**Contenu :**
- `service_id` : Identifiant unique du calendrier de service
- `monday`, `tuesday`, `wednesday`, etc. : 1 si le service fonctionne ce jour, 0 sinon
- `start_date` : Date de début du service (format YYYYMMDD)
- `end_date` : Date de fin du service

**Exemple d'utilisation :** Déterminer si un bus circule un mardi spécifique.

---

### 3. **calendar_dates.csv** (31,9 Ko)
**Description :** Exceptions aux calendriers réguliers (jours fériés, grèves, modifications ponctuelles).

**Contenu :**
- `service_id` : Référence au calendrier concerné
- `date` : Date de l'exception (format YYYYMMDD)
- `exception_type` :
  - 1 = Service ajouté ce jour
  - 2 = Service supprimé ce jour

**Exemple d'utilisation :** Savoir qu'une ligne ne circule pas le 1er mai (jour férié).

---

### 4. **feed_info.csv** (164 octets)
**Description :** Métadonnées sur l'export GTFS lui-même.

**Contenu :**
- `feed_publisher_name` : Nom du producteur du flux (ITO World)
- `feed_publisher_url` : Site web du producteur
- `feed_lang` : Langue du flux (EN)
- `feed_start_date` : Date de début de validité des données
- `feed_end_date` : Date de fin de validité des données
- `feed_version` : Version de l'export (20251231_200102)

**Exemple d'utilisation :** Vérifier la période de validité des données avant de les utiliser.

---

### 5. **pathways.csv** (359,7 Ko)
**Description :** Chemins piétons au sein des stations (passages, escaliers, ascenseurs).

**Contenu :**
- `pathway_id` : Identifiant unique du chemin
- `from_stop_id` : Point de départ
- `to_stop_id` : Point d'arrivée
- `pathway_mode` : Type de chemin (1 = passage piéton, 2 = escalier, etc.)
- `is_bidirectional` : 1 si bidirectionnel, 0 sinon
- `length` : Longueur en mètres
- `traversal_time` : Temps de traversée en secondes

**Exemple d'utilisation :** Calculer le temps de correspondance entre deux quais dans une station.

---

### 6. **routes.csv** (79,3 Ko)
**Description :** Lignes de transport (bus, métro, RER, tramway).

**Contenu :**
- `route_id` : Identifiant unique de la ligne
- `agency_id` : Agence exploitant la ligne
- `route_short_name` : Nom court (numéro de ligne)
- `route_long_name` : Nom complet de la ligne
- `route_type` : Type de transport (0=tram, 1=métro, 2=train, 3=bus, etc.)
- `route_color` : Couleur de la ligne en hexadécimal
- `route_text_color` : Couleur du texte

**Exemple d'utilisation :** Afficher toutes les lignes de métro avec leurs couleurs officielles.

---

### 7. **stop_times.csv** (796,5 Mo) ⚠️ **FICHIER VOLUMINEUX**
**Description :** Horaires détaillés de passage à chaque arrêt pour chaque trajet.

**Contenu :**
- `trip_id` : Référence au trajet
- `arrival_time` : Heure d'arrivée (format HH:MM:SS, peut dépasser 24h)
- `departure_time` : Heure de départ
- `stop_id` : Référence à l'arrêt
- `stop_sequence` : Ordre de l'arrêt dans le trajet
- `stop_headsign` : Indication de direction
- `pickup_type` : Type de montée (0=régulier, 1=non disponible)
- `drop_off_type` : Type de descente
- `timepoint` : 1 si horaire exact, 0 si approximatif

**Exemple d'utilisation :** Obtenir tous les horaires de passage d'un bus à un arrêt spécifique.

---

### 8. **stops.csv** (3,5 Mo)
**Description :** Liste de tous les arrêts, stations et points d'accès.

**Contenu :**
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

**Exemple d'utilisation :** Trouver tous les arrêts accessibles en fauteuil roulant dans un rayon de 500m.

---

### 9. **transfers.csv** (6,2 Mo)
**Description :** Correspondances possibles entre arrêts et temps de correspondance.

**Contenu :**
- `from_stop_id` : Arrêt de départ
- `to_stop_id` : Arrêt d'arrivée
- `transfer_type` : Type de correspondance
  - 0 = Point de correspondance recommandé
  - 1 = Point de correspondance chronométré
  - 2 = Temps de correspondance minimum requis
  - 3 = Correspondance impossible
- `min_transfer_time` : Temps minimum de correspondance en secondes

**Exemple d'utilisation :** Calculer si une correspondance est faisable en 3 minutes.

---

### 10. **trips.csv** (33,7 Mo)
**Description :** Trajets individuels effectués sur une ligne.

**Contenu :**
- `route_id` : Référence à la ligne
- `service_id` : Référence au calendrier
- `trip_id` : Identifiant unique du trajet
- `trip_headsign` : Destination affichée
- `trip_short_name` : Nom court du trajet
- `direction_id` : Direction (0 ou 1)
- `wheelchair_accessible` : Accessibilité PMR (0=inconnu, 1=accessible, 2=non accessible)
- `bikes_allowed` : Vélos autorisés (0=inconnu, 1=oui, 2=non)

**Exemple d'utilisation :** Lister tous les trajets d'une ligne de métro vers une destination donnée.

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

## Informations pratiques

- **Période de validité :** 27 décembre 2025 au 28 janvier 2026
- **Version :** 20251231_200102
- **Producteur :** ITO World
- **Opérateurs :** RATP, Aérobus
- **Fuseau horaire :** Europe/Paris

---

## Utilisation recommandée

1. **Planification d'itinéraires :** Combiner `routes.csv`, `trips.csv`, `stop_times.csv` et `stops.csv`
2. **Accessibilité :** Filtrer par `wheelchair_boarding` dans `stops.csv` et `wheelchair_accessible` dans `trips.csv`
3. **Temps réel :** Ces données sont statiques ; pour le temps réel, utiliser l'API GTFS-RT
4. **Calcul de correspondances :** Utiliser `transfers.csv` et `pathways.csv`

---

## Ressources supplémentaires

- Spécification GTFS complète : https://gtfs.org/
- Portail Île-de-France Mobilités : https://www.iledefrance-mobilites.fr
- API et données : https://app.idf-mobilites.fr/gtfs
