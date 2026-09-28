#!/bin/bash
set -e

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

# Write PAT secret to a temporary file as required by TabBridgeClientCmd tokenLogin
PAT_FILE="/tmp/pat_token.txt"
echo -n "${PAT_SECRET}" > "${PAT_FILE}"
chmod 600 "${PAT_FILE}"

# Locate Tableau Bridge binary
BIN_PATH=""
if [ -f "/opt/tableau/tableau_bridge/bin/TabBridgeClientCmd" ]; then
  BIN_PATH="/opt/tableau/tableau_bridge/bin/TabBridgeClientCmd"
elif [ -f "/opt/tableau/tableau_bridge/bin/tableau-bridge-cli" ]; then
  BIN_PATH="/opt/tableau/tableau_bridge/bin/tableau-bridge-cli"
else
  echo "[ERROR] Tableau Bridge executable not found in /opt/tableau/tableau_bridge/bin/"
  exit 1
fi

echo "Launching Tableau Bridge process via tokenLogin..."

exec "${BIN_PATH}" tokenLogin -e \
  --client "${CLIENT_NAME}" \
  --site "${TABLEAU_SITE_NAME}" \
  --userEmail "${USER_EMAIL}" \
  --patTokenId "${PAT_NAME}" \
  --patTokenFile "${PAT_FILE}" \
  --poolId "${POOL_ID}"
