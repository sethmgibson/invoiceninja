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

# Find the supervisor config
SUPERVISOR_CONF=""
for conf in /etc/supervisord.conf /etc/supervisor/supervisord.conf /etc/supervisord/supervisord.conf; do
    if [ -f "$conf" ]; then
        SUPERVISOR_CONF="$conf"
        break
    fi
done

# Add nginx to supervisor config if not already there
if [ -n "$SUPERVISOR_CONF" ]; then
    # Check if nginx program already exists in config
    if ! grep -q "\[program:nginx\]" "$SUPERVISOR_CONF" 2>/dev/null; then
        # Find nginx binary location
        NGINX_BIN=""
        if [ -x /usr/sbin/nginx ]; then
            NGINX_BIN="/usr/sbin/nginx"
        elif command -v nginx >/dev/null 2>&1; then
            NGINX_BIN="$(command -v nginx)"
        fi
        
        # Add nginx to supervisor config
        if [ -n "$NGINX_BIN" ]; then
            echo "" >> "$SUPERVISOR_CONF"
            echo "[program:nginx]" >> "$SUPERVISOR_CONF"
            echo "command=$NGINX_BIN -g 'daemon off;'" >> "$SUPERVISOR_CONF"
            echo "autostart=true" >> "$SUPERVISOR_CONF"
            echo "autorestart=true" >> "$SUPERVISOR_CONF"
            echo "stdout_logfile=/dev/stdout" >> "$SUPERVISOR_CONF"
            echo "stdout_logfile_maxbytes=0" >> "$SUPERVISOR_CONF"
            echo "stderr_logfile=/dev/stderr" >> "$SUPERVISOR_CONF"
            echo "stderr_logfile_maxbytes=0" >> "$SUPERVISOR_CONF"
        fi
    fi
    
    # Start supervisor with the modified config
    exec /usr/bin/supervisord -n -c "$SUPERVISOR_CONF"
fi

# Fallback if no supervisor config found
exec /usr/bin/supervisord -n

