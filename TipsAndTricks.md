# Useful tools and commands

## k9s
https://k9scli.io/

## kubectl
Tail logs (leave off `-f` to see all logs):
```
kubectl logs -n <namespace> -f -c onms pods/onms-core-0
```

Get a shell:
```
kubectl exec -it -n <namespace> pods/onms-core-0 -c onms -- /bin/bash
```

Restart OpenNMS:
```
kubectl rollout restart -n <namespace> statefulset/onms-core
```

Stop OpenNMS:
```
kubectl scale -n <namespace> --replicas=0 statefulset/onms-core
```

Start OpenNMS:
```
kubectl scale -n <namespace> --replicas=1 statefulset/onms-core
```

# Inspector pod
This can be used to cleanly shutdown OpenNMS but have a way to edit configuration files, inspect files before a backup or after a restore, etc.

Enable Inspector pod (shutdown OpenNMS):
```
helm upgrade --reuse-values --set opennms.inspector.enabled=true <namespace> ./opennms
```

How to connect:
```
kubectl exec -it -n <namespace> pods/inspector -- /bin/bash
```

Examples:
```
# Run configuration tester
./bin/config-tester -a

# Forcing the installer to re-run 
rm etc/configured
```

Disable Inspector pod (start OpenNMS):
```
helm upgrade --reuse-values --set opennms.inspector.enabled=false <namespace> ./opennms
```