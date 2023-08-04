# This script assume that a Kafka connection called "ViridianTrialKafka" and 
# a Postgres connection called "ViridianTrialPostgres" already exist.

# Create mappings to particular topics/tables using those data connections.
#
CREATE OR REPLACE MAPPING "departures"
EXTERNAL NAME "viridiantrial.flights.departures" (
  event_time timestamp with time zone,
  "day" date,
  flight varchar,
  airport varchar,
  departure_gate varchar,
  departure_time timestamp
)
DATA CONNECTION "ViridianTrialKafka"
OPTIONS (
    'keyFormat' = 'varchar',
    'valueFormat' = 'json-flat'
);


CREATE OR REPLACE MAPPING "arrivals"
EXTERNAL NAME "viridiantrial.flights.arrivals" (
  event_time timestamp with time zone,
  "day" date,
  flight varchar,
  airport varchar,
  arrival_gate varchar,
  arrival_time timestamp 
)
DATA CONNECTION "ViridianTrialKafka"
OPTIONS (
    'keyFormat' = 'varchar',
    'valueFormat' = 'json-flat'
);

# Now tell Hazelcast how the streaming data is ordered

CREATE OR REPLACE VIEW arrivals_ordered AS
SELECT * FROM TABLE (
  IMPOSE_ORDER(
     TABLE arrivals, 
     DESCRIPTOR(event_time),  
     INTERVAL '1' HOUR
  )
)

CREATE OR REPLACE VIEW departures_ordered AS
SELECT * FROM TABLE (
  IMPOSE_ORDER(
     TABLE departures, 
     DESCRIPTOR(event_time),  
     INTERVAL '1' HOUR
  )
)



# Postgres Mappings
CREATE MAPPING "connections"
EXTERNAL NAME "public"."connections" (
  arriving_flight varchar,
  departing_flight varchar
)
DATA CONNECTION "ViridianTrialPostgres"

CREATE MAPPING "minimum_connection_times"
EXTERNAL NAME "public"."minimum_connection_times" (
  airport varchar,
  arrival_terminal varchar,
  departure_terminal varchar,
  minutes integer
)
DATA CONNECTION "ViridianTrialPostgres"


#  copy mct and connection data from Postgres into IMaps
CREATE MAPPING local_mct(
  airport varchar,
  arrival_terminal varchar,
  departure_terminal varchar,
  minutes integer
)
Type IMap 
OPTIONS (
    'keyFormat' = 'varchar',
  'valueFormat' = 'json-flat'
);


INSERT INTO local_mct(__key, airport, arrival_terminal, departure_terminal, minutes) 
SELECT airport||arrival_terminal||departure_terminal, airport, arrival_terminal, departure_terminal, minutes 
FROM minimum_connection_times

CREATE MAPPING local_connections(
  arriving_flight varchar,
  departing_flight varchar
)
Type IMap 
OPTIONS (
    'keyFormat' = 'varchar',
  'valueFormat' = 'json-flat'
);

INSERT INTO local_connections(__key, arriving_flight, departing_flight) 
SELECT arriving_flight || departing_flight, arriving_flight, departing_flight FROM "connections"

# finally, create the job that joins everything up and sinks it to 

CREATE MAPPING live_connections(
  arriving_flight varchar,
  arrival_gate varchar,
  arrival_time timestamp,
  departing_flight varchar,
  departure_gate varchar,
  departure_time timestamp,
  connection_minutes integer,
  mct integer
)
Type IMap 
OPTIONS (
    'keyFormat' = 'varchar',
  'valueFormat' = 'json-flat'
);


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
  mct
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
  M.minutes as mct 
FROM arrivals_ordered A 
INNER JOIN local_connections C 
  ON C.arriving_flight = A.flight 
INNER JOIN departures_ordered D
  ON D.event_time BETWEEN A.event_time - INTERVAL '10' SECONDS AND A.event_time + INTERVAL '10' SECONDS 
  AND D.flight = C.departing_flight 
INNER JOIN local_mct M
ON A.airport = M.airport
AND SUBSTRING(A.arrival_gate FROM 1 FOR 1) = M.arrival_terminal 
AND SUBSTRING(D.departure_gate FROM 1 FOR 1) = M.departure_terminal 
