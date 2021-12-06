#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# External environment variables:
# POSTGRES_HOST
# POSTGRES_PORT
# OPENNMS_SERVER
# OPENNMS_INSTANCE_ID
# KAFKA_BOOTSTRAP_SERVER
# KAFKA_SASL_USERNAME
# KAFKA_SASL_PASSWORD
# KAFKA_SASL_MECHANISM
# KAFKA_SECURITY_PROTOCOL
# ELASTICSEARCH_SERVER
# ELASTICSEARCH_USER
# ELASTICSEARCH_PASSWORD
# ELASTICSEARCH_INDEX_STRATEGY_FLOWS
# ELASTICSEARCH_NUM_SHARDS
# ELASTICSEARCH_REPLICATION_FACTOR
# NUM_LISTENER_THREADS

umask 002

function wait_for {
  echo "Waiting for $1"
  IFS=':' read -a data <<< $1
  until echo -n >/dev/tcp/${data[0]}/${data[1]} 2>/dev/null; do
    sleep 5
  done
  echo "done"
}

echo "OpenNMS Sentinel Configuration Script..."

NUM_LISTENER_THREADS=${NUM_LISTENER_THREADS-6}
KAFKA_SASL_MECHANISM=${KAFKA_SASL_MECHANISM-PLAIN}
KAFKA_SECURITY_PROTOCOL=${KAFKA_SECURITY_PROTOCOL-SASL_PLAINTEXT}
ELASTICSEARCH_INDEX_STRATEGY_FLOWS=${ELASTICSEARCH_INDEX_STRATEGY_FLOWS-daily}
ELASTICSEARCH_REPLICATION_FACTOR=${ELASTICSEARCH_REPLICATION_FACTOR-2}
ELASTICSEARCH_NUM_SHARDS=${ELASTICSEARCH_NUM_SHARDS-6}

OVERLAY=/opt/sentinel-etc-overlay

wait_for ${ELASTICSEARCH_SERVER}
wait_for ${KAFKA_BOOTSTRAP_SERVER}
wait_for ${POSTGRES_HOST}:${POSTGRES_PORT}
wait_for ${OPENNMS_SERVER}:8980

# Configure the instance ID and Interface-to-Node cache
# Required when having multiple OpenNMS backends sharing a Kafka cluster or an Elasticsearch cluster.
CUSTOM_PROPERTIES=${OVERLAY}/custom.system.properties
if [[ ${OPENNMS_INSTANCE_ID} ]]; then
  cat <<EOF >> ${CUSTOM_PROPERTIES}
# Used for Kafka Topics
org.opennms.instance.id=${OPENNMS_INSTANCE_ID}
# Refresh Interface-to-Node cache every 2 hours
org.opennms.interface-node-cache.refresh-timer=7200000
EOF
else
  OPENNMS_INSTANCE_ID="OpenNMS"
fi

FEATURES_DIR=${OVERLAY}/featuresBoot.d
mkdir -p ${FEATURES_DIR}
cat <<EOF > ${FEATURES_DIR}/persistence.boot
sentinel-persistence
sentinel-jsonstore-postgres
sentinel-blobstore-noop
EOF

if [[ ${ELASTICSEARCH_SERVER} ]]; then
  cat <<EOF > ${FEATURES_DIR}/flows.boot
sentinel-flows
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-ipfix.cfg
name=IPFIX
adapters.0.name=IPFIX-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.adapter.ipfix.IpfixAdapter
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-netflow5.cfg
name=Netflow-5
adapters.0.name=Netflow-5-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow5.Netflow5Adapter
queue.threads=${NUM_LISTENER_THREADS}
EOF

  cat <<EOF > ${OVERLAY}/org.opennms.features.telemetry.adapters-netflow9.cfg
name=Netflow-9
adapters.0.name=Netflow-9-Adapter
adapters.0.class-name=org.opennms.netmgt.telemetry.protocols.netflow.adapter.netflow9.Netflow9Adapter
queue.threads=${NUM_LISTENER_THREADS}
EOF

  PREFIX=$(echo ${OPENNMS_INSTANCE_ID} | tr '[:upper:]' '[:lower:]')-
  cat <<EOF > ${OVERLAY}/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=https://${ELASTICSEARCH_SERVER}
globalElasticUser=${ELASTICSEARCH_USER}
globalElasticPassword=${ELASTICSEARCH_PASSWORD}
elasticIndexStrategy=${ELASTICSEARCH_INDEX_STRATEGY_FLOWS}
indexPrefix=${PREFIX}
# The following settings should be consistent with your ES cluster
settings.index.number_of_shards=${ELASTICSEARCH_NUM_SHARDS}
settings.index.number_of_replicas=${ELASTICSEARCH_REPLICATION_FACTOR}
EOF
fi

if [[ ${KAFKA_BOOTSTRAP_SERVER} ]]; then
  FILE_PREFIX="${OVERLAY}/org.opennms.core.ipc.sink.kafka"
  echo "sentinel-kafka" > ${FEATURES_DIR}/kafka.boot

  cat <<EOF > ${FILE_PREFIX}.cfg
# Producers
bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}
acks=1
EOF

  cat <<EOF > ${FILE_PREFIX}.consumer.cfg
# Consumers
group.id=${OPENNMS_INSTANCE_ID}_Sentinel
bootstrap.servers=${KAFKA_BOOTSTRAP_SERVER}
max.partition.fetch.bytes=5000000
EOF

  if [[ ${KAFKA_SASL_USERNAME} && ${KAFKA_SASL_PASSWORD} ]]; then
    JAAS_CLASS="org.apache.kafka.common.security.plain.PlainLoginModule"
    if [[ "${KAFKA_SASL_MECHANISM}" == *"SCRAM"* ]]; then
      JAAS_CLASS="org.apache.kafka.common.security.scram.ScramLoginModule"
    fi
    for f in ${FILE_PREFIX}.cfg ${FILE_PREFIX}.consumer.cfg; do
      cat <<EOF >> $f
# Security
security.protocol=${KAFKA_SECURITY_PROTOCOL}
sasl.mechanism=${KAFKA_SASL_MECHANISM}
sasl.jaas.config=${JAAS_CLASS} required username="${KAFKA_SASL_USERNAME}" password="${KAFKA_SASL_PASSWORD}";
EOF
    done
  fi
fi
