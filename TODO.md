# TODO

* Learn how the GKE Ingress works (in case the Nginx Ingress is not an option).

* Describe a vendor-independent procedure to manage the wildcard DNS entry for the Ingress.
  * The entry should point to the public IP of the Ingress Controller.

* Ensure the solution works on Google Cloud.

* Test the solution using Google SQL for PostgreSQL.

* Test the solution with Kafka outside K8s [Optional].

* Evaluate options for centralized logging based on [Grafana Loki](https://grafana.com/oss/loki/).

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  * For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  * We could let the user choose between discrete assignments via Xms/Xmx or percentage.

* Evaluate and test solutions with private container registries ([Google Artifact Registry](https://cloud.google.com/artifact-registry/docs/overview), [Azure Container Registry](https://azure.microsoft.com/en-us/services/container-registry/)).
  Allows us to use Meridian instead of Horizon.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers.
  Ensure everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes.

* Detect OpenNMS flavor and apply configuration changes accordingly.
  For instance, H29 requires Twin API with Kafka, whereas M2021 doesn't.

* Consider `NetworkPolicies` to isolate resources on a given namespace.

* Find a way to create OpenNMS users for Sentinel and Grafana.
  Changing `http_username` or `http_password` will affect those applications until the changes are reflected in OpenNMS.

* Evaluate the idea of having custom entry point scripts replacing the initialization scripts.
  * The less invasive option to expand our possibility without building custom images.
  * There are limitations with `confd` in OpenNMS, besides other restrictions inside the `entrypoint.sh` script in OpenNMS and Sentinel that prevents enabling certain features.

* Improve Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make Sentinel creation optional (Telemetryd handles Flows when disabled).
  * Choose between RRD over shared volume and Cortex.
  * Improve variables documentation in `values.yaml`.
  * Use the `lookup` function to ensure that the `StorageClass` exists and fail if it doesn't. Or use it to only create it if it doesn't exist (and reduce requirements).

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
