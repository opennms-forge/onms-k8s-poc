# OpenNMS K8s PoC

The objective of this project is to serve as a reference to implement [OpenNMS](https://www.opennms.com/) running in [Kubernetes](https://kubernetes.io/), deployed via [Helm](https://helm.sh/).

Each deployment would have a single Core Server, multiple read-only UI servers plus Grafana and a custom Ingress, sharing the RRD files and some configuration files, and Sentinels for flow processing.

Keep in mind that we expect Kafka, Elasticsearch, and PostgreSQL to run externally (and maintained separately from the solution), all with SSL enabled.

> *This is one way to approach the solution, without saying this is the only one or the best one. You should carefully study the content of this Helm Chart and tune it for your needs*.