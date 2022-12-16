#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# External environment variables used by this script:
# OPENNMS_SERVER
# OPENNMS_HTTP_USER
# OPENNMS_HTTP_PASS
# OPENNMS_ADMIN_PASS
# ENABLE_GRAFANA
# GRAFANA_SERVER
# GF_SECURITY_ADMIN_PASSWORD

set -euo pipefail
trap 's=$?; echo >&2 "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

trap 'echo "Received SIGHUP: exiting."; exit 2' HUP
trap 'echo "Received SIGTERM: exiting."; exit 2' TERM

function wait_for {
  echo "Waiting for $1"
  IFS=':' read -a data <<< $1
  until printf "" 2>>/dev/null >>/dev/tcp/${data[0]}/${data[1]}; do
    sleep 5
  done
  echo "Done"
}

echo "OpenNMS Post-Initialization Script..."

# Requirements
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1   || { echo >&2 "jq is required but it's not installed. Aborting.";   exit 1; }

# Wait for dependencies
wait_for ${OPENNMS_SERVER}:8980

ONMS_AUTH="admin:${OPENNMS_ADMIN_PASS}"

if [[ ${ENABLE_GRAFANA} == "true" ]]; then
  # Configure Grafana Endpoint for Reports
  ID=$(curl -sSf -u "${ONMS_AUTH}" http://${OPENNMS_SERVER}:8980/opennms/rest/endpoints/grafana | jq ".[] | select(.uid=\"$(hostname)\") | .id") || true
  if [[ $ID == "" ]]; then
    GRAFANA_KEY=$(curl -sSf -u "${ONMS_AUTH}" -X POST -H "Content-Type: application/json" -d "{\"name\":\"$(hostname)\",\"role\": \"Viewer\"}" "http://${GRAFANA_SERVER}:3000/api/auth/keys" | jq -r .key)
    if [[ ${GRAFANA_KEY} == "null" ]]; then
      echo "WARNING: cannot get Grafana Key"
    else
      echo "Configuring Grafana Endpoint..."
      curl -sSf -u "${ONMS_AUTH}" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"uid\":\"$(hostname)\",\"apiKey\":\"${GRAFANA_KEY}\",\"url\":\"http://${GRAFANA_SERVER}:3000\"}" \
        "http://${OPENNMS_SERVER}:8980/opennms/rest/endpoints/grafana"
    fi
  else
    echo "WARNING: Grafana Endpoint already configured"
  fi
  echo "Grafana is not enabled, not configuration Grafana Endpoint"
fi

# Add user to access ReST API for Grafana, Sentinels and Minions
echo "Adding user ${OPENNMS_HTTP_USER} (for Grafana and Sentinels)"
curl -sSf -u "${ONMS_AUTH}" -X POST \
  -H "Content-Type: application/xml" \
  -d "<user><user-id>${OPENNMS_HTTP_USER}</user-id><password>${OPENNMS_HTTP_PASS}</password><role>ROLE_REST</role><role>ROLE_MINION</role></user>" \
  "http://${OPENNMS_SERVER}:8980/opennms/rest/users?hashPassword=true"
