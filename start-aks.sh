#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# WARNING: For testing purposes only

set -e

for cmd in "az" "kubectl"; do
  type $cmd >/dev/null 2>&1 || { echo >&2 "$cmd required but it's not installed; aborting."; exit 1; }
done

if [[ "$SERVICE_PRINCIPAL" == "" ]]; then
  echo "Please create and export an environment variable called SERVICE_PRINCIPAL with the ID of the Service Account to use with AKS"
  exit 1
fi

if [[ "$CLIENT_SECRET" == "" ]]; then
  echo "Please create and export an environment variable called CLIENT_SECRET with the Password of the Service Account to use with AKS"
  exit 1
fi

RESOURCE_GROUP=${RESOURCE_GROUP-support-testing}
LOCATION=${LOCATION-eastus}
DOMAIN=${DOMAIN-k8s.agalue.net}
AKS_NODE_COUNT=${AKS_NODE_COUNT-3}
AKS_VM_SIZE=${AKS_VM_SIZE-Standard_DS4_v2}

VERSION=$(az aks get-versions --location "$LOCATION" | jq -r '.orchestrators[-1].orchestratorVersion')

echo "Starting Kubernetes version $VERSION"
az aks create --name "$USER-opennms" \
  --resource-group "$RESOURCE_GROUP" \
  --service-principal "$SERVICE_PRINCIPAL" \
  --client-secret "$CLIENT_SECRET" \
  --dns-name-prefix "$USER-opennms" \
  --kubernetes-version "$VERSION" \
  --location "$LOCATION" \
  --node-count $AKS_NODE_COUNT \
  --node-vm-size $AKS_VM_SIZE \
  --network-plugin azure \
  --network-policy azure \
  --ssh-key-value ~/.ssh/id_rsa.pub \
  --admin-username "$USER" \
  --nodepool-tags "Owner=$USER" \
  --tags "Owner=$USER"

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$USER-opennms" --overwrite-existing

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
kubectl wait pod -l app.kubernetes.io/component=controller --for=condition=Ready --timeout=300s -n ingress-nginx

export NGINX_EXTERNAL_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
az network dns record-set a add-record -g "$RESOURCE_GROUP" -z "$DOMAIN" -n "*" -a $NGINX_EXTERNAL_IP
