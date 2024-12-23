ARG GRAFANA_VERSION=10.4.12
# Use the official Renterd image as base
FROM grafana/grafana:${GRAFANA_VERSION} AS grafana

# Switch to root to perform installations
USER root

VOLUME [ "/var/lib/grafana" ]

# Copy configuration files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN apk add --no-cache mysql-client mariadb-connector-c

# Expose ports
EXPOSE 3000

# Switch back to original user
USER 1000

# Define volumes
VOLUME ["/var/lib/grafana", "/var/log/grafana"]

# Use entrypoint
ENTRYPOINT ["/entrypoint.sh"]
