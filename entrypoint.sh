#!/bin/bash
set -eo pipefail

# Configure logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Parse database connection details from URL
parse_db_url() {
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

    # Extract and decode credentials
    DB_USER_PASS=${DB_URL#*://}
    DB_USER_PASS=${DB_USER_PASS%@*}
    DB_USER=${DB_USER_PASS%:*}
    DB_PASS=${DB_USER_PASS#*:}
    DB_USER=$(printf '%b' "${DB_USER//%/\\x}")
    DB_PASS=$(printf '%b' "${DB_PASS//%/\\x}")
}

# Wait for database to be ready
wait_for_db() {
    local retries=30
    local wait_time=2
    
    log "Waiting for database connection..."
    while ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [ $retries -eq 0 ]; then
            log "Error: Could not connect to database after 60 seconds"
            exit 1
        fi
        log "Database not ready, waiting ${wait_time}s... ($retries attempts left)"
        sleep $wait_time
    done
    log "Database connection established"
}

# Create database if it doesn't exist
create_database() {
    log "Creating database $DB_NAME if it doesn't exist..."
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME"; then
        log "Database setup completed successfully"
    else
        log "Error: Failed to create database"
        exit 1
    fi
}

# Update admin credentials if provided
update_admin_credentials() {
    if [ -n "${GF_SECURITY_ADMIN_USER}" ] && [ -n "${GF_SECURITY_ADMIN_PASSWORD}" ]; then
        log "Updating admin user credentials..."
        if grafana-cli admin reset-admin-password "${GF_SECURITY_ADMIN_PASSWORD}"; then
            log "Admin credentials updated successfully"
        else
            log "Warning: Failed to update admin credentials"
        fi
    fi
}

# Get Grafana server PID
get_grafana_pid() {
    pgrep -f "grafana server"
}

# Monitor database connectivity
monitor_db() {
    while true; do
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1" >/dev/null 2>&1; then
            log "Database connection lost, waiting for recovery..."
            wait_for_db
            log "Database recovered, restarting Grafana..."
            local grafana_pid=$(get_grafana_pid)
            if [ -n "$grafana_pid" ]; then
                kill $grafana_pid
            fi
            return
        fi
        sleep 10
    done
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    local grafana_pid=$(get_grafana_pid)
    if [ -n "$grafana_pid" ]; then
        kill $grafana_pid 2>/dev/null || true
    fi
    kill $1 2>/dev/null || true  # Kill monitor process
}

# Main execution
main() {
    # Configure proxy settings
    export GF_SERVER_HTTP_PORT=${GF_SERVER_HTTP_PORT:-3000}
    export GF_SERVER_ROOT_URL="%(protocol)s://%(domain)s/"

    while true; do
        parse_db_url
        wait_for_db
        create_database
        update_admin_credentials

        log "Starting Grafana..."
        /run.sh "$@" &
        sleep 2  # Give time for exec to occur
        grafana_pid=$(get_grafana_pid)

        # Start database monitor in background
        monitor_db &
        monitor_pid=$!

        # Setup cleanup trap
        trap "cleanup $monitor_pid" EXIT

        # Wait for Grafana to exit
        wait $grafana_pid || true
        
        log "Grafana exited, restarting..."
        sleep 2
    done
}

main "$@"
