#!/bin/bash
set -e

# Check Docker access
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not accessible. Trying with sudo..."
    exec sudo "$0" "$@"
fi

# NGINX Deployment Script with OAuth2 Proxy
# Purpose: Deploy NGINX reverse proxy with Keycloak authentication

# Load environment variables
ENV_FILE="$HOME/projects/secrets/nginx.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "❌ Environment file not found: $ENV_FILE"
    echo "Creating template environment file..."
    cat > "$ENV_FILE" <<'EOF'
# NGINX Configuration
NGINX_CONTAINER=nginx
NGINX_IMAGE=cgr.dev/chainguard/nginx:latest
NGINX_PORT=80
NGINX_SSL_PORT=443
NGINX_NETWORK=traefik-net

# OAuth2 Proxy Configuration  
OAUTH2_PROXY_CONTAINER=nginx-oauth2-proxy
OAUTH2_PROXY_IMAGE=quay.io/oauth2-proxy/oauth2-proxy:latest
OAUTH2_PROXY_PORT=4180

# Keycloak Configuration
KEYCLOAK_URL=https://keycloak.ai-servicers.com
KEYCLOAK_INTERNAL_URL=https://keycloak.linuxserver.lan:8443
KEYCLOAK_REALM=master
KEYCLOAK_CLIENT_ID=nginx
KEYCLOAK_CLIENT_SECRET=CHANGE_ME_IN_KEYCLOAK

# Authentication Settings
OAUTH2_PROXY_ENABLED=false
EOF
    echo "✅ Created template at $ENV_FILE"
    echo "Please configure Keycloak client and update KEYCLOAK_CLIENT_SECRET"
    exit 1
fi

source "$ENV_FILE"

echo "========================================="
echo "Deploying NGINX Reverse Proxy"
echo "========================================="

# Stop and remove existing containers
echo "Stopping existing containers..."
docker stop "$NGINX_CONTAINER" 2>/dev/null || true
docker rm "$NGINX_CONTAINER" 2>/dev/null || true
docker stop "$OAUTH2_PROXY_CONTAINER" 2>/dev/null || true
docker rm "$OAUTH2_PROXY_CONTAINER" 2>/dev/null || true

# Create network if not exists
if ! docker network ls --format '{{.Name}}' | grep -qx "$NGINX_NETWORK"; then
    echo "Creating network $NGINX_NETWORK..."
    docker network create "$NGINX_NETWORK"
fi

# Create directories for NGINX
echo "Creating directories..."
mkdir -p /home/administrator/projects/data/nginx/certs
mkdir -p /home/administrator/projects/nginx/configs
mkdir -p /home/administrator/projects/nginx/sites

# Check if custom configs exist, if not create default
if [ ! -f "/home/administrator/projects/nginx/configs/services.conf" ]; then
    echo "No custom configuration found, using default..."
    cat > "/home/administrator/projects/nginx/configs/default.conf" <<'EOF'
server {
    listen 80;
    server_name _;
    
    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
    }
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
fi

