#!/usr/bin/env python3
"""
Script d'import des données de vols dans PostgreSQL
Alternative à l'import SQL direct, utilise psycopg2
"""

import psycopg2
from psycopg2.extras import execute_batch
import csv
import time
from datetime import datetime

# Configuration PostgreSQL
DB_CONFIG = {
    'dbname': 'flights_db',
    'user': 'postgres',
    'password': 'your_password',  # À modifier
    'host': 'localhost',
    'port': 5432
}

# Chemins des fichiers
AIRLINES_FILE = "../import/airlines.csv"
AIRPORTS_FILE = "../import/airports_projet.csv"
FLIGHTS_FILE = "../import/flights_projet.csv"

# Taille des batches
BATCH_SIZE = 1000


class PostgreSQLImporter:
    def __init__(self, db_config):
        self.conn = psycopg2.connect(**db_config)
        self.conn.autocommit = False

    def close(self):
        self.conn.close()

    def create_tables(self):
        """Crée les tables"""
        print("🗄️  Création des tables...")

        with self.conn.cursor() as cur:
            # Drop existing tables
            cur.execute("DROP TABLE IF EXISTS flights CASCADE")
            cur.execute("DROP TABLE IF EXISTS airports CASCADE")
            cur.execute("DROP TABLE IF EXISTS airlines CASCADE")

            # Create airlines table
            cur.execute("""
                CREATE TABLE airlines (
                    iata_code VARCHAR(2) PRIMARY KEY,
                    name VARCHAR(100) NOT NULL
                )
            """)

            # Create airports table
            cur.execute("""
                CREATE TABLE airports (
                    iata_code VARCHAR(3) PRIMARY KEY,
                    name VARCHAR(200) NOT NULL,
                    city VARCHAR(100) NOT NULL,
                    state VARCHAR(2) NOT NULL,
                    country VARCHAR(50) NOT NULL,
                    latitude DECIMAL(10, 6) NOT NULL,
                    longitude DECIMAL(10, 6) NOT NULL
                )
            """)

            # Create flights table
            cur.execute("""
                CREATE TABLE flights (
                    id SERIAL PRIMARY KEY,
                    source VARCHAR(3) NOT NULL,
                    target VARCHAR(3) NOT NULL,
                    airline VARCHAR(2) NOT NULL,
                    departure_ts TIMESTAMP NOT NULL,
                    arrival_ts TIMESTAMP NOT NULL,
                    distance INTEGER NOT NULL,
                    delay DECIMAL(10, 2),

                    CONSTRAINT fk_source FOREIGN KEY (source) REFERENCES airports(iata_code),
                    CONSTRAINT fk_target FOREIGN KEY (target) REFERENCES airports(iata_code),
                    CONSTRAINT fk_airline FOREIGN KEY (airline) REFERENCES airlines(iata_code),
                    CONSTRAINT chk_different_airports CHECK (source != target),
                    CONSTRAINT chk_positive_distance CHECK (distance > 0)
                )
            """)

            self.conn.commit()
            print("✅ Tables créées")

    def import_airlines(self):
        """Import des compagnies aériennes"""
        print("\n✈️  Import des compagnies aériennes...")

        with open(AIRLINES_FILE, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            airlines = [(row['IATA_CODE'], row['AIRLINE']) for row in reader]

        with self.conn.cursor() as cur:
            execute_batch(cur, """
                INSERT INTO airlines (iata_code, name)
                VALUES (%s, %s)
            """, airlines)

        self.conn.commit()
        print(f"✅ {len(airlines)} compagnies importées")

    def import_airports(self):
        """Import des aéroports"""
        print("\n🏢 Import des aéroports...")

        with open(AIRPORTS_FILE, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            airports = [
                (
                    row['IATA_CODE'],
                    row['AIRPORT'],
                    row['CITY'],
                    row['STATE'],
                    row['COUNTRY'],
                    float(row['LATITUDE']),
                    float(row['LONGITUDE'])
                )
                for row in reader
            ]

        with self.conn.cursor() as cur:
            execute_batch(cur, """
                INSERT INTO airports (iata_code, name, city, state, country, latitude, longitude)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, airports)

        self.conn.commit()
        print(f"✅ {len(airports)} aéroports importés")

    def import_flights(self):
        """Import des vols en batches"""
        print("\n🛫 Import des vols (par batches)...")

        with open(FLIGHTS_FILE, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)

            batch = []
            total = 0
            start_time = time.time()

            for row in reader:
                batch.append((
                    row['source'],
                    row['target'],
                    row['airline'],
                    row['departure_ts'],
                    row['arrival_ts'],
                    int(row['distance']),
                    float(row['delay']) if row['delay'] else None
                ))

                if len(batch) >= BATCH_SIZE:
                    self._insert_flight_batch(batch)
                    total += len(batch)
                    elapsed = time.time() - start_time
                    rate = total / elapsed if elapsed > 0 else 0
                    print(f"  📊 {total} vols importés ({rate:.0f} vols/sec)")
                    batch = []

            # Dernier batch
            if batch:
                self._insert_flight_batch(batch)
                total += len(batch)

        self.conn.commit()
        elapsed = time.time() - start_time
        print(f"✅ {total} vols importés en {elapsed:.1f}s ({total/elapsed:.0f} vols/sec)")

    def _insert_flight_batch(self, batch):
        """Insert un batch de vols"""
        with self.conn.cursor() as cur:
            execute_batch(cur, """
                INSERT INTO flights (source, target, airline, departure_ts, arrival_ts, distance, delay)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, batch, page_size=BATCH_SIZE)

    def create_indexes(self):
        """Crée les index pour les performances"""
        print("\n📊 Création des index...")

        with self.conn.cursor() as cur:
            indexes = [
                "CREATE INDEX idx_airports_city ON airports(city)",
                "CREATE INDEX idx_airports_state ON airports(state)",
                "CREATE INDEX idx_airports_location ON airports(latitude, longitude)",
                "CREATE INDEX idx_flights_source ON flights(source)",
                "CREATE INDEX idx_flights_target ON flights(target)",
                "CREATE INDEX idx_flights_airline ON flights(airline)",
                "CREATE INDEX idx_flights_departure_ts ON flights(departure_ts)",
                "CREATE INDEX idx_flights_arrival_ts ON flights(arrival_ts)",
                "CREATE INDEX idx_flights_delay ON flights(delay)",
                "CREATE INDEX idx_flights_distance ON flights(distance)",
                "CREATE INDEX idx_flights_source_target ON flights(source, target)",
                "CREATE INDEX idx_flights_departure_date ON flights(DATE(departure_ts))",
            ]

            for idx in indexes:
                cur.execute(idx)

        self.conn.commit()
        print("✅ Index créés")

    def create_views(self):
        """Crée les vues utiles"""
        print("\n👁️  Création des vues...")

        with self.conn.cursor() as cur:
            # Vue flights_detailed
            cur.execute("""
                CREATE OR REPLACE VIEW flights_detailed AS
                SELECT
                    f.id,
                    f.source,
                    src.name AS source_name,
                    src.city AS source_city,
                    src.state AS source_state,
                    f.target,
                    dst.name AS target_name,
                    dst.city AS target_city,
                    dst.state AS target_state,
                    f.airline,
                    al.name AS airline_name,
                    f.departure_ts,
                    f.arrival_ts,
                    f.arrival_ts - f.departure_ts AS duration,
                    f.distance,
                    f.delay
                FROM flights f
                JOIN airports src ON f.source = src.iata_code
                JOIN airports dst ON f.target = dst.iata_code
                JOIN airlines al ON f.airline = al.iata_code
            """)

            # Vue airport_stats
            cur.execute("""
                CREATE OR REPLACE VIEW airport_stats AS
                SELECT
                    a.iata_code,
                    a.name,
                    a.city,
                    a.state,
                    COUNT(DISTINCT f_out.id) AS departures,
                    COUNT(DISTINCT f_in.id) AS arrivals,
                    COUNT(DISTINCT f_out.id) + COUNT(DISTINCT f_in.id) AS total_flights,
                    AVG(f_out.delay) AS avg_departure_delay,
                    COUNT(DISTINCT f_out.target) AS direct_destinations
                FROM airports a
                LEFT JOIN flights f_out ON a.iata_code = f_out.source
                LEFT JOIN flights f_in ON a.iata_code = f_in.target
                GROUP BY a.iata_code, a.name, a.city, a.state
            """)

            # Vue airline_stats
            cur.execute("""
                CREATE OR REPLACE VIEW airline_stats AS
                SELECT
                    al.iata_code,
                    al.name,
                    COUNT(f.id) AS total_flights,
                    AVG(f.delay) AS avg_delay,
                    AVG(f.distance) AS avg_distance,
                    COUNT(CASE WHEN f.delay > 0 THEN 1 END) AS delayed_flights,
                    100.0 * COUNT(CASE WHEN f.delay > 0 THEN 1 END) / NULLIF(COUNT(f.id), 0) AS delay_rate_pct
                FROM airlines al
                LEFT JOIN flights f ON al.iata_code = f.airline
                GROUP BY al.iata_code, al.name
            """)

        self.conn.commit()
        print("✅ Vues créées")

    def verify_import(self):
        """Vérifie l'import avec des statistiques"""
        print("\n📈 Vérification de l'import...")

        with self.conn.cursor() as cur:
            # Compter les enregistrements
            cur.execute("SELECT COUNT(*) FROM airlines")
            airline_count = cur.fetchone()[0]
            print(f"  ✓ Compagnies: {airline_count}")

            cur.execute("SELECT COUNT(*) FROM airports")
            airport_count = cur.fetchone()[0]
            print(f"  ✓ Aéroports: {airport_count}")

            cur.execute("SELECT COUNT(*) FROM flights")
            flight_count = cur.fetchone()[0]
            print(f"  ✓ Vols: {flight_count}")

            # Top 5 hubs
            print("\n  📍 Top 5 hubs (par total de vols):")
            cur.execute("""
                SELECT iata_code, city, total_flights
                FROM airport_stats
                ORDER BY total_flights DESC
                LIMIT 5
            """)
            for row in cur.fetchall():
                print(f"    {row[0]} ({row[1]}): {row[2]} vols")

            # Taille de la base
            cur.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
            db_size = cur.fetchone()[0]
            print(f"\n  💾 Taille de la base: {db_size}")

    def analyze_tables(self):
        """Lance ANALYZE pour mettre à jour les statistiques"""
        print("\n🔍 Analyse des tables (ANALYZE)...")

        with self.conn.cursor() as cur:
            cur.execute("ANALYZE airlines")
            cur.execute("ANALYZE airports")
            cur.execute("ANALYZE flights")

        self.conn.commit()
        print("✅ Tables analysées")


def create_database():
    """Crée la base de données si elle n'existe pas"""
    print("🔨 Vérification/Création de la base de données...")

    try:
        # Se connecter à la base postgres par défaut
        conn = psycopg2.connect(
            dbname='postgres',
            user=DB_CONFIG['user'],
            password=DB_CONFIG['password'],
            host=DB_CONFIG['host'],
            port=DB_CONFIG['port']
        )
        conn.autocommit = True

        with conn.cursor() as cur:
            # Vérifier si la base existe
            cur.execute("""
                SELECT 1 FROM pg_database WHERE datname = %s
            """, (DB_CONFIG['dbname'],))

            if not cur.fetchone():
                cur.execute(f"CREATE DATABASE {DB_CONFIG['dbname']}")
                print(f"✅ Base de données '{DB_CONFIG['dbname']}' créée")
            else:
                print(f"ℹ️  Base de données '{DB_CONFIG['dbname']}' existe déjà")

        conn.close()

    except Exception as e:
        print(f"⚠️  Impossible de créer la base: {e}")
        print("   Continuons avec la base existante...")


def main():
    print("=" * 60)
    print("  Import des données de vols dans PostgreSQL")
    print("=" * 60)

    try:
        start_time = time.time()

        # 1. Créer la base de données
        create_database()

        # 2. Créer l'importeur
        importer = PostgreSQLImporter(DB_CONFIG)

        # 3. Créer les tables
        importer.create_tables()

        # 4. Importer les données
        importer.import_airlines()
        importer.import_airports()
        importer.import_flights()

        # 5. Créer les index
        importer.create_indexes()

        # 6. Créer les vues
        importer.create_views()

        # 7. Analyser les tables
        importer.analyze_tables()

        # 8. Vérifier
        importer.verify_import()

        total_time = time.time() - start_time
        print(f"\n🎉 Import terminé avec succès en {total_time:.1f}s!")

        importer.close()

    except Exception as e:
        print(f"\n❌ Erreur lors de l'import: {e}")
        import traceback
        traceback.print_exc()
        raise


if __name__ == "__main__":
    main()
