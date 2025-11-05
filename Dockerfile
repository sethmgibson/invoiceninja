# Dockerfile
FROM invoiceninja/invoiceninja:5

# Ensure we run as root so we can fix volume permissions at boot
USER root

# entrypoint to fix storage perms, then start supervisor (nginx+php-fpm)
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# The base image already exposes/serves on 9000
EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
