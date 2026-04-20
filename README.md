# Wazuh Custom Metrics Exporter

Lightweight Bash-based monitoring script for a single-node Wazuh instance.
Collects operational metrics via the Wazuh API and OpenSearch, then exposes them in Prometheus format via a PushGateway.

## Configuration:

edit the exsiting environment file (wazuh-monitor.env)
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
