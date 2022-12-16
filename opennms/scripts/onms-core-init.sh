#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# Intended to be used as part of an InitContainer expecting the same Container Image as OpenNMS
# Designed for Horizon 29 or Meridian 2021 and 2022. Newer or older versions are not supported.
#
# External environment variables used by this script:
# OPENNMS_ADMIN_PASS
# OPENNMS_INSTANCE_ID (initialized by onms-common-init.sh)
# OPENNMS_DATABASE_CONNECTION_MAXPOOL
# OPENNMS_RRAS
# ENABLE_ALEC
# ENABLE_TELEMETRYD
# ENABLE_GRAFANA
# KAFKA_BOOTSTRAP_SERVER
# KAFKA_SASL_USERNAME
# KAFKA_SASL_PASSWORD
# KAFKA_SASL_MECHANISM
# KAFKA_SECURITY_PROTOCOL

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

function update_rras {
  if grep -q "[<]rrd" $1; then
    echo "Processing $1"
    sed -i -r "/[<]rra/d" $1
    sed -i -r "/[<]rrd/a $2" $1
  fi
}

echo "OpenNMS Core Configuration Script..."

# Requirements
command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync is required but it's not installed. Aborting."; exit 1; }
if [[ ! -e /scripts/onms-common-init.sh ]]; then
  echo >&2 "onms-common-init.sh required but it's not present. Aborting."; exit 1;
fi

# Defaults
OPENNMS_DATABASE_CONNECTION_MAXPOOL=${OPENNMS_DATABASE_CONNECTION_MAXPOOL-50}
KAFKA_SASL_MECHANISM=${KAFKA_SASL_MECHANISM-PLAIN}
KAFKA_SECURITY_PROTOCOL=${KAFKA_SECURITY_PROTOCOL-SASL_PLAINTEXT}

# See if we can get the OpenNMS package name and version from the package manager
if command -v rpm   >/dev/null 2>&1; then
  PKG=$(rpm -qa | egrep '(meridian|opennms)-core')
  VERSION=$(rpm -q --queryformat '%{VERSION}' $PKG)
elif command -v dpkg-query >/dev/null 2>&1; then
  if PKG=$(dpkg-query -f '${Package}\n' -W | grep -Fx -e opennms-common -e meridian-common); then
    VERSION=$(dpkg-query -f '${Version}\n' -W "${PKG}")
  else
    PKG="unknown"
  fi
else
  PKG="unknown"
fi

if [[ "${PKG}" == "unknown" ]]; then
  if [[ ! -e jetty-webapps/opennms/WEB-INF/version.properties ]]; then
    echo >&2 "Couldn't determine version number from package manager (which is normal for newer containers) and jetty-webapps/opennms/WEB-INF/version.properties does not exist. Aborting."; exit 1;
  fi
  VERSION=$(grep '^version\.display=' jetty-webapps/opennms/WEB-INF/version.properties | sed -e 's/^version.display=//' -e 's/#.*//')
  if [[ "$VERSION" == 20?? ]]; then
    PKG=meridian-assumed
  else
    PKG=horizon-assumed
  fi
fi

MAJOR=${VERSION%%.*}
echo "Package: ${PKG}"
echo "Version: ${VERSION}"
echo "Major: ${MAJOR}"

# Verify if Twin API is available
USE_TWIN="false"
if [[ "$PKG" == *"meridian"* ]]; then
  echo "OpenNMS Meridian $MAJOR detected"
  if (( $MAJOR > 2021 )); then
    USE_TWIN=true
  fi
else
  echo "OpenNMS Horizon $MAJOR detected"
  if (( $MAJOR > 28 )); then
    USE_TWIN=true
  fi
fi
echo "Twin API Available? $USE_TWIN"

# Wait for dependencies
wait_for ${POSTGRES_HOST}:${POSTGRES_PORT}
if [[ -v KAFKA_BOOTSTRAP_SERVER ]]; then
  wait_for ${KAFKA_BOOTSTRAP_SERVER}
fi

