#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-europe-west1}"
BACKEND_SERVICE="${BACKEND_SERVICE:-ludo-websocket-backend}"
WEB_SERVICE="${WEB_SERVICE:-ludo-world-web}"
ARTIFACT_REPOSITORY="${ARTIFACT_REPOSITORY:-cloud-run-source-deploy}"
SQL_INSTANCE="${SQL_INSTANCE:-ludo-world-free3:us-central1:lodu-postgres-instance}"
DATABASE_NAME="${DATABASE_NAME:-ludo}"
DATABASE_USER_SECRET="${DATABASE_USER_SECRET:-db-user}"
DATABASE_PASSWORD_SECRET="${DATABASE_PASSWORD_SECRET:-db-password}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "Set PROJECT_ID or configure a default project with gcloud config." >&2
  exit 1
fi

gcloud config set project "$PROJECT_ID"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  sqladmin.googleapis.com

gcloud artifacts repositories describe "$ARTIFACT_REPOSITORY" \
  --location="$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$ARTIFACT_REPOSITORY" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run application images"

JDBC_URL="jdbc:postgresql:///${DATABASE_NAME}?cloudSqlInstance=${SQL_INSTANCE}&socketFactory=com.google.cloud.sql.postgres.SocketFactory"

gcloud run deploy "$BACKEND_SERVICE" \
  --source=backend \
  --region="$REGION" \
  --platform=managed \
  --min=1 \
  --max=1 \
  --allow-unauthenticated \
  --add-cloudsql-instances="$SQL_INSTANCE" \
  --set-env-vars="SPRING_PROFILES_ACTIVE=prod,SPRING_DATASOURCE_URL=${JDBC_URL},APP_CORS_ALLOWED_ORIGINS=*" \
  --set-secrets="SPRING_DATASOURCE_USERNAME=${DATABASE_USER_SECRET}:latest,SPRING_DATASOURCE_PASSWORD=${DATABASE_PASSWORD_SECRET}:latest"

BACKEND_URL="$(gcloud run services describe "$BACKEND_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')"
API_BASE_URL="${BACKEND_URL}/api/v1"
WEBSOCKET_URL="${BACKEND_URL/https:/wss:}/ws"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPOSITORY}/${WEB_SERVICE}:$(date -u +%Y%m%d%H%M%S)"

gcloud builds submit mobile \
  --config=mobile/cloudbuild.yaml \
  --substitutions="_API_BASE_URL=${API_BASE_URL},_WEBSOCKET_URL=${WEBSOCKET_URL},_IMAGE_URI=${IMAGE_URI}"

gcloud run deploy "$WEB_SERVICE" \
  --image="$IMAGE_URI" \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated

WEB_URL="$(gcloud run services describe "$WEB_SERVICE" \
  --region="$REGION" \
  --format='value(status.url)')"

echo "Backend: ${BACKEND_URL}"
echo "Web app: ${WEB_URL}"
echo "Set WEB_URL as a trusted OAuth redirect/origin in each provider console where needed."
