# Minion Deployment & SNMP Trap Test

This to solve the device source IP in UDP datagram being overwritten by a K8s endpoint IP address for SNMP Traps. This is in the context of minion being deployed to K8s.

The following is an example of deploying from Mac to Azure's K8s AKS instance.

## Setup Azure Components 

Other env vars: 
```
SERVICE_PRINCIPAL=<client_id> 
CLIENT_SECRET=<client_secret> 
RESOURCE_GROUP=${RESOURCE_GROUP-<resource_group_name>} 
LOCATION=${LOCATION-eastus} 
DOMAIN=${DOMAIN-<sud_domain1>.<domain1>} 
AKS_NODE_COUNT=${AKS_NODE_COUNT-3} 
AKS_VM_SIZE=${AKS_VM_SIZE-Standard_DS4_v2} 
VERSION=$(az aks get-versions --location "$LOCATION" | jq \
   -r '.orchestrators[-1].orchestratorVersion')  
```

Create resource group: 
```
az group create -l eastus -n "$RESOURCE_GROUP" 
echo "Starting Kubernetes version $VERSION" 
az aks create --name "$USER-opennms" \ 
  --enable-node-public-ip \
  --resource-group "$RESOURCE_GROUP" \ 
  --service-principal "$SERVICE_PRINCIPAL" \ 
  --client-secret "$CLIENT_SECRET" \ 
  --dns-name-prefix "$USER-opennms" \ 
  --kubernetes-version "$VERSION" \ 
  --location "$LOCATION" \ 
  --node-count $AKS_NODE_COUNT \ 
  --node-vm-size $AKS_VM_SIZE \ 
  --network-plugin azure \ 
  --network-policy azure \ 
  --ssh-key-value ~/.ssh/id_rsa.pub \ 
  --admin-username "$USER" \ 
  --nodepool-tags "Owner=$USER" \ 
  --tags "Owner=$USER" 
```

Authenticate to aks:  
```
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$USER-opennms" --overwrite-existing 
```

## Setup Ingress & update DNS 

Ingress: 
```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml 
kubectl wait pod -l app.kubernetes.io/component=controller --for=condition=Ready --timeout=300s -n ingress-nginx 
# To wait for at least one pod with the label "app.kubernetes.io/component=controller" on the namespace "ingress-nginx" to be in a ready state before proceeding. In other words, wait until Nginx is ready after fixing it. Strimzi requires SSL Passthrough when using Ingress to expose Kafka (used for testing purposes). 
```

DNS Entry: 
```
export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}') 
az network dns record-set a add-record -g "cloud-ops" -z "<domain1>" -n "*.<subdomain1>" -a $NGINX_EXTERNAL_IP 
```

## Deploy Dependencies 

Make sure to cd into root dir of repo.

Make sure to have Java 11 installed for keytool, seen in start-dependencies.sh. Had to set the sdk source for the terminal session that I will run the build from (install sdkman): 
```
sdk 
which keytool 
# Output: /usr/bin/keytool 
source "$HOME/.sdkman/bin/sdkman-init.sh" 
which keytool 
# Output: /Users/<user_name>/.sdkman/candidates/java/current/bin/keytool 
```

Run Scripts: 
```
./start-dependencies.sh 
./create-storageclass.sh aks onms-share 
```

## Change yaml Configs before Deploying OpenNMS

Change the following for test.

In opennms/values.yaml
* security_protocol: PLAINTEXT # PLAINTEXT, SSL, SASL_PLAINTEXT, SASL_SSL
* tag: '29.0.5' # Defaults to opennmsVersion
  * This aligns with the version in minion.yaml.

In helm-cloud.yaml
* opennms.uiServers.replicaCount: 1
  * This gives us a UI.

In dependencies/kafka.yaml, change the following:
* host: kafka.<sud_domain1>.<domain1>

## Deploy OpenNMS Instance

Run:
```
helm install -f helm-cloud.yaml \
  --set domain=$DOMAIN \
  --set storageClass=onms-share \
  --set ingress.certManager.clusterIssuer=opennms-issuer \
  --set dependencies.truststore.content=$(cat jks/truststore.jks | base64) \
  --set dependencies.postgresql.ca_cert=$(cat jks/postgresql-ca.crt | base64) \
  --set dependencies.postgresql.hostname=onms-db.shared.svc \
  --set dependencies.kafka.hostname=onms-kafka-bootstrap.shared.svc \
  --set dependencies.elasticsearch.hostname=onms-es-http.shared.svc \
  apex1 ./opennms
```

