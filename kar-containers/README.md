# KAR Docker Images

To avoid reaching GitHub every time the OpenNMS Core container starts to install ALEC, the Cortex TSS plugin or other plugins,the idea is to create a place-holder container, meaning a container that has no functionality but contains the appropriate KAR file.

The idea is to use this container within the `initContainers` section of the OpenNMS `StatefulSet` to copy the KAR file to the `$OPENNMS_HOME/deploy` directory at runtime.

## Compilation

```bash
cd alec
make
```

If you want to build for a specific version, provide a GitHub release reference on the command-line, like:
```bash
make RELEASE=tags/v2.0.1
```

## Publishing

```bash
make RELEASE=tags/v2.0.1 push
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
