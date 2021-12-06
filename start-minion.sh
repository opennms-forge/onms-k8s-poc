#!env bash
# @author Alejandro Galue <agalue@opennms.com>

minion_version="29.0.1" # Must match the version chosen for OpenNMS
minion_location="Apex"
minion_id="minion-1"
instance_id="apex1"  # Must match name of the Helm instance (or the Kubernetes namespace)
kafka_boostrap="kafka.k8s.agalue.net:443" # Must match dependencies.kafka.hostname from the Helm deployment
kafka_user="opennms" # Must match dependencies.kafka.username from the Helm deployment
kafka_passwd="0p3nNM5" # Must match dependencies.kafka.password from the Helm deployment
jks_passwd="0p3nNM5" # Must match dependencies.kafka.truststore.password from the Helm deployment
karaf_port="8201"
syslog_port="1514"
snmp_port="1162"

# Parse external variables
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    param="${1/--/}"
    declare $param="$2"
  fi
  shift
done

# JKS file
jks_file="jks/truststore.jks"
jks_path="$(pwd)/${jks_file}"
if [ ! -e ${jks_path} ]; then
  echo "ERROR: ${jks_path} doesn't exist, aborting."
  exit 1
fi

# Temp file
yaml="/tmp/_${minion_id}-$(date +%s).yaml"

# Build Minion Configuration
cat <<EOF > $yaml
id: ${minion_id}
location: ${minion_location}
system:
  properties:
    org.opennms.instance.id: ${instance_id}
ipc:
EOF
for module in rpc sink twin; do
  cat <<EOF >> $yaml
  $module:
    kafka:
      bootstrap.servers: ${kafka_boostrap}
      security.protocol: SASL_SSL
      sasl.mechanism: SCRAM-SHA-512
      sasl.jaas.config: org.apache.kafka.common.security.scram.ScramLoginModule required username="${kafka_user}" password="${kafka_passwd}";
EOF
done

# Start Minion via Docker
docker run --name ${minion_id} -it --rm \
 -e TZ=America/New_York \
 -e JAVA_OPTS="-XX:+AlwaysPreTouch -XX:+UseG1GC -XX:+UseStringDeduplication -Djavax.net.ssl.trustStore=/etc/java/${jks_file} -Djavax.net.ssl.trustStorePassword=${jks_passwd}" \
 -p ${karaf_port}:8201 \
 -p ${syslog_port}:1514/udp \
 -p ${snmp_port}:1162/udp \
 -v ${jks_path}:/etc/java/${jks_file} \
 -v $yaml:/opt/minion/minion-config.yaml \
 opennms/minion:${minion_version} -c
rm -f $yaml