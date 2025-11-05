#!/bin/sh
set -e

# Mount target used on Railway
STOR="/var/www/app/storage"

# Ensure the mount root exists and is writable (volume may be empty)
mkdir -p "$STOR"

# Take ownership of the volume so app user can write (try common users, fallback)
chown -R www-data:www-data "$STOR" 2>/dev/null || \
chown -R nginx:nginx       "$STOR" 2>/dev/null || \
chown -R 1000:1000         "$STOR" 2>/dev/null || true

# Create expected subdirs (idempotent)
mkdir -p "$STOR/logs" \
         "$STOR/framework/cache" \
         "$STOR/framework/sessions" \
         "$STOR/framework/views" \
         "$STOR/app/public"

# Link public/storage → storage/app/public (safe if already exists)
php artisan storage:link || true

# Hand off to the image's supervisor (foreground)
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf

