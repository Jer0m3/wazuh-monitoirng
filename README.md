# Wazuh Custom Metrics Exporter

Lightweight Bash-based monitoring script for a single-node Wazuh instance.
Collects operational metrics via the Wazuh API and OpenSearch, then exposes them in Prometheus format via a PushGateway.

## Configuration:

edit the exsiting environment file (wazuh-monitor.env)

 * The Wazuh user ia an user for the Wazuh API. The user needs readall permissions
  
 * The push user is an user for the Pushgateway
  
 * The Indexer User is an user for the Opensearch API
  

edit the pushgateway URL in the file: 'wazuh-monitor.sh'



# Installation (systemd)

Service:
```
sudo nano /etc/systemd/system/wazuh-monitor.service
```
Copy into: /etc/systemd/system/wazuh-monitor.service
```
[Unit]
Description=Wazuh Monitoring Script

[Service]
Type=oneshot
EnvironmentFile=/root/wazuh-monitor.env
ExecStart=/root/monitor.sh
```

Create timer:

```
sudo nano /etc/systemd/system/wazuh-monitor.timer
```

Copy into: /etc/systemd/system/wazuh-monitor.timer

```
[Unit]
Description=Run Wazuh Monitor every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=wazuh-monitor.service

[Install]
WantedBy=timers.target
```

enable Service:

```
sudo systemctl daemon-reexec
sudo systemctl daemon-reload

sudo systemctl enable --now wazuh-monitor.timer
```
# normal Console Output when running the script
```
[*] Authenticating...
[*] Cluster metrics...
[*] Agent overview...
[*] Group metrics...
[*] Analysisd metrics...
[*] Indexer cluster health...
[*] Pushing to PushGateway...
[✓] Done.
```

# Notes
Designed for single-node setups
Uses PushGateway (push model, not scrape-based)
TLS verification is disabled by default (-k)
Requires curl and jq

# Security

Restrict access to credentials:
```
chmod 600 /root/wazuh-monitor.env
```
