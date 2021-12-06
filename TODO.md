# TODO

* Learn how the GKE Ingress works (in case the Nginx Ingress is not an option).

* Enable TLS in PostgreSQL for the test dependencies.
  Update the central Truststore in OpenNMS.

* Describe a vendor-independent procedure to manage the wildcard DNS entry for the Ingress.
  The entry should point to the public IP of the Ingress Controller.

* Ensure the solution works on Google Cloud.

* Test the solution using Google SQL for PostgreSQL.

* Test the solution with Kafka outside K8s [Optional].

* Evaluate options for centralized logging (side-car with Fluentd).

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  We could let the user choose between discrete assignments via Xms/Xmx or percentage.

* Evaluate and test solutions with private container registries.
  Allows us to use Meridian instead of Horizon.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers.
  Ensure everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes.

* Detect OpenNMS flavor and apply configuration changes accordingly.
  For instance, H29 requires Twin API with Kafka, whereas M2021 doesn't.

* Improve Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make Sentinel creation optional (Telemetryd handles Flows when disabled).
  * Choose between RRD over shared volume and Cortex.
  * Improve variables documentation in `values.yaml`.

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
