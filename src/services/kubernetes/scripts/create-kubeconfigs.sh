#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-}"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Usage: $0 <config.json>"
  exit 1
fi

if ! command -v jq &>/dev/null || ! command -v kubectl &>/dev/null; then
  echo "Missing dependencies: install jq and kubectl"
  exit 1
fi

CONFIG_JSON="$(< "$CONFIG_FILE")"

CLUSTER_NAME=$(echo "$CONFIG_JSON" | jq -r '.cluster.name')
CLUSTER_SERVER=$(echo "$CONFIG_JSON" | jq -r '.cluster.server')
CLUSTER_CA_CERT=$(echo "$CONFIG_JSON" | jq -r '.cluster.caCert')

create_kubeconfig() {
  local ROLE=$1
  local USER_NAME=$(echo "$CONFIG_JSON" | jq -r ".${ROLE}.user // empty")
  local CERT_FILE=$(echo "$CONFIG_JSON" | jq -r ".${ROLE}.cert // empty")
  local KEY_FILE=$(echo "$CONFIG_JSON" | jq -r ".${ROLE}.key // empty")
  local KUBECONFIG_FILE="${ROLE}.kubeconfig"

  if [[ -z "$USER_NAME" || -z "$CERT_FILE" || -z "$KEY_FILE" ]]; then
    echo "[INFO] Skipping $ROLE: incomplete or missing config"
    return
  fi

  echo "[INFO] Generating kubeconfig for $ROLE → $KUBECONFIG_FILE"

  kubectl config set-cluster "$CLUSTER_NAME" \
    --certificate-authority="$CLUSTER_CA_CERT" \
    --embed-certs=true \
    --server="$CLUSTER_SERVER" \
    --kubeconfig="$KUBECONFIG_FILE"

  kubectl config set-credentials "$USER_NAME" \
    --client-certificate="$CERT_FILE" \
    --client-key="$KEY_FILE" \
    --embed-certs=true \
    --kubeconfig="$KUBECONFIG_FILE"

  kubectl config set-context "$ROLE-context" \
    --cluster="$CLUSTER_NAME" \
    --user="$USER_NAME" \
    --kubeconfig="$KUBECONFIG_FILE"

  kubectl config use-context "$ROLE-context" --kubeconfig="$KUBECONFIG_FILE"

  echo "[OK] Created $KUBECONFIG_FILE"
}

# Create configs if present
create_kubeconfig "kubelet"
create_kubeconfig "kube-proxy"
create_kubeconfig "kube-controller-manager"
create_kubeconfig "kube-scheduler"
create_kubeconfig "admin"
