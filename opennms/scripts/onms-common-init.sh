#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# Intended to be used from the corresponding initialization script
# Includes common settings for both, the Core OpenNMS Instance and the UI-only OpenNMS Instance
# Designed for Horizon 29 or Meridian 2021 and 2022. Newer or older versions are not supported.
#
# External environment variables used by this script:
# CONFIG_DIR_OVERLAY (initialized by the caller script)
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
# ENABLE_ACLS
# ENABLE_CORTEX
# CORTEX_WRITE_URL
# CORTEX_READ_URL
# CORTEX_MAX_CONCURRENT_HTTP_CONNECTIONS
# CORTEX_WRITE_TIMEOUT
# CORTEX_READ_TIMEOUT
# CORTEX_METRIC_CACHE_SIZE
# CORTEX_EXTERNAL_TAGS_CACHE_SIZE
# CORTEX_BULKHEAD_MAX_WAIT_DURATION
# ENABLE_TSS_DUAL_WRITE
# ELASTICSEARCH_SERVER
# ELASTICSEARCH_USER
# ELASTICSEARCH_PASSWORD
# ELASTICSEARCH_INDEX_STRATEGY_FLOWS

set -euo pipefail
trap 's=$?; echo >&2 "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

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

# Disable data choices (optional)
cat <<EOF > ${CONFIG_DIR_OVERLAY}/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Sun Mar 01 00\:00\:00 EDT 2020
EOF

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
    minPool="25"
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
                    password="${POSTGRES_PASSWORD}">
    <connection-pool idleTimeout="600"
                     minPool="0"
                     maxPool="10"
                     maxSize="${OPENNMS_DATABASE_CONNECTION_MAXPOOL}" />
  </jdbc-data-source>
  
  <jdbc-data-source name="opennms-monitor" 
                    database-name="postgres" 
                    class-name="org.postgresql.Driver" 
                    url="jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/postgres?sslmode=${POSTGRES_SSL_MODE}&amp;sslfactory=${POSTGRES_SSL_FACTORY}"
                    user-name="${POSTGRES_USER}"
                    password="${POSTGRES_PASSWORD}">
    <connection-pool idleTimeout="600"
                     minPool="0"
                     maxPool="10"
                     maxSize="${OPENNMS_DATABASE_CONNECTION_MAXPOOL}" />
  </jdbc-data-source>
</datasource-configuration>
EOF

# Enable storeByGroup to improve performance
# RRD Strategy is enabled by default
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
EOF

# Configure Timeseries for Cortex if enabled
if [[ ${ENABLE_CORTEX} == "true" ]]; then
  if [[ ! -e /opt/opennms/deploy/opennms-cortex-tss-plugin.kar ]]; then
    KAR_VER=$(curl -sSf https://api.github.com/repos/OpenNMS/opennms-cortex-tss-plugin/releases/latest | grep tag_name | cut -d '"' -f 4)
    KAR_URL="https://github.com/OpenNMS/opennms-cortex-tss-plugin/releases/download/${KAR_VER}/opennms-cortex-tss-plugin.kar"
    curl -sSf -LJ -o ${DEPLOY_DIR}/opennms-cortex-tss-plugin.kar ${KAR_URL}
  fi

  if [[ ${ENABLE_TSS_DUAL_WRITE} == "true" ]]; then
    # Do *not* set org.opennms.timeseries.strategy=integration but do make sure the file exists and is empty for later
    echo -n > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/timeseries.properties
  else
    cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/timeseries.properties
org.opennms.timeseries.strategy=integration
EOF
  fi

  cat <<EOF >> ${CONFIG_DIR_OVERLAY}/opennms.properties.d/timeseries.properties
org.opennms.timeseries.tin.metatags.tag.node=\${node:label}
org.opennms.timeseries.tin.metatags.tag.location=\${node:location}
org.opennms.timeseries.tin.metatags.tag.geohash=\${node:geohash}
org.opennms.timeseries.tin.metatags.tag.ifDescr=\${interface:if-description}
org.opennms.timeseries.tin.metatags.tag.label=\${resource:label}
EOF

  cat <<EOF > ${CONFIG_DIR_OVERLAY}/org.opennms.plugins.tss.cortex.cfg
writeUrl=${CORTEX_WRITE_URL}
readUrl=${CORTEX_READ_URL}
maxConcurrentHttpConnections=${CORTEX_MAX_CONCURRENT_HTTP_CONNECTIONS}
writeTimeoutInMs=${CORTEX_WRITE_TIMEOUT}
readTimeoutInMs=${CORTEX_READ_TIMEOUT}
metricCacheSize=${CORTEX_METRIC_CACHE_SIZE}
externalTagsCacheSize=${CORTEX_EXTERNAL_TAGS_CACHE_SIZE}
bulkheadMaxWaitDuration=${CORTEX_BULKHEAD_MAX_WAIT_DURATION}
organizationId=${OPENNMS_INSTANCE_ID}
EOF

  # Needed for UI container
  mkdir -p ${CONFIG_DIR_OVERLAY}/featuresBoot.d

  cat <<EOF > ${CONFIG_DIR_OVERLAY}/featuresBoot.d/cortex.boot
opennms-plugins-cortex-tss wait-for-kar=opennms-cortex-tss-plugin
EOF

  if [[ ${ENABLE_TSS_DUAL_WRITE} == "true" ]]; then
    cat <<EOF > ${CONFIG_DIR_OVERLAY}/featuresBoot.d/timeseries.boot
opennms-timeseries-api
EOF
  fi
fi

  # Needed for UI container
  mkdir -p ${CONFIG_DIR_OVERLAY}/opennms.properties.d

# Enable ACLs
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/acl.properties
org.opennms.web.aclsEnabled=${ENABLE_ACLS}
EOF

# Required changes in order to use HTTPS through Ingress
cat <<EOF > ${CONFIG_DIR_OVERLAY}/opennms.properties.d/webui.properties
opennms.web.base-url=https://%x%c/
org.opennms.security.disableLoginSuccessEvent=true
org.opennms.web.defaultGraphPeriod=last_2_hour
EOF

# Configure Elasticsearch to allow Helm/Grafana to access Flow data
if [[ -v ELASTICSEARCH_SERVER ]]; then
  echo "Configuring Elasticsearch for Flows..."
  PREFIX=$(echo ${OPENNMS_INSTANCE_ID} | tr '[:upper:]' '[:lower:]')-
  cat <<EOF > ${CONFIG_DIR_OVERLAY}/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=https://${ELASTICSEARCH_SERVER}
globalElasticUser=${ELASTICSEARCH_USER}
globalElasticPassword=${ELASTICSEARCH_PASSWORD}
elasticIndexStrategy=${ELASTICSEARCH_INDEX_STRATEGY_FLOWS}
indexPrefix=${PREFIX}
EOF
fi
