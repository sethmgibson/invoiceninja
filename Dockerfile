# Dockerfile
FROM invoiceninja/invoiceninja:5

# Ensure we run as root so we can fix volume permissions at boot
USER root

# Install nginx if not present (Alpine-based image)
RUN apk add --no-cache nginx 2>/dev/null || \
    apt-get update && apt-get install -y nginx 2>/dev/null || \
    true

# Create nginx directories
RUN mkdir -p /var/run /var/log/nginx /etc/nginx

# entrypoint to fix storage perms, then start services
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose port 80 for HTTP (Railway will override with PORT env var)
# Also expose 9000 for direct PHP-FPM access if needed
EXPOSE 80 9000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
