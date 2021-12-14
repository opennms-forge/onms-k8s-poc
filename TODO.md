# TODO

* When using RRDtool, allow configuring RRAs.

* Analyze the possibility to ignore the custom `StorageClass` when you don't need dedicated UI servers for RRD files; which asumes the default one (I believe it is `gce-pd` for Google Cloud or Azure Disk for AKS).
  * For configuration, using a NFS-like solution could have benefits in terms of accessing the data for troubleshooting purposes without the need to have access to Kubernetes.

* Test the solution against a secured [Grafana Loki](https://grafana.com/oss/loki/) server.
  * Explore [logcli](https://grafana.com/docs/loki/latest/getting-started/logcli/) to extract OpenNMS logs for troubleshooting purposes.
  * Review documentaion about handling Java Exceptions ([multiline](https://grafana.com/docs/loki/latest/clients/promtail/stages/multiline/) log entries).

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  * For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  * We could let the user choose between discrete assignments via Xms/Xmx or percentage.

* Evaluate and test solutions with private container registries ([Google Artifact Registry](https://cloud.google.com/artifact-registry/docs/overview), [Azure Container Registry](https://azure.microsoft.com/en-us/services/container-registry/)).
  Allows us to use Meridian instead of Horizon.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers, ensuring everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes. This is crucial for GKE as ownership is configured via `securityContext.fsGroup` (not required for AKS).

* Evaluate the idea of having custom entry point scripts replacing the initialization scripts.
  * The less invasive option to expand our possibility without building custom images.
  * There are limitations with `confd` in OpenNMS, besides other restrictions inside the `entrypoint.sh` script in OpenNMS and Sentinel that prevents enabling certain features.

* Improve Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make readiness/liveness probes configurable (DB migration time could impact behavior). Or keep them fixed and expose settings for the startup probe.
  * Improve variables documentation in `values.yaml`.
  * Use the `lookup` function to ensure that the `StorageClass` exists and fail if it doesn't. Or use it to only create it if it doesn't exist (and reduce requirements).

## Optional

* Learn how the GKE Ingress works, in case the Nginx Ingress is not an option.

* Consider `NetworkPolicies` to isolate resources on a given namespace.

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
