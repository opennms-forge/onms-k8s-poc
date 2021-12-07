#!env bash
# @author Alejandro Galue <agalue@opennms.com>
#
# WARNING: For testing purposes only

set -e

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
AKS_NODE_COUNT=${AKS_NODE_COUNT-3}
AKS_VM_SIZE=${AKS_VM_SIZE-Standard_DS4_v2}

VERSION=$(az aks get-versions --location "$LOCATION" | jq -r '.orchestrators[-1].orchestratorVersion')

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
