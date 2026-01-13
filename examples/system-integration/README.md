# System Integration Example

This example demonstrates how to deploy Elastic Agent with the System integration to collect system metrics and logs from your Kubernetes nodes.

## What Gets Collected

The System integration collects:

### Metrics
- **CPU**: Usage, percentages, per-core stats
- **Memory**: Total, used, free, available, swap
- **Load**: System load averages (1m, 5m, 15m)
- **Network**: I/O per interface, packets, errors
- **Filesystem**: Disk usage per mount point
- **Process**: Top processes by CPU and memory
- **Socket**: Network socket summary

### Logs
- System logs from `/var/log/messages` and `/var/log/syslog`
- Rotated logs are excluded (`.gz` files)

## Prerequisites

Before deploying, ensure you have:

1. **Elastic Stack running** in the `elastic` namespace
   - Elasticsearch
   - Kibana

2. **Local registry** with Elastic Agent image at `localhost:5000`

3. **kubectl and helm** installed and configured

Verify prerequisites:
```bash
# Check Elasticsearch
kubectl get pods -n elastic -l app=elasticsearch

# Check Kibana
kubectl get pods -n elastic -l app=kibana

# Check local registry
curl http://localhost:5000/v2/_catalog | grep elastic-agent
```

## Quick Deploy

From the `helm_charts` directory:

```bash
cd /path/to/agent_deployment_airgapped/helm_charts

# Deploy using the example values file
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --create-namespace \
  -f ../examples/system-integration/values-system.yaml
```

## Using the Deployment Script

Alternatively, use the interactive deployment script:

```bash
cd /path/to/agent_deployment_airgapped/helm_charts

./deploy-agents.sh
```

When prompted:
- **Deployment mode**: `daemonset` (default)
- **Use Fleet Server**: `n` (using standalone mode)
- **Custom values file**: `y` then enter `../examples/system-integration/values-system.yaml`

## Verify Deployment

Check that agent pods are running on all nodes:

```bash
# View agent pods
kubectl get pods -n elastic -l app=elastic-agent -o wide

# You should see one pod per node
# Example output:
# NAME                  READY   STATUS    NODE
# elastic-agent-abc12   1/1     Running   node1
# elastic-agent-def34   1/1     Running   node2
```

Check agent logs:

```bash
# View logs from all agents
kubectl logs -n elastic -l app=elastic-agent --tail=50

# View logs from specific agent
kubectl logs -n elastic elastic-agent-abc12 -f
```

## View Data in Kibana

1. **Port-forward Kibana** (if not already done):
   ```bash
   kubectl port-forward -n elastic svc/kibana 5601:5601
   ```

2. **Open Kibana**: http://localhost:5601
   - Username: `elastic`
   - Password: `elastic`

3. **View System Metrics**:
   - Go to: **Analytics** → **Discover**
   - Select index pattern: `metrics-system.*`
   - You should see system metrics flowing in

4. **Create Visualizations**:
   - Go to: **Analytics** → **Dashboard**
   - Create new dashboard
   - Add visualizations for:
     - CPU usage over time
     - Memory usage over time
     - Disk usage by filesystem
     - Network I/O
     - Top processes

5. **View System Logs**:
   - Go to: **Analytics** → **Discover**
   - Select index pattern: `logs-system.*`
   - View system log entries

## Customization

### Adjust Collection Frequency

Edit the values file to change how often metrics are collected:

```yaml
agentPolicy:
  inputs:
    system:
      metrics:
        period: "30s"  # Collect every 30 seconds instead of 10
```

### Collect Specific Metricsets Only

To reduce resource usage, collect only specific metrics:

```yaml
agentPolicy:
  inputs:
    system:
      metrics:
        metricsets:
          - cpu
          - memory
          # Remove other metricsets you don't need
```

### Add Custom Log Paths

Collect logs from additional locations:

```yaml
agentPolicy:
  inputs:
    system:
      logs:
        streams:
          - paths:
              - /var/log/messages
              - /var/log/syslog
              - /var/log/myapp/*.log  # Add custom path
            exclude_files: ['.gz$', '.zip$']
```

### Adjust Resource Limits

For nodes with different resource constraints:

```yaml
resources:
  requests:
    cpu: "50m"      # Lower for smaller nodes
    memory: "100Mi"
  limits:
    cpu: "1000m"    # Higher for larger nodes
    memory: "1Gi"
```

## Troubleshooting

### Agents Not Starting

Check pod status and events:
```bash
kubectl describe pod -n elastic -l app=elastic-agent
```

Common issues:
- **ImagePullBackOff**: Image not in local registry
- **CrashLoopBackOff**: Check logs for configuration errors

### No Data in Elasticsearch

Verify agent can connect to Elasticsearch:
```bash
# From inside an agent pod
kubectl exec -n elastic -it <agent-pod-name> -- curl http://elasticsearch-master:9200
```

Check agent logs for connection errors:
```bash
kubectl logs -n elastic -l app=elastic-agent | grep -i error
```

### Permission Errors

If you see permission errors in logs, verify security context:
```bash
kubectl get pod -n elastic -l app=elastic-agent -o yaml | grep -A 10 securityContext
```

The agent should run as root (UID 0) to access system metrics.

### High Memory Usage

If agents are using too much memory:

1. Reduce collection frequency
2. Collect fewer metricsets
3. Increase memory limits
4. Filter processes more aggressively

## Upgrade

To upgrade the agent configuration:

```bash
helm upgrade elastic-agent ./elastic-agent \
  --namespace elastic \
  -f ../examples/system-integration/values-system.yaml
```

## Uninstall

To remove the agents:

```bash
helm uninstall elastic-agent -n elastic

# Verify removal
kubectl get pods -n elastic -l app=elastic-agent
```

## Next Steps

Once system monitoring is working:

1. **Set up dashboards** in Kibana for system metrics
2. **Create alerts** for high CPU/memory usage
3. **Add more integrations**:
   - Kubernetes integration for pod metrics
   - Security integration for endpoint monitoring
   - Custom integrations for applications

## Reference

- [System Integration Docs](https://www.elastic.co/guide/en/integrations/current/system.html)
- [Elastic Agent Reference](https://www.elastic.co/guide/en/fleet/current/elastic-agent-installation.html)
- [Main README](../../README.md)
