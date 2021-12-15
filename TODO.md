# TODO

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  * For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  * We could let the user choose between discrete assignments via Xms/Xmx or percentage.

* Analyze the possibility to ignore the custom `StorageClass` when you don't need dedicated UI servers; which would use the default one (I believe it is `gce-pd` for Google Cloud or Azure Disk for AKS).
  * However, using a NFS-like solution could have benefits in terms of backups or accessing the data for troubleshooting or management purposes without the need to have access to Kubernetes.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers, ensuring everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes. This is crucial for GKE as ownership is configured via `securityContext.fsGroup` (not required for AKS).

* Evaluate the idea of having custom entry point scripts replacing the initialization scripts.
  * The less invasive option to expand our possibility without building custom images.
  * There are limitations with `confd` in OpenNMS, besides other restrictions inside the `entrypoint.sh` script in OpenNMS and Sentinel that prevents enabling certain features.

* Improve Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make readiness/liveness probes configurable (DB migration time could impact behavior). Or keep them fixed and expose settings for the startup probe.
  * Use the `lookup` function to ensure that the `StorageClass` exists and fail if it doesn't. Or use it to only create it if it doesn't exist (and reduce requirements).

## Optional

* Learn how the GKE Ingress works, in case the Nginx Ingress is not an option.

* Consider `NetworkPolicies` to isolate resources on a given namespace.

* Test the solution against a secured [Grafana Loki](https://grafana.com/oss/loki/) server.
  * Explore [logcli](https://grafana.com/docs/loki/latest/getting-started/logcli/) to extract OpenNMS logs for troubleshooting purposes.

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
