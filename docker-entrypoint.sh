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

# Start nginx in the background (it will proxy to PHP-FPM that supervisor starts)
if [ -x /usr/sbin/nginx ]; then
    /usr/sbin/nginx
elif command -v nginx >/dev/null 2>&1; then
    nginx
fi

# Now start supervisor which will manage PHP-FPM and queue workers
# Try to find supervisor config and use it
for conf in /etc/supervisord.conf /etc/supervisor/supervisord.conf /etc/supervisord/supervisord.conf; do
    if [ -f "$conf" ]; then
        exec /usr/bin/supervisord -n -c "$conf"
    fi
done

# If no config found, try without explicit config
exec /usr/bin/supervisord -n

