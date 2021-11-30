#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>

function wait_for {
  echo "Waiting for $1:$2"
  until echo -n >/dev/tcp/$1/$2 2>/dev/null; do
    sleep 5
  done
  echo "done"
}

echo "OpenNMS UI Configuration Script..."

wait_for ${OPENNMS_SERVER} 8980

umask 002

command -v jq   >/dev/null 2>&1 || { echo >&2 "jq is required but it's not installed. Aborting.";   exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but it's not installed. Aborting."; exit 1; }

CORE_CONFIG_DIR=/opennms-core/etc
DATA_DIR=/opt/opennms-overlay

CONFIG_DIR=${DATA_DIR}/etc
WEB_DIR=${DATA_DIR}/webapps/opennms/WEB-INF

mkdir -p ${WEB_DIR}
mkdir -p ${CONFIG_DIR}/opennms.properties.d/

# Ensure the install script won't be executed
touch ${CONFIG_DIR}/configured

# Disable data choices (optional)
cat <<EOF > ${CONFIG_DIR}/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

# Trim down the events configuration, as event processing is not required for the WebUI
cat <<EOF > ${CONFIG_DIR}/eventconf.xml
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
grep 'events\/opennms' /opt/opennms/share/etc-pristine/eventconf.xml >> ${CONFIG_DIR}/eventconf.xml
cat <<EOF >> ${CONFIG_DIR}/eventconf.xml
</events>
EOF

# Trim down the services/daemons configuration, as only the WebUI will be running
cat <<EOF > ${CONFIG_DIR}/service-configuration.xml
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

# Required changes in order to use HTTPS through Ingress
cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
opennms.report.scheduler.enabled=false
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
org.opennms.web.defaultGraphPeriod=last_2_hour
EOF

# RRD Strategy is enabled by default
cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
EOF

# Create links to files from Core server
ln -s ${CORE_CONFIG_DIR}/users.xml ${CONFIG_DIR}/users.xml
ln -s ${CORE_CONFIG_DIR}/groups.xml ${CONFIG_DIR}/groups.xml

# Guard against allowing administration changes through the WebUI
SECURITY_CONFIG=${WEB_DIR}/applicationContext-spring-security.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml ${SECURITY_CONFIG}
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' ${SECURITY_CONFIG}
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' ${SECURITY_CONFIG}
sed -r -i -e '/intercept-url.*measurements/a\' -e '    <intercept-url pattern="/rest/resources/generateId" method="POST" access="ROLE_REST,ROLE_DISABLED,ROLE_USER"/>' ${SECURITY_CONFIG}

# Enabling CORS
WEB_CONFIG=${WEB_DIR}/web.xml
cp /opt/opennms/jetty-webapps/opennms/WEB-INF/web.xml ${WEB_CONFIG}
sed -r -i '/[<][!]--/{$!{N;s/[<][!]--\n  ([<]filter-mapping)/\1/}}' ${WEB_CONFIG}
sed -r -i '/nrt/{$!{N;N;s/(nrt.*\n  [<]\/filter-mapping[>])\n  --[>]/\1/}}' ${WEB_CONFIG}
