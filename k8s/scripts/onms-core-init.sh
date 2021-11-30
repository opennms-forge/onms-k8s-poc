#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# External environment variables:
# KAFKA_BOOTSTRAP_SERVER
# KAFKA_SASL_USERNAME (for SASL in plain text)
# KAFKA_SASL_PASSWORD (for SASL in plain text)

function wait_for {
  echo "Waiting for $1:$2"
  until echo -n >/dev/tcp/$1/$2 2>/dev/null; do
    sleep 5
  done
  echo "done"
}

echo "OpenNMS Core Configuration Script..."

umask 002

command -v rsync >/dev/null 2>&1 || { echo >&2 "rsync is required but it's not installed. Aborting."; exit 1; }

wait_for ${POSTGRES_HOST} ${POSTGRES_PORT}
wait_for ${KAFKA_BOOTSTRAP_SERVER} 9092

CONFIG_DIR=/opennms-etc
BACKUP_ETC=/opt/opennms/etc
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
ls -ld ${CONFIG_DIR}

# Initialize configuration directory
if [ ! -f ${CONFIG_DIR}/configured ]; then
  echo "Initializing configuration directory for the first time ..."
  rsync -arO --no-perms ${BACKUP_ETC}/ ${CONFIG_DIR}/

  echo "Disabling data choices"
  cat <<EOF > ${CONFIG_DIR}/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

  echo "Initialize default foreign source definition"
  cat <<EOF > ${CONFIG_DIR}/default-foreign-source.xml
<foreign-source xmlns="http://xmlns.opennms.org/xsd/config/foreign-source" name="default" date-stamp="2018-01-01T00:00:00.000-05:00">
  <scan-interval>1d</scan-interval>
  <detectors>
    <detector name="ICMP" class="org.opennms.netmgt.provision.detector.icmp.IcmpDetector"/>
    <detector name="SNMP" class="org.opennms.netmgt.provision.detector.snmp.SnmpDetector"/>
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
  rsync -aruO --no-perms ${BACKUP_ETC}/ ${CONFIG_DIR}/
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
rsync -aO --no-perms ${MANDATORY}/ ${CONFIG_DIR}/

# RRD Strategy is enabled by default
cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
EOF

cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/collectd.properties
# To get data as close as possible to PDP
org.opennms.netmgt.collectd.strictInterval=true
EOF

# Required changes in order to use HTTPS through Ingress
cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/webui.properties
opennms.web.base-url=http://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.defaultGraphPeriod=last_2_hour
EOF

# Enable Syslogd
sed -r -i '/enabled="false"/{$!{N;s/ enabled="false"[>]\n(.*OpenNMS:Name=Syslogd.*)/>\n\1/}}' ${CONFIG_DIR}/service-configuration.xml

# Configure Sink and RPC to use Kafka, and the Kafka Producer.
if [[ ${KAFKA_BOOTSTRAP_SERVER} ]]; then
  echo "Configuring Kafka..."

  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/amq.properties
org.opennms.activemq.broker.disable=true
EOF

  cat <<EOF > ${CONFIG_DIR}/opennms.properties.d/kafka.properties
org.opennms.core.ipc.strategy=kafka

# Twin
org.opennms.core.ipc.twin.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}:9092
org.opennms.core.ipc.twin.kafka.group.id=OpenNMS-Core-Twin

# Sink
org.opennms.core.ipc.sink.initialSleepTime=60000
org.opennms.core.ipc.sink.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}:9092
org.opennms.core.ipc.sink.kafka.group.id=OpenNMS-Core-Sink

# Sink Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.sink.kafka.session.timeout.ms=30000
org.opennms.core.ipc.sink.kafka.max.poll.records=50

# RPC
org.opennms.core.ipc.rpc.kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}:9092
org.opennms.core.ipc.rpc.kafka.ttl=30000
org.opennms.core.ipc.rpc.kafka.single-topic=true
org.opennms.core.ipc.rpc.kafka.group.id=OpenNMS-Core-RPC

# RPC Consumer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.request.timeout.ms=30000
org.opennms.core.ipc.rpc.kafka.session.timeout.ms=30000
org.opennms.core.ipc.rpc.kafka.max.poll.records=50
org.opennms.core.ipc.rpc.kafka.auto.offset.reset=latest

# RPC Producer (verify Kafka broker configuration)
org.opennms.core.ipc.rpc.kafka.acks=0
org.opennms.core.ipc.rpc.kafka.linger.ms=5
org.opennms.core.ipc.rpc.kafka.compression.type=zstd
EOF

  if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
    for module in rpc sink twin; do
      cat <<EOF >> ${CONFIG_DIR}/opennms.properties.d/kafka.properties

# Authentication for $module
org.opennms.core.ipc.$module.kafka.security.protocol=SASL_PLAINTEXT
org.opennms.core.ipc.$module.kafka.sasl.mechanism=PLAIN
org.opennms.core.ipc.$module.kafka.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
    done
  fi
fi

# Cleanup temporary requisition files:
rm -f ${CONFIG_DIR}/imports/pending/*.xml.*
rm -f ${CONFIG_DIR}/foreign-sources/pending/*.xml.*

# Force to execute runjava and the install script
touch ${CONFIG_DIR}/do-upgrade
