# Air-gapped Elastic Agent Deployment

Helm charts and deployment tools for deploying Elastic Agents to remote machines in air-gapped Kubernetes environments, sending data to Elastic integrations.

## Overview

This repository provides Helm charts and deployment automation for deploying Elastic Agents in air-gapped environments. Agents collect logs, metrics, and security data from remote systems and forward them to your Elastic Stack deployment.

**Key capabilities:**
- Deploy Elastic Agents as Kubernetes DaemonSets or Deployments
- Configure agents to send data to Elastic integrations
- Support for multiple agent policies and configurations
- Air-gapped deployment using local container registry
- Integration with Fleet Server for centralized management

## Prerequisites

Before using this repository, you **must** have a functioning air-gapped Elastic Stack environment. See [PREREQUISITES.md](PREREQUISITES.md) for detailed setup instructions.

### Quick Prerequisites Summary

- **Air-gapped Kubernetes cluster** (k3s or similar) - See [helm-fleet-deployment_airgapped](../helm_fleet_deplyment_airgapped/helm-fleet-deployment_airgapped)
- **Elasticsearch and Kibana** deployed and accessible
- **Fleet Server** deployed and configured (optional, for centralized management)
- **Local container registry** at `localhost:5000` with Elastic Agent images loaded
- **kubectl** configured and connected to your cluster
- **Helm 3.x** installed

## Project Structure

```
agent_deployment_airgapped/
├── README.md                          # This file
├── PREREQUISITES.md                   # Setup requirements
├── helm_charts/                       # Helm charts for agent deployment
│   ├── elastic-agent/                 # Main agent Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                # Default configuration
│   │   └── templates/
│   │       ├── daemonset.yaml         # DaemonSet for node-level collection
│   │       ├── deployment.yaml        # Deployment for centralized agents
│   │       ├── configmap.yaml         # Agent configuration
│   │       ├── secret.yaml            # Credentials and tokens
│   │       └── service.yaml           # Service definition
│   └── deploy-agents.sh               # Deployment automation script
├── examples/                          # Example configurations
│   ├── system-metrics/                # System metrics collection
│   ├── kubernetes-logs/               # Kubernetes log collection
│   ├── security-monitoring/           # Security event collection
│   └── custom-integrations/           # Custom integration examples
└── scripts/                           # Utility scripts
    ├── generate-enrollment-token.sh   # Generate Fleet enrollment tokens
    └── verify-agent-connection.sh     # Verify agent connectivity
```

## Quick Start

### Step 1: Verify Prerequisites

Ensure you have completed the setup from [helm-fleet-deployment_airgapped](../helm_fleet_deplyment_airgapped/helm-fleet-deployment_airgapped):

```bash
# Verify Elasticsearch is running
kubectl get pods -n elastic -l app=elasticsearch

# Verify Fleet Server is running (if using Fleet management)
kubectl get pods -n elastic -l app=fleet-server

# Verify local registry has agent images
curl http://localhost:5000/v2/_catalog
```

### Step 2: Configure Agent Deployment

Edit [helm_charts/elastic-agent/values.yaml](helm_charts/elastic-agent/values.yaml) to configure:

```yaml
# Agent image from local registry
image:
  registry: localhost:5000
  repository: elastic-agent/elastic-agent
  tag: "9.2.3"

# Deployment mode: daemonset or deployment
deploymentMode: daemonset  # Use daemonset for node-level collection

# Elasticsearch connection
elasticsearch:
  host: "http://elasticsearch-master:9200"
  username: "elastic"
  password: "elastic"

# Fleet Server connection (optional)
fleet:
  enabled: true
  url: "http://fleet-server:8220"
  enrollmentToken: "YOUR_ENROLLMENT_TOKEN"

# Agent policy configuration
agentPolicy:
  name: "default-policy"
  outputs:
    default:
      type: "elasticsearch"
      hosts: ["http://elasticsearch-master:9200"]
```

### Step 3: Deploy Elastic Agents

```bash
cd helm_charts
./deploy-agents.sh
```

The script will:
- Prompt for deployment configuration
- Create necessary secrets and configmaps
- Deploy agents to your Kubernetes cluster
- Verify agent connectivity

**Or deploy manually using Helm:**

```bash
# Deploy as DaemonSet (collects from all nodes)
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --create-namespace

# Deploy as Deployment (centralized agents)
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=deployment \
  --set replicas=3
```

### Step 4: Verify Deployment

```bash
# Check agent pods
kubectl get pods -n elastic -l app=elastic-agent

# View agent logs
kubectl logs -n elastic -l app=elastic-agent -f

# Verify agents in Fleet (if using Fleet Server)
# Navigate to Kibana → Fleet → Agents
# Open browser: http://localhost:5601/app/fleet/agents
```

