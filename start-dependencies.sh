#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# WARNING: For testing purposes only

set -euo pipefail
trap 's=$?; echo >&2 "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

for cmd in "kubectl" "helm" "keytool"; do
  type $cmd >/dev/null 2>&1 || { echo >&2 "$cmd required but it's not installed; aborting."; exit 1; }
done

# Optional dependencies
INSTALL_ELASTIC=${INSTALL_ELASTIC:-false} # needed for Flow processing
INSTALL_KAFKA=${INSTALL_KAFKA:-false} # needed for Sentinel and Minion support
INSTALL_LOKI=${INSTALL_LOKI:-true} # needed for log aggregation together with promtail in containers; make sure dependencies.loki.hostname='' for the helm chart if this is disabled

# Required dependencies (if you don't install them here, they need to be running somewhere else)
INSTALL_POSTGRESQL=${INSTALL_POSTGRESQL:-true}

NAMESPACE="shared"
TARGET_DIR="jks" # Expected location for the JKS Truststores
PG_USER="postgres" # Must match dependencies.postgresql.username from the Helm deployment
PG_PASSWORD="P0stgr3s" # Must match dependencies.postgresql.password from the Helm deployment
PG_ONMS_USER="opennms" # Must match dependencies.opennms.configuration.database.username from the Helm deployment
PG_ONMS_PASSWORD="0p3nNM5" # Must match dependencies.opennms.configuration.database.password from the Helm deployment
KAFKA_USER="opennms" # Must match dependencies.kafka.username from the Helm deployment
KAFKA_PASSWORD="0p3nNM5" # Must match dependencies.kafka.password from the Helm deployment
ELASTIC_USER="elastic" # Must match dependencies.elasticsearch.username from the Helm deployment
ELASTIC_PASSWORD="31@st1c" # Must match dependencies.elasticsearch.password from the Helm deployment
TRUSTSTORE_PASSWORD="0p3nNM5" # Must match dependencies.kafka.truststore.password from the Helm deployment
CLUSTER_NAME="onms" # Must match the name of the cluster inside dependencies/kafka.yaml and dependencies/elasticsearch.yaml

# Patch NGinx to allow SSL Passthrough for Strimzi
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type json -p \
  '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-ssl-passthrough"}]'

# Update Helm Repositories
helm repo add jetstack https://charts.jetstack.io
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Cert-Manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set installCRDs=true --wait
kubectl apply -f ca -n cert-manager

# Create a namespace for most of the dependencies except for cert-manager (above), and the postgres and elastic operators (added below).
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install Grafana Loki
if [ "$INSTALL_LOKI" == "true" ]; then
  helm upgrade --install loki --namespace=$NAMESPACE \
    --set "fullnameOverride=loki" \
    --set "gateway.enabled=false" \
    --set "loki.storage.type=filesystem" \
    --set "loki.rulerConfig.storage.type=local" \
    --set "loki.auth_enabled=false" \
    --set "loki.commonConfig.replication_factor=1" \
    --set "loki.commonConfig.ring.instance_addr=127.0.0.1" \
    --set "loki.commonConfig.ring.kvstore.store=inmemory" \
    --set "monitoring.selfMonitoring.enabled=false" \
    --set "monitoring.selfMonitoring.grafanaAgent.installOperator=false" \
    --set "monitoring.selfMonitoring.lokiCanary.enabled=false" \
    --set "monitoring.serviceMonitor.enabled=false" \
    --set "monitoring.dashboards.enabled=false" \
    --set "monitoring.rules.enabled=false" \
    --set "monitoring.alerts.enabled=false" \
    --set "persistence.enabled=true" \
    --set "persistence.accessModes={ReadWriteOnce}" \
    --set "persistence.size=50Gi" \
    grafana/loki
fi

