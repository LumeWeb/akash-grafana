#!/bin/bash
set -e

# Configure proxy settings
export GF_SERVER_HTTP_PORT=${GF_SERVER_HTTP_PORT:-3000}
export GF_SERVER_ROOT_URL="%(protocol)s://%(domain)s/"

# Update admin user if environment variables are set
if [ -n "${GF_SECURITY_ADMIN_USER}" ] && [ -n "${GF_SECURITY_ADMIN_PASSWORD}" ]; then
    echo "Updating admin user credentials..."
    grafana-cli admin reset-admin-password "${GF_SECURITY_ADMIN_PASSWORD}" || true
fi

# Run the original entrypoint
exec /run.sh "$@"