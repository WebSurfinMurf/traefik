#!/bin/bash

# ==============================================================================
# Traefik Deployment Script
# ==============================================================================
#
# Description:
#   This script deploys the Traefik reverse proxy using Docker.
#   It sources configuration variables from an external .env file to make
#   the deployment flexible and keep sensitive data out of the script.
#
# Pre-requisites:
#   - Docker installed and running.
#   - A .env file located at '../secrets/traefik.env' with the required
#     variables defined.
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

# Source the environment variables
# The `set -a` command exports all variables defined in the sourced file.
set -a
source "$ENV_FILE"
set +a

# Check for essential variables
if [ -z "$TRAEFIK_CONTAINER_NAME" ] || [ -z "$TRAEFIK_IMAGE" ] || [ -z "$TRAEFIK_WEB_PORT" ] || [ -z "$TRAEFIK_WEBSECURE_PORT" ]; then
    echo "Error: One or more essential environment variables are not set in $ENV_FILE."
    echo "Please define TRAEFIK_CONTAINER_NAME, TRAEFIK_IMAGE, TRAEFIK_WEB_PORT, and TRAEFIK_WEBSECURE_PORT."
    exit 1
fi

# --- Main Logic ---

echo "Starting Traefik deployment..."

# Create the Docker network if it doesn't exist
# This network will be used by Traefik and the services it routes to.
docker network create "$TRAEFIK_NETWORK" 2>/dev/null || echo "Network '$TRAEFIK_NETWORK' already exists."

# Create the acme.json file for Let's Encrypt certificates
# and set the correct permissions.
echo "Creating acme.json for Let's Encrypt..."
touch acme.json
chmod 600 acme.json

# Stop and remove any existing container with the same name
echo "Checking for existing Traefik container..."
if [ "$(docker ps -q -f name="$TRAEFIK_CONTAINER_NAME")" ]; then
    echo "Stopping and removing existing container: $TRAEFIK_CONTAINER_NAME"
    docker stop "$TRAEFIK_CONTAINER_NAME"
    docker rm "$TRAEFIK_CONTAINER_NAME"
fi

# Pull the latest version of the Traefik image
echo "Pulling the latest Traefik image: $TRAEFIK_IMAGE..."
docker pull "$TRAEFIK_IMAGE"

# Run the Traefik container
echo "Deploying Traefik container: $TRAEFIK_CONTAINER_NAME..."

docker run -d \
  --name "$TRAEFIK_CONTAINER_NAME" \
  --restart always \
  --network "$TRAEFIK_NETWORK" \
  -p "$TRAEFIK_WEB_PORT":80 \
  -p "$TRAEFIK_WEBSECURE_PORT":443 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$(pwd)/acme.json":/acme.json \
  -v "$(pwd)/traefik.yml":/etc/traefik/traefik.yml:ro \
  -e "TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT=false" \
  -e "TRAEFIK_PROVIDERS_DOCKER_NETWORK=$TRAEFIK_NETWORK" \
  -e "TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:$TRAEFIK_WEB_PORT" \
  -e "TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:$TRAEFIK_WEBSECURE_PORT" \
  -e "TRAEFIK_API_INSECURE=true" \
  -e "TRAEFIK_API_DASHBOARD=true" \
  -e "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=$ACME_EMAIL" \
  -e "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/acme.json" \
  -e "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_CASERVER=https://acme-v02.api.letsencrypt.org/directory" \
  -e "TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_HTTPCHALLENGE_ENTRYPOINT=web" \
  "$TRAEFIK_IMAGE"

# --- Post-deployment ---

echo ""
echo "Traefik deployment completed successfully!"
echo "-----------------------------------------"
echo "Container Name: $TRAEFIK_CONTAINER_NAME"
echo "Dashboard (API): http://localhost:8080"
echo "Web Entrypoint: Port $TRAEFIK_WEB_PORT"
echo "Websecure Entrypoint: Port $TRAEFIK_WEBSECURE_PORT"
echo "-----------------------------------------"

