#!env bash
# @author Alejandro Galue <agalue@opennms.com>

minion_repository="opennms/minion"
minion_version="29.0.4" # Must match the version chosen for OpenNMS (careful with NMS-13610)
minion_location="Apex"
minion_id="minion-1"
instance_id="apex1"  # Must match name of the Helm instance (or the Kubernetes namespace)
http_url="" # For M2021/H28 or older
kafka_boostrap="kafka.k8s.agalue.net:443" # Must match dependencies.kafka.hostname from the Helm deployment
kafka_user="opennms" # Must match dependencies.kafka.username from the Helm deployment
kafka_passwd="0p3nNM5" # Must match dependencies.kafka.password from the Helm deployment
jks_passwd="0p3nNM5" # Must match dependencies.kafka.truststore.password from the Helm deployment
karaf_port="8201"
syslog_port="1514"
snmp_port="1162"
flow_port="8877"
debug="0"

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
EOF

if [[ "$http_url" != "" ]]; then
  echo "http-url: ${http_url}" >> $yaml
fi

cat <<EOF >> $yaml
system:
  properties:
    org.opennms.instance.id: ${instance_id}
telemetry:
  flows:
    listeners:
      Flow-Listener:
        class-name: "org.opennms.netmgt.telemetry.listeners.UdpListener"
        parameters:
          port: ${flow_port}
        parsers:
          Netflow-9:
            class-name: "org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow9UdpParser"
            queue:
              use-routing-key: "true"
            parameters:
              dnsLookupsEnabled: "false"
          Netflow-5:
            class-name: "org.opennms.netmgt.telemetry.protocols.netflow.parser.Netflow5UdpParser"
            queue:
              use-routing-key: "true"
            parameters:
              dnsLookupsEnabled: "false"
          IPFIX:
            class-name: "org.opennms.netmgt.telemetry.protocols.netflow.parser.IpfixUdpParser"
            queue:
              use-routing-key: "true"
            parameters:
              dnsLookupsEnabled: "false"
          SFlow:
            class-name: "org.opennms.netmgt.telemetry.protocols.sflow.parser.SFlowUdpParser"
            queue:
              use-routing-key: "true"
            parameters:
              dnsLookupsEnabled: "false"
ipc:
EOF

modules="rpc sink"
if [[ "${http_url}" == "" ]]; then
  modules="twin ${modules}"
fi
for module in ${modules}; do
  cat <<EOF >> $yaml
  $module:
    kafka:
      bootstrap.servers: ${kafka_boostrap}
      security.protocol: SASL_SSL
      sasl.mechanism: SCRAM-SHA-512
      sasl.jaas.config: org.apache.kafka.common.security.scram.ScramLoginModule required username="${kafka_user}" password="${kafka_passwd}";
EOF
done

if [[ "${debug}" != "0" ]]; then
  cat $yaml
  exit
fi

# Start Minion via Docker
docker run --name ${minion_id} -it --rm \
 -e TZ=America/New_York \
 -e JAVA_OPTS="-XX:+AlwaysPreTouch -XX:+UseG1GC -XX:+UseStringDeduplication -Djavax.net.ssl.trustStore=/etc/java/${jks_file} -Djavax.net.ssl.trustStorePassword=${jks_passwd}" \
 -p ${karaf_port}:8201 \
 -p ${syslog_port}:1514/udp \
 -p ${snmp_port}:1162/udp \
 -p ${flow_port}:${flow_port}/udp \
 -v ${jks_path}:/etc/java/${jks_file} \
 -v $yaml:/opt/minion/minion-config.yaml \
 ${minion_repository}:${minion_version} -c
rm -f $yaml
