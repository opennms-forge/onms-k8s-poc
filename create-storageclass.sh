#!env bash
# @author Alejandro Galue <agalue@opennms.com>

set -e

environment=${1}
storageclass=${2}

if [[ "${environment}" != "gke" ]] && [[ "${environment}" != "aks" ]] && [[ "${environment}" != "minikube" ]]; then
  echo "Please specify the target environment: gke, aks, minikube"
  exit 1
fi

if [[ "${storageclass}" == "" ]]; then
  echo "Please specify the name of the storage class"
  exit 1
fi

yaml="/tmp/_opennms.storageclass-$(date +%s).yaml"

cat <<EOF >$yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${storageclass}
  labels:
    tier: storage
EOF

if [[ "${environment}" == "aks" ]]; then
  cat <<EOF >>$yaml
provisioner: file.csi.azure.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
mountOptions:
- dir_mode=0755
- file_mode=0644
- uid=10001 # OpenNMS User
- gid=10001 # OpenNMS Group
- mfsymlinks
- cache=strict
- actimeo=30
parameters:
  skuName: Standard_LRS
EOF
fi

if [[ "${environment}" == "gke" ]]; then
  cat <<EOF >>$yaml
provisioner: filestore.csi.storage.gke.io
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  tier: standard # standard, premium, or enterprise
  network: default
EOF
fi

if [[ "${environment}" == "minikube" ]]; then
  cat <<EOF >>$yaml
provisioner: k8s.io/minikube-hostpath
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
- dir_mode=0755
- file_mode=0644
- uid=10001
- gid=10001
EOF
fi

kubectl apply -f $yaml
rm -f $yaml

echo "Done!"