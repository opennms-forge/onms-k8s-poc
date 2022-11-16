# ALEC Docker Image

To avoid reaching GitHub every time the OpenNMS Core container starts to install ALEC, the idea is to create a place-holder container, meaning a container that has no functionality but contains the ALEC KAR file.

The idea is to use this container within the `initContainers` section of the OpenNMS `StatefulSet` to copy the KAR file to the `$OPENNMS_HOME/deploy` directory at runtime.

## Compilation

```bash
ALEC_VER=$(curl -s https://api.github.com/repos/OpenNMS/alec/releases/latest | grep tag_name | cut -d '"' -f 4)
docker build -t opennms/alec:$ALEC_VER .
docker push opennms/alec:$ALEC_VER
```

## Usage

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: onms-core
...
      initContainers:
      - name: alec
        image: opennms/alec:v1.1.1
        imagePullPolicy: IfNotPresent
        command: [ cp, /plugins/opennms-alec-plugin.kar, /opennms-deploy ]
        volumeMounts:
        - name: deploy
          mountPath: /opennms-deploy
...
      containers:
      - name: onms
      ...
        volumeMounts:
        - name: deploy
          mountPath: /opt/opennms/deploy
...
      volumes:
      - name: deploy
        emptyDir: {}
```