# Generate index page for sites directory if it doesn't exist
if [ ! -f "/home/administrator/projects/nginx/sites/index.html" ]; then
    echo "Generating sites index page..."
    cat > "/home/administrator/projects/nginx/sites/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>NGINX - Static Sites</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 40px 20px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            max-width: 800px;
            width: 100%;
        }
        header {
            text-align: center;
            color: white;
            margin-bottom: 40px;
        }
        h1 {
            font-size: 3em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
        }
        .sites-list {
            background: white;
            border-radius: 15px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        .site-item {
            padding: 20px;
            margin-bottom: 15px;
            border-radius: 10px;
            background: #f8f9fa;
            transition: all 0.3s ease;
            text-decoration: none;
            color: inherit;
            display: block;
        }
        .site-item:hover {
            background: #667eea;
            color: white;
            transform: translateX(10px);
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
        }
        .site-item:last-child {
            margin-bottom: 0;
        }
        .site-name {
            font-size: 1.3em;
            font-weight: 600;
            margin-bottom: 5px;
        }
        .site-url {
            font-size: 0.9em;
            opacity: 0.7;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📄 NGINX Static Sites</h1>
            <p class="subtitle">Sites hosted under /nginx/sites/</p>
        </header>

        <div class="sites-list">
            <a href="https://langchain-portal.ai-servicers.com" class="site-item">
                <div class="site-name">🔗 LangChain Portal</div>
                <div class="site-url">langchain-portal.ai-servicers.com</div>
            </a>
        </div>
    </div>
</body>
</html>
EOF
fi

if [ "$OAUTH2_PROXY_ENABLED" = "true" ] && [ "$KEYCLOAK_CLIENT_SECRET" != "CHANGE_ME_IN_KEYCLOAK" ]; then
    echo "==========================================="
    echo "Deploying with OAuth2 Proxy Authentication"
    echo "==========================================="
    
    # Generate cookie secret if not exists
    COOKIE_SECRET_FILE="$HOME/projects/secrets/nginx-oauth2-cookie.secret"
    if [ ! -f "$COOKIE_SECRET_FILE" ]; then
        echo "Generating cookie secret..."
        python3 -c 'import os,base64; print(base64.b64encode(os.urandom(24)).decode())' > "$COOKIE_SECRET_FILE"
        chmod 600 "$COOKIE_SECRET_FILE"
    fi
    COOKIE_SECRET=$(cat "$COOKIE_SECRET_FILE")
    
    # Deploy NGINX (internal only)
    echo "Starting NGINX container (internal)..."
    docker run -d \
        --name "$NGINX_CONTAINER" \
        --network "$NGINX_NETWORK" \
        --restart unless-stopped \
        -v /home/administrator/projects/nginx/configs:/etc/nginx/conf.d:ro \
        -v /home/administrator/projects/nginx/sites:/usr/share/nginx/sites:ro \
        -v /home/administrator/projects/data/nginx/certs:/etc/nginx/certs:ro \
        "$NGINX_IMAGE"
    
    # Deploy OAuth2 Proxy
    echo "Starting OAuth2 Proxy..."
    docker run -d \
        --name "$OAUTH2_PROXY_CONTAINER" \
        --network "$NGINX_NETWORK" \
        --restart unless-stopped \
        -p "${NGINX_PORT}:4180" \
        -e OAUTH2_PROXY_PROVIDER=oidc \
        -e OAUTH2_PROXY_SKIP_OIDC_DISCOVERY=true \
        -e OAUTH2_PROXY_OIDC_ISSUER_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}" \
        -e OAUTH2_PROXY_CLIENT_ID="$KEYCLOAK_CLIENT_ID" \
        -e OAUTH2_PROXY_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
        -e OAUTH2_PROXY_REDIRECT_URL="http://linuxserver.lan/oauth2/callback" \
        -e OAUTH2_PROXY_LOGIN_URL="${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/auth" \
        -e OAUTH2_PROXY_REDEEM_URL="${KEYCLOAK_INTERNAL_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token" \
        -e OAUTH2_PROXY_OIDC_JWKS_URL="${KEYCLOAK_INTERNAL_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs" \
        -e OAUTH2_PROXY_VALIDATE_URL="${KEYCLOAK_INTERNAL_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/userinfo" \
        -e OAUTH2_PROXY_COOKIE_SECRET="$COOKIE_SECRET" \
        -e OAUTH2_PROXY_COOKIE_SECURE=false \
        -e OAUTH2_PROXY_EMAIL_DOMAINS="*" \
        -e OAUTH2_PROXY_UPSTREAMS="http://${NGINX_CONTAINER}:80" \
        -e OAUTH2_PROXY_HTTP_ADDRESS="0.0.0.0:4180" \
        -e OAUTH2_PROXY_PASS_ACCESS_TOKEN=true \
        -e OAUTH2_PROXY_PASS_AUTHORIZATION_HEADER=true \
        -e OAUTH2_PROXY_SET_XAUTHREQUEST=true \
        -e OAUTH2_PROXY_SKIP_PROVIDER_BUTTON=true \
        -e OAUTH2_PROXY_INSECURE_OIDC_ALLOW_UNVERIFIED_EMAIL=true \
        -e OAUTH2_PROXY_INSECURE_OIDC_SKIP_ISSUER_VERIFICATION=true \
        "$OAUTH2_PROXY_IMAGE"
    
    echo ""
    echo "✅ Deployed with OAuth2 Proxy authentication"
    echo "Access: http://linuxserver.lan (requires Keycloak login)"
    
else
    echo "==========================================="
    echo "Deploying without Authentication (Direct)"
    echo "==========================================="
    
    # Deploy NGINX with direct access
    echo "Starting NGINX container..."
    docker run -d \
        --name "$NGINX_CONTAINER" \
        --network "$NGINX_NETWORK" \
        --restart unless-stopped \
        -p "${NGINX_PORT}:80" \
        -v /home/administrator/projects/nginx/configs:/etc/nginx/conf.d:ro \
        -v /home/administrator/projects/nginx/sites:/usr/share/nginx/sites:ro \
        -v /home/administrator/projects/data/nginx/certs:/etc/nginx/certs:ro \
        --label "traefik.enable=true" \
        --label "traefik.docker.network=traefik-net" \
        --label "traefik.http.routers.nginx.rule=Host(\`nginx.ai-servicers.com\`) || Host(\`infrastructure-docs.ai-servicers.com\`) || Host(\`langchain-portal.ai-servicers.com\`)" \
        --label "traefik.http.routers.nginx.entrypoints=websecure" \
        --label "traefik.http.routers.nginx.tls=true" \
        --label "traefik.http.routers.nginx.tls.certresolver=letsencrypt" \
        --label "traefik.http.services.nginx.loadbalancer.server.port=80" \
        "$NGINX_IMAGE"
    
    echo ""
    echo "✅ Deployed without authentication"
    echo "Access: http://linuxserver.lan"
    echo ""
    echo "To enable authentication:"
    echo "1. Configure Keycloak client for 'nginx'"
    echo "2. Update KEYCLOAK_CLIENT_SECRET in $ENV_FILE"
    echo "3. Set OAUTH2_PROXY_ENABLED=true in $ENV_FILE"
    echo "4. Run this script again"
fi

echo ""
echo "Waiting for services to start..."
sleep 3

# Check status
echo ""
echo "Container Status:"
docker ps | grep -E "nginx|oauth2" || echo "No containers running"

echo ""
echo "==========================================="
echo "Deployment Complete"
echo "==========================================="
echo ""
echo "Next steps:"
echo "1. Configure upstream services in /etc/nginx/conf.d/"
echo "2. Set up SSL certificates if needed"
echo "3. Configure subdomain routing for services"