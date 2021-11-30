# OpenNMS PoC

This project aims to serve as a reference implementation of OpenNMS in the cloud, having a single Core Server and multiple read-only UI servers, sharing the RRD files and some configuration files running in Kubernetes.

We expect that Kafka and PostgreSQL running externally (and maintained separately from the solution), so a pair of special services of type `ExternalName` would be created for them. That facilitates using local shared resources within Kubernetes for testing purposes without changing the workload manifests.

## Requirements

### For Kubernetes

* A single instance of OpenNMS Core (backend) for centralized monitoring.
  OpenNMS doesn't support distributed mode, meaning the `StatefulSet` cannot have more than one replica.

* Multiple instances of read-only OpenNMS UI (frontend).
  Must be stateless (unconfigurable).
  The `Deployment` must have multiple instances.
  Any configuration change goes to the core server.
  
* Multiple instances of Grafana (frontend), using PostgreSQL as the backend, pointing to the UI service.

* A custom `StorageClass` for shared content (Google Filestore or Azure Files) to use `ReadWriteMany`.
  Use the same `UID` and `GID` as the OpenNMS image with proper file modes.

* A shared volume for the RRD files, mounted as read-only on the UI instances.

* A shared volume for the core configuration files, mounted as read-only on the UI instances.
  The purpose is to share configuration across all the OpenNMS instances.

* A `Secret` to store the credentials.

* A `ConfigMap` to store initialization scripts and standard configuration settings.

* An `ExternalName` service that represents a PostgreSQL server.

* An `ExternalName` service that represents a Kafka bootstrap server.

* An `Ingress` to control TLS termination and provide access to all the components.
  We could manage certificates using LetsEncrypt via `cert-manager`.
  To integrate with Google Cloud DNS managed zones or Azure DNS, we need a wild-card entry.

### External Dependencies

* PostgreSQL server as the central database for OpenNMS and Grafana.

* External Kafka cluster for OpenNMS-to-Minion communication.

* Google Filestore or Azure Files for the OpenNMS configuration and RRD files (managed by provider)
  The documentation recommends 1.21 or later for the CSI driver.

* Private Container Registry for custom Meridian Images (if applicable), in case OpenNMS Horizon is not an option.

## Deployment

* Use` Terraform` to deploy the infrastructure in Google Cloud or Azure
  That is for testing purposes. The customer must have this running and provide access to it.

* Use `kubectl` to deploy the Kubernetes components (applications).
  We could offer to create a `Helm` chart in the future to simplify the deployment.

* Use `initContainers` to initialize the mandatory configuration settings.
  That should take care of OpenNMS upgrades in the Core instance.
  WebUI servers are stateless, so they don't need configuration life-cycle management.

## Run in the cloud

For testing purposes, initialize the test dependencies:

```bash
kubectl apply -k dependencies
```

Ensure that [k8s/postgresql.service.yaml](k8s/postgresql.service.yaml) and [k8s/kafka.service.yaml](k8s/kafka.service.yaml) point to the correct external resources. By default, they point to the test resources in the `shared` namespace.

Ensure that [k8s/ingress.yaml](k8s/ingress.yaml) and `GF_SERVER_DOMAIN` within [k8s/kustomization.yaml](k8s/kustomization.yaml) use the correct domain for the hostnames.

Start the cluster in Azure:

```bash
kubectl apply -k aks
```

Start the cluster in Google Cloud:

```bash
kubectl apply -k gke
```

## Run locally

```bash
minikube start --cpus=4 --memory=24g --addons=ingress --addons=ingress-dns --addons=metrics-server
kubectl apply -k minikube
```

## Manual configuration changes

* Access the OpenNMS container via a remote shell.
* Edit the file using `vi` (the only editor available within the OpenNMS container).
* Send the reload configuration event via `send-event.pl` or the Karaf Shell (not accessible within the container).
  In case OpenNMS has to be restarted, delete the Pod, and Kubernetes will recreate it again.
  Changes persisted to the PV.
