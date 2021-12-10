# TODO

* Learn how the GKE Ingress works (in case the Nginx Ingress is not an option).

* Describe a vendor-independent procedure to manage the wildcard DNS entry for the Ingress.
  * The entry should point to the public IP of the Ingress Controller.

* Ensure the solution works on Google Cloud.

* Test the solution using Google SQL for PostgreSQL.

* Test the solution with Kafka outside K8s [Optional].

* Analyze the possibility to ignore the custom StorageClass when you don't need dedicated UI servers for RRD files; which asumes the default one (I believe it is `gce-pd` for Google Cloud or Azure Disk for AKS).
  * For configuration, using a NFS-like solution could have benefits in terms of accessing the data for troubleshooting purposes without the need to have access to Kubernetes.

* Integrate Grafana into the OpenNMS Core and UI to generate PDF reports and access dashboards.

* Evaluate options for centralized logging based on [Grafana Loki](https://grafana.com/oss/loki/), for instance, as explained [here](https://grafana.com/docs/loki/latest/clients/promtail/installation/).
  * We should consider the Loki Server an external dependency like PostgreSQL or Kafka.
  * Explore adding a new Grafana Dashboard to see the logs (constrained by namespace).
  * Explore `logcli` to extract OpenNMS logs for troubleshooting purposes.
  * Research about handling Java Exceptions (multi-line log entries) with Loki.

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  * For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  * We could let the user choose between discrete assignments via Xms/Xmx or percentage.

* Evaluate and test solutions with private container registries ([Google Artifact Registry](https://cloud.google.com/artifact-registry/docs/overview), [Azure Container Registry](https://azure.microsoft.com/en-us/services/container-registry/)).
  Allows us to use Meridian instead of Horizon.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers.
  Ensure everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes. This is crucial for GKE as ownership is configured via `securityContext.fsGroup` (not required for AKS).

* Detect OpenNMS flavor and apply configuration changes accordingly.
  For instance, H29 requires Twin API with Kafka, whereas M2021 doesn't.

* Consider `NetworkPolicies` to isolate resources on a given namespace.

* Find a way to create OpenNMS users for Sentinel and Grafana.
  * Changing `http_username` or `http_password` will affect those applications until the changes are reflected in OpenNMS.
  * One approach could be create a `Job` that runs once after the Core server is up and running that uses the ReST API to add the users and change the admin password.

* Evaluate the idea of having custom entry point scripts replacing the initialization scripts.
  * The less invasive option to expand our possibility without building custom images.
  * There are limitations with `confd` in OpenNMS, besides other restrictions inside the `entrypoint.sh` script in OpenNMS and Sentinel that prevents enabling certain features.

* Improve Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make readiness/liveness probes configurable (DB migration time could impact behavior). Or keep them fixed and expose settings for the startup probe.
  * Improve variables documentation in `values.yaml`.
  * Use the `lookup` function to ensure that the `StorageClass` exists and fail if it doesn't. Or use it to only create it if it doesn't exist (and reduce requirements).

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
