#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# External environment variables:
# - OPENNMS_SERVER
# - OPENNMS_HTTP_USER
# - OPENNMS_HTTP_PASS
# - OPENNMS_ADMIN_PASS

function wait_for {
  echo "Waiting for $1"
  IFS=':' read -a data <<< $1
  until printf "" 2>>/dev/null >>/dev/tcp/${data[0]}/${data[1]}; do
    sleep 5
  done
  echo "Done"
}

command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Aborting."; exit 1; }

wait_for ${OPENNMS_SERVER}:8980

# Add user to access ReST API for Grafana and Sentinel
curl -u admin:admin -v -X POST \
  -H "Content-Type: application/xml" \
  -d "<user><user-id>${OPENNMS_HTTP_USER}</user-id><password>${OPENNMS_HTTP_PASS}</password><role>ROLE_REST</role></user>" \
  "http://${OPENNMS_SERVER}:8980/opennms/rest/users?hashPassword=true"

# Change password for the admin account
if [[ ${OPENNMS_ADMIN_PASS} != "" ]]; then
  curl -u admin:admin -v -X PUT \
    -d "password=${OPENNMS_ADMIN_PASS}" \
    "http://${OPENNMS_SERVER}:8980/opennms/rest/users/admin?hashPassword=true"
fi