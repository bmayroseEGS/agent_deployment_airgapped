# Prerequisites

This document outlines the requirements and setup process for deploying Elastic Agents in air-gapped Kubernetes environments using the tools and procedures in this repository.

## Required Infrastructure

### Air-gapped Elastic Stack Deployment

To deploy Elastic Agents using this repository, you **must** have a functioning air-gapped Elastic Stack environment. This repository focuses on agent deployment and assumes you have already deployed the core Elastic infrastructure.

**Minimum Requirements:**
- **Elasticsearch**: Version 8.x or 9.x, deployed in Kubernetes
- **Kibana**: Matching version to Elasticsearch
- **Fleet Server**: (Optional) For centralized agent management
- **Kubernetes Cluster**: k3s, minikube, or production cluster
- **Local Container Registry**: Running at `localhost:5000` with agent images
- **kubectl**: Configured and connected to your cluster
- **Helm**: Version 3.x installed

### Why You Need This

Elastic Agent deployment requires:
1. **Elasticsearch** to receive and store collected data
2. **Kibana** for agent policy configuration and monitoring
3. **Fleet Server** (optional) for centralized agent enrollment and management
4. **Local container registry** with Elastic Agent images in air-gapped environment
5. **Kubernetes access** for deploying agent DaemonSets or Deployments

---

## Setup Using helm-fleet-deployment_airgapped

If you don't already have an air-gapped Elastic Stack deployment, you **must** use the `helm-fleet-deployment_airgapped` repository to set up your environment first.

### Step 1: Clone the Base Infrastructure Repository

**IMPORTANT:** Complete this setup **before** deploying agents from this repository.

```bash
# Clone the infrastructure repository
git clone https://github.com/bmayroseEGS/helm-fleet-deployment-airgapped.git
cd helm-fleet-deployment-airgapped
```

### Step 2: Collect Required Images (Internet-connected Machine)

On a machine with internet access, collect all required container images including Elastic Agent:

```bash
cd deployment_infrastructure
./collect-all.sh
```

**What This Collects:**
- k3s Kubernetes binaries and airgap images
- Helm binary
- Elasticsearch container image
- Kibana container image
- Logstash container image (optional)
- Fleet Server container image
- **Elastic Agent container image** (required for this repository)
- Docker registry image

**When prompted for additional images, include:**
```
docker.elastic.co/beats/elastic-agent:9.2.3
```

### Step 3: Transfer to Air-gapped Machine

Transfer the entire project directory to your air-gapped machine:

```bash
# From internet-connected machine
scp -r helm-fleet-deployment_airgapped/ user@airgapped-server:/path/to/destination/
```

### Step 4: Setup Air-gapped Infrastructure

On the air-gapped machine, run the infrastructure setup:

```bash
cd helm-fleet-deployment_airgapped/deployment_infrastructure

# Install k3s in air-gapped mode
./install-k3s-airgap.sh
```

**What This Does:**
- Installs k3s Kubernetes cluster using local binaries
- Configures kubectl
- Starts the Kubernetes cluster
- Verifies cluster health

### Step 5: Deploy Local Container Registry

Deploy the local Docker registry and load all images:

```bash
cd ../epr_deployment
./epr.sh
```

**What This Does:**
- Deploys local Docker registry at `localhost:5000`
- Loads all collected images into the registry
- Verifies registry health
- Makes images available for Kubernetes deployments

**Verify registry has agent images:**
```bash
curl http://localhost:5000/v2/_catalog

# Should show:
# {
#   "repositories": [
#     "elasticsearch",
#     "kibana",
#     "elastic-agent/elastic-agent",
#     ...
#   ]
# }
```

### Step 6: Deploy Elasticsearch and Kibana

Deploy the core Elastic Stack components:

```bash
cd ../helm_charts
./deploy.sh
```

**Component Selection:**

When prompted, deploy at minimum:
- **Elasticsearch**: `y` (Yes) - Required for data storage
- **Kibana**: `y` (Yes) - Required for agent management
- **Fleet Server**: `y` (Yes) - Recommended for centralized agent management
- **Logstash**: `n` (No) - Not required for agent deployment

```
Deploy Elasticsearch? (y/n): y
Deploy Kibana? (y/n): y
Deploy Logstash? (y/n): n
Deploy Fleet Server? (y/n): y
```

