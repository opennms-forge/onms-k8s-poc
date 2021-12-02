# TODO

* Add TLS termination for the Ingress Controller.
  Use cert-manager with either LetsEncrypt or private certificates.

* Learn how the GKE Ingress works (in case the Nginx Ingress is not an option).

* Describe a vendor-independept procedure to manage the wildcard DNS entry for the Ingress.
  The entry should point to the public IP of the Ingress Controller.

* Ensure the solution works on GCloud.

* Test the solution using Google SQL for PostgreSQL.

* Test the solution with Kafka outside K8s [Optional].

* Evaluate options for centralized logging (side-car with Fluentd).

* Start monitoring a local network and try to use the UI/Grafana servers.
  Ensure everything works.

* Create a Helm Chart for OpenNMS and relatives (no external dependencies).