CONFIG_DIR="/opennms-etc"          # Mounted externally
BACKUP_ETC="/opt/opennms/etc"      # Requires OpenNMS Image
OVERLAY_DIR="/opt/opennms-overlay" # Mounted Externally
DEPLOY_DIR="/opennms-deploy"       # Mounted Externally

CONFIG_DIR_OVERLAY=${OVERLAY_DIR}/etc

KARAF_FILES=( \
"config.properties" \
"startup.properties" \
"custom.properties" \
"jre.properties" \
"profile.cfg" \
"jmx.acl.*" \
"org.apache.felix.*" \
"org.apache.karaf.*" \
"org.ops4j.pax.url.mvn.cfg" \
)

# Show permissions (debug purposes)
echo "Configuration directory:"
ls -ld ${CONFIG_DIR}

### Initialize etc directory

# First, we need to handle updates from older Helm charts before we do anything else.
# Older charts (0.3.0 and before) didn't use helm-chart-configured, but only used
# OpenNMS' configured file. If configured exists, but no helm-chart-configured exists,
# assume we are updating from an older Helm chart and create helm-chart-configured.
if [ -f ${CONFIG_DIR}/configured ] && [ ! -f ${CONFIG_DIR}/helm-chart-configured ]; then
  echo "Upgrading from older Helm chart that has already been configured: creating helm-chart-configured file."
  touch ${CONFIG_DIR}/helm-chart-configured
  echo "version not stored previously" > ${CONFIG_DIR}/helm-chart-opennms-version
fi

# Include all the configuration files that must be added once but could change after the first run
if [ ! -f ${CONFIG_DIR}/helm-chart-configured ]; then
  echo "Initializing configuration directory for the first time ..."
  rsync -arO --no-perms --no-owner --no-group ${BACKUP_ETC}/ ${CONFIG_DIR}/

  echo "Initialize default foreign source definition"
  cat <<EOF > ${CONFIG_DIR}/default-foreign-source.xml
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="default" date-stamp="2018-01-01T00:00:00.000-05:00">
  <scan-interval>1d</scan-interval>
  <detectors>
    <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
    <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
    <detector name="OpenNMS-JVM" class="org.opennms.netmgt.provision.detector.jmx.Jsr160Detector">
      <parameter key="port" value="18980"/>
      <parameter key="factory" value="PASSWORD-CLEAR"/>
      <parameter key="username" value="admin"/>
      <parameter key="password" value="admin"/>
      <parameter key="protocol" value="rmi"/>
      <parameter key="urlPath" value="/jmxrmi"/>
      <parameter key="timeout" value="3000"/>
      <parameter key="retries" value="2"/>
      <parameter key="type" value="default"/>
      <parameter key="ipMatch" value="127.0.0.1"/>
    </detector>
  </detectors>
  <policies>
    <policy name="Do Not Persist Discovered IPs" class="org.opennms.netmgt.provision.persist.policies.MatchingIpInterfacePolicy">
      <parameter key="action" value="DO_NOT_PERSIST"/>
      <parameter key="matchBehavior" value="NO_PARAMETERS"/>
    </policy>
    <policy name="Enable Data Collection" class="org.opennms.netmgt.provision.persist.policies.MatchingSnmpInterfacePolicy">
      <parameter key="action" value="ENABLE_COLLECTION"/>
      <parameter key="matchBehavior" value="ANY_PARAMETER"/>
      <parameter key="ifOperStatus" value="1"/>
    </policy>
  </policies>
</foreign-source>
EOF
  touch ${CONFIG_DIR}/helm-chart-configured
else
  echo "Previous configuration found. Synchronizing only new files..."
  rsync -aruO --no-perms --no-owner --no-group ${BACKUP_ETC}/ ${CONFIG_DIR}/
fi

# See if we are on a fresh install or a different version of OpenNMS and remove
# the "configured" file so the installer runs.
if [ ! -f ${CONFIG_DIR}/helm-chart-opennms-version ]; then
  previous_opennms="new Helm chart install"
