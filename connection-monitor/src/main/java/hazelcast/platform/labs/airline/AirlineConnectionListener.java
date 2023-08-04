package hazelcast.platform.labs.airline;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.hazelcast.core.EntryEvent;
import com.hazelcast.core.HazelcastInstance;
import com.hazelcast.core.HazelcastJsonValue;
import com.hazelcast.map.listener.EntryAddedListener;
import com.hazelcast.map.listener.EntryUpdatedListener;
import com.hazelcast.sql.SqlResult;
import com.hazelcast.sql.SqlRow;

/*
 * The Hazelcast connection is configured using environment variables.  See ConnectionHelper for details.
 *
 * To listen for connection updates, run the program with 2 arguments, the first being the arriving flight number
 * and the second being the departing flight number.
 *
 * If run with no arguments, this program will print out a list of connections.
 *
 */
public class AirlineConnectionListener {
    public static void main(String []args){
        HazelcastInstance hz = ConnectionHelper.connect();
        Runtime.getRuntime().addShutdownHook(new Thread(hz::shutdown));

        if (args.length == 0) {
            printConnections(hz);
        } else if (args.length == 2){
            String arrivingFlight = args[0];
            String departingFlight = args[1];

            String key = arrivingFlight + departingFlight;
            if (hz.getMap("local_connections").get(key) == null){
                System.out.println(arrivingFlight + " -> " + departingFlight + " is not a connection");
            } else {
                ObjectMapper mapper = new ObjectMapper();
                HazelcastJsonValue json = hz.<String, HazelcastJsonValue>getMap("live_connections").get(key);
                if (json == null){
                    System.out.println("There is currently no information about this connection");
                } else {
                    printConnectionStatus(mapper, json.getValue());
                    System.out.println("Listening for updates ...");
                    hz.<String,HazelcastJsonValue>getMap("live_connections").addEntryListener(new Listener(), key, true);
                }
            }
        } else {
            System.out.println("Please provide 0 or 2 arguments.  If you provide 2 arguments, they should be the " +
                    "arriving and departing flight numbers, in that order");
        }
    }

    private static void printConnectionStatus(ObjectMapper mapper, String json){
        try {
            ObjectNode connection = (ObjectNode) mapper.readTree(json);
            String arrivingFlight = connection.get("arriving_flight").asText();
            String arrivalGate = connection.get("arrival_gate").asText();
            String arrivalTime = connection.get("arrival_time").asText();
            arrivalTime = arrivalTime.substring(arrivalTime.length() - 5);
            String departingFlight = connection.get("departing_flight").asText();
            String departureGate = connection.get("departure_gate").asText();
            String departureTime = connection.get("departure_time").asText();
            departureTime = departureTime.substring(departureTime.length() - 4);
            int connectionMinutes = connection.get("connection_minutes").asInt();
            int mct = connection.get("mct").asInt();

            String status = "OK";
            String compare = ">=";
            if (connectionMinutes < mct){
                status = "INSUFFICIENT TIME";
                compare = "<";
            }

            System.out.println(arrivingFlight + " ARR " + arrivalTime + " GATE " + arrivalGate + " TO "
                    + departingFlight + " DEP " + departureTime + " GATE " + departureGate + " "
                    + connectionMinutes + " " + compare + " " + mct + " " + status);

        } catch (JsonProcessingException e) {
            System.out.println("Error printing connection status: " + json);
        }
    }

    private static void printConnections(HazelcastInstance hz) {
        System.out.println("Connections ...");
        try (SqlResult connections = hz.getSql().execute("SELECT arriving_flight, departing_flight " +
                "FROM local_connections ORDER BY arriving_flight")) {
            for (SqlRow row : connections) {
                System.out.println("   " + row.<String>getObject(0) + " -> " + row.<String>getObject(1));
            }
        }
    }

    private static class Listener implements EntryAddedListener<String,HazelcastJsonValue>, EntryUpdatedListener<String,HazelcastJsonValue> {

        private final ObjectMapper mapper = new ObjectMapper();

        @Override
        public void entryAdded(EntryEvent<String, HazelcastJsonValue> entryEvent) {
            printConnectionStatus(mapper, entryEvent.getValue().getValue());
        }

        @Override
        public void entryUpdated(EntryEvent<String, HazelcastJsonValue> entryEvent) {
            printConnectionStatus(mapper, entryEvent.getValue().getValue());
        }
    }
}
