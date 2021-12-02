# OpenNMS K8s PoC

This project aims to serve as a reference implementation of OpenNMS in the cloud, having a single Core Server and multiple read-only UI servers, sharing the RRD files and some configuration files running in Kubernetes.

We expect that Kafka and PostgreSQL running externally (and maintained separately from the solution), so a pair of special services of type `ExternalName` would be created for them. That facilitates using local shared resources within Kubernetes for testing purposes without changing the workload manifests.

We expect `SASL_SSL` configured in Kafka using `SCRAM-SHA-512` for authentication.

## Requirements

### For Kubernetes

* A single instance of OpenNMS Core (backend) for centralized monitoring.
  OpenNMS doesn't support distributed mode, meaning the `StatefulSet` cannot have more than one replica.

* Multiple instances of read-only OpenNMS UI (frontend).
  Must be stateless (unconfigurable).
  The `Deployment` must have multiple instances.
  Any configuration change goes to the core server.
  
* Multiple instances of Grafana (frontend), using PostgreSQL as the backend, pointing to the UI service.

* Multiple instances of Sentinel to handle Flows.

* A custom `StorageClass` for shared content (Google Filestore or Azure Files) to use `ReadWriteMany`.
  Use the same `UID` and `GID` as the OpenNMS image with proper file modes.

* A shared volume for the RRD files, mounted as read-only on the UI instances.

* A shared volume for the core configuration files, mounted as read-only on the UI instances.
  The purpose is to share configuration across all the OpenNMS instances.

* A `Secret` to store the credentials.

* A `ConfigMap` to store initialization scripts and standard configuration settings.

* An `ExternalName` service that represents a PostgreSQL server.

* An `ExternalName` service that represents a Kafka bootstrap server.

* An `ExternalName` service that represents an Elasticsearch server.

* An `Ingress` to control TLS termination and provide access to all the components.
  We could manage certificates using LetsEncrypt via `cert-manager`.
  To integrate with Google Cloud DNS managed zones or Azure DNS, we need a wild-card entry.

### External Dependencies

* PostgreSQL server as the central database for OpenNMS and Grafana.

* External Kafka cluster for OpenNMS-to-Minion communication.

* Google Filestore or Azure Files for the OpenNMS configuration and RRD files (managed by provider)
  The documentation recommends 1.21 or later for the CSI driver.

* Private Container Registry for custom Meridian Images (if applicable), in case OpenNMS Horizon is not an option.

* [cert-manager](https://cert-manager.readthedocs.io/en/latest/) to provide HTTPS/TLS support to the web-based services managed by the ingress controller.

## Deployment

* Use` Terraform` or your preferred methodology to deploy the Kubernetes Cluster and the shared infrastructure in Google Cloud or Azure.

* Use `kubectl` to deploy the Kubernetes components (applications).
  We could offer to create a `Helm` chart in the future to simplify the deployment.

* Use `initContainers` to initialize the mandatory configuration settings.
  That should take care of OpenNMS upgrades in the Core instance.
  WebUI servers are stateless, so they don't need configuration life-cycle management.

## Run in the cloud

The following assumes that you already have an AKS or GKE cluster up and running with Nginx Ingress Controller and `cert-manager`, and `kubectl` is correctly configured on your machine to access the cluster. At a minimum, it should have three instances with 4 Cores and 16GB of RAM on each of them.

Place the Java Truststore with the CA Certificate Chain of your Kafka cluster on a JKS file located at `k8s/pki/kafka-truststore.jks`. Otherwise, the deployment will fail.

Ensure that [k8s/postgresql.service.yaml](k8s/postgresql.service.yaml) and [k8s/kafka.service.yaml](k8s/kafka.service.yaml) point to the correct external resources. By default, they point to the test resources in the `shared` namespace.

Ensure that [k8s/ingress.yaml](k8s/ingress.yaml) and `GF_SERVER_DOMAIN` within [k8s/kustomization.yaml](k8s/kustomization.yaml) use the correct domain for the hostnames.

For testing purposes, use the following script to initialize the dependencies within Kubernetes (no need to update the `ExternalName` services, and the script generates the Truststore for you, and it includes `cert-manager`):

```bash
./start-dependencies.sh
```

> You should enable SSL Passthrough on your NGinx Ingress controller to let Strimzi works properly.

Start the cluster in Azure:

```bash
kubectl apply -k aks
```

Start the cluster in Google Cloud:

```bash
kubectl apply -k gke
```

To access the cluster from external Minions, make sure to configure the DNS service correctly on your cloud provider.

## Run locally

Start Minikube:

```bash
minikube start --cpus=4 --memory=24g --addons=ingress --addons=ingress-dns --addons=metrics-server
```

Enable SSL Passthrough to use Ingress with Strimzi:

```bash
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type json -p \
  '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-ssl-passthrough"}]'
pod=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller | grep Running | awk '{print $1}')
kubectl delete pod/$pod -n ingress-nginx
```

Start the test dependencies:

```bash
./start-dependencies.sh
```

Start OpenNMS:

```bash
kubectl apply -k minikube
```

Take a look at the documentation of [ingress-dns](https://github.com/kubernetes/minikube/tree/master/deploy/addons/ingress-dns) for more information about how to use it, to avoid messing with `/etc/hosts`.

For instance, for macOS:

```bash
DOMAIN="k8s.agalue.net" # Please use your own, and ensure it matches k8s/ingress.yaml

cat <<EOF | sudo tee /etc/resolver/minikube-default-test
domain $DOMAIN
nameserver $(minikube ip)
search_order 1
timeout 5
EOF
```

## Start an external Minion

Adjust the [start-minion.sh](start-minion.sh) script accordingly and run it. By default, it connects to the Kafka cluster managed by Strimzi for testing purposes.

## Pending

* Find a way to use the Graph Templates from the Core Server within the UI servers.

## Manual configuration changes

* Access the OpenNMS container via a remote shell.
* Edit the file using `vi` (the only editor available within the OpenNMS container).
* Send the reload configuration event via `send-event.pl` or the Karaf Shell (not accessible within the container).
  In case OpenNMS has to be restarted, delete the Pod, and Kubernetes will recreate it again.
  Changes persisted to the PV.
