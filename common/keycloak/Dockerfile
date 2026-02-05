FROM quay.io/keycloak/keycloak:26.5.2 as builder

# Enable health and metrics support
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Configure a database vendor
ENV KC_DB=postgres

WORKDIR /opt/keycloak

# Build Keycloak with PostgreSQL support
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.5.2
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Configure runtime settings for HA deployment
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false
ENV KC_HTTP_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
