#!env bash
# @author Alejandro Galue <agalue@opennms.com>
#
# WARNING: For testing purposes only

NAMESPACE="shared"
TARGET_DIR="jks" # Expected location for the JKS Truststores
ONMS_USER="opennms" # Must match dependencies.kafka.username from the Helm deployment
ONMS_PASSWORD="0p3nNM5" # Must match dependencies.kafka.password from the Helm deployment
TRUSTSTORE_FILE="kafka-truststore.jks"
TRUSTSTORE_PASSWORD="0p3nNM5" # Must match dependencies.kafka.truststore.password from the Helm deployment
CLUSTER_NAME="onms" # Must match the name of the cluster inside dependencies/kafka.yaml

kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type json -p \
  '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-ssl-passthrough"}]'
NGINX_POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller | grep Running | awk '{print $1}')
kubectl delete pod/$NGINX_POD -n ingress-nginx

CMVER=$(curl -s https://api.github.com/repos/jetstack/cert-manager/releases/latest | grep tag_name | cut -d '"' -f 4)
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/$CMVER/cert-manager.yaml
kubectl wait pod -l app.kubernetes.io/instance=cert-manager --for=condition=Ready --timeout=300s -n cert-manager
kubectl apply -f ca -n cert-manager

kubectl create namespace $NAMESPACE
kubectl create secret generic kafka-user-credentials --from-literal="$ONMS_USER=$ONMS_PASSWORD" -n $NAMESPACE
kubectl apply -f "https://strimzi.io/install/latest?namespace=$NAMESPACE" -n $NAMESPACE
kubectl apply -f dependencies -n $NAMESPACE
kubectl wait kafka/$CLUSTER_NAME --for=condition=Ready --timeout=300s -n $NAMESPACE

mkdir -p $TARGET_DIR

CERT_FILE_PATH="$TARGET_DIR/kafka-ca.crt"
kubectl get secret $CLUSTER_NAME-cluster-ca-cert -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' | base64 --decode > $CERT_FILE_PATH

TEMP_TRUSTSTORE="/tmp/ca.truststore.$(date +%s)"
keytool -import -trustcacerts -alias root -file $CERT_FILE_PATH -keystore $TEMP_TRUSTSTORE -storepass "$TRUSTSTORE_PASSWORD" -noprompt
mv -f $TEMP_TRUSTSTORE $TARGET_DIR/$TRUSTSTORE_FILE

kubectl get all -n $NAMESPACE

echo "Done!"
echo "The Truststore for Kafka Clients is available at $TARGET_DIR/$TRUSTSTORE_FILE"