**Deployment Time:**
- Elasticsearch: ~2-5 minutes
- Kibana: ~1-3 minutes
- Fleet Server: ~1-2 minutes

**Verify deployment:**
```bash
kubectl get pods -n elastic

# Expected output:
# NAME                               READY   STATUS    RESTARTS   AGE
# elasticsearch-master-0             1/1     Running   0          5m
# kibana-xxx                         1/1     Running   0          3m
# fleet-server-xxx                   1/1     Running   0          2m
```

### Step 7: Access Kibana

Set up access to Kibana from your local machine.

**If deploying on a remote server:**

From your **local machine**, create an SSH tunnel:

```bash
ssh -i your-key.pem -L 9200:localhost:9200 -L 5601:localhost:5601 user@server
```

Then, on the **remote server**, run:

```bash
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
kubectl port-forward -n elastic svc/kibana 5601:5601 &
```

**If deploying locally:**

```bash
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
kubectl port-forward -n elastic svc/kibana 5601:5601 &
```

**Access Kibana:**

Open your browser and navigate to:
```
http://localhost:5601
```

**Login credentials:**
- **Username**: `elastic`
- **Password**: `elastic`

### Step 8: Configure Fleet Server (Optional but Recommended)

If you deployed Fleet Server, configure it in Kibana:

**Navigate to Fleet Settings:**
1. Open Kibana: `http://localhost:5601`
2. Go to: `Management` → `Fleet` → `Settings`
3. Verify Fleet Server host is configured: `http://fleet-server:8220`

**Create Agent Policy:**
1. Go to: `Fleet` → `Agent policies` → `Create agent policy`
2. Name: `kubernetes-monitoring`
3. Description: `Policy for Kubernetes agent monitoring`
4. Click: `Create agent policy`

**Add Integrations to Policy:**
1. Select your policy: `kubernetes-monitoring`
2. Click: `Add integration`
3. Add desired integrations:
   - System (metrics and logs)
   - Kubernetes (pod, container, node metrics)
   - Log (custom log collection)

**Generate Enrollment Token:**
1. Go to: `Fleet` → `Enrollment tokens`
2. Click: `Create enrollment token`
3. Select policy: `kubernetes-monitoring`
4. Copy the generated token for use in agent deployment

### Step 9: Verify Prerequisites Complete

Before proceeding to agent deployment, verify all requirements:

**Check Elasticsearch:**
```bash
curl http://localhost:9200
```

Expected response:
```json
{
  "name" : "elasticsearch-master-0",
  "cluster_name" : "elasticsearch",
  "version" : {
    "number" : "9.2.2"
  }
}
```

**Check Kibana:**
```bash
curl http://localhost:5601/api/status
```

**Check Fleet Server (if deployed):**
```bash
kubectl exec -n elastic -it deployment/fleet-server -- curl http://localhost:8220/api/status
```

**Check Local Registry:**
```bash
curl http://localhost:5000/v2/_catalog | grep elastic-agent
```

---

## Alternative Deployment Methods

If you already have an air-gapped Elastic Stack deployed through other means (custom Helm charts, ECK, etc.), ensure you have:

### Required Components

1. **Elasticsearch Cluster:**
   - Version 8.x or 9.x
   - Accessible within Kubernetes cluster
   - Sufficient storage for incoming agent data

2. **Kibana:**
   - Matching Elasticsearch version
   - Accessible for policy configuration
   - Fleet UI enabled (if using Fleet management)

3. **Fleet Server (Recommended):**
   - Deployed and healthy
   - Enrolled with Elasticsearch
   - Accessible at stable endpoint (e.g., `http://fleet-server:8220`)

4. **Local Container Registry:**
   - Running at `localhost:5000`
   - Contains Elastic Agent image: `localhost:5000/elastic-agent/elastic-agent:9.2.3`

### Required Access Permissions

**Kibana Access:**
- Fleet management
- Integration management
- Agent policy creation
- Enrollment token generation

**Elasticsearch Access:**
- `manage` cluster privilege
- `write` and `read` access to agent data streams
- Permission to create data streams and indices

**Kubernetes Access:**
- Create and manage DaemonSets/Deployments
- Create and manage ConfigMaps and Secrets
- Read pod logs
- Access to `elastic` namespace

---

## Network Requirements

### Within Kubernetes Cluster

Agents must be able to reach:
- **Elasticsearch**: `http://elasticsearch-master:9200`
- **Fleet Server**: `http://fleet-server:8220` (if using Fleet)

### From Local Machine (for management)

- **Kibana**: `http://localhost:5601` (via port-forward)
- **Elasticsearch**: `http://localhost:9200` (via port-forward)

---

## Storage Considerations

### Elasticsearch Storage

Agent data can generate significant storage requirements:

**Estimate storage needs:**
- **System metrics**: ~50-100 MB/day per node
- **Kubernetes metrics**: ~100-200 MB/day per cluster
- **Logs**: Variable (100 MB - 10 GB/day depending on verbosity)
- **Security events**: ~500 MB - 2 GB/day per node

**Verify available storage:**
```elasticsearch
# In Kibana Dev Tools
GET _cat/allocation?v&h=node,disk.used,disk.avail,disk.total,disk.percent
```

**Ensure sufficient space:**
- Hot tier: At least 50 GB available
- Warm tier: Plan for long-term retention
- ILM policies configured to manage data lifecycle

### Agent Resource Requirements

**DaemonSet mode (per node):**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "200Mi"
  limits:
    cpu: "500m"
    memory: "500Mi"
```

**Deployment mode (per replica):**
```yaml
resources:
  requests:
    cpu: "100m"
    memory: "200Mi"
  limits:
    cpu: "500m"
    memory: "1Gi"
```

---

## Verifying Prerequisites

Run these checks before deploying agents:

### 1. Kubernetes Cluster Health

```bash
kubectl cluster-info
kubectl get nodes
```

Expected: All nodes in `Ready` status

### 2. Elasticsearch Running

```bash
kubectl get pods -n elastic -l app=elasticsearch

# Check logs
kubectl logs -n elastic elasticsearch-master-0
```

Expected: Pod in `Running` status with healthy logs

### 3. Kibana Accessible

```bash
curl http://localhost:5601/api/status
```

Expected: HTTP 200 response

### 4. Fleet Server Running (if using Fleet)

```bash
kubectl get pods -n elastic -l app=fleet-server

# Verify Fleet Server is enrolled
kubectl logs -n elastic -l app=fleet-server | grep -i enrolled
```

Expected: Pod running and enrolled with Elasticsearch

### 5. Container Registry Has Agent Image

```bash
curl http://localhost:5000/v2/_catalog | jq '.repositories[]' | grep elastic-agent

# Check specific image tags
curl http://localhost:5000/v2/elastic-agent/elastic-agent/tags/list
```

Expected: `elastic-agent/elastic-agent` in repository list

### 6. Helm Installed

```bash
helm version
```

Expected: Version 3.x

### 7. kubectl Configured

```bash
kubectl config current-context
kubectl auth can-i create daemonsets --namespace elastic
```

Expected: Current context set and permissions confirmed

---

## Fleet Server Configuration

If using Fleet for centralized management:

### Verify Fleet Server Host

In Kibana:
1. Navigate to: `Fleet` → `Settings`
2. Verify: `Fleet Server hosts` = `http://fleet-server:8220`
3. Verify: `Elasticsearch hosts` = `http://elasticsearch-master:9200`

### Create Agent Policy

```bash
# In Kibana UI:
# Fleet → Agent policies → Create agent policy
# Name: kubernetes-monitoring
# Advanced options → Agent monitoring → Enabled
```

### Generate Enrollment Token

```bash
# In Kibana UI:
# Fleet → Enrollment tokens → Create enrollment token
# Policy: kubernetes-monitoring
# Copy token for agent deployment
```

---

## Troubleshooting Prerequisites

### Cannot Access Kibana

**Check pod status:**
```bash
kubectl get pods -n elastic -l app=kibana
kubectl describe pod -n elastic -l app=kibana
```

**Check logs:**
```bash
kubectl logs -n elastic -l app=kibana | tail -50
```

**Verify port-forward:**
```bash
# Kill existing port-forward
pkill -f "port-forward.*kibana"

# Restart port-forward
kubectl port-forward -n elastic svc/kibana 5601:5601
```

### Fleet Server Not Reachable

