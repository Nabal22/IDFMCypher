// REQUÊTE 5 : CONTRAINTES TEMPORELLES
// Chemins LAX->JFK avec au minimum 45 minutes entre chaque vol

CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  (()-[f:FLIGHT]->(:Airport)){2,3}
  (end:Airport {iata_code: 'JFK'})
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
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [r IN relationships(path) | r.departure_ts] AS departures,
  [r IN relationships(path) | r.arrival_ts] AS arrivals
LIMIT 10;