**General Diagram**

![Diagram](diagrams/onms-k8s-poc-diagrams.001.png)

**Customer Namespace Deployment Diagram**

![Diagram](diagrams/onms-k8s-poc-diagrams.002.png)

**Shared Volumes Diagram**

The following describes the use case when having dedicated OpenNMS UI instances:

![Diagram](diagrams/onms-k8s-poc-diagrams.003.png)

The above doesn't apply when creating an environment without UI instances, meaning the Helm Chart won't use the custom `StorageClass`. Instead, it assumes the usage of the default from your Kubernetes cluster. For example, on GKE, it is called `standard` and uses `kubernetes.io/gce-pd`.

## Design

The solution is based and tested against the latest Horizon 29 and should work with Meridian 2021 and 2022. However, versions newer than that won't work without modifying the logic of the Helm Chart and initialization scripts.

Keep in mind that you need a subscription to use Meridian. In this case, you would have to build the Docker images and place them on a private registry to use Meridian with this deployment. Doing that falls outside the scope of this repository, but the main GitHub Repository for OpenNMS offers a [guide](https://github.com/OpenNMS/opennms/tree/master/opennms-container) that you could use as a reference.

Due to how the current Docker Images were designed and implemented, the solution requires multiple specialized scripts to configure each application properly. You could build your images and move the logic from the scripts executed via `initContainers` to your custom entry point script and simplify the Helm Chart. 

The scripts configure only a certain number of things. Each deployment would likely need additional configuration, which is the main reason for using a Persistent Volume for the Configuration Directory of the Core OpenNMS instance.

We must place the core configuration on a PVC configured as `ReadWriteMany` to allow the usage of independent UI servers so that the Core can make changes and the UI instances can read from them. Unfortunately, this imposes some restrictions on the chosen cloud provider. For example, in Google Cloud, you would have to use [Google Filestore](https://cloud.google.com/filestore), which cannot have volumes less than 1TB, exaggerated for what the configuration directory would ever have (if UI servers are required). In contrast, that's not a problem when using [Azure Files](https://azure.microsoft.com/en-us/services/storage/files/), which has more flexibility than Google Filestore. The former exposes the volumes via SMB or NFS with essentially any size, whereas the latter only uses NFS with size restrictions.

One advantage of configuring that volume is allowing backups and access to the files without accessing the OpenNMS instances running in Kubernetes.

The reasoning for the UI servers is to alleviate the Core Server from ReST and UI-only requests. Unfortunately, this makes the deployment more complex. It is a trade-off you would have to evaluate. Field tests are required to decide whether or not this is needed and how many instances would be required.

The UI servers need to access multiple files from the Core server to serve multiple requests (including the ReST API). For this reason, a solution based on symlinks is in place via the initialization scripts. Also, to reduce the complexity, the UI servers are forced to be read-only, meaning even users with `ROLD_ADMIN` cannot make any changes (not even through ReST). You should apply any configuration change via the Core Instance.

Similarly, when using RRDtool instead of Newts/Cassandra or Cortex, a shared volume with `ReadWriteMany` is required for the same reasons (the Core would be writing to it, and the UI servers would be reading from it). Additionally, when switching strategies and migration are required, you could work outside Kubernetes.

Please note that the volumes would still be configured that way even if you decide not to use UI instances; unless you modify the logic of the Helm Chart.

To alleviate load from OpenNMS, you can optionally start Sentinel instances for Flow Processing. That requires having an Elasticsearch cluster available. When Sentinels are present, Telemetryd would be disabled in OpenNMS.

The OpenNMS Core and Sentinels would be backed by a `StatefulSet` but keep in mind that there can be one and only one Core instance. To have multiple Sentinels, make sure to have enough partitions for the Flow topics in your Kafka clusters, as all of them would be part of the same consumer group.

The current OpenNMS instances are not friendly when accessing log files. The Helm Chart allows you to configure [Grafana Loki](https://grafana.com/oss/loki/) to centralize all the log messages. When the Loki server is configured, the Core instance, the UI instances, and the Sentinel instances will be forwarding logs to Loki. The current solution uses the sidecar pattern using [Grafana Promtail](https://grafana.com/docs/loki/latest/clients/promtail/) to deliver the logs.

All the Docker Images can be customizable via Helm Values. The solution allows you to configure custom Docker Registries to access your custom images, or when all the images you're planning to use won't be in Docker Hub or your Kubernetes cluster won't have Internet Access. Please keep in mind that your custom images should be based on those currently in use.

If you plan to use the TSS Cortex plugin, the current solution will download the KAR file from GitHub every time the containers start. If your cluster doesn't have Internet access, you must build custom images with the KAR file.

For the ALEC KAR plugin, the latest release will be fetched from GitHub like the TSS Cortex Plugin above unless `alecImage` is set, in which case it will be loaded from the specified Docker image.

Also, the Helm Chart assumes that all external dependencies are running somewhere else. None of them would be initialized or maintained here. Those are Loki, PostgreSQL, Elasticsearch, Kafka and Cortex (when applies). There is a script provided to startup a set of dependencies for testing as a part of the same cluster but **this is not intended for production use.**