## Deployment Modes

### DaemonSet Mode (Recommended for Node Monitoring)

Deploys one agent per Kubernetes node. Ideal for:
- System metrics collection (CPU, memory, disk)
- Kubernetes logs and events
- Host-level security monitoring
- Node filesystem scanning

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=daemonset
```

### Deployment Mode (Recommended for Centralized Collection)

Deploys a fixed number of agent replicas. Ideal for:
- Centralized log aggregation
- Application performance monitoring
- Custom integrations
- External API polling

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=deployment \
  --set replicas=3
```

## Configuration Options

### Basic Configuration

```yaml
# values.yaml
image:
  registry: localhost:5000
  repository: elastic-agent/elastic-agent
  tag: "9.2.3"

deploymentMode: daemonset  # or deployment

replicas: 1  # Only for deployment mode

resources:
  requests:
    cpu: "100m"
    memory: "200Mi"
  limits:
    cpu: "500m"
    memory: "500Mi"
```

### Elasticsearch Connection

```yaml
elasticsearch:
  host: "http://elasticsearch-master:9200"
  username: "elastic"
  password: "elastic"

  # TLS/SSL configuration (optional)
  ssl:
    enabled: false
    certificateAuthorities: ""
    certificate: ""
    key: ""
```

### Fleet Server Integration

```yaml
fleet:
  enabled: true
  url: "http://fleet-server:8220"
  enrollmentToken: "YOUR_ENROLLMENT_TOKEN"

  # Insecure mode for air-gapped environments
  insecure: true
```

### Agent Policy Configuration

```yaml
agentPolicy:
  name: "kubernetes-monitoring"

  # Data collection inputs
  inputs:
    - type: "system/metrics"
      enabled: true
      streams:
        - metricset: "cpu"
        - metricset: "memory"
        - metricset: "network"
        - metricset: "filesystem"

    - type: "kubernetes/metrics"
      enabled: true
      streams:
        - metricset: "pod"
        - metricset: "container"
        - metricset: "node"

    - type: "log"
      enabled: true
      streams:
        - paths:
            - "/var/log/containers/*.log"
          processors:
            - add_kubernetes_metadata: {}

  # Output configuration
  outputs:
    default:
      type: "elasticsearch"
      hosts: ["http://elasticsearch-master:9200"]
      username: "elastic"
      password: "elastic"
```

## Common Use Cases

### Use Case 1: Kubernetes Monitoring

Collect metrics and logs from all Kubernetes nodes:

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=daemonset \
  --set agentPolicy.inputs.system/metrics.enabled=true \
  --set agentPolicy.inputs.kubernetes/metrics.enabled=true \
  --set agentPolicy.inputs.log.enabled=true
```

### Use Case 2: Security Monitoring

Deploy agents for endpoint security and threat detection:

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=daemonset \
  --set agentPolicy.inputs.endpoint.enabled=true \
  --set agentPolicy.inputs.auditd.enabled=true \
  --set agentPolicy.inputs.file_integrity.enabled=true
```

### Use Case 3: Custom Application Monitoring

Monitor specific applications with custom integrations:

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set deploymentMode=deployment \
  --set replicas=2 \
  --set agentPolicy.inputs.custom-app/metrics.enabled=true
```

## Fleet Server Enrollment

If using Fleet Server for centralized management:

### Step 1: Generate Enrollment Token

```bash
# In Kibana UI:
# Fleet → Settings → Enrollment tokens → Create enrollment token

# Or use the script:
./scripts/generate-enrollment-token.sh
```

### Step 2: Configure Agents with Token

```bash
helm install elastic-agent ./elastic-agent \
  --namespace elastic \
  --set fleet.enabled=true \
  --set fleet.url="http://fleet-server:8220" \
  --set fleet.enrollmentToken="YOUR_TOKEN_HERE"
```

### Step 3: Verify in Kibana

Navigate to: `Fleet → Agents`

You should see your enrolled agents with:
- Status: Healthy
- Policy: Applied
- Last checkin: Recent timestamp

## Integrations

Agents can send data to various Elastic integrations:

### System Integration
- Collects system metrics (CPU, memory, disk, network)
- Monitors system logs and events
- Tracks process information

### Kubernetes Integration
- Pod and container metrics
- Kubernetes events and audit logs
- Cluster state monitoring

### Security Integration
- Endpoint detection and response
- File integrity monitoring
- System audit logs
- Network traffic analysis

### Custom Integrations
- Application-specific metrics
- Custom log parsing
- Third-party service monitoring

## Scaling and Resource Management

### Scaling DaemonSet Deployments

DaemonSets automatically scale with your cluster (one pod per node). To control resource usage:

```yaml
resources:
  requests:
    cpu: "200m"      # Increase for more intensive collection
    memory: "400Mi"
  limits:
    cpu: "1000m"     # Prevent resource exhaustion
    memory: "1Gi"
