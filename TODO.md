# TODO

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers, ensuring everything works.

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  * For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  * We could let the user choose between discrete assignments via Xms/Xmx or percentage.

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

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
