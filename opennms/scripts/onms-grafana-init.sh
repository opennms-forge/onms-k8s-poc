#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# Intended to be used from the OpenNMS initialization script
# Designed for Horizon 29 or Meridian 2021 and 2022. Newer or older versions are not supported.
#
# External environment variables used by this script:
# CONFIG_DIR_OVERLAY (initialized by the caller script)
# GRAFANA_SERVER
# GF_SERVER_DOMAIN
# GF_SECURITY_ADMIN_PASSWORD

function wait_for {
  echo "Waiting for $1"
  IFS=':' read -a data <<< $1
  until printf "" 2>>/dev/null >>/dev/tcp/${data[0]}/${data[1]}; do
    sleep 5
  done
  echo "Done"
}

echo "OpenNMS Grafana Integration Script..."

# Requirements
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but it's not installed. Aborting."; exit 1; }
if [[ ${CONFIG_DIR_OVERLAY} == "" ]]; then
  echo >&2 "CONFIG_DIR_OVERLAY cannot be empty. Aborting."
  exit 1
fi

# Wait for dependencies
wait_for ${GRAFANA_SERVER}:3000

GRAFANA_AUTH="admin:${GF_SECURITY_ADMIN_PASSWORD}"

# Configure Flow Dashboard Link
FLOW_DASHBOARD=$(curl -u "${GRAFANA_AUTH}" "http://${GRAFANA_SERVER}:3000/api/search?query=flow" 2>/dev/null | jq '.[0].url' | sed 's/"//g')
echo "Flow Dashboard: ${FLOW_DASHBOARD}"
if [ "${FLOW_DASHBOARD}" == "null" ]; then
  echo "WARNING: cannot get Dashboard URL for the Deep Dive Tool"
else
  cat <<EOF > ${CONFIG_DIR_OVERLAY}/org.opennms.netmgt.flows.rest.cfg
flowGraphUrl=https://${GF_SERVER_DOMAIN}${FLOW_DASHBOARD}?node=\$nodeId&interface=\$ifIndex
EOF
fi

# Delete Grafana API Key if exists
KEY_ID=$(curl -u "${GRAFANA_AUTH}" "http://${GRAFANA_SERVER}:3000/api/auth/keys" 2>/dev/null | jq ".[] | select(.name==\"$(hostname)\") | .id")
if [ "${KEY_ID}" != "" ]; then
  echo "WARNING: API Key ${KEY_ID} exist for $(hostname), deleting it prior re-creating it again"
  curl -XDELETE -u "${GRAFANA_AUTH}" "http://${GRAFANA_SERVER}:3000/api/auth/keys/${KEY_ID}" 2>/dev/null
  echo ""
fi

# Create Grafana API Key and configure Grafana Box
GRAFANA_KEY=$(curl -u "${GRAFANA_AUTH}" -X POST -H "Content-Type: application/json" -d "{\"name\":\"$(hostname)\",\"role\": \"Viewer\"}" "http://${GRAFANA_SERVER}:3000/api/auth/keys" 2>/dev/null | jq .key - | sed 's/"//g')
if [ "${GRAFANA_KEY}" == "null" ]; then
  echo "WARNING: cannot get Grafana Key for $(hostname)"
else
  echo "Configuring Grafana Box for $(hostname)"
  cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/grafana.properties
org.opennms.grafanaBox.show=true
org.opennms.grafanaBox.hostname=${GF_SERVER_DOMAIN}
org.opennms.grafanaBox.port=443
org.opennms.grafanaBox.basePath=/
org.opennms.grafanaBox.apiKey=${GRAFANA_KEY}
EOF
fi
