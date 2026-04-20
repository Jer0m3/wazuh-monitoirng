#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

############################################
# CONFIG 
############################################

HOSTNAME_API="https://127.0.0.1"
API_PORT="55000"
LOGIN_ENDPOINT="/security/user/authenticate?raw=true"
: "${WAZUH_USER:?missing}"
: "${WAZUH_PASS:?missing}"

PUSHGATEWAY="https://metric.honeydock.de"
: "${PUSH_USER:?missing}"
: "${PUSH_PASS:?missing}"
JOB_NAME="wazuh_custom_metrics"
INSTANCE="$(hostname)"

INDEXER_URL="https://127.0.0.1:9200"
: "${INDEXER_USER:?missing}"
: "${INDEXER_PASS:?missing}"
############################################
# TYPE NORMALIZATION
############################################

normalize_value() {
    local val="${1:-0}"

    case "$val" in
        yes|true|True|TRUE) echo 1 ;;
        no|false|False|FALSE|null|"") echo 0 ;;
        *)
            if [[ "$val" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
                echo "$val"
            else
                echo 0
            fi
            ;;
    esac
}

############################################
# INDEXER STATUS MAPPING
############################################

map_indexer_status() {
    case "$1" in
        green) echo 2 ;;
        yellow) echo 1 ;;
        red) echo 0 ;;
        *) echo 0 ;;
    esac
}

############################################
# METRIC BUFFER
############################################

METRICS=""

add_metric() {
    local name="$1"
    local raw_value="${2:-0}"
    local labels="${3:-}"

    local value
    value=$(normalize_value "$raw_value")

    if [[ -n "$labels" ]]; then
        METRICS+="${name}{${labels}} ${value}"$'\n'
    else
        METRICS+="${name} ${value}"$'\n'
    fi
}

############################################
# AUTH
############################################

echo "[*] Authenticating..."

TOKEN=$(curl -s -k -u "$WAZUH_USER:$WAZUH_PASS" \
  -X POST "$HOSTNAME_API:$API_PORT$LOGIN_ENDPOINT")

if [[ -z "$TOKEN" ]]; then
    echo "[!] Authentication failed"
    exit 1
fi

AUTH_HEADER="Authorization: Bearer $TOKEN"

############################################
# SAFE API CALL
############################################

api_call() {
    local endpoint="$1"
    curl -s -k -H "$AUTH_HEADER" \
        --connect-timeout 5 \
        "$HOSTNAME_API:$API_PORT$endpoint"
}

############################################
# CLUSTER
############################################

echo "[*] Cluster metrics..."

cluster_json=$(api_call "/cluster/status")

add_metric "wazuh_cluster_enabled" \
  "$(jq -r '.data.enabled // 0' <<< "$cluster_json")"

add_metric "wazuh_cluster_running" \
  "$(jq -r '.data.running // 0' <<< "$cluster_json")"

############################################
# AGENTS
############################################

echo "[*] Agent overview..."

agent_json=$(api_call "/overview/agents")

add_metric "wazuh_agents_total" \
  "$(jq -r '.data.agent_status.connection.total // 0' <<< "$agent_json")"

add_metric "wazuh_agents_status" \
  "$(jq -r '.data.agent_status.connection.active // 0' <<< "$agent_json")" \
  'status="active"'

add_metric "wazuh_agents_status" \
  "$(jq -r '.data.agent_status.connection.disconnected // 0' <<< "$agent_json")" \
  'status="disconnected"'

add_metric "wazuh_agents_status" \
  "$(jq -r '.data.agent_status.connection.pending // 0' <<< "$agent_json")" \
  'status="pending"'

add_metric "wazuh_agents_status" \
  "$(jq -r '.data.agent_status.connection.never_connected // 0' <<< "$agent_json")" \
  'status="never_connected"'

add_metric "wazuh_agents_config_status" \
  "$(jq -r '.data.agent_status.configuration.synced // 0' <<< "$agent_json")" \
  'config="synced"'

add_metric "wazuh_agents_config_status" \
  "$(jq -r '.data.agent_status.configuration.not_synced // 0' <<< "$agent_json")" \
  'config="not_synced"'

############################################
# GROUPS
############################################

echo "[*] Group metrics..."

group_json=$(api_call "/groups")

add_metric "wazuh_groups_total" \
  "$(jq -r '.data.affected_items | length // 0' <<< "$group_json")"

############################################
# ANALYSISD
############################################

echo "[*] Analysisd metrics..."

analysis_json=$(api_call "/manager/stats/analysisd")

jq -r '.data.affected_items[0] // {} | to_entries[] | "\(.key) \(.value)"' \
  <<< "$analysis_json" |
while read -r key value; do
    add_metric "wazuh_analysisd_${key}" "$value"
done

############################################
# INDEXER (OpenSearch) CLUSTER HEALTH
############################################

echo "[*] Indexer cluster health..."

health_json=$(curl -s -k -u "$INDEXER_USER:$INDEXER_PASS" \
    --connect-timeout 5 \
    "$INDEXER_URL/_cluster/health")

cluster_status_raw=$(jq -r '.status // "red"' <<< "$health_json")
cluster_status_numeric=$(map_indexer_status "$cluster_status_raw")

# Numerische Health Metric
add_metric "wazuh_indexer_cluster_status" "$cluster_status_numeric"

# Status als Info-Label
add_metric "wazuh_indexer_cluster_status_info" 1 \
  "status=\"$cluster_status_raw\""

# Node Count
add_metric "wazuh_indexer_number_of_nodes" \
  "$(jq -r '.number_of_nodes // 0' <<< "$health_json")"

# Shard Metrics
add_metric "wazuh_indexer_active_primary_shards" \
  "$(jq -r '.active_primary_shards // 0' <<< "$health_json")"

add_metric "wazuh_indexer_active_shards" \
  "$(jq -r '.active_shards // 0' <<< "$health_json")"

add_metric "wazuh_indexer_relocating_shards" \
  "$(jq -r '.relocating_shards // 0' <<< "$health_json")"

add_metric "wazuh_indexer_initializing_shards" \
  "$(jq -r '.initializing_shards // 0' <<< "$health_json")"

add_metric "wazuh_indexer_unassigned_shards" \
  "$(jq -r '.unassigned_shards // 0' <<< "$health_json")"

add_metric "wazuh_indexer_delayed_unassigned_shards" \
  "$(jq -r '.delayed_unassigned_shards // 0' <<< "$health_json")"


############################################
# INTERNAL HEALTH METRIC
############################################

add_metric "wazuh_exporter_up" 1

############################################
# PROMETHEUS FORMAT
############################################

PROM_OUTPUT=""

while read -r line; do
    metric_name=$(awk '{print $1}' <<< "$line" | cut -d'{' -f1)

    if ! grep -q "# HELP ${metric_name}" <<< "$PROM_OUTPUT"; then
        PROM_OUTPUT+="# HELP ${metric_name} Wazuh metric\n"
        PROM_OUTPUT+="# TYPE ${metric_name} gauge\n"
    fi

    PROM_OUTPUT+="$line\n"
done <<< "$METRICS"

############################################
# PUSH
############################################

echo "[*] Pushing to PushGateway..."

printf "%b" "$PROM_OUTPUT" | \
curl -s -u "$PUSH_USER:$PUSH_PASS" \
  --data-binary @- \
  "$PUSHGATEWAY/metrics/job/$JOB_NAME/instance/$INSTANCE"

echo "[✓] Done."
