#!/bin/bash
set -e

# Configure proxy settings
export GF_SERVER_HTTP_PORT=${GF_SERVER_HTTP_PORT:-3000}
export GF_SERVER_ROOT_URL="%(protocol)s://%(domain)s/"

 # Parse database URL to extract database name and port
 DB_URL=${GF_DATABASE_URL}
 DB_NAME=${DB_URL##*/}
 DB_NAME=${DB_NAME%%\?*}
 DB_HOST_PORT=${DB_URL#*@}
 DB_HOST_PORT=${DB_HOST_PORT%%/*}
 if echo "$DB_HOST_PORT" | grep -q ":"; then
   DB_HOST=${DB_HOST_PORT%:*}
   DB_PORT=${DB_HOST_PORT#*:}
 else
   DB_HOST=$DB_HOST_PORT
   DB_PORT=3306
 fi

 # Extract username and password from DB_URL
 DB_USER_PASS=${DB_URL#*://}
 DB_USER_PASS=${DB_USER_PASS%@*}
 DB_USER=${DB_USER_PASS%:*}
 DB_PASS=${DB_USER_PASS#*:}

# URL decode both username and password
DB_USER=$(printf '%b' "${DB_USER//%/\\x}")
DB_PASS=$(printf '%b' "${DB_PASS//%/\\x}")

 # Create database if it doesn't exist
 echo "Creating database $DB_NAME if it doesn't exist..."
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME"

# Update admin user if environment variables are set
if [ -n "${GF_SECURITY_ADMIN_USER}" ] && [ -n "${GF_SECURITY_ADMIN_PASSWORD}" ]; then
  echo "Updating admin user credentials..."
  grafana-cli admin reset-admin-password "${GF_SECURITY_ADMIN_PASSWORD}" || true
fi

# Run the original entrypoint
exec /run.sh "$@"
