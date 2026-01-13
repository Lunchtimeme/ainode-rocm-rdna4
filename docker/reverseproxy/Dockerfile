# ==============================================================================
# Reverse Proxy Container (nginx)
# ==============================================================================
# nginx reverse proxy for routing traffic to internal AINode services.
# Provides SSL termination, load balancing, and unified access point.
#
# Features:
#   - nginx with minimal configuration
#   - SSL/TLS termination
#   - Virtual host support via sites-enabled
#   - Basic authentication support via htpasswd
#
# Exposed ports (configured in compose.yml):
#   - 80:    HTTP
#   - 443:   HTTPS
#   - 5000:  Additional service port
#   - 11434: Ollama API
#
# Volume mounts:
#   - sites-enabled: nginx virtual host configurations
#   - htpasswd:      Basic auth password files
#   - certs:         SSL certificates
# ==============================================================================

FROM archlinux

# ------------------------------------------------------------------------------
# nginx installation and configuration
# ------------------------------------------------------------------------------
# Single layer for minimal image size:
# 1. Update system and install nginx
# 2. Create base nginx configuration
# 3. Clean package cache
# ------------------------------------------------------------------------------
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm nginx \
    # Clean package cache (saves ~200MB)
    && rm -rf /var/cache/pacman/pkg/* \
    && rm -rf /var/lib/pacman/sync/* \
    # Create minimal nginx.conf
    # - worker_processes: 1 is sufficient for reverse proxy
    # - worker_connections: 1024 handles typical load
    # - sites-enabled: virtual hosts mounted from host
    && printf '%s\n' \
        'worker_processes 1;' \
        '' \
        'include modules.d/*.conf;' \
        '' \
        'events {' \
        '    worker_connections 1024;' \
        '}' \
        '' \
        'http {' \
        '    include sites-enabled/*;' \
        '}' \
        > /etc/nginx/nginx.conf

WORKDIR /etc/nginx

# ------------------------------------------------------------------------------
# Container startup
# ------------------------------------------------------------------------------
# Run nginx in foreground (daemon off) for Docker compatibility
# ------------------------------------------------------------------------------
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
