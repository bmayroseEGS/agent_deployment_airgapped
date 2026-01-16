# Windows Synthetic Agent Example

This example demonstrates a high-volume Windows security event simulation with diverse users, computers, and processes.

## Overview

This configuration:
- Generates **10 events per second** (vs default 5)
- Focuses on **security events** (logon success/failure, process creation)
- Includes **more diverse synthetic data**:
  - 10 computer names (domain controllers, web servers, workstations)
  - 8 user accounts (including service accounts and an "attacker")
  - 10 source IPs (internal and external/suspicious)
  - 10 process types (including potentially suspicious ones like whoami, net)

## Deployment

```bash
# From the helm_charts directory
helm install windows-synthetic ./windows-synthetic-agent \
  -n elastic \
  -f ../examples/windows-synthetic/values-windows-synthetic.yaml
```

## Use Cases

### Security Monitoring Testing

This configuration is ideal for testing:
- **SIEM rules** - Detection rules for failed logins, suspicious processes
- **Anomaly detection** - Unusual logon patterns or process executions
- **Dashboards** - Windows security dashboards and visualizations

### Example Queries in Kibana

**Failed Logons from External IPs:**
```kql
winlog.event_id: 4625 AND source.ip: (203.0.113.* OR 198.51.100.*)
```

**Suspicious Process Execution:**
```kql
winlog.event_id: 4688 AND process.name: (whoami.exe OR net.exe OR powershell.exe)
```

**Privilege Escalation:**
```kql
winlog.event_id: 4672 AND user.name: NOT (SYSTEM OR administrator)
```

**User Account Changes:**
```kql
winlog.event_id: (4720 OR 4726)
```

## Customization

### Increase Event Volume

```yaml
generator:
  eventsPerSecond: 20
```

### Add More Suspicious Activity

```yaml
generator:
  eventWeights:
    security:
      logonFailure: 100  # More failed logins
      processCreation: 80
```

### Add Custom Users

```yaml
generator:
  syntheticData:
    users:
      - name: "your.user"
        domain: "YOURDOMAIN"
        sid: "S-1-5-21-xxx-xxx-xxx-xxxx"
```

## Expected Data Volume

At 10 events/second:
- ~600 events/minute
- ~36,000 events/hour
- ~864,000 events/day

Adjust `generator.eventsPerSecond` based on your testing needs and Elasticsearch capacity.
