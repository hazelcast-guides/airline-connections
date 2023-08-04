package hazelcast.platform.labs.airline;

import com.hazelcast.client.HazelcastClient;
import com.hazelcast.client.config.ClientConfig;
import com.hazelcast.client.config.ClientConnectionStrategyConfig;
import com.hazelcast.config.SSLConfig;
import com.hazelcast.core.HazelcastInstance;

import java.io.File;
import java.util.Properties;

/**
 * Static methods that help with connecting to a Hazelcast cluster.
 *
 * For Viridian Connections, the following environment variables are required.
 *
 * VIRIDIAN_SECRETS_DIR  The unzipped contents of the file downloaded from the "Advanced" configuration tab
 * VIRIDIAN_CLUSTER_ID
 * VIRIDIAN_DISCOVERY_TOKEN
 * VIRIDIAN_PASSWORD
 *
 * For non-Viridian connections, provide the following environment variables
 *
 * HZ_SERVERS  A comma separated list of members (e.g. member1:5701,member2:5701)
 * HZ_CLUSTER_NAME  The cluster name
 *
 */
public class ConnectionHelper {
    public static final String VIRIDIAN_SECRETS_DIR_PROP = "VIRIDIAN_SECRETS_DIR";
    public static final String VIRIDIAN_CLUSTER_ID_PROP = "VIRIDIAN_CLUSTER_ID";
    public static final String VIRIDIAN_PASSWORD_PROP = "VIRIDIAN_PASSWORD";
    public static final String VIRIDIAN_DISCOVERY_TOKEN_PROP = "VIRIDIAN_DISCOVERY_TOKEN";
    private static final String HZ_SERVERS_PROP = "HZ_SERVERS";
    private static final String HZ_CLUSTER_NAME_PROP = "HZ_CLUSTER_NAME";

    public static HazelcastInstance connect(){
        ClientConfig clientConfig = new ClientConfig();
        String message;
        if (ConnectionHelper.viridianConfigPresent()){
            ConnectionHelper.configureViridianClientFromEnvironment(clientConfig);
            message = "Connected to Viridian Cluster: " +
                    System.getenv(ConnectionHelper.VIRIDIAN_CLUSTER_ID_PROP);
        } else {
            String hzServersProp = getRequiredEnv(HZ_SERVERS_PROP);
            String []hzServers = hzServersProp.split(",");
            for (int i = 0; i < hzServers.length; ++i) hzServers[i] = hzServers[i].trim();

            String hzClusterName = getRequiredEnv(HZ_CLUSTER_NAME_PROP);

            clientConfig.setClusterName(hzClusterName);
            for(String server: hzServers) clientConfig.getNetworkConfig().addAddress(server);
            message = "Connected to cluster [" + hzClusterName + "] at " + hzServersProp;
        }
        clientConfig.getConnectionStrategyConfig().setAsyncStart(false);
        clientConfig.getConnectionStrategyConfig().setReconnectMode(ClientConnectionStrategyConfig.ReconnectMode.ON);

        HazelcastInstance hzClient = HazelcastClient.newHazelcastClient(clientConfig);
        System.out.println(message);
        return hzClient;
    }

    private static String getRequiredEnv(String envVarName){
        String result = System.getenv(envVarName);
        if (result == null)
            throw new RuntimeException("Required environment variable (" + envVarName + ") was not provided.");

        return result;
    }

    /*
     * Looks for Viridian configuration in the environment
     */
    public static boolean viridianConfigPresent(){
        String secretsDir = System.getenv(VIRIDIAN_SECRETS_DIR_PROP);
        return secretsDir != null;
    }
    public static void configureViridianClientFromEnvironment(ClientConfig clientConfig){
        String secretsDir = getRequiredEnv(VIRIDIAN_SECRETS_DIR_PROP);
        String password = getRequiredEnv(VIRIDIAN_PASSWORD_PROP);
        String clusterId = getRequiredEnv(VIRIDIAN_CLUSTER_ID_PROP);
        String discoveryToken = getRequiredEnv(VIRIDIAN_DISCOVERY_TOKEN_PROP);
        configureViridian(clusterId, discoveryToken, password, secretsDir, clientConfig);
    }

    public static void configureViridian(String clusterId, String discoveryToken, String password, String secretsDir, ClientConfig clientConfig){
        File configDir = new File(secretsDir);
        if (!configDir.isDirectory()){
            throw new RuntimeException("Could not initialize Viridian connection because the given secrets directory (" + secretsDir + ") does not exist or is not a directory.");
        }

        File keyStoreFile = new File(configDir, "client.keystore");
        File trustStoreFile = new File(configDir, "client.truststore");
        if (!keyStoreFile.isFile() || !keyStoreFile.canRead()){
            throw new RuntimeException("The keystore file (" + keyStoreFile.getPath() +") was not found or could not be read.");
        }
        if (!trustStoreFile.isFile() || !trustStoreFile.canRead()){
            throw new RuntimeException("The truststore file (" + trustStoreFile.getPath() +") was not found or could not be read.");
        }

        Properties props = new Properties();
        props.setProperty("javax.net.ssl.keyStore", keyStoreFile.getPath());
        props.setProperty("javax.net.ssl.keyStorePassword", password);
        props.setProperty("javax.net.ssl.trustStore", trustStoreFile.getPath());
        props.setProperty("javax.net.ssl.trustStorePassword", password);

        clientConfig.getNetworkConfig().setSSLConfig(new SSLConfig().setEnabled(true).setProperties(props));
        clientConfig.getNetworkConfig().getCloudConfig().setEnabled(true).setDiscoveryToken(discoveryToken);
        clientConfig.setProperty("hazelcast.client.cloud.url", "https://api.viridian.hazelcast.com");
        clientConfig.setClusterName(clusterId);
    }
}