```

### Scaling Deployment Mode

For deployment mode, scale replicas based on load:

```bash
# Scale to 5 replicas
helm upgrade elastic-agent ./elastic-agent \
  --namespace elastic \
  --set replicas=5
```

## Troubleshooting

### Agents Not Appearing in Fleet

**Check agent logs:**
```bash
kubectl logs -n elastic -l app=elastic-agent | grep -i error
```

**Common issues:**
- Incorrect enrollment token
- Fleet Server not reachable
- Network connectivity issues

**Solution:**
```bash
# Verify Fleet Server is accessible
kubectl exec -n elastic -it deployment/elastic-agent -- curl http://fleet-server:8220/api/status

# Regenerate enrollment token
./scripts/generate-enrollment-token.sh
```

### Agents Stuck in "Unhealthy" Status

**Check Elasticsearch connectivity:**
```bash
kubectl exec -n elastic -it deployment/elastic-agent -- curl http://elasticsearch-master:9200
```

**Verify credentials:**
```bash
kubectl get secret -n elastic elastic-agent-credentials -o yaml
```

### High Memory Usage

**Reduce collection frequency:**
```yaml
agentPolicy:
  inputs:
    - type: "system/metrics"
      period: "60s"  # Increase from default 10s
```

**Limit data streams:**
```yaml
agentPolicy:
  inputs:
    - type: "system/metrics"
      streams:
        - metricset: "cpu"     # Only collect CPU metrics
```

### Missing Data in Elasticsearch

**Verify agent is sending data:**
```bash
# Check agent logs for output errors
kubectl logs -n elastic -l app=elastic-agent | grep -i output

# Check Elasticsearch indices
curl http://localhost:9200/_cat/indices?v | grep metrics
```

**Verify index permissions:**
```elasticsearch
# In Kibana Dev Tools
GET _security/user/elastic
```

## Best Practices

1. **Use Fleet Server**: For centralized policy management and updates
2. **Monitor Resource Usage**: Set appropriate resource limits based on collection load
3. **Separate Policies**: Create different policies for different workload types
4. **Test Before Deploy**: Test configuration in a single pod before scaling
5. **Use DaemonSet for Node Data**: Collect host metrics using DaemonSet mode
6. **Version Control**: Keep agent versions consistent with Elasticsearch version
7. **Secure Credentials**: Use Kubernetes secrets for sensitive data
8. **Monitor Agent Health**: Set up alerts for agent connectivity issues

## Upgrading Agents

### Via Fleet Server (Recommended)

```bash
# In Kibana:
# Fleet → Agents → Select agents → Upgrade agents
```

### Manual Helm Upgrade

```bash
# Update image tag in values.yaml
helm upgrade elastic-agent ./elastic-agent \
  --namespace elastic \
  --set image.tag="9.3.0"
```

## Cleanup

```bash
# Remove agent deployment
helm uninstall elastic-agent -n elastic

# Remove associated configmaps and secrets
kubectl delete configmap -n elastic -l app=elastic-agent
kubectl delete secret -n elastic -l app=elastic-agent

# Verify removal
kubectl get all -n elastic -l app=elastic-agent
```

## Support

For detailed setup and troubleshooting:
- [PREREQUISITES.md](PREREQUISITES.md) - Environment setup requirements
- [helm-fleet-deployment_airgapped](../helm_fleet_deplyment_airgapped/helm-fleet-deployment_airgapped) - Base infrastructure deployment
- [Elastic Agent Documentation](https://www.elastic.co/guide/en/fleet/current/elastic-agent-installation.html)
- [Elastic Integrations](https://www.elastic.co/integrations)

## References

- [Elastic Agent Reference](https://www.elastic.co/guide/en/fleet/current/index.html)
- [Fleet and Elastic Agent Guide](https://www.elastic.co/guide/en/fleet/current/fleet-overview.html)
- [Kubernetes Integration](https://www.elastic.co/guide/en/integrations/current/kubernetes.html)

## Contributing

Contributions are welcome! Please:
- Follow existing Helm chart conventions
- Test deployments before submitting
- Include example configurations for new use cases
- Update this README with new sections

## License

This project is provided as-is for operational deployment purposes.

## Author

Maintained by Brian Mayrose
