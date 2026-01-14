# Quick Start Guide: Deploying Elastic Agents with Fleet

This guide walks you through deploying Elastic Agents that are managed by Fleet Server in an air-gapped Kubernetes environment.

## Prerequisites

Before deploying agents, ensure you have completed the setup from [helm-fleet-deployment-airgapped](https://github.com/bmayroseEGS/helm-fleet-deployment-airgapped):

- ✅ Elasticsearch running in Kubernetes
- ✅ Kibana running and accessible
- ✅ Fleet Server deployed and healthy
- ✅ **Fleet Server Elasticsearch output configured** (see [FLEET_SETUP.md Step 6](https://github.com/bmayroseEGS/helm-fleet-deployment-airgapped/blob/main/docs/FLEET_SETUP.md#step-6-fix-elasticsearch-output-configuration-important))

## Step 1: Access Kibana

### On Remote Server

Start port-forwarding for Kibana:

```bash
kubectl port-forward -n elastic svc/kibana 5601:5601
```

### On Your Local Machine

Create an SSH tunnel to access Kibana:

```bash
ssh -i your-key.pem -L 5601:localhost:5601 ubuntu@your-server-ip
```

Open your browser to: **http://localhost:5601**

**Login credentials:**
- Username: `elastic`
- Password: `elastic`

## Step 2: Get Fleet Enrollment Token

### Navigate to Fleet Enrollment Tokens

1. **Open Kibana** at http://localhost:5601
2. Click the **hamburger menu (☰)** in the top left
3. Scroll down to **Management**
4. Click **Fleet**
5. Click **Enrollment tokens** (in left sidebar or top tabs)

### Option A: Use an Existing Token

You'll see a list of enrollment tokens for different agent policies:

1. Find the policy you want to use (e.g., "Agent policy 1")
2. Click the **eyeball icon (👁️)** to reveal the token
3. Click the **copy icon** to copy the token to your clipboard

The token looks like this:
```
V3d6Y3VKc0JzaGpFOFl0YjIyRjA6MXN0c1piYU1MVjJlUkhqVW82UFVRZw==
```

### Option B: Create a New Token with System Integration

If you want to set up the System integration before enrolling agents:

1. **Create Agent Policy**
   - In Fleet, go to **Agent policies**
   - Click **Create agent policy**
   - Name: `system-monitoring`
   - Description: `Policy for system metrics and logs collection`
   - Click **Create agent policy**

2. **Add System Integration**
   - Click **Add integration**
   - Search for "System" and click it
   - Click **Add System**
   - Configure settings (defaults are fine):
     - ✅ Collect system metrics (CPU, memory, network, disk)
     - ✅ Collect system logs
   - Click **Save and continue**
   - Click **Add Elastic Agent to your hosts**

3. **Generate Enrollment Token**
   - In the "Add agent" flyout, you'll see an enrollment token
   - Click **Copy to clipboard**
   - Or navigate to **Fleet** → **Enrollment tokens** and find your new policy's token

## Step 3: Deploy Elastic Agents

### On Your Remote Server

Navigate to the agent deployment repository:

```bash
cd ~/agent_deployment_airgapped/helm_charts
```

### Option A: Interactive Deployment Script (Recommended)

Run the deployment script:

```bash
./deploy-agents.sh
```

**Answer the prompts:**

1. **Deployment mode**: `daemonset` (deploys one agent per node)
   ```
   Deployment mode (daemonset/deployment) [daemonset]: daemonset
   ```

2. **Use Fleet Server**: `y` (yes)
   ```
   Use Fleet Server for agent management? (y/n) [n]: y
   ```

3. **Fleet enrollment token**: Paste the token you copied from Kibana
   ```
   Enter Fleet enrollment token: V3d6Y3VKc0JzaGpFOFl0YjIyRjA6MXN0c1piYU1MVjJlUkhqVW82UFVRZw==
   ```

4. **Custom values file**: `n` (no - use defaults with Fleet)
   ```
   Use custom values file? (y/n) [n]: n
   ```

5. **Confirm deployment**: `y` (yes)
   ```
   Proceed with deployment? (y/n): y
   ```

The script will:
- Deploy the agents
- Wait for pods to be ready
- Show deployment status
- Offer to display logs

### Option B: Direct Helm Deployment

Deploy directly with Helm:

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --create-namespace \
  --set deploymentMode=daemonset \
  --set fleet.enabled=true \
  --set fleet.url="http://fleet-server:8220" \
  --set fleet.enrollmentToken="YOUR_TOKEN_HERE"
```

Replace `YOUR_TOKEN_HERE` with your actual enrollment token.

## Step 4: Verify Agent Enrollment

### Check Agent Pods

```bash
# View agent pods (should be one per node)
kubectl get pods -n elastic -l app=elastic-agent

# Expected output:
# NAME                  READY   STATUS    RESTARTS   AGE
# elastic-agent-abc123  1/1     Running   0          30s
```

### Check Agent Logs

```bash
# View logs
kubectl logs -n elastic -l app=elastic-agent --tail=50

# Follow logs in real-time
kubectl logs -n elastic -l app=elastic-agent -f
```

Look for messages like:
- `"Successfully enrolled"`
- `"Fleet Server connected"`
- `"Healthy"`

### Verify in Kibana Fleet UI

1. Go to **Management** → **Fleet** → **Agents**
2. You should see your agent(s) listed with:
   - ✅ Status: **Healthy**
   - ✅ Policy: The policy you selected
   - ✅ Last checkin: Recent timestamp

![Fleet Agents Healthy](../images/fleet-agents-healthy.png)

## Step 5: Add Integrations (If Not Already Added)

If you used an existing enrollment token without integrations, add them now:

### System Integration

1. **Navigate to Agent Policy**
   - Go to **Management** → **Fleet** → **Agent policies**
   - Click on the policy your agents are using

2. **Add System Integration**
   - Click **Add integration**
   - Search for "System"
   - Click **Add System**
   - Leave defaults (collects CPU, memory, disk, network, logs)
   - Click **Save and continue**
   - Click **Save and deploy changes**

3. **Wait for Policy Update**
   - Fleet will automatically push the new policy to your agents
   - Wait about 30 seconds for agents to receive the update

## Step 6: Verify Data in Kibana

### View System Metrics

1. **Open Discover**
   - Go to **Analytics** → **Discover**

2. **Create Data View** (if needed)
   - Click **Create a data view**
   - Index pattern: `metrics-*`
   - Timestamp field: `@timestamp`
   - Click **Save data view to Kibana**

3. **Search for System Metrics**
   - Select your `metrics-*` data view
   - You should see data coming in!
   - Try filtering by data stream:
     - `data_stream.dataset: "system.cpu"`
     - `data_stream.dataset: "system.memory"`
     - `data_stream.dataset: "system.network"`

### View System Logs

1. In Discover, search for:
   ```
   data_stream.dataset: "system.syslog"
   ```

2. You should see system logs from `/var/log/messages` and `/var/log/syslog`

### Example Queries

**CPU usage over 50%:**
```
system.cpu.total.pct > 0.5 AND data_stream.dataset: "system.cpu"
```

**Memory usage:**
```
data_stream.dataset: "system.memory"
```

**Network traffic:**
```
data_stream.dataset: "system.network"
```

## Troubleshooting

### Agents Not Appearing in Fleet

**Symptom**: No agents showing in Fleet UI after deployment

**Check:**
```bash
# Verify pods are running
kubectl get pods -n elastic -l app=elastic-agent

# Check logs for enrollment errors
kubectl logs -n elastic -l app=elastic-agent --tail=100 | grep -i error
```

**Common Issues:**
- Wrong enrollment token
- Fleet Server not reachable from agents
- Network connectivity issues

**Solution:**
```bash
# Test Fleet Server connectivity from agent pod
kubectl exec -n elastic <agent-pod-name> -- curl http://fleet-server:8220/api/status

# Should return: {"name":"fleet-server","status":"HEALTHY"}
```

### Agents Showing as "Offline"

**Symptom**: Agents appear in Fleet but status is "Offline"

**Check:**
```bash
# View agent logs
kubectl logs -n elastic -l app=elastic-agent -f
```

**Common Issues:**
- Elasticsearch not reachable
- Authentication failures
- Network policy blocking traffic

**Solution:**
```bash
# Test Elasticsearch connectivity
kubectl exec -n elastic <agent-pod-name> -- curl http://elasticsearch-master:9200

# Should return Elasticsearch cluster info
```

### No Data Appearing in Kibana

**Symptom**: Agents are healthy but no data in Discover

**Check:**

1. **Verify Integration is Added**
   - Go to Fleet → Agent policies → Your policy
   - Confirm System (or other) integration is listed

2. **Check Agent Logs**
   ```bash
   kubectl logs -n elastic -l app=elastic-agent | grep -i "system"
   ```

   Look for messages about starting system inputs

3. **Verify Indices Exist**
   - In Kibana, go to **Dev Tools**
   - Run:
     ```
     GET _cat/indices/metrics-system*?v
     ```

   You should see indices like:
   - `metrics-system.cpu-default`
   - `metrics-system.memory-default`

4. **Check Data Stream**
   ```
   GET _data_stream/metrics-system.*
   ```

### High Memory Usage

**Symptom**: Agent pods using excessive memory

**Solution**: Adjust resource limits in values file:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "200Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"  # Increase if needed
```

Upgrade the deployment:
```bash
helm upgrade elastic-agent ./elastic-agent \
  --namespace elastic \
  --set resources.limits.memory="1Gi"
```

## Next Steps

### Add More Integrations

Explore available integrations:
- **Kubernetes**: Pod, container, and node metrics
- **Nginx**: Web server monitoring
- **Apache**: HTTP server monitoring
- **MySQL/PostgreSQL**: Database monitoring
- **Docker**: Container monitoring
- **Custom Logs**: Collect application logs

### Scale Agent Deployment

**DaemonSet** (default): Automatically scales with nodes
- One agent per node
- Ideal for system and Kubernetes monitoring

**Deployment mode**: Fixed number of replicas
```bash
helm upgrade elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=deployment \
  --set replicas=3
```

### Create Dashboards

1. Go to **Analytics** → **Dashboard**
2. Click **Create dashboard**
3. Add visualizations for:
   - CPU usage over time
   - Memory usage trends
   - Disk space utilization
   - Network I/O
   - Top processes

### Set Up Alerts

1. Go to **Stack Management** → **Rules and Connectors**
2. Create rules for:
   - High CPU usage (> 80%)
   - Low disk space (< 10%)
   - High memory usage (> 90%)
   - Service failures

## Additional Resources

- [Main README](../README.md) - Full documentation
- [System Integration Example](../examples/system-integration/README.md) - Detailed System integration guide
- [Fleet Server Setup](https://github.com/bmayroseEGS/helm-fleet-deployment-airgapped/blob/main/docs/FLEET_SETUP.md) - Fleet Server configuration
- [Elastic Agent Documentation](https://www.elastic.co/guide/en/fleet/current/elastic-agent-installation.html)
- [Elastic Integrations](https://www.elastic.co/integrations)

## Summary Commands

```bash
# Deploy agents with Fleet
cd ~/agent_deployment_airgapped/helm_charts
./deploy-agents.sh

# Check agent status
kubectl get pods -n elastic -l app=elastic-agent

# View agent logs
kubectl logs -n elastic -l app=elastic-agent -f

# Access Kibana
kubectl port-forward -n elastic svc/kibana 5601:5601
# Then: http://localhost:5601

# Verify Fleet enrollment
# Kibana → Management → Fleet → Agents

# View metrics in Kibana
# Kibana → Analytics → Discover → metrics-*

# Uninstall agents
helm uninstall elastic-agent -n elastic
```

---

**Questions or issues?** Check the [troubleshooting section](#troubleshooting) or open an issue on GitHub.
