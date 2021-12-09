#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# External environment variables:
# POSTGRES_HOST
# POSTGRES_PORT
# POSTGRES_USER
# POSTGRES_PASSWORD
# POSTGRES_SSL_MODE
# POSTGRES_SSL_FACTORY
# OPENNMS_DATABASE_CONNECTION_MAXPOOL
# OPENNMS_DBNAME
# OPENNMS_DBUSER
# OPENNMS_DBPASS
# OPENNMS_INSTANCE_ID
# ENABLE_ALEC
# ENABLE_ACLS
# ENABLE_TELEMETRYD
# KAFKA_BOOTSTRAP_SERVER
# KAFKA_SASL_USERNAME
# KAFKA_SASL_PASSWORD
# KAFKA_SASL_MECHANISM
# KAFKA_SECURITY_PROTOCOL
# ELASTICSEARCH_SERVER
# ELASTICSEARCH_USER
# ELASTICSEARCH_PASSWORD

umask 002

function wait_for {
  echo "Waiting for $1"
  IFS=':' read -a data <<< $1
  until echo -n >/dev/tcp/${data[0]}/${data[1]} 2>/dev/null; do
    sleep 5
  done
  echo "done"
}

echo "OpenNMS Core Configuration Script..."

OPENNMS_DATABASE_CONNECTION_MAXPOOL=${OPENNMS_DATABASE_CONNECTION_MAXPOOL-50}
KAFKA_SASL_MECHANISM=${KAFKA_SASL_MECHANISM-PLAIN}
KAFKA_SECURITY_PROTOCOL=${KAFKA_SECURITY_PROTOCOL-SASL_PLAINTEXT}

command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync is required but it's not installed. Aborting."; exit 1; }

PKG=$(rpm -qa | egrep '(meridian|opennms)-core')
VERSION=$(rpm -q --queryformat '%{VERSION}' $PKG)
MAJOR=${VERSION%%.*}
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

wait_for ${POSTGRES_HOST}:${POSTGRES_PORT}
wait_for ${KAFKA_BOOTSTRAP_SERVER}

CONFIG_DIR_OVERLAY="/opennms-overlay/etc"  # Mounted externally
CONFIG_DIR="/opennms-etc"                  # Mounted externally
BACKUP_ETC="/opt/opennms/etc"              # Requires OpenNMS Image
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

# Initialize configuration directory
if [ ! -f ${CONFIG_DIR}/configured ]; then
  echo "Initializing configuration directory for the first time ..."
  rsync -arO --no-perms --no-owner --no-group ${BACKUP_ETC}/ ${CONFIG_DIR}/

  echo "Disabling data choices"
  cat <<EOF > ${CONFIG_DIR}/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Sun Mar 01 00\:00\:00 EDT 2020
EOF

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
else
  echo "Previous configuration found. Synchronizing only new files..."
  rsync -aruO --no-perms --no-owner --no-group ${BACKUP_ETC}/ ${CONFIG_DIR}/
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

# Configure the instance ID
# Required when having multiple OpenNMS backends sharing a Kafka cluster or an Elasticsearch cluster.
if [[ ${OPENNMS_INSTANCE_ID} ]]; then
  cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/instanceid.properties
# Used for Kafka Topics and Elasticsearch Index Prefixes
org.opennms.instance.id=${OPENNMS_INSTANCE_ID}
EOF
else
  OPENNMS_INSTANCE_ID="OpenNMS"
fi

# Configure Database access
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms-datasources.xml
<?xml version="1.0" encoding="UTF-8"?>
<datasource-configuration xmlns:this="http://xmlns.opennms.org/xsd/config/opennms-datasources"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://xmlns.opennms.org/xsd/config/opennms-datasources
  http://www.opennms.org/xsd/config/opennms-datasources.xsd ">

  <connection-pool factory="org.opennms.core.db.HikariCPConnectionFactory"
    idleTimeout="600"
    loginTimeout="3"
    minPool="50"
    maxPool="50"
    maxSize="${OPENNMS_DATABASE_CONNECTION_MAXPOOL}" />

  <jdbc-data-source name="opennms"
                    database-name="${OPENNMS_DBNAME}"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/${OPENNMS_DBNAME}?sslmode=${POSTGRES_SSL_MODE}&amp;sslfactory=${POSTGRES_SSL_FACTORY}"
                    user-name="${OPENNMS_DBUSER}"
                    password="${OPENNMS_DBPASS}" />

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/template1?sslmode=${POSTGRES_SSL_MODE}&amp;sslfactory=${POSTGRES_SSL_FACTORY}"
                    user-name="${POSTGRES_USER}"
                    password="${POSTGRES_PASSWORD}"/>