Wait for all pods to come online in namespace apex1.

Test OpenNMS:
* Go to incognito web browser: https://onms.apex1.<subdomain1>.<domain1>
  * User: admin
  * PW: 0p3nNM5 # Same as password seen in start-dependencies.sh. For testing purposes only.

Test Grafana:
* Goto grafana.apex1.<subdomain1>.<domain1> has same credentials as above.

The ssl is self-signed.

Port forward to and ssh to karaf, run this, shows what is running: $ kafka-sink-topics

## Deploy Minion

Update minion.yaml secret:
```
cat jks/truststore.jks | base64
# Add it to secret app-jks at location 'data.truststore.jks’ in minion/minion.yaml.
```

Run
```
cd minion/
vi minion.yaml
```

Update the following values:
* In the ConfigMap:
  * data.minion-config.yaml.ipc.twin.kafka.bootstrap.servers: kafka-0.<subdomain1>.<domain1>.com:443
  * data.minion-config.yaml.rpc.kafka.bootstrap.servers: kafka-0.<subdomain1>.<domain1>.com:443
  * data.minion-config.yaml.sink.kafka.bootstrap.servers: kafka-0.<subdomain1>.<domain1>.com:443
* In the Secret:
  * data.truststore.jks: <base64_output_from_jks_truststore>

Run
```
kubectl apply -f minion.yaml
```

## Source IP through Minion Using Node Port

```
kubectl -n minion1 expose pod/minion --port=1162 --protocol=UDP --type=NodePort --name=udp-server

# Get the nodePort port number (i.e. 30923) and updated the udp-server svc’s following configs to Local rather than Cluster, it worked. 
kubectl -n minion1 edit service udp-server
# Change to the following:
#   externalTrafficPolicy: Local 
#   internalTrafficPolicy: Local 
```

In Azure, list Network Security Groups, select the one that is related to the mc_* one for the AKS instance created above. Add an inbound rule that allows the nodePort (see previous step) destination port on UDP. 

Test the snmp trap. 
```
# See the node that contains the pod.
kubectl -n minion1 get pods -o wide  

# Gives ip of node that the pod is on. 
kubectl -n minion1 get nodes -o wide  
$  sudo snmptrap -v 2c -c public <node_ip>:<nodeport> '' NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification netSnmpExampleHeartbeatRate i 1234333 
```

Go to the OpenNMS instance created, select Status from the top menu and then select Events. Check the Interface, it should contain the IP of your laptop or whatever device is sending the SNMP trap.

Worked, may take time to propogate. 

The ip address showing up in the opennms node events is the same from the following output: 
```
dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com 
```

## Deploy UDP Ingress - Does not work for our purposes for information purposes only

This shows a typical UDP deployment through ingress-nginx, but it will not preserve the source IP in the UDP datagram of the SNMP Trap.

Run
```
# Create a separate UDP ingress class.
kubectl apply -f ingress-nginx-udp.yaml

# Update the domain here: spec.rules.host
vi minion-ingress-udp.yaml

# Add an ingress to the minion service.
kubectl apply -f minion-ingress-udp.yaml 
```

Update DNS for minion1.<subdomain2>.<domain1> with the external ip from the following:
```
kubectl -n ingress-nginx get service/ingress-nginx-udp-controller
kubectl -n ingress-nginx get ingress
```

Update dns, set propogation time to 3 mins. New domain name. IMPORTANT: Make sure this domain is has a different subdomain, or else it will get caught by the ingress.
```
nslookup minion1.<subdomain2>.<domain1>
```

Test Connection:
* Is minion showing up in opennms? If so, then good.

Test SNMP Trap:
```
# Look at events. Run the following from laptop.
sudo snmptrap -v 2c -c public minion1.<subdomain2>.<domain1>:1162 '' NET-SNMP-EXAMPLES-MIB::netSnmpExampleHeartbeatNotification netSnmpExampleHeartbeatRate i 123456678
```

IP is the IP of the ingress-nginx-udp controller class endpoint.
