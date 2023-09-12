-- Mappings to Kafka topics

CREATE OR REPLACE MAPPING "departures"
EXTERNAL NAME "demo.flights.departures" (
  event_time timestamp with time zone,
  "day" date,
  flight varchar,
  airport varchar,
  departure_gate varchar,
  departure_time timestamp
)
DATA CONNECTION "DemoKafkaConnection"
OPTIONS (
    'keyFormat' = 'varchar',
    'valueFormat' = 'json-flat'
);


-- STOP AND RUN demo_setup

-- Join departures, arrivals and connections

SELECT 
  C.arriving_flight,
  A.arrival_gate, 
  A.arrival_time, 
  C.departing_flight, 
  D.departure_gate, 
  D.departure_time,
  CAST((EXTRACT(EPOCH FROM D.departure_time) - EXTRACT(EPOCH FROM A.arrival_time))/60 AS INTEGER) AS connection_minutes
FROM arrivals_ordered A 
INNER JOIN local_connections C 
  ON C.arriving_flight = A.flight 
INNER JOIN departures_ordered D
  ON D.event_time BETWEEN A.event_time - INTERVAL '10' SECONDS AND A.event_time + INTERVAL '10' SECONDS 
  AND D.flight = C.departing_flight 

-- finally, create the job that joins everything up and sinks it to 


DROP JOB IF EXISTS update_connections;

CREATE JOB update_connections 
AS
SINK INTO live_connections(
  __key, 
  arriving_flight,
  arrival_gate,
  arrival_time,
  departing_flight,
  departure_gate,
  departure_time,
  connection_minutes,
  mct,
  connection_status
) 
SELECT 
  C.arriving_flight || C.departing_flight,
  C.arriving_flight,
  A.arrival_gate, 
  A.arrival_time, 
  C.departing_flight, 
  D.departure_gate, 
  D.departure_time,
  CAST((EXTRACT(EPOCH FROM D.departure_time) - EXTRACT(EPOCH FROM A.arrival_time))/60 AS INTEGER) AS connection_minutes,
  M.minutes as mct, 
  CASE 
    WHEN CAST((EXTRACT(EPOCH FROM D.departure_time) - EXTRACT(EPOCH FROM A.arrival_time))/60 AS INTEGER) < M.minutes THEN 'AT RISK'
    ELSE 'OK'
  END as connection_status
FROM arrivals_ordered A 
INNER JOIN local_connections C 
  ON C.arriving_flight = A.flight 
INNER JOIN departures_ordered D
  ON D.event_time BETWEEN A.event_time - INTERVAL '10' SECONDS AND A.event_time + INTERVAL '10' SECONDS 
  AND D.flight = C.departing_flight 
INNER JOIN local_mct M
ON A.airport = M.airport
AND SUBSTRING(A.arrival_gate FROM 1 FOR 1) = M.arrival_terminal 
AND SUBSTRING(D.departure_gate FROM 1 FOR 1) = M.departure_terminal;
