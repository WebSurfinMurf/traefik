#!/bin/bash
# Validate traefik configuration files before deployment.
#
# Checks:
# 1. YAML syntax for traefik.yml and redirect.yml
# 2. docker-compose.yml validity
# 3. Required config keys present in traefik.yml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

ERRORS=0

echo "Validating traefik configuration..."

# 1. YAML syntax check via python
for f in traefik.yml redirect.yml; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f not found"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    if python3 -c "import yaml; yaml.safe_load(open('$f'))" 2>&1; then
        echo "OK: $f — valid YAML"
    else
        echo "ERROR: $f — invalid YAML"
        ERRORS=$((ERRORS + 1))
    fi
done

# 2. docker-compose.yml validation
echo ""
echo "Validating docker-compose.yml..."
if docker compose config > /dev/null 2>&1; then
    echo "OK: docker-compose.yml — valid"
else
    echo "ERROR: docker-compose.yml — invalid"
    docker compose config 2>&1 | head -20
    ERRORS=$((ERRORS + 1))
fi

# 3. Required config keys in traefik.yml
echo ""
echo "Checking required traefik.yml keys..."
for key in entryPoints providers certificatesResolvers; do
    if python3 -c "
import yaml
cfg = yaml.safe_load(open('traefik.yml'))
assert '$key' in cfg, '$key missing'
" 2>&1; then
        echo "OK: $key present"
    else
        echo "ERROR: $key missing from traefik.yml"
        ERRORS=$((ERRORS + 1))
    fi
done

# 4. Check redirect.yml references valid structure
echo ""
echo "Checking redirect.yml structure..."
if python3 -c "
import yaml
cfg = yaml.safe_load(open('redirect.yml'))
assert 'http' in cfg, 'http section missing'
http = cfg['http']
assert 'routers' in http, 'http.routers missing'
assert 'middlewares' in http, 'http.middlewares missing'
assert 'services' in http, 'http.services missing'
" 2>&1; then
    echo "OK: redirect.yml structure valid"
else
    echo "ERROR: redirect.yml structure invalid"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: $ERRORS validation error(s)"
    exit 1
fi
echo "All validations passed"