</datasource-configuration>
EOF

# RRD Strategy is enabled by default
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
EOF

# Collectd Optimizations
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/collectd.properties
# To get data as close as possible to PDP
org.opennms.netmgt.collectd.strictInterval=true
EOF

# Required changes in order to use HTTPS through Ingress
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.defaultGraphPeriod=last_2_hour
EOF

# Enable ALEC standalone
if [[ ${ENABLE_ALEC} == "true" ]]; then
  KAR_URL="https://github.com/OpenNMS/alec/releases/download/v1.1.1/opennms-alec-plugin.kar"
  curl -LJ -o /opennms-deploy/opennms-alec-plugin.kar $KAR_URL 2>/dev/null
  cat <<EOF > ${CONFIG_DIR_OVERLAY}/featuresBoot.d/alec.boot
alec-opennms-standalone wait-for-kar=opennms-alec-plugin
EOF
fi

# Enable ACLs
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/acl.properties
org.opennms.web.aclsEnabled=${ENABLE_ACLS}
EOF

# Configure Sink and RPC to use Kafka, and the Kafka Producer.
if [[ ${KAFKA_BOOTSTRAP_SERVER} ]]; then
  echo "Configuring Kafka..."

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

  if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
    JAAS_CLASS="org.apache.kafka.common.security.plain.PlainLoginModule"
    if [[ "${KAFKA_SASL_MECHANISM}" == *"SCRAM"* ]]; then
      JAAS_CLASS="org.apache.kafka.common.security.scram.ScramLoginModule"
    fi
    MODULES="rpc sink"
    if [[ "$USE_TWIN" == "true" ]]; then
      MODULES="twin $MODULES"
    fi
    for module in $MODULES; do
      cat <<EOF >> ${CONFIG_DIR_OVERLAY}/opennms.properties.d/kafka.properties

# ${module^^} Security
org.opennms.core.ipc.$module.kafka.security.protocol=${KAFKA_SECURITY_PROTOCOL}
org.opennms.core.ipc.$module.kafka.sasl.mechanism=${KAFKA_SASL_MECHANISM}
org.opennms.core.ipc.$module.kafka.sasl.jaas.config=${JAAS_CLASS} required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
    done
  fi
fi

# Configure Elasticsearch to allow Helm/Grafana to access Flow data
if [[ ${ELASTICSEARCH_SERVER} ]]; then
  PREFIX=$(echo ${OPENNMS_INSTANCE_ID} | tr '[:upper:]' '[:lower:]')-
  cat <<EOF > ${CONFIG_DIR_OVERLAY}/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=https://${ELASTICSEARCH_SERVER}
globalElasticUser=${ELASTICSEARCH_USER}
globalElasticPassword=${ELASTICSEARCH_PASSWORD}
elasticIndexStrategy=${ELASTICSEARCH_INDEX_STRATEGY_FLOWS}
indexPrefix=${PREFIX}
EOF
fi

# Enable Syslogd
sed -r -i '/enabled="false"/{$!{N;s/ enabled="false"[>]\n(.*OpenNMS:Name=Syslogd.*)/>\n\1/}}' ${CONFIG_DIR}/service-configuration.xml

# Disable Telemetryd
if [[ ${ENABLE_TELEMETRYD} == "false" ]]; then
  sed -i -r '/opennms-flows/d' ${CONFIG_DIR}/org.apache.karaf.features.cfg
  sed -i 'N;s/service.*\n\(.*Telemetryd\)/service enabled="false">\n\1/;P;D' ${CONFIG_DIR}/service-configuration.xml
fi

# Cleanup temporary requisition files:
rm -f ${CONFIG_DIR}/imports/pending/*.xml.*
rm -f ${CONFIG_DIR}/foreign-sources/pending/*.xml.*

# Force to execute runjava and the install script
touch ${CONFIG_DIR}/do-upgrade
