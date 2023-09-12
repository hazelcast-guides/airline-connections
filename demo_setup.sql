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


CREATE OR REPLACE MAPPING "arrivals"
EXTERNAL NAME "demo.flights.arrivals" (
  event_time timestamp with time zone,
  "day" date,
  flight varchar,
  airport varchar,
  arrival_gate varchar,
  arrival_time timestamp 
)
DATA CONNECTION "DemoKafkaConnection"
OPTIONS (
    'keyFormat' = 'varchar',
    'valueFormat' = 'json-flat'
);

-- Now tell Hazelcast how the streaming data is ordered

CREATE OR REPLACE VIEW arrivals_ordered AS
SELECT * FROM TABLE (
  IMPOSE_ORDER(
     TABLE arrivals, 
     DESCRIPTOR(event_time),  
     INTERVAL '1' HOUR
  )
);

CREATE OR REPLACE VIEW departures_ordered AS
SELECT * FROM TABLE (
  IMPOSE_ORDER(
     TABLE departures, 
     DESCRIPTOR(event_time),  
     INTERVAL '1' HOUR
  )
);


-- Mappings to Postgres
CREATE OR REPLACE MAPPING "connections"
EXTERNAL NAME "public"."connections" (
  arriving_flight varchar,
  departing_flight varchar
)
DATA CONNECTION "DemoPostgresConnection";

CREATE OR REPLACE MAPPING "minimum_connection_times"
EXTERNAL NAME "public"."minimum_connection_times" (
  airport varchar,
  arrival_terminal varchar,
  departure_terminal varchar,
  minutes integer
)
DATA CONNECTION "DemoPostgresConnection";

-- mappings to IMaps
CREATE OR REPLACE MAPPING local_mct(
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

CREATE OR REPLACE MAPPING local_connections(
  arriving_flight varchar,
  departing_flight varchar
)
Type IMap 
OPTIONS (
    'keyFormat' = 'varchar',
  'valueFormat' = 'json-flat'
);

CREATE OR REPLACE MAPPING live_connections(
  arriving_flight varchar,
  arrival_gate varchar,
  arrival_time timestamp,
  departing_flight varchar,
  departure_gate varchar,
  departure_time timestamp,
  connection_minutes integer,
  mct integer,
  connection_status varchar
)
Type IMap 
OPTIONS (
    'keyFormat' = 'varchar',
  'valueFormat' = 'json-flat'
);


--  copy mct and connection data from Postgres into IMaps

DELETE FROM local_mct;
INSERT INTO local_mct(__key, airport, arrival_terminal, departure_terminal, minutes) 
SELECT airport||arrival_terminal||departure_terminal, airport, arrival_terminal, departure_terminal, minutes 
FROM minimum_connection_times;


DELETE FROM local_connections;
INSERT INTO local_connections(__key, arriving_flight, departing_flight) 
SELECT arriving_flight || departing_flight, arriving_flight, departing_flight FROM "connections";

