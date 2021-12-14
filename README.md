# OpenNMS K8s PoC

The objective of this project is to serve as a reference to implement [OpenNMS](https://www.opennms.com/) running in [Kubernetes](https://kubernetes.io/), deployed via [Helm](https://helm.sh/).

Each deployment would have a single Core Server, multiple read-only UI servers plus Grafana and a custom Ingress, sharing the RRD files and some configuration files, and Sentinels for flow processing.

Keep in mind that we expect Kafka, Elasticsearch, and PostgreSQL to run externally (and maintained separately from the solution), all with SSL enabled.

> *This is one way to approach the solution, without saying this is the only one or the best one. You should carefully study the content of this Helm Chart and tune it for your needs*.

**General Diagram**

![Diagram](diagrams/onms-k8s-poc-diagrams.001.png)

**Customer Namespace Deployment Diagram**

![Diagram](diagrams/onms-k8s-poc-diagrams.002.png)

**Shared Volumes Diagram**

![Diagram](diagrams/onms-k8s-poc-diagrams.003.png)

## Requirements

### Local

* Have `kubectl` installed on your machine.

* Have `helm` version 3 installed on your machine.

* When using Cloud Resources, `az` for Azure, or `gcloud` for Google Cloud.

### For Kubernetes

* All components on a single `namespace` represent a single OpenNMS environment or customer deployment or a single tenant. The name of the `namespace` will be used as:
  * Customer/Deployment identifier.
  * A prefix for the OpenNMS and Grafana databases in PostgreSQL.
  * A prefix for the index names in Elasticsearch when processing flows.
  * A prefix for the topics in Kafka (requires configuring the OpenNMS Instance ID on Minions).
  * A prefix for the Consumer Group IDs in OpenNMS and Sentinel.
  * Part of the sub-domain used by the Ingress Controller to expose WebUIs. It should not contain special characters and must follow FQDN restrictions.

* A single instance of OpenNMS Core (backend) for centralized monitoring running ALEC in standalone mode.
  OpenNMS doesn't support distributed mode, meaning the `StatefulSet` cannot have more than one replica.

* Multiple instances of read-only OpenNMS UI (frontend).
  * Must be stateless (unconfigurable), meaning the `Deployment` must work with multiple replicas.
  * Any configuration change goes to the core server.
  
* Multiple instances of Grafana (frontend), using PostgreSQL as the backend, pointing to the OpenNMS UI service.
  * When UI instances are not present, the OpenNMS Helm data sources would point to the OpenNMS Core service.

* Multiple instances of Sentinel to handle Flows (requires Elasticsearch as an external dependency).
  * When Sentinels are present, `Telemetryd` would be disabled on the OpenNMS Core instance.

* A custom `StorageClass` for shared content (Google Filestore or Azure Files) to use `ReadWriteMany`.
  * Use the same `UID` and `GID` as the OpenNMS image with proper file modes.
  * Due to how Google Filestore works, we need to specify `securityContext.fsGroup` (not required for Azure Files). Check [here](https://github.com/kubernetes-sigs/gcp-filestore-csi-driver/blob/master/docs/kubernetes/fsgroup.md) for more information. Keep in mind that the minimum size of a Filestore instance is 1TB.

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
  * For Google Cloud, the solution was tested using Google SQL for PostgreSQL with SSL and a Private IP.

* Kafka cluster for OpenNMS-to-Minion communication.

* Elasticsearch cluster for Flow persistence.

* Grafana Loki server for log aggregation.

* Google Filestore or Azure Files for the OpenNMS configuration and RRD files (managed by provider)
  The documentation recommends 1.21 or later for the CSI driver.

* Private Container Registry for custom Meridian Images (if applicable), in case OpenNMS Horizon is not an option.

* [cert-manager](https://cert-manager.readthedocs.io/en/latest/) to provide HTTPS/TLS support to the web-based services managed by the ingress controller.

* Nginx Ingress Controller

## Ingress

When deploying the Helm Chart names `acme` (remember about the rules for the `namespace`) with a value of `k8s.agalue.net` for the `domain`, it would create an Ingress instance exposing the following resources via custom FQDNs:

- OpenNMS UI (read-only): onms.acme.k8s.agalue.net
- OpenNMS Core: onms-core.acme.k8s.agalue.net
- Grafana: grafana.acme.k8s.agalue.net

To customize behavior, you could pass custom annotations via `ingress.annotations` when deploying the Helm Chart.

Please note that it is expected to have [cert-manager](https://cert-manager.io/docs/) deployed on your Kubernetes cluster as that would be used to manage the certificates (configured via `ingress.certManager.clusterIssuer`).

## Design

The solution is based on the latest Horizon 29. It should work with older versions of Horizon that fully support Kafka and Telemetryd and Meridian 2021 or newer.

Keep in mind that you need a subscription to use Meridian. With that, you would have to build the Docker images and place them on a private registry to use with this deployment. Doing that falls outside the scope of this guide.

Due to how the current Docker Images were designed and implemented, the solution requires multiple specialized scripts to configure each application properly. You could build your images and move the logic from the scripts executed via `initContainers` to your custom entry point script and simplify the Helm Chart. 

The scripts configure only a certain number of things. Each deployment would likely need additional configuration, which is the main reason why a Persistent Volume will back the OpenNMS Configuration Directory.

We must place the core configuration on a PVC configured as `ReadWriteMany` to allow the usage of independent UI servers so that the Core can make changes and the UI instances can read from them. Unfortunately, this imposes some restrictions on the chosen cloud provider. For example, in Google Cloud, you would have to use [Google Filestore](https://cloud.google.com/filestore), which cannot have volumes less than 1TB, exaggerated for what the configuration directory would ever haven (if UI servers are required). In contrast, that's not a problem when using [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/), which has more flexibility than Google Filestore. The former exposes the volumes via SMB or NFS with essentially any size, whereas the latter only uses NFS with size restrictions.

One advantage of configuring that volume is allowing backups and access to the files without accessing the OpenNMS instances running in Kubernetes.

The reasoning for the UI servers is to alleviate the Core Server from ReST and UI-only requests. Unfortunately, this makes the deployment more complex. It is a trade-off you would have to evaluate. Field tests are required to decide whether or not this is needed and how many instances would be required.

Similarly, when using RRDtool instead of Newts/Cassandra or Cortex, a shared volume with `ReadWriteMany` is required for the same reasons (the Core would be writing to it, and the UI servers would be reading from it). Additionally, when switching strategies and migration is required, this can be done outside Kubernetes.

Please note that even the volumes would still be configured that way even if you decide not to use UI instances; unless you modify the logic.

To alleviate load from OpenNMS, you can optionally start Sentinel instances for Flow Processing. That requires having an Elasticsearch cluster available. When Sentinels are present, Telemetryd would be disabled in OpenNMS.

The OpenNMS Core and Sentinels would be backed by a `StatefulSet` but keep in mind that there can be one and only one Core instance. To have multiple Sentinels, make sure to have enough partitions for the Flow topics in your Kafka clusters, as all of them would be part of the same consumer group.

As the current OpenNMS instances are not friendly in accessing logs, the solution allows you to configure [Grafana Loki](https://grafana.com/oss/loki/) to centralize all the log messages. When the Loki server is configured, the Core instance, the UI instances, and the Sentinel instances will be forwarding logs to Loki. The current solution uses the sidecar pattern using [Grafana Promtail](https://grafana.com/docs/loki/latest/clients/promtail/) to deliver the logs.

All the Docker Images can be customizable via Helm Values. The solution allows you to configure custom Docker Registries to access your custom images, or when all the images you're planning to use won't be in Docker Hub or your Kubernetes cluster won't have Internet Access. Please keep in mind that your custom images should be based on those currently in use.

If you plan to use ALEC or the TSS Cortex plugin, the current solution will download the KAR files from GitHub every time the containers start. If your cluster doesn't have Internet access, you must build custom images with the KAR files.

Also, the Helm Chart assumes that all external dependencies are running somewhere else. None of them would be initialized or maintained here. Those are Loki, PostgreSQL, Elasticsearch, and Kafka.

## Run in the cloud

The following assumes that you already have an AKS or GKE cluster up and running with [Nginx Ingress](https://kubernetes.github.io/ingress-nginx/) Controller and [cert-manager](https://cert-manager.io/docs/), and `kubectl` is correctly configured on your machine to access the cluster.

At a minimum, the cluster should have three instances with 4 Cores and 16GB of RAM on each of them.

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

> Please use your own domain

Please note that `apex1` uniquely identifies the environment. That word will be used as the namespace, the OpenNMS Instance ID, and prefix the `domain` for the FQDNs used in the Ingress Controller. Ensure to use the correct hostname for your dependencies, and the same name for the `StorageClass` used when created it.

Keep in mind the above is only an example. You must treat the content of `helm-cloud.yaml` as a sample for testing purposes.

To tune further, edit [helm-cloud.yaml](helm-cloud.yaml).

To access the cluster from external Minions, make sure to configure the DNS service correctly on your cloud provider.

To test Ingress access, you must configure a wildcard DNS entry for the chosen domain on your registrar, pointing to the public IP of the Ingress Controller, obtained as follow:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

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

Create the storage class (this must be done once):
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

> Please use your own domain

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

> Please use your own domain, and ensure it matches the domain passed to OpenNMS via Helm

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
  --kafka_boostrap kafka1.example.com:9092
```

Check the script for more details.

## Problems/Limitations

* The WebUI sends events handled by Queued to promote updating RRD files to ensure data is available. That won't work with dedicated UI servers (as Queued is not running there).
* When using Newts, the resource cache won't exist on the UI servers (maintained by Collectd), meaning all requests will hit Cassandra, slowing down the graph generation. The same applies when using Grafana via the UI servers.

## Manual configuration changes

* Either access the OpenNMS container via a remote shell through `kubectl`, and edit the file using `vi` (the only editor available within the OpenNMS container), or mount the NFS share from Google Filestore or Azure Files from a VM or a temporary container and make the changes.
* Send the reload configuration event via `send-event.pl` or the Karaf Shell (not accessible within the container).
* In case OpenNMS has to be restarted, delete the Pod (not the StatefulSet), and Kubernetes controller will recreate it again.

## RRDtool performance on Google Filestore

Using the `metrics-stress` command via Karaf Shell, emulating 1500 nodes and persisting 5000 metrics per second, the solution seems to stabilize around 5 minutes after having all the RRD files created (which took about 10 minutes after starting the command).

Enable port forwarding to access the Karaf Shell:

```bash
kubectl port-forward -n apex1 onms-core-0 8101
```

> Ensure to use the appropriate namespace.

From a different console, start the Karaf Shell:

```bash
ssh -o ServerAliveInterval=10 -p 8101 admin@localhost
```

Then,

```
opennms:stress-metrics -r 60 -n 1500 -f 20 -g 1 -a 50 -s 2 -t 100 -i 300
```

Google's Metric Explorer showed that Filestore writes were around 120 MiB/sec on average while the files were being created. After that, it decreased to about ten times less the initial throughput.

Note that at 5 minutes collection interval, persisting 5000 metrics per second implies having 1.5 million unique metrics.
