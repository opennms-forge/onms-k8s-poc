# TODO

* Learn how the GKE Ingress works (in case the Nginx Ingress is not an option).

* Enable TLS in PostgreSQL for the test dependencies.

* Describe a vendor-independent procedure to manage the wildcard DNS entry for the Ingress.
  The entry should point to the public IP of the Ingress Controller.

* Ensure the solution works on GCloud.

* Test the solution using Google SQL for PostgreSQL.

* Test the solution with Kafka outside K8s [Optional].

* Evaluate options for centralized logging (side-car with Fluentd).

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.

* Evaluate and test solutions for private container registries.
  Allows us to use Meridian instead of Horizon.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers.
  Ensure everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes.

* Detect OpenNMS flavor and apply configuration changes accordingly.
  For instance, H29 requires Twin API with Kafka, whereas M2021 doesn't.

* Create a Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make the Namespace and the Instance ID the same.
  * Make Sentinel creation optional (Telemetryd handles Flows when disabled).
  * Choose between RRD over shared volume and Cortex.

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL