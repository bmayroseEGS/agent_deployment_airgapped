# Windows Synthetic Data Generator Guide

This guide walks through deploying the Windows Synthetic Data Generator, which creates fake Windows event logs and sends them directly to Elasticsearch for demo and testing purposes.

## Overview

The generator creates realistic Windows event logs including:
- **Security Events**: Logon success (4624), logon failure (4625), process creation (4688), process termination (4689), privilege assigned (4672), user created (4720), user deleted (4726)
- **System Events**: Information (1), service started (6005), service stopped (6006)
- **Application Events**: Error (1000), hang (1001), crash (1002)

Events are sent directly to Elasticsearch via the Bulk API to the correct Windows data streams:
- `logs-windows.security-default`
- `logs-windows.system-default`
- `logs-windows.application-default`

## Prerequisites

- Kubernetes cluster running
- Elasticsearch deployed in the `elastic` namespace
- Helm installed
- Python image (`python:3.11-slim`) loaded in local registry

## Deployment

### 1. Run the Deploy Script

```bash
cd helm_charts
./deploy-windows-synthetic.sh
```

### 2. Configure Options

The script will prompt for configuration:

```
========================================
  Configuration
========================================

Events per minute [60]: 10
```
Enter the number of events to generate per minute (default: 60).

```
Generation mode:
  1) continuous - Generate events continuously
  2) batch - Generate events in batches with pauses
Select mode [1]: 1
```
Select continuous mode for steady event generation.

```
Use custom values file? (path or empty):
```
Press Enter to use defaults, or provide a path to a custom values file.

### 3. Wait for Deployment

The script will deploy the generator and wait for the pod to be ready:

```
========================================
  Deploying Windows Synthetic Generator
========================================

Running: helm install windows-synthetic ./windows-synthetic-agent -n elastic --set generator.eventsPerMinute=10 --set generator.mode=continuous

Deployment initiated successfully!

Waiting for pod to be ready...
pod/windows-synthetic-windows-synthetic-agent-xxxxx condition met
✓ Pod is ready!
```

## Verifying the Generator

### Check Pod Status

```bash
kubectl get pods -n elastic -l app=windows-synthetic-agent
```

Expected output:
```
NAME                                                         READY   STATUS    RESTARTS   AGE
windows-synthetic-windows-synthetic-agent-64b97484f5-xxxxx   1/1     Running   0          1m
```

### View Generator Logs

```bash
kubectl logs -n elastic -l app=windows-synthetic-agent -f
```

Expected output:
```
2026-01-16 19:27:28,973 - INFO - Starting Windows Event Generator (Direct ES Mode)
2026-01-16 19:27:28,973 - INFO - Config path: /config/generator-config.yaml
2026-01-16 19:27:28,973 - INFO - Elasticsearch: http://elasticsearch-master:9200
2026-01-16 19:27:29,163 - INFO - Connected to Elasticsearch: elasticsearch
2026-01-16 19:27:29,163 - INFO - Mode: continuous, Events/min: 10 (every 6.0s)
2026-01-16 19:28:29,200 - INFO - Indexed 10 events (total: 10)
2026-01-16 19:29:29,250 - INFO - Indexed 10 events (total: 20)
```

The generator batches events and sends them to Elasticsearch in groups of 10.

## Viewing Data in Kibana

### 1. Open Kibana Discover

Navigate to **Kibana → Discover**

### 2. Create Data View (if needed)

If you don't have a Windows data view:
1. Go to **Stack Management → Data Views**
2. Click **Create data view**
3. Set index pattern to `logs-windows.*`
4. Select `@timestamp` as the time field
5. Click **Save data view to Kibana**

### 3. View Events

1. In Discover, select the `logs-windows.*` data view
2. Set the time range to "Last 15 minutes"
3. You should see events appearing

### 4. Explore Event Fields

Key fields to examine:
- `winlog.event_id` - Windows event ID (4624, 4625, 4688, etc.)
- `winlog.channel` - Event channel (Security, System, Application)
- `winlog.computer_name` - Synthetic computer name
- `event.action` - Action description (logged-in, logon-failed, created-process, etc.)
- `event.outcome` - success or failure
- `user.name` - Username from the event
- `source.ip` - Source IP for network logons
- `labels.synthetic` - Always `true` for synthetic events

### 5. Filter Synthetic Events

To see only synthetic events, add a filter:
```
labels.synthetic: true
```

### 6. Example KQL Queries

**Failed logons:**
```
winlog.event_id: 4625
```

**Process creation events:**
```
winlog.event_id: 4688
```

**Events for a specific user:**
```
user.name: "john.doe"
```

**Security channel events:**
```
winlog.channel: "Security"
```

## Managing the Generator

### Upgrade with New Settings

```bash
helm upgrade windows-synthetic ./windows-synthetic-agent -n elastic \
    --set generator.eventsPerMinute=30 \
    --set generator.mode=continuous
```

### Stop the Generator

```bash
helm uninstall windows-synthetic -n elastic
```

### Restart the Generator

```bash
kubectl rollout restart deployment/windows-synthetic-windows-synthetic-agent -n elastic
```

## Configuration Options

Key values that can be customized in `values.yaml` or via `--set`:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `generator.eventsPerMinute` | Events generated per minute | 60 |
| `generator.mode` | `continuous` or `batch` | continuous |
| `generator.batchSize` | Events per batch (batch mode) | 100 |
| `generator.batchIntervalSeconds` | Pause between batches | 60 |
| `elasticsearch.host` | Elasticsearch URL | http://elasticsearch-master:9200 |
| `elasticsearch.username` | ES username | elastic |
| `elasticsearch.password` | ES password | elastic |

### Event Weights

Adjust the frequency of different event types in `values.yaml`:

```yaml
generator:
  eventWeights:
    security:
      logonSuccess: 50       # Event 4624
      logonFailure: 20       # Event 4625
      processCreation: 40    # Event 4688
      processTermination: 30 # Event 4689
      privilegeAssigned: 10  # Event 4672
      userCreated: 2         # Event 4720
      userDeleted: 1         # Event 4726
    system:
      information: 15        # Event 1
      serviceStarted: 5      # Event 6005
      serviceStopped: 5      # Event 6006
    application:
      error: 8               # Event 1000
      hang: 3                # Event 1001
      crash: 2               # Event 1002
```

### Synthetic Data

Customize computer names, users, IPs, and processes in `values.yaml`:

```yaml
generator:
  syntheticData:
    computerNames:
      - "WIN-DC01"
      - "WIN-WORKSTATION-01"
    users:
      - name: "admin"
        domain: "CORP"
        sid: "S-1-5-21-xxx-500"
    sourceIPs:
      - "192.168.1.100"
      - "10.0.0.50"
    processes:
      - path: "C:\\Windows\\System32\\cmd.exe"
        name: "cmd.exe"
```

## Troubleshooting

### Pod not starting

Check pod events:
```bash
kubectl describe pod -n elastic -l app=windows-synthetic-agent
```

### No events being indexed

1. Check generator logs for errors:
   ```bash
   kubectl logs -n elastic -l app=windows-synthetic-agent
   ```

2. Verify Elasticsearch is accessible:
   ```bash
   kubectl exec -n elastic -it <generator-pod> -- curl -u elastic:elastic http://elasticsearch-master:9200
   ```

3. Check if data streams exist:
   ```bash
   kubectl exec -n elastic -it elasticsearch-master-0 -- curl -s localhost:9200/_data_stream/logs-windows.*
   ```

### Permission errors

If you see pip permission errors, ensure the pod is running as root:
```yaml
podSecurityContext:
  runAsUser: 0
  fsGroup: 0
```
