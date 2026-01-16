# Windows Synthetic Agent Helm Chart

This Helm chart deploys a synthetic Windows event log generator with an Elastic Agent to simulate Windows event data in environments without actual Windows machines.

## Overview

The chart deploys a single pod with two containers:
1. **Windows Event Generator** - Python sidecar that generates fake Windows event logs
2. **Elastic Agent** - Reads the generated logs and ships them to Elasticsearch

## Prerequisites

- Kubernetes cluster with Helm 3.x
- Elastic Stack deployed (Elasticsearch, Kibana, optionally Fleet Server)
- Required images pre-loaded in local registry (for air-gapped environments):
  - `localhost:5000/elastic-agent/elastic-agent:9.2.3`
  - `localhost:5000/library/python:3.11-slim`
  - `localhost:5000/library/busybox:1.36`

## Quick Start

### 1. Load Required Images (Air-gapped)

On an internet-connected machine:
```bash
docker pull python:3.11-slim
docker tag python:3.11-slim localhost:5000/library/python:3.11-slim
docker save localhost:5000/library/python:3.11-slim -o python-slim.tar

docker pull busybox:1.36
docker tag busybox:1.36 localhost:5000/library/busybox:1.36
docker save localhost:5000/library/busybox:1.36 -o busybox.tar
```

On the air-gapped machine:
```bash
docker load -i python-slim.tar
docker push localhost:5000/library/python:3.11-slim

docker load -i busybox.tar
docker push localhost:5000/library/busybox:1.36
```

### 2. Deploy the Chart

```bash
cd helm_charts
helm install windows-synthetic ./windows-synthetic-agent -n elastic
```

### 3. Verify Deployment

```bash
# Check pod status
kubectl get pods -n elastic | grep windows-synthetic

# View generator logs
kubectl logs -n elastic -l app=windows-synthetic-agent -c windows-event-generator

# View agent logs
kubectl logs -n elastic -l app=windows-synthetic-agent -c elastic-agent
```

### 4. View Data in Kibana

1. Go to Kibana > Discover
2. Create index pattern: `logs-windows.synthetic-*`
3. Search for events with `winlog.event_id` field

## Events Generated

| Event ID | Channel | Description |
|----------|---------|-------------|
| 4624 | Security | Successful logon |
| 4625 | Security | Failed logon |
| 4688 | Security | Process creation |
| 4689 | Security | Process termination |
| 4672 | Security | Special privileges assigned |
| 4720 | Security | User account created |
| 4726 | Security | User account deleted |
| 1 | System | System resumed |
| 6005 | System | Event log service started |
| 6006 | System | Event log service stopped |
| 1000 | Application | Application error |
| 1001 | Application | Application hang |
| 1002 | Application | Application crash |

## Configuration

### Key Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `generator.mode` | Generation mode: `continuous` or `batch` | `continuous` |
| `generator.eventsPerSecond` | Events per second (continuous mode) | `5` |
| `generator.batchSize` | Events per batch (batch mode) | `100` |
| `generator.eventWeights` | Relative weights for event types | See values.yaml |
| `generator.syntheticData.computerNames` | Computer names to use | 5 synthetic names |
| `generator.syntheticData.users` | User accounts for events | 4 synthetic users |
| `generator.syntheticData.sourceIPs` | Source IPs for logon events | 5 IPs |
| `generator.syntheticData.processes` | Processes for creation events | 5 processes |
| `elasticsearch.host` | Elasticsearch endpoint | `http://elasticsearch-master:9200` |
| `elasticsearch.username` | Elasticsearch username | `elastic` |
| `elasticsearch.password` | Elasticsearch password | `elastic` |
| `fleet.enabled` | Use Fleet-managed mode | `false` |
| `fleet.enrollmentToken` | Fleet enrollment token | `""` |

### Example: Custom Event Rate

```yaml
# values-custom.yaml
generator:
  eventsPerSecond: 10
  eventWeights:
    security:
      logonSuccess: 100
      logonFailure: 50
```

Deploy with:
```bash
helm install windows-synthetic ./windows-synthetic-agent -n elastic -f values-custom.yaml
```

### Example: Fleet-Managed Mode

```yaml
# values-fleet.yaml
fleet:
  enabled: true
  url: "http://fleet-server:8220"
  enrollmentToken: "YOUR_ENROLLMENT_TOKEN"
  insecure: true
```

## Architecture

```
+--------------------------------------------------+
|                    Pod                           |
|  +---------------------+  +-------------------+  |
|  |  windows-event-gen  |  |   elastic-agent   |  |
|  |  (Python sidecar)   |  |   (filestream)    |  |
|  |                     |  |                   |  |
|  |  Writes NDJSON to   |  |  Reads from       |  |
|  |  shared volume      |  |  shared volume    |  |
|  +----------+----------+  +--------+----------+  |
|             |                      |             |
|             v                      v             |
|  +------------------------------------------+   |
|  |          EmptyDir Volume (500Mi)         |   |
|  |     /var/log/windows-synthetic/          |   |
|  +------------------------------------------+   |
+--------------------------------------------------+
                         |
                         v
              +--------------------+
              |   Elasticsearch    |
              | (logs-windows.*)   |
              +--------------------+
```

## Data Format

Generated events follow the ECS schema with `winlog.*` fields:

```json
{
  "@timestamp": "2024-01-15T10:30:45.123Z",
  "event": {
    "kind": "event",
    "category": ["authentication"],
    "type": ["start"],
    "action": "logged-in",
    "outcome": "success",
    "code": "4624"
  },
  "winlog": {
    "event_id": 4624,
    "channel": "Security",
    "provider_name": "Microsoft-Windows-Security-Auditing",
    "computer_name": "WIN-SYNTHETIC-001",
    "event_data": { ... }
  },
  "user": {
    "name": "john.doe",
    "domain": "SYNTHETIC"
  },
  "labels": {
    "synthetic": true,
    "source": "windows-synthetic-generator"
  }
}
```

## Filtering Synthetic Data

All generated events include labels for easy identification:
- `labels.synthetic: true`
- `labels.source: windows-synthetic-generator`

In Kibana, you can filter:
- **Include synthetic**: `labels.synthetic: true`
- **Exclude synthetic**: `NOT labels.synthetic: true`

## Troubleshooting

### Generator not producing events

Check generator logs:
```bash
kubectl logs -n elastic -l app=windows-synthetic-agent -c windows-event-generator
```

### Agent not shipping data

1. Check agent logs:
```bash
kubectl logs -n elastic -l app=windows-synthetic-agent -c elastic-agent
```

2. Verify Elasticsearch connectivity:
```bash
kubectl exec -n elastic -it <pod-name> -c elastic-agent -- curl -u elastic:elastic http://elasticsearch-master:9200
```

### No data in Kibana

1. Check the index exists:
```bash
curl -u elastic:elastic http://localhost:9200/_cat/indices?v | grep windows
```

2. Verify data stream:
```bash
curl -u elastic:elastic http://localhost:9200/logs-windows.synthetic-default/_search?size=1
```

## Uninstall

```bash
helm uninstall windows-synthetic -n elastic
```
