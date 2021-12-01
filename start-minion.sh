#!/bin/bash

minion_version="29.0.1"
minion_location="Apex"
minion_id="minion-1"
kafka_boostrap="kafka.k8s.agalue.net:443"
kafka_user="opennms"
kafka_passwd="0p3nNM5"
jks_passwd="0p3nNM5"
jks_file="kafka-truststore.jks"

# Build Minion Configuration
cat <<EOF > minion.yaml
id: "${minion_id}"
location: "${minion_location}"
ipc:
EOF
for module in rpc sink twin; do
  cat <<EOF >> minion.yaml
  $module:
    kafka:
      bootstrap.servers: ${kafka_boostrap}
      security.protocol: SASL_SSL
      sasl.mechanism: SCRAM-SHA-512
      sasl.jaas.config: org.apache.kafka.common.security.scram.ScramLoginModule required username="${kafka_user}" password="${kafka_passwd}";
      ssl.truststore.location: /opt/minion/etc/${jks_file}
      ssl.truststore.password: ${jks_passwd}
EOF
done

# Start Minion via Docker
docker run --name minion -it --rm \
 -e TZ=America/New_York \
 -p 8201:8201 \
 -p 1514:1514/udp \
 -p 1162:1162/udp \
 -v $(pwd)/k8s/pki/${jks_file}:/opt/minion/etc/${jks_file} \
 -v $(pwd)/minion.yaml:/opt/minion/minion-config.yaml \
 opennms/minion:${minion_version} -c
rm minion.yaml