else
  previous_opennms="$(<${CONFIG_DIR}/helm-chart-opennms-version)"
fi
current_opennms="${PKG}-${VERSION}"
if [ "${previous_opennms}" != "${current_opennms}" ]; then
  echo "OpenNMS version change detected from '${previous_opennms}' to '${current_opennms}': triggering installer to run by removing configured file."
  rm -f ${CONFIG_DIR}/configured # it might not already exist
  echo "${current_opennms}" > ${CONFIG_DIR}/helm-chart-opennms-version
else
  echo "No OpenNMS version change detected: still on '${current_opennms}'"
fi

# Guard against application upgrades
MANDATORY=/tmp/opennms-mandatory
mkdir -p ${MANDATORY}
for file in "${KARAF_FILES[@]}"; do
  echo "Backing up ${file} to ${MANDATORY}..."
  cp --force ${BACKUP_ETC}/${file} ${MANDATORY}/
done
# WARNING: if the volume behind CONFIG_DIR doesn't have the right permissions, the following fails
echo "Overriding mandatory files from ${MANDATORY}..."
rsync -aO --no-perms --no-owner --no-group ${MANDATORY}/ ${CONFIG_DIR}/

# Initialize overlay
mkdir -p ${CONFIG_DIR_OVERLAY}/opennms.properties.d ${CONFIG_DIR_OVERLAY}/featuresBoot.d

# Apply common OpenNMS configuration settings
source /scripts/onms-common-init.sh

# Collectd Optimizations
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/collectd.properties
# To get data as close as possible to PDP
org.opennms.netmgt.collectd.strictInterval=true
EOF

# Enable ALEC standalone
if [[ ${ENABLE_ALEC} == "true" ]]; then
  if [[ ! -e /opt/opennms/deploy/opennms-alec-plugin.kar ]] && [[ ! -e ${DEPLOY_DIR}/opennms-alec-plugin.kar ]]; then
    KAR_VER=$(curl -sSf https://api.github.com/repos/OpenNMS/alec/releases/latest | grep tag_name | cut -d '"' -f 4)
    KAR_URL="https://github.com/OpenNMS/alec/releases/download/${KAR_VER}/opennms-alec-plugin.kar"
    echo "Downloading ALEC $KAR_VER from GitHub..."
    curl -sSf -LJ -o ${DEPLOY_DIR}/opennms-alec-plugin.kar ${KAR_URL}
  fi

  cat <<EOF > ${CONFIG_DIR_OVERLAY}/featuresBoot.d/alec.boot
alec-opennms-standalone wait-for-kar=opennms-alec-plugin
EOF
fi

# Configure Sink and RPC to use Kafka, and the Kafka Producer.
if [[ -v KAFKA_BOOTSTRAP_SERVER ]]; then
  if [[ ${OPENNMS_INSTANCE_ID} == "" ]]; then
    echo >&2 "OPENNMS_INSTANCE_ID cannot be empty. Aborting."
    exit 1
  fi

  echo "Configuring Kafka for IPC..."

  cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
EOF

  cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/kafka.properties
org.opennms.core.ipc.strategy=kafka
EOF

  if [[ "$USE_TWIN" == "true" ]]; then
    cat <<EOF >> ${CONFIG_DIR_OVERLAY}/opennms.properties.d/kafka.properties

# TWIN
org.opennms.core.ipc.twin.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}
org.opennms.core.ipc.twin.kafka.group.id=${OPENNMS_INSTANCE_ID}-Core-Twin
EOF
  fi

  cat <<EOF >> ${CONFIG_DIR_OVERLAY}/opennms.properties.d/kafka.properties

# SINK
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}
org.opennms.core.ipc.sink.kafka.group.id=${OPENNMS_INSTANCE_ID}-Core-Sink

# SINK Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.sink.kafka.session.timeout.ms=30000
org.opennms.core.ipc.sink.kafka.max.poll.records=50

