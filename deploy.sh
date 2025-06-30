#!/bin/bash

# ==============================================================================
# Traefik Deployment Script
# ==============================================================================
#
# Description:
#   This script deploys the Traefik reverse proxy using Docker.
#   It uses an external .env file for all configuration, which is passed
#   directly to the container.
#
# Pre-requisites:
#   - Docker installed and running.
#   - A .env file located at '../secrets/traefik.env'.
#   - A 'traefik.yml' configuration file in the same directory as this script.
#
# Usage:
#   ./deploy.sh
#
# ==============================================================================

# --- Configuration ---

# Set the path to the environment file.
# The script expects it to be in a 'secrets' directory one level above.
ENV_FILE="../secrets/traefik.env"

# --- Pre-flight Checks ---

# Check if the .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Environment file not found at $ENV_FILE"
    echo "Please create it and define the necessary variables."
    exit 1
fi

# Source the environment variables locally for the script's checks.
# Note: The --env-file flag will be used to pass these to the container.
source "$ENV_FILE"

# Check for essential variables within the script
if [ -z "$TRAEFIK_CONTAINER_NAME" ] || [ -z "$TRAEFIK_IMAGE" ] || [ -z "$TRAEFIK_WEB_PORT" ] || [ -z "$TRAEFIK_WEBSECURE_PORT" ] || [ -z "$TRAEFIK_METRICS_PORT" ] || [ -z "$ACME_EMAIL" ]; then
    echo "Error: One or more essential environment variables are not set in $ENV_FILE."
    exit 1
fi

# --- Main Logic ---

echo "Starting Traefik deployment..."

# Create the Docker network if it doesn't exist.
# This network will be used by Traefik and the services it routes to.
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || echo "Network '$TRAEFIK_NETWORK' already exists."

# Create the acme.json file for Let's Encrypt certificates
# and set the correct permissions (readable/writable only by the owner).
echo "Creating acme.json for Let's Encrypt..."
touch acme.json
chmod 600 acme.json

# Stop and remove any existing container with the same name to ensure a clean start.
echo "Checking for existing Traefik container..."
if [ "$(docker ps -q -f name="$TRAEFIK_CONTAINER_NAME")" ]; then
    echo "Stopping and removing existing container: $TRAEFIK_CONTAINER_NAME"
    docker stop "$TRAEFIK_CONTAINER_NAME"
    docker rm "$TRAEFIK_CONTAINER_NAME"
fi

# Pull the latest version of the Traefik image
echo "Pulling the Traefik image: $TRAEFIK_IMAGE..."
docker pull "$TRAEFIK_IMAGE"

# Run the Traefik container
echo "Deploying Traefik container: $TRAEFIK_CONTAINER_NAME..."

docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart always \
  --network "$TRAEFIK_NETWORK" \
  --env-file "$ENV_FILE" \
  -p "$TRAEFIK_WEB_PORT":80 \
  -p "$TRAEFIK_WEBSECURE_PORT":443 \
  -p "$TRAEFIK_METRICS_PORT":9100 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$(pwd)/acme.json":/acme.json \
  -v "$(pwd)/traefik.yml":/etc/traefik/traefik.yml:ro \
  "$TRAEFIK_IMAGE"

# --- Post-deployment ---

echo ""
echo "Traefik deployment completed successfully!"
echo "-----------------------------------------"
echo "Container Name: $TRAEFIK_CONTAINER_NAME"
echo "Dashboard (API): http://localhost:8080"
echo "Metrics (Prometheus): http://localhost:$TRAEFIK_METRICS_PORT/metrics"
echo "Web Entrypoint (HTTP): Port $TRAEFIK_WEB_PORT"
echo "Websecure Entrypoint (HTTPS): Port $TRAEFIK_WEBSECURE_PORT"
echo "-----------------------------------------"

