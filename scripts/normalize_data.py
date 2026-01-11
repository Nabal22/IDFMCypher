import pandas as pd
import numpy as np

# --- CONFIGURATION ---
INPUT_FLIGHTS = '../source/flights.csv'
INPUT_AIRPORTS = '../source/airports.csv'
OUTPUT_FLIGHTS = '../import/flights_projet.csv'
OUTPUT_AIRPORTS = '../import/airports_projet.csv'

# 1. Chargement uniquement des colonens voulues
columns_to_keep = [
    'YEAR', 'MONTH', 'DAY',
    'AIRLINE',
    'ORIGIN_AIRPORT', 'DESTINATION_AIRPORT',
    'DEPARTURE_TIME', 'ARRIVAL_TIME',
    'DEPARTURE_DELAY', 'DISTANCE'
]

print("Lecture du fichier flights.csv ...")

dtype_dict = {'ORIGIN_AIRPORT': str, 'DESTINATION_AIRPORT': str}
df = pd.read_csv(INPUT_FLIGHTS, usecols=columns_to_keep, dtype=dtype_dict)

print(f"Nombre de lignes chargées : {len(df)}")

# 2. Filtre des vols sur la date (1ère semaine de l'année)
df_small = df[
    (df['MONTH'] == 1) &
    (df['DAY'] <= 7)
].copy()

print(f"Taille de l'échantillon : {len(df_small)}")

print("Calcul des timestamps Départ et Arrivée...")

# On nettoie les lignes vides
df_small = df_small.dropna(subset=['DEPARTURE_TIME', 'ARRIVAL_TIME'])

def format_time_str(t):
    try:
        s = str(int(t)).zfill(4)
        if s == '2400': s = '0000'
        if len(s) > 4: return None
        return f"{s[:2]}:{s[2:]}:00"
    except:
        return None

# Formattage des horaires de départs et d'arrivée
df_small['dep_time_str'] = df_small['DEPARTURE_TIME'].apply(format_time_str)
df_small['arr_time_str'] = df_small['ARRIVAL_TIME'].apply(format_time_str)
df_small = df_small.dropna(subset=['dep_time_str', 'arr_time_str'])

# Construction des date times de départ
df_small['temp_date_str'] = (
    df_small['YEAR'].astype(str) + '-' +
    df_small['MONTH'].astype(str).str.zfill(2) + '-' +
    df_small['DAY'].astype(str).str.zfill(2) + ' ' +
    df_small['dep_time_str']
)
df_small['departure_dt'] = pd.to_datetime(df_small['temp_date_str'], format='%Y-%m-%d %H:%M:%S')

#Construction des horaires d'arrivée en incrémentant la date si le lendemain
overnight = df_small['ARRIVAL_TIME'].astype(int) < df_small['DEPARTURE_TIME'].astype(int)

# On construit le timestamp d'arrivée
# Si c'est overnight, on ajoute 1 jour à la date de départ
arrival_dates = df_small['departure_dt'].dt.date.copy()
arrival_dates[overnight] = arrival_dates[overnight] + pd.Timedelta(days=1)

df_small['arrival_ts'] = (
    arrival_dates.astype(str) + 'T' +
    df_small['arr_time_str']
)

# On formate le timestamp de départ au format final ISO
df_small['departure_ts'] = df_small['departure_dt'].dt.strftime('%Y-%m-%dT%H:%M:%S')

# 4. Finalisation
final_flights = df_small[[
    'ORIGIN_AIRPORT',
    'DESTINATION_AIRPORT',
    'AIRLINE',
    'departure_ts',
    'arrival_ts',
    'DISTANCE',
    'DEPARTURE_DELAY'
]]

final_flights.columns = ['source', 'target', 'airline', 'departure_ts', 'arrival_ts', 'distance', 'delay']

print("Filtrage des aéroports...")
airports = pd.read_csv(INPUT_AIRPORTS)

# On ne garde que les aéroports qui apparaissent dans nos vols filtrés
used_airports = set(final_flights['source']).union(set(final_flights['target']))
final_airports = airports[airports['IATA_CODE'].isin(used_airports)]

# 6. Exportation
print("Écriture des fichiers CSV...")
final_flights.to_csv(OUTPUT_FLIGHTS, index=False)
final_airports.to_csv(OUTPUT_AIRPORTS, index=False)

print("--- TERMINÉ ---")
print(f"Fichier vols généré : {OUTPUT_FLIGHTS} (Contient ~{len(final_flights)} vols)")
print(f"Fichier aéroports généré : {OUTPUT_AIRPORTS}")