**Check Fleet Server logs:**
```bash
kubectl logs -n elastic -l app=fleet-server
```

**Verify enrollment:**
```bash
kubectl logs -n elastic -l app=fleet-server | grep -i enrollment
```

**Test connectivity from agent pod:**
```bash
kubectl run test-pod --image=curlimages/curl:latest -it --rm -- curl http://fleet-server:8220/api/status
```

### Registry Missing Agent Image

**Verify image was collected:**
```bash
ls -lh /path/to/helm-fleet-deployment_airgapped/epr_deployment/images/
```

**Re-run image collection:**
```bash
cd /path/to/helm-fleet-deployment_airgapped/deployment_infrastructure
./collect-all.sh
# Enter: docker.elastic.co/beats/elastic-agent:9.2.3
```

**Reload images into registry:**
```bash
cd ../epr_deployment
./nuke_registry.sh  # Remove old registry
./epr.sh            # Redeploy with new images
```

### Insufficient Kubernetes Permissions

**Check current permissions:**
```bash
kubectl auth can-i create daemonsets --namespace elastic
kubectl auth can-i create configmaps --namespace elastic
kubectl auth can-i create secrets --namespace elastic
```

**If using RBAC, create appropriate role:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: elastic-agent-deployer
  namespace: elastic
rules:
- apiGroups: ["apps"]
  resources: ["daemonsets", "deployments"]
  verbs: ["create", "get", "list", "update", "delete"]
- apiGroups: [""]
  resources: ["configmaps", "secrets", "services"]
  verbs: ["create", "get", "list", "update", "delete"]
```

### Low Elasticsearch Storage

**Check current usage:**
```elasticsearch
GET _cat/allocation?v
```

**Clean up old data:**
```elasticsearch
# Delete old indices
DELETE /logs-*-2024.*

# Configure ILM to delete old data
PUT _ilm/policy/logs
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "7d"
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

---

## Next Steps

Once all prerequisites are verified:

1. **Return to agent deployment**: Navigate to the [README.md](README.md) for agent deployment procedures
2. **Configure agent policies**: Define what data agents should collect
3. **Deploy agents**: Use Helm charts to deploy agents to your cluster
4. **Monitor agent health**: Verify agents are sending data to Elasticsearch

---

## Quick Reference Commands

**Port Forwarding (Remote Server):**
```bash
# From local machine
ssh -i your-key.pem -L 9200:localhost:9200 -L 5601:localhost:5601 user@server

# On remote server
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
kubectl port-forward -n elastic svc/kibana 5601:5601 &
kubectl port-forward -n elastic svc/fleet-server 8220:8220 &
```

**Port Forwarding (Local):**
```bash
kubectl port-forward -n elastic svc/elasticsearch-master 9200:9200 &
kubectl port-forward -n elastic svc/kibana 5601:5601 &
kubectl port-forward -n elastic svc/fleet-server 8220:8220 &
```

**Access URLs:**
- Elasticsearch: `http://localhost:9200`
- Kibana: `http://localhost:5601`
- Fleet: `http://localhost:5601/app/fleet`
- Dev Tools: `http://localhost:5601/app/dev_tools#/console`

**Default Credentials:**
- Username: `elastic`
- Password: `elastic`

**Verify Services:**
```bash
# Elasticsearch
curl http://localhost:9200

# Kibana
curl http://localhost:5601/api/status

# Fleet Server
kubectl exec -n elastic -it deployment/fleet-server -- curl http://localhost:8220/api/status

# Registry
curl http://localhost:5000/v2/_catalog
```

---

## Support

For setup issues with the base infrastructure repository:
- Visit: [helm-fleet-deployment-airgapped](https://github.com/bmayroseEGS/helm-fleet-deployment-airgapped)
- Check: [TROUBLESHOOTING.md](https://github.com/bmayroseEGS/helm-fleet-deployment-airgapped/blob/main/TROUBLESHOOTING.md)

For Elasticsearch/Kibana/Fleet specific issues:
- Elasticsearch Documentation: https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- Kibana Documentation: https://www.elastic.co/guide/en/kibana/current/index.html
- Fleet Documentation: https://www.elastic.co/guide/en/fleet/current/index.html
- Elastic Agent Documentation: https://www.elastic.co/guide/en/fleet/current/elastic-agent-installation.html
