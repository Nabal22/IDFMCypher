import pandas as pd
import numpy as np

INPUT_FLIGHTS = '../source/flights.csv'
INPUT_AIRPORTS = '../source/airports.csv'
OUTPUT_FLIGHTS = '../import/flights_projet.csv'
OUTPUT_AIRPORTS = '../import/airports_projet.csv'

# Chargement uniquement des colonens voulues
columns_to_keep = [
    'YEAR', 'MONTH', 'DAY',
    'AIRLINE',
    'ORIGIN_AIRPORT', 'DESTINATION_AIRPORT',
    'DEPARTURE_TIME', 'ARRIVAL_TIME',
    'DEPARTURE_DELAY', 'DISTANCE'
]

dtype_dict = {'ORIGIN_AIRPORT': str, 'DESTINATION_AIRPORT': str}
df = pd.read_csv(INPUT_FLIGHTS, usecols=columns_to_keep, dtype=dtype_dict)

# Filtre des vols sur la date du 1er au 7 janvier
df_small = df[
    (df['MONTH'] == 1) &
    (df['DAY'] <= 7)
].copy()

print(f"Taille de l'échantillon : {len(df_small)}")

df_small = df_small.dropna(subset=['DEPARTURE_TIME', 'ARRIVAL_TIME'])

def format_time_str(t):
    try:
        s = str(int(t)).zfill(4)
        if s == '2400': s = '0000'
        if len(s) > 4: return None
        return f"{s[:2]}:{s[2:]}:00"
    except:
        return None

df_small['dep_time_str'] = df_small['DEPARTURE_TIME'].apply(format_time_str)
df_small['arr_time_str'] = df_small['ARRIVAL_TIME'].apply(format_time_str)
df_small = df_small.dropna(subset=['dep_time_str', 'arr_time_str'])

df_small['temp_date_str'] = (
    df_small['YEAR'].astype(str) + '-' +
    df_small['MONTH'].astype(str).str.zfill(2) + '-' +
    df_small['DAY'].astype(str).str.zfill(2) + ' ' +
    df_small['dep_time_str']
)
df_small['departure_dt'] = pd.to_datetime(df_small['temp_date_str'], format='%Y-%m-%d %H:%M:%S')

overnight = df_small['ARRIVAL_TIME'].astype(int) < df_small['DEPARTURE_TIME'].astype(int)

arrival_dates = df_small['departure_dt'].dt.date.copy()
arrival_dates[overnight] = arrival_dates[overnight] + pd.Timedelta(days=1)

df_small['arrival_ts'] = (
    arrival_dates.astype(str) + 'T' +
    df_small['arr_time_str']
)

df_small['departure_ts'] = df_small['departure_dt'].dt.strftime('%Y-%m-%dT%H:%M:%S')

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

airports = pd.read_csv(INPUT_AIRPORTS)

# On ne garde que les aéroports qui apparaissent dans nos vols filtrés
used_airports = set(final_flights['source']).union(set(final_flights['target']))
final_airports = airports[airports['IATA_CODE'].isin(used_airports)]

# 6. Exportation
final_flights.to_csv(OUTPUT_FLIGHTS, index=False)
final_airports.to_csv(OUTPUT_AIRPORTS, index=False)

print("TERMINÉ")