# RPC
org.opennms.core.ipc.rpc.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}
org.opennms.core.ipc.rpc.kafka.ttl=30000
org.opennms.core.ipc.rpc.kafka.single-topic=true
org.opennms.core.ipc.rpc.kafka.group.id=${OPENNMS_INSTANCE_ID}-Core-RPC

# RPC Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.request.timeout.ms=30000
org.opennms.core.ipc.rpc.kafka.session.timeout.ms=30000
org.opennms.core.ipc.rpc.kafka.max.poll.records=50
org.opennms.core.ipc.rpc.kafka.auto.offset.reset=latest

# RPC Producer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.acks=0
org.opennms.core.ipc.rpc.kafka.linger.ms=5
EOF

  MODULES="rpc sink"
  if [[ "$USE_TWIN" == "true" ]]; then
    MODULES="twin $MODULES"
  fi
  for module in $MODULES; do
    cat <<EOF >> ${CONFIG_DIR_OVERLAY}/opennms.properties.d/kafka.properties

# ${module^^} Security
org.opennms.core.ipc.$module.kafka.security.protocol=${KAFKA_SECURITY_PROTOCOL}
org.opennms.core.ipc.$module.kafka.sasl.mechanism=${KAFKA_SASL_MECHANISM}
EOF
    if [[ -v KAFKA_SASL_USERNAME ]] &&  [[ -v KAFKA_SASL_PASSWORD ]]; then
      if [[ -v KAFKA_SASL_MECHANISM ]] && [[ "${KAFKA_SASL_MECHANISM}" == *"SCRAM"* ]]; then
        JAAS_CLASS="org.apache.kafka.common.security.scram.ScramLoginModule"
      else
        JAAS_CLASS="org.apache.kafka.common.security.plain.PlainLoginModule"
      fi
      cat <<EOF >> ${CONFIG_DIR_OVERLAY}/opennms.properties.d/kafka.properties
org.opennms.core.ipc.$module.kafka.sasl.jaas.config=${JAAS_CLASS} required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
    fi
  done
fi

# Configure RRAs
if [[ -v OPENNMS_RRAS ]]; then
  echo "Configuring RRAs..."
  IFS=';' read -a RRAS <<< ${OPENNMS_RRAS}
  RRACFG=""
  for RRA in ${RRAS[@]}; do
    RRACFG+="<rra>${RRA}</rra>"
  done
  echo ${RRACFG}
  for XML in $(find ${CONFIG_DIR} -name *datacollection*.xml -or -name *datacollection*.d); do
    if [ -d $XML ]; then
      for XML in $(find ${XML} -name *.xml); do
        update_rras ${XML} ${RRACFG}
      done
    else
      update_rras ${XML} ${RRACFG}
    fi
  done
fi

# Enable Syslogd
sed -r -i '/enabled="false"/{$!{N;s/ enabled="false"[>]\n(.*OpenNMS:Name=Syslogd.*)/>\n\1/}}' ${CONFIG_DIR}/service-configuration.xml

# Disable Telemetryd
if [[ ${ENABLE_TELEMETRYD} == "false" ]]; then
  sed -i -r '/opennms-flows/d' ${CONFIG_DIR}/org.apache.karaf.features.cfg
  sed -i 'N;s/service.*\n\(.*Telemetryd\)/service enabled="false">\n\1/;P;D' ${CONFIG_DIR}/service-configuration.xml
fi

# Cleanup temporary requisition files
rm -f ${CONFIG_DIR}/imports/pending/*.xml.*
rm -f ${CONFIG_DIR}/foreign-sources/pending/*.xml.*

if [[ ${ENABLE_GRAFANA} == "true" ]]; then
  # Configure Grafana
  if [[ -e /scripts/onms-grafana-init.sh ]]; then
    source /scripts/onms-grafana-init.sh
  else
    echo "Warning: cannot find onms-grafana-init.sh"
  fi
else
  echo "Grafana is not enabled, not running onms-grafana-init.sh"
fi

echo "Updating admin password"
perl /scripts/onms-set-admin-password.pl ${CONFIG_DIR}/users.xml admin "${OPENNMS_ADMIN_PASS}"
