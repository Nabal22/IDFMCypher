import pandas as pd
import numpy as np

# 1. Chargement des données (on ne charge que les colonnes utiles pour économiser la RAM)
print("Chargement des vols...")
cols_to_keep = ['YEAR', 'MONTH', 'DAY', 'AIRLINE', 'FLIGHT_NUMBER', 
                'ORIGIN_AIRPORT', 'DESTINATION_AIRPORT', 
                'DEPARTURE_TIME', 'ARRIVAL_TIME', 'DISTANCE', 'DEPARTURE_DELAY']

# On lit tout le fichier mais c'est rapide si on filtre ensuite
df = pd.read_csv('../source/flights.csv', usecols=cols_to_keep)

# 2. Filtrage : On garde seulement les 7 premiers jours de Janvier
# Cela donne environ 100k lignes, soit ~10-15 Mo
df_small = df[(df['MONTH'] == 1) & (df['DAY'] <= 15)].copy()

# 3. Nettoyage et Formatage des Dates pour Neo4j
print("Nettoyage des dates...")

# Fonction pour convertir le format '1345' (float) en '13:45:00'
def format_time(t):
    if pd.isna(t): return None
    s = str(int(t)).zfill(4) # Transforme 900.0 en "0900"
    if s == '2400': s = '0000' # Gestion minuit
    if len(s) > 4: return None
    return f"{s[:2]}:{s[2:]}:00"

# Création de la colonne timestamp complète (ISO 8601)
# Format attendu par Neo4j : "YYYY-MM-DDTHH:MM:SS"
df_small['dep_time_str'] = df_small['DEPARTURE_TIME'].apply(format_time)
df_small = df_small.dropna(subset=['dep_time_str']) # On vire les vols annulés sans heure

df_small['full_date'] = (
    df_small['YEAR'].astype(str) + '-' + 
    df_small['MONTH'].astype(str).str.zfill(2) + '-' + 
    df_small['DAY'].astype(str).str.zfill(2) + 'T' + 
    df_small['dep_time_str']
)

# 4. Finalisation du fichier Vols
# On garde les colonnes propres pour l'export
final_flights = df_small[['ORIGIN_AIRPORT', 'DESTINATION_AIRPORT', 'AIRLINE', 
                          'full_date', 'DISTANCE', 'DEPARTURE_DELAY']]
final_flights.columns = ['source', 'target', 'airline', 'timestamp', 'distance', 'delay']

# 5. Préparation des Aéroports (Noeuds)
print("Préparation des aéroports...")
airports = pd.read_csv('../source/airports.csv')
# On ne garde que les aéroports présents dans nos vols filtrés
valid_airports = set(final_flights['source']).union(set(final_flights['target']))
final_airports = airports[airports['IATA_CODE'].isin(valid_airports)]

# 6. Export en CSV
print("Exportation...")
final_flights.to_csv('../import/flights_projet.csv', index=False)
final_airports.to_csv('../import/airports_projet.csv', index=False)

print(f"Terminé ! Fichier vols : {len(final_flights)} lignes.")