#!/bin/bash
set -e

# Fix Qt locale requirement - Qt6 requires UTF-8 locale
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US:en

# Ensure driver, logs, and IPC socket directories exist with correct permissions
mkdir -p /opt/tableau/tableau_driver/jdbc /root/Documents/My_Tableau_Bridge_Repository/Logs /tmp/tableau-temp/LD/domain
chmod 777 /tmp/tableau-temp /tmp/tableau-temp/LD /tmp/tableau-temp/LD/domain 2>/dev/null || true

echo "========================================================"
echo " Starting Tableau Bridge HA Client Container"
echo " Container Hostname: ${HOSTNAME:-$(uname -n)}"
echo "========================================================"

# Validate Mandatory Environment Variables
if [ -z "$TABLEAU_SERVER_URL" ] || [ -z "$TABLEAU_SITE_NAME" ] || [ -z "$PAT_NAME" ] || [ -z "$PAT_SECRET" ] || [ -z "$POOL_ID" ]; then
  echo "[ERROR] Missing required environment variables!"
  echo "Required variables:"
  echo "  - TABLEAU_SERVER_URL (e.g. https://prod-ap-northeast-1.online.tableau.com)"
  echo "  - TABLEAU_SITE_NAME (Site URL name)"
  echo "  - PAT_NAME (Personal Access Token Name/ID)"
  echo "  - PAT_SECRET (Personal Access Token Secret)"
  echo "  - POOL_ID (Tableau Bridge Pool ID)"
  exit 1
fi

CLIENT_NAME="${CLIENT_NAME_PREFIX:-tb-bridge-k8s}-${HOSTNAME:-$(uname -n)}"
USER_EMAIL="${TABLEAU_USER_EMAIL:-admin@example.com}"

echo "Site URL:        ${TABLEAU_SERVER_URL}"
echo "Site Name:       ${TABLEAU_SITE_NAME}"
echo "User Email:      ${USER_EMAIL}"
echo "Pool ID:         ${POOL_ID}"
echo "Client Name:     ${CLIENT_NAME}"

# Write PAT token as JSON file: {"<PAT_NAME>": "<PAT_SECRET>"}
# TabBridgeClientCmd v2026+ expects JSON format where the PAT name is the key
PAT_FILE="/tmp/pat_token.json"
printf '{ "%s": "%s" }' "${PAT_NAME}" "${PAT_SECRET}" > "${PAT_FILE}"
chmod 600 "${PAT_FILE}"

# Locate Tableau Bridge binaries
CMD_PATH="/opt/tableau/tableau_bridge/bin/TabBridgeClientCmd"
WORKER_PATH="/opt/tableau/tableau_bridge/bin/TabBridgeClientWorker"

if [ ! -f "${CMD_PATH}" ] || [ ! -f "${WORKER_PATH}" ]; then
  echo "[ERROR] Tableau Bridge executables not found in /opt/tableau/tableau_bridge/bin/"
  exit 1
fi

echo "Configuring Tableau Cloud service URL..."
"${CMD_PATH}" setServiceConnection \
  --service="${TABLEAU_SERVER_URL}" \
  --ignoreCertificatesErrors=false \
  --connectionConnectTimeout=30

# Launch Tableau Minerva service (required for query federation / live data protocol)
MINERVA_BIN=$(find /opt/tableau/ -name tabminerva 2>/dev/null | head -n 1)
MINERVA_CFG="/opt/tableau/tableau_bridge/config/MinervaBridge.yml"

if [ -f "${MINERVA_BIN}" ] && [ -f "${MINERVA_CFG}" ]; then
  echo "Launching Tableau Minerva query engine..."
  "${MINERVA_BIN}" -paramFile:"${MINERVA_CFG}" &
  export SERVICE_NAME=minerva
fi

# TabBridgeClientWorker -e is the correct binary for running Bridge as embedded service.
# TabBridgeClientCmd tokenLogin fails with IThreadContext assertion under container environments.
echo "Launching Tableau Bridge Worker service..."

exec "${WORKER_PATH}" -e \
  --client="${CLIENT_NAME}" \
  --site="${TABLEAU_SITE_NAME}" \
  --userEmail="${USER_EMAIL}" \
  --patTokenId="${PAT_NAME}" \
  --patTokenFile="${PAT_FILE}" \
  --poolId="${POOL_ID}"
