#!/usr/bin/env bash
set -euo pipefail

# Default values
CLUSTER_NAME="kubernetes"
OUTPUT_DIR="./kubeconfigs"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -r, --role <name>         Role name (e.g. admin, kubelet, controller-manager) [required]
  -s, --server <url>        Kubernetes API server URL (e.g. https://10.0.0.1:6443) [required]
  -c, --cert-dir <path>     Directory containing certificates and keys [required]
  -a, --ca-name <name>      Name of the CA certificate/key pair (without .crt/.key) [required]
  -n, --cluster-name <name> Cluster name (default: kubernetes)
  -o, --output-dir <path>   Output directory for kubeconfig (default: ./kubeconfigs)
  -h, --help                Show this help message

Example:
  $0 -r admin -s https://192.168.122.210:6443 -c ./pki -a k8s-ca -o ./out -n mycluster
EOF
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role) ROLE="$2"; shift 2 ;;
    -s|--server) SERVER="$2"; shift 2 ;;
    -c|--cert-dir) CERT_DIR="$2"; shift 2 ;;
    -a|--ca-name) CA_NAME="$2"; shift 2 ;;
    -n|--cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
    -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

# Validate required arguments
if [[ -z "${ROLE:-}" || -z "${SERVER:-}" || -z "${CERT_DIR:-}" || -z "${CA_NAME:-}" ]]; then
  echo "[ERROR] Missing required arguments."
  usage
fi

# Paths
mkdir -p "$OUTPUT_DIR"
CA_CERT="${CERT_DIR}/${CA_NAME}.crt"
CLIENT_CERT="${CERT_DIR}/${ROLE}.crt"
CLIENT_KEY="${CERT_DIR}/${ROLE}.key"
OUTPUT_FILE="${OUTPUT_DIR}/${ROLE}.kubeconfig"

# Validate files
for f in "$CA_CERT" "$CLIENT_CERT" "$CLIENT_KEY"; do
  if [[ ! -f "$f" ]]; then
    echo "[ERROR] Missing required file: $f"
    exit 1
  fi
done

USER_NAME="${ROLE}"
CONTEXT_NAME="${ROLE}@${CLUSTER_NAME}"

echo "[INFO] Generating kubeconfig for role '${ROLE}' → ${OUTPUT_FILE}"
echo "[INFO] Cluster: ${CLUSTER_NAME}"
echo "[INFO] Server: ${SERVER}"
echo "[INFO] Using CA: ${CA_NAME}"

kubectl config set-cluster "${CLUSTER_NAME}" \
  --certificate-authority="${CA_CERT}" \
  --embed-certs=true \
  --server="${SERVER}" \
  --kubeconfig="${OUTPUT_FILE}"

kubectl config set-credentials "${USER_NAME}" \
  --client-certificate="${CLIENT_CERT}" \
  --client-key="${CLIENT_KEY}" \
  --embed-certs=true \
  --kubeconfig="${OUTPUT_FILE}"

kubectl config set-context "${CONTEXT_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --user="${USER_NAME}" \
  --kubeconfig="${OUTPUT_FILE}"

kubectl config use-context "${CONTEXT_NAME}" \
  --kubeconfig="${OUTPUT_FILE}"

echo "[OK] Kubeconfig generated at: ${OUTPUT_FILE}"
