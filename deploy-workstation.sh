#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "Error: .env file not found at ${ENV_FILE}" >&2
  exit 1
fi

# Load variables from .env
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

REPO_NAME="${REPO_NAME:-containers}"
IMAGE_NAME="${IMAGE_NAME:-selkies-antigravity}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-8}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:latest"

# Resolve default Compute Engine service account dynamically if not provided in .env
if [ -z "${SERVICE_ACCOUNT:-}" ]; then
  PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")"
  SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi

echo "=== Configuration (.env) ==="
echo "PROJECT_ID       : ${PROJECT_ID}"
echo "REGION           : ${REGION}"
echo "CLUSTER          : ${CLUSTER}"
echo "CONFIG_NAME      : ${CONFIG_NAME}"
echo "WORKSTATION_NAME : ${WORKSTATION_NAME}"
echo "IMAGE_URI        : ${IMAGE_URI}"
echo "SERVICE_ACCOUNT  : ${SERVICE_ACCOUNT}"
echo "============================"

echo "0. Checking Cloud Workstations Cluster (${CLUSTER})..."
if ! gcloud workstations clusters describe "${CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Cluster ${CLUSTER} not found. Creating cluster ${CLUSTER}..."
  gcloud workstations clusters create "${CLUSTER}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --network="projects/${PROJECT_ID}/global/networks/default" \
    --subnetwork="projects/${PROJECT_ID}/regions/${REGION}/subnetworks/default"
fi

echo "1. Building and pushing container image via Cloud Build..."
gcloud builds submit \
  --config="${SCRIPT_DIR}/cloudbuild.yaml" \
  --project="${PROJECT_ID}" \
  --substitutions="_REGION=${REGION},_REPO_NAME=${REPO_NAME},_IMAGE_NAME=${IMAGE_NAME}" \
  "${SCRIPT_DIR}"

echo "2. Creating Cloud Workstations Configuration (${CONFIG_NAME})..."
ACCESS_TOKEN="$(gcloud auth print-access-token)"
curl -s -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://workstations.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/workstationClusters/${CLUSTER}/workstationConfigs?workstationConfigId=${CONFIG_NAME}" \
  -d "{
    \"host\": {
      \"gceInstance\": {
        \"machineType\": \"${MACHINE_TYPE}\",
        \"serviceAccount\": \"${SERVICE_ACCOUNT}\",
        \"poolSize\": 0,
        \"bootDiskSizeGb\": 50,
        \"disablePublicIpAddresses\": false
      }
    },
    \"container\": {
      \"image\": \"${IMAGE_URI}\",
      \"runAsUser\": 0,
      \"env\": {
        \"CUSTOM_PORT\": \"80\",
        \"PIXELFLUX_WAYLAND\": \"true\",
        \"SELKIES_ENCODER\": \"x264enc,jpeg\",
        \"LANG\": \"ko_KR.UTF-8\",
        \"LC_ALL\": \"ko_KR.UTF-8\"
      }
    },
    \"idleTimeout\": \"7200s\",
    \"runningTimeout\": \"43200s\"
  }"

echo ""
echo "Waiting for Configuration (${CONFIG_NAME}) to finish reconciling..."
for _ in $(seq 1 30); do
  RECON="$(gcloud workstations configs describe "${CONFIG_NAME}" --cluster="${CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}" --format="value(reconciling)" 2>/dev/null || echo "true")"
  if [ -z "${RECON}" ]; then
    break
  fi
  sleep 5
done

echo "3. Creating and starting Workstation (${WORKSTATION_NAME})..."
gcloud workstations create "${WORKSTATION_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --cluster="${CLUSTER}" \
  --config="${CONFIG_NAME}" || true

gcloud workstations start "${WORKSTATION_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --cluster="${CLUSTER}" \
  --config="${CONFIG_NAME}"

HOST="$(gcloud workstations describe "${WORKSTATION_NAME}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --cluster="${CLUSTER}" \
  --config="${CONFIG_NAME}" \
  --format="value(host)")"

echo ""
echo "=== Deployment Complete ==="
echo "Workstation URL: https://80-${HOST}/"
