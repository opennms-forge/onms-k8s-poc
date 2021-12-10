# OpenNMS K8s PoC

This project aims to serve as a reference to implement [OpenNMS](https://www.opennms.com/) running in [Kubernetes](https://kubernetes.io/) and deployed via [Helm](https://helm.sh/), having a single Core Server and multiple read-only UI servers plus Grafana and a custom Ingress, sharing the RRD files and some configuration files.

We expect Kafka, Elasticsearch, and PostgreSQL to run externally (and maintained separately from the solution).

We expect `SASL_SSL` configured in Kafka using `SCRAM-SHA-512` for authentication.

## Requirements

### Local

* Have `kubectl` installed on your machine.

* Have `helm` version 3 installed on your machine.

* When using Cloud Resources, `az` for Azure, or `gcloud` for Google Cloud.

### For Kubernetes

* All components on a single `namespace` represent a single OpenNMS environment or customer deployment or a single tenant.

* A single instance of OpenNMS Core (backend) for centralized monitoring running ALEC in standalone mode.
  OpenNMS doesn't support distributed mode, meaning the `StatefulSet` cannot have more than one replica.

* Multiple instances of read-only OpenNMS UI (frontend).
  * Must be stateless (unconfigurable), meaning the `Deployment` must work with multiple replicas.
  * Any configuration change goes to the core server.
  
* Multiple instances of Grafana (frontend), using PostgreSQL as the backend, pointing to the UI service.

* Multiple instances of Sentinel to handle Flows (requires Elasticsearch as an external dependency).

* A custom `StorageClass` for shared content (Google Filestore or Azure Files) to use `ReadWriteMany`.
  * Use the same `UID` and `GID` as the OpenNMS image with proper file modes.
  * Due to how Google Filestore works, we need to specify `securityContext.fsGroup` (not required for Azure Files). Check [here](https://github.com/kubernetes-sigs/gcp-filestore-csi-driver/blob/master/docs/kubernetes/fsgroup.md) for more information.

* A shared volume for the RRD files, mounted as read-write on the Core instance, and as read-only on the UI instances.

* A shared volume for the core configuration files, mounted as read-only on the UI instances.
  The purpose is to share configuration across all the OpenNMS instances (i.e., `users.xml`, `groups.xml`).

* `Secrets` to store the credentials, certificates and truststores.

* `ConfigMaps` to store initialization scripts and standard configuration settings.

* An `Ingress` to control TLS termination and provide access to all the components (using Nginx).
  We could manage certificates using LetsEncrypt via `cert-manager`.
  To integrate with Google Cloud DNS managed zones or Azure DNS, we need a wild-card entry.

> **Please note that unless you build custom images for OpenNMS, the latest available versions of ALEC and the TSS Cortex Plugin (when enabled) as KAR files will be downloaded directly from Github every time the container starts, as those binaries are not part of the current Docker Image for OpenNMS.**

### External Dependencies

* PostgreSQL server as the central database for OpenNMS and Grafana.

* Kafka cluster for OpenNMS-to-Minion communication.

* Elasticsearch cluster for Flow persistence.

* Grafana Loki server for log aggregation.

* Google Filestore or Azure Files for the OpenNMS configuration and RRD files (managed by provider)
  The documentation recommends 1.21 or later for the CSI driver.

* Private Container Registry for custom Meridian Images (if applicable), in case OpenNMS Horizon is not an option.

* [cert-manager](https://cert-manager.readthedocs.io/en/latest/) to provide HTTPS/TLS support to the web-based services managed by the ingress controller.

* Nginx Ingress Controller

## Deployment

* Use` Terraform` or your preferred methodology to deploy the Kubernetes Cluster and the shared infrastructure in Google Cloud or Azure.

* Use `kubectl` to deploy the Kubernetes components (applications).
  We could offer to create a `Helm` chart in the future to simplify the deployment.

* Use `initContainers` to initialize the mandatory configuration settings.
  That should take care of OpenNMS upgrades in the Core instance.
  WebUI servers are stateless, so they don't need configuration life-cycle management.

## Run in the cloud

The following assumes that you already have an AKS or GKE cluster up and running with Nginx Ingress Controller and `cert-manager`, and `kubectl` is correctly configured on your machine to access the cluster. At a minimum, it should have three instances with 4 Cores and 16GB of RAM on each of them.

> **Place the Java Truststore with the CA Certificate Chain of your Kafka cluster, your Elasticsearch cluster, and your PostgreSQL server/cluster on a JKS file located at `jks/truststore.jks`, and also the Root CA used for your PostgreSQL server certificate on a PKCS12 file located at `jks/postgresql-ca.crt`. Then, pass them to OpenNMS via Helm (set the JKS password or update the values file).**

When using Google Cloud, ensure that `GcpFilestoreCsiDriver` is enabled in your GKE Cluster, if not, you can enabled it as follow (according to the [documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/filestore-csi-driver)):

```bash
gcloud container clusters update CLUSTER_NAME_HERE \
   --update-addons=GcpFilestoreCsiDriver=ENABLED
```

Optionally, for testing purposes, use the following script to initialize all the dependencies within Kubernetes (including `cert-manager`):

```bash
./start-dependencies.sh
```

Create the Storage Class in Google Cloud, using `onms-share` as the name of the `StorageClass`:

```bash
./create-storageclass.sh gke onms-share
```

For Azure, replace `gke` with `aks`. On GKE, please keep in mind that it uses the standard tier and the default network/VPC, refer to Google's documentation for a custom networks/VPC, whereas on Azure it uses `Standard_LRS`.

Start the OpenNMS environment on your cloud environment:

```bash
helm install -f helm-cloud.yaml \
  --set domain=k8s.agalue.net \
  --set storageClass=onms-share \
  --set dependencies.truststore.content=$(cat jks/truststore.jks | base64) \
  --set dependencies.postgresql.ca_cert=$(cat jks/postgresql-ca.crt | base64) \
  --set dependencies.postgresql.hostname=onms-db.shared.svc \
  --set dependencies.kafka.hostname=onms-kafka-bootstrap.shared.svc \
  --set dependencies.elasticsearch.hostname=onms-es-http.shared.svc \
  apex1 ./opennms
```

Please note that `apex1` uniquely identifies the environment. That word will be used as the namespace, the OpenNMS Instance ID, and prefix the `domain` for the FQDNs used in the Ingress Controller. Ensure to use the correct hostname for your dependencies, and the same name for the `StorageClass` used when created it.

Keep in mind the above is only an example. You must treat the content of `helm-cloud.yaml` as a sample for testing purposes.

To tune further, edit [helm-cloud.yaml](helm-cloud.yaml).

To access the cluster from external Minions, make sure to configure the DNS service correctly on your cloud provider.

## Run locally

Start Minikube:

```bash
minikube start --cpus=4 --memory=24g \
  --cni=calico \
  --container-runtime=containerd \
  --addons=ingress \
  --addons=ingress-dns \
  --addons=metrics-server
```

Start the test dependencies:

```bash
./start-dependencies.sh
```

Create the storage class:
```bash
./create-storageclass.sh minikube onms-share
```

Start OpenNMS:

```bash
helm install -f helm-minikube.yaml \
  --set domain=k8s.agalue.net \
  --set storageClass=onms-share \
  --set dependencies.truststore.content=$(cat jks/truststore.jks | base64) \
  --set dependencies.postgresql.ca_cert=$(cat jks/postgresql-ca.crt | base64) \
  apex1 ./opennms
```

Take a look at the documentation of [ingress-dns](https://github.com/kubernetes/minikube/tree/master/deploy/addons/ingress-dns) for more information about how to use it, to avoid messing with `/etc/hosts`.

For instance, for macOS:

```bash
cat <<EOF | sudo tee /etc/resolver/minikube-default-test
domain k8s.agalue.net
nameserver $(minikube ip)
search_order 1
timeout 5
EOF
```

> Use your own, and ensure it matches the domain passed to OpenNMS via Helm

## Testing multiple OpenNMS environments

The current approach allows you to start multiple independent OpenNMS environments using the same Helm Chart. Ensure the deployment name is different every time you install or deploy a new environment (as mentioned, used for the namespace and the OpenNMS instance ID, among other things).

> Remember to change all username/password pairs for each environment to increase security.

## Start an external Minion

The [start-minion.sh](start-minion.sh) script is designed for the test use case. To tune it for your use case, you can alter all the environment variables with argument flags, for instance:

```bash
./start-minion.sh \
  --instance_id Texas \
  --minion_id minion01 \
  --minion_location Houston \
  --kafka_boostrap kafka1.example.com:9044
```

Check the script for more details.

## Pending

* Find a way to use the Graph Templates from the Core Server within the UI servers.

## Problems/Limitations

* The WebUI sends events handled by Queued to promote updating RRD files to ensure data is available. That won't work with dedicated UI servers (as Queued is not running there).
* When using Newts, the resource cache won't exist on the UI servers (maintained by Collectd), meaning all requests will hit Cassandra, slowing down the graph generation. The same applies when using Grafana via the UI servers.

## Manual configuration changes

* Either access the OpenNMS container via a remote shell through `kubectl`, and edit the file using `vi` (the only editor available within the OpenNMS container), or mount the NFS share from Google Filestore or Azure Files from a VM or a temporary container and make the changes.
* Send the reload configuration event via `send-event.pl` or the Karaf Shell (not accessible within the container).
* In case OpenNMS has to be restarted, delete the Pod (not the StatefulSet), and Kubernetes controller will recreate it again.