# Install PostgreSQL
if [ "$INSTALL_POSTGRESQL" == "true" ]; then
  kubectl apply -f https://raw.githubusercontent.com/zalando/postgres-operator/master/manifests/postgresql.crd.yaml
  kubectl apply -k github.com/zalando/postgres-operator/manifests
  kubectl create secret generic $PG_USER.onms-db.credentials.postgresql.acid.zalan.do --from-literal="username=$PG_USER" --from-literal="password=$PG_PASSWORD" -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  kubectl create secret generic $PG_ONMS_USER.onms-db.credentials.postgresql.acid.zalan.do --from-literal="username=$PG_ONMS_USER" --from-literal="password=$PG_ONMS_PASSWORD" -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f dependencies/postgresql.yaml -n $NAMESPACE
fi

if [ "$INSTALL_KAFKA" == "true" ]; then
  # Install Kafka via Strimzi
  kubectl create secret generic kafka-user-credentials --from-literal="$KAFKA_USER=$KAFKA_PASSWORD" -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "https://strimzi.io/install/latest?namespace=$NAMESPACE" -n $NAMESPACE
  kubectl apply -f dependencies/kafka.yaml -n $NAMESPACE
fi

if [ "$INSTALL_ELASTIC" == "true" ]; then
  # Install Elasticsearch via ECK
  kubectl create secret generic $CLUSTER_NAME-es-elastic-user --from-literal="$ELASTIC_USER=$ELASTIC_PASSWORD" -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  kubectl create -f https://download.elastic.co/downloads/eck/2.4.0/crds.yaml --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f https://download.elastic.co/downloads/eck/2.4.0/operator.yaml
  kubectl apply -f dependencies/elasticsearch.yaml -n $NAMESPACE
fi

# Wait for the clusters
if [ "$INSTALL_KAFKA" == "true" ]; then
  kubectl wait kafka/$CLUSTER_NAME --for=condition=Ready --timeout=300s -n $NAMESPACE
fi
if [ "$INSTALL_ELASTIC" == "true" ]; then
  kubectl wait pod -l elasticsearch.k8s.elastic.co/cluster-name=$CLUSTER_NAME --for=condition=Ready --timeout=300s -n $NAMESPACE
fi

# Prepare target directory for the Truststores
mkdir -p $TARGET_DIR
TRUSTSTORE_TEMP="/tmp/ca.truststore.$(date +%s)"

if [ "$INSTALL_POSTGRESQL" == "true" ]; then
  # Add OpenNMS CA (used for PostgreSQL) to the Truststore
  CERT_FILE_PATH="$TARGET_DIR/postgresql-ca.crt"
  kubectl get secret onms-ca -n cert-manager -o go-template='{{index .data "ca.crt" | base64decode }}' > $CERT_FILE_PATH
  keytool -import -trustcacerts -alias postgresql-ca -file $CERT_FILE_PATH -keystore $TRUSTSTORE_TEMP -storepass "$TRUSTSTORE_PASSWORD" -noprompt
fi

if [ "$INSTALL_ELASTIC" == "true" ]; then
  # Add Elasticsearch CA to the Truststore
  CERT_FILE_PATH="$TARGET_DIR/elasticsearch-ca.crt"
  kubectl get secret $CLUSTER_NAME-es-http-certs-internal -n $NAMESPACE -o go-template='{{index .data "ca.crt" | base64decode }}' > $CERT_FILE_PATH
  keytool -import -trustcacerts -alias elasticsearch-ca -file $CERT_FILE_PATH -keystore $TRUSTSTORE_TEMP -storepass "$TRUSTSTORE_PASSWORD" -noprompt
fi

if [ "$INSTALL_KAFKA" == "true" ]; then
  # Add Kafka CA to the Truststore
  CERT_FILE_PATH="$TARGET_DIR/kafka-ca.crt"
  kubectl get secret $CLUSTER_NAME-cluster-ca-cert -n $NAMESPACE -o go-template='{{index .data "ca.crt" | base64decode }}' > $CERT_FILE_PATH
  keytool -import -trustcacerts -alias kafka-ca -file $CERT_FILE_PATH -keystore $TRUSTSTORE_TEMP -storepass "$TRUSTSTORE_PASSWORD" -noprompt
fi

# Move Truststore to the target location
if [ -e $TRUSTSTORE_TEMP ]; then
  mv -f $TRUSTSTORE_TEMP $TARGET_DIR/truststore.jks
fi

# Show all resources
kubectl get all -n $NAMESPACE

echo "Done!"
