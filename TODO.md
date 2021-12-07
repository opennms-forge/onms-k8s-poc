# TODO

* Learn how the GKE Ingress works (in case the Nginx Ingress is not an option).

* Learn how to configure Grafana when PostgreSQL has strict TLS mode using private certificates.

* Allow tuning the DB connection pool for OpenNMS Core, UIs, and Sentinels.
  The number of connections, as the DB server must allow all DB pools per environment to connect.

* Add Server Certificates in PEM format besides the common Truststore.
  * Grafana requires it for `database.ca_cert_path` or `GF_DATABASE_CA_CERT_PATH` when using PostgreSQL with TLS, which is the only non-java application.

* Describe a vendor-independent procedure to manage the wildcard DNS entry for the Ingress.
  * The entry should point to the public IP of the Ingress Controller.

* Ensure the solution works on Google Cloud.

* Test the solution using Google SQL for PostgreSQL.

* Test the solution with Kafka outside K8s [Optional].

* Evaluate options for centralized logging (side-car with Fluentd).

* Use relative/percentage size for the Java Heap, based on Pod resources (instead of fixed values) for OpenNMS.
  * For instance, `-XX:MaxRAMPercentage={{ .Values.opennms.jvm.heapPercentage }}`
  * We could let the user choose between discrete assignments via Xms/Xmx or percentage.

* Evaluate and test solutions with private container registries.
  Allows us to use Meridian instead of Horizon.

* Start monitoring a local network with Flow processing and verify usage of the UI/Grafana servers.
  Ensure everything works.

* Perform stress tests using the `opennms:metrics-stress` command to ensure performance using RRD and shared volumes.

* Detect OpenNMS flavor and apply configuration changes accordingly.
  For instance, H29 requires Twin API with Kafka, whereas M2021 doesn't.

* Consider `NetworkPolicies` to isolate resources on a given namespace.

* Evaluate the idea of having custom entry point scripts replacing the initialization scripts.
  * The less invasive option to expand our possibility without building custom images.
  * There are limitations with `confd` in OpenNMS, besides other restrictions inside the `entrypoint.sh` script in OpenNMS and Sentinel that prevents enabling certain features like TLS for PostgreSQL.
  * Override the whole `datasource.url` for `org.opennms.netmgt.distributed.datasource.cfg` in Sentinel
  * Override the whole URLs for `opennms-datasources.xml` in OpenNMS.

* Improve Helm Chart for OpenNMS and relatives (no external dependencies).
  * Make Sentinel creation optional (Telemetryd handles Flows when disabled).
  * Choose between RRD over shared volume and Cortex.
  * Improve variables documentation in `values.yaml`.

* Build Terraform recipes for the Cloud Infrastructure resources.
  * Private container registry
  * Kubernetes cluster
  * SQL Service for PostgreSQL
