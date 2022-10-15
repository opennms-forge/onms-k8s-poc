#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# Intended to be used as part of an InitContainer expecting the same Container Image as OpenNMS
# Designed for Horizon 29 or Meridian 2021 and 2022. Newer or older versions are not supported.
#
# External environment variables used by this script:
# OPENNMS_SERVER
# OPENNMS_DATABASE_CONNECTION_MAXPOOL

set -euo pipefail
trap 's=$?; echo >&2 "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

umask 002

function wait_for {
  echo "Waiting for $1"
  IFS=':' read -a data <<< $1
  until printf "" 2>>/dev/null >>/dev/tcp/${data[0]}/${data[1]}; do
    sleep 5
  done
  echo "Done"
}

echo "OpenNMS UI Configuration Script..."

# Requirements
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Aborting."; exit 1; }
if [[ ! -e /scripts/onms-common-init.sh ]]; then
  echo >&2 "onms-common-init.sh required but it's not present. Aborting."; exit 1;
fi

# Defaults
OPENNMS_DATABASE_CONNECTION_MAXPOOL=${OPENNMS_DATABASE_CONNECTION_MAXPOOL-50}

# Wait for Dependencies
wait_for ${OPENNMS_SERVER}:8980

CORE_CONFIG_DIR=/opennms-core/etc # Mounted Externally
OVERLAY_DIR=/opt/opennms-overlay  # Mounted Externally

CONFIG_DIR_OVERLAY=${OVERLAY_DIR}/etc
WEB_DIR_OVERLAY=${OVERLAY_DIR}/jetty-webapps/opennms/WEB-INF
TEMPLATES_DIR_OVERLAY=${WEB_DIR_OVERLAY}/templates

mkdir -p ${TEMPLATES_DIR_OVERLAY}
mkdir -p ${CONFIG_DIR_OVERLAY}/opennms.properties.d/

# Ensure the install script won't be executed
touch ${CONFIG_DIR_OVERLAY}/configured

# Apply common OpenNMS configuration settings
source /scripts/onms-common-init.sh

# Trim down the events configuration, as event processing is not required for the WebUI
cat <<EOF > ${CONFIG_DIR_OVERLAY}/eventconf.xml
<?xml version="1.0"?>
<events xmlns="http://xmlns.opennms.org/xsd/eventconf">
  <global>
    <security>
      <doNotOverride>logmsg</doNotOverride>
      <doNotOverride>operaction</doNotOverride>
      <doNotOverride>autoaction</doNotOverride>
      <doNotOverride>tticket</doNotOverride>
      <doNotOverride>script</doNotOverride>
    </security>
  </global>
EOF
grep 'events\/opennms' /opt/opennms/share/etc-pristine/eventconf.xml >> ${CONFIG_DIR_OVERLAY}/eventconf.xml
cat <<EOF >> ${CONFIG_DIR_OVERLAY}/eventconf.xml
</events>
EOF

# Trim down the services/daemons configuration, as only the WebUI will be running
cat <<EOF > ${CONFIG_DIR_OVERLAY}/service-configuration.xml
<?xml version="1.0"?>
<service-configuration xmlns="http://xmlns.opennms.org/xsd/config/vmmgr">
  <service>
    <name>OpenNMS:Name=Manager</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="stop" pass="1" method="doSystemExit"/>
  </service>
  <service>
    <name>OpenNMS:Name=TestLoadLibraries</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="start" pass="0" method="doTestLoadLibraries"/>
  </service>
  <service>
    <name>OpenNMS:Name=Eventd</name>
    <class-name>org.opennms.netmgt.eventd.jmx.Eventd</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
  <service>
    <name>OpenNMS:Name=JettyServer</name>
    <class-name>org.opennms.netmgt.jetty.jmx.JettyServer</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
</service-configuration>
EOF

# Additional changes for the UI-Only use case
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/webui-extra.properties
opennms.report.scheduler.enabled=false
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
EOF

# Create links to files from Core server
# The following is not a comprehensive list of files to share
CORE_FILES=(
  'categories.xml' \
  'groups.xml' \
  'notifd-configuration.xml' \
  'surveillance-views.xml' \
  'users.xml' \
  'viewsdisplay.xml' \
  '*datacollection-config.xml' \
  'datacollection/*' \
  'resource-types.d/*' \
  'snmp-graph.properties.d/*' \
  'jmx-datacollection-config.d/*' \
  'prometheus-datacollection.d/*' \
  'wsman-datacollection.d/*'
)
for file in "${CORE_FILES[@]}"; do
  target=${file}
  if [[ ${file} == *"/*" ]]; then
    mkdir -p ${CONFIG_DIR_OVERLAY}/${file::-2}/
    target=${file::-2}
  fi
  if [[ ${file} == "*"* ]]; then
    target=""
  fi
  ln -s ${CORE_CONFIG_DIR}/${file} ${CONFIG_DIR_OVERLAY}/${target}
done

# Guard against allowing administration changes through the WebUI
SECURITY_CONFIG=${WEB_DIR_OVERLAY}/applicationContext-spring-security.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml ${SECURITY_CONFIG}
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' ${SECURITY_CONFIG}
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' ${SECURITY_CONFIG}
sed -r -i -e '/intercept-url.*measurements/a\' -e '    <intercept-url pattern="/rest/resources/generateId" method="POST" access="ROLE_REST,ROLE_DISABLED,ROLE_USER"/>' ${SECURITY_CONFIG}

# Remove links to the admin pages
NAVBAR=${TEMPLATES_DIR_OVERLAY}/navbar.ftl
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/templates/navbar.ftl ${NAVBAR}
for title in 'Flow Management' 'Quick-Add Node'; do
  sed -r -i "/$title/,+2d" ${NAVBAR}
  sed -r -i "/$title/d" ${NAVBAR}
done
sed -r -i "/Configure OpenNMS/d" ${NAVBAR}

# Enabling CORS
WEB_CONFIG=${WEB_DIR_OVERLAY}/web.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/web.xml ${WEB_CONFIG}
sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' ${WEB_CONFIG}
sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' ${WEB_CONFIG}

# Configure Grafana
if [[ -e /scripts/onms-grafana-init.sh ]]; then
  source /scripts/onms-grafana-init.sh
fi
