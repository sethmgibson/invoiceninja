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

# Use Railway's PORT environment variable, default to 80
HTTP_PORT=${PORT:-80}

# Create a minimal nginx configuration for Railway
cat > /etc/nginx/nginx.conf <<EOF
worker_processes 1;
error_log /dev/stderr warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    access_log /dev/stdout;
    
    sendfile on;
    keepalive_timeout 65;
    
    server {
        listen ${HTTP_PORT} default_server;
        listen [::]:${HTTP_PORT} default_server;
        
        root /var/www/app/public;
        index index.php index.html;
        
        location / {
            try_files \$uri \$uri/ /index.php?\$query_string;
        }
        
        location ~ \.php\$ {
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
        
        location ~ /\.ht {
            deny all;
        }
    }
}
EOF

echo "Nginx will listen on port: $HTTP_PORT"

# Find the supervisor config
SUPERVISOR_CONF=""
for conf in /etc/supervisord.conf /etc/supervisor/supervisord.conf /etc/supervisord/supervisord.conf; do
    if [ -f "$conf" ]; then
        SUPERVISOR_CONF="$conf"
        break
    fi
done

# Add nginx to supervisor config if not already there and if nginx exists
if [ -n "$SUPERVISOR_CONF" ]; then
    # Find nginx binary location
    NGINX_BIN=""
    if [ -x /usr/sbin/nginx ]; then
        NGINX_BIN="/usr/sbin/nginx"
    elif [ -x /usr/bin/nginx ]; then
        NGINX_BIN="/usr/bin/nginx"
    elif command -v nginx >/dev/null 2>&1; then
        NGINX_BIN="$(command -v nginx)"
    fi
    
    # Add nginx to supervisor config if we found the binary
    if [ -n "$NGINX_BIN" ]; then
        if ! grep -q "\[program:nginx\]" "$SUPERVISOR_CONF" 2>/dev/null; then
            echo "" >> "$SUPERVISOR_CONF"
            echo "[program:nginx]" >> "$SUPERVISOR_CONF"
            echo "command=$NGINX_BIN -g 'daemon off;' -c /etc/nginx/nginx.conf" >> "$SUPERVISOR_CONF"
            echo "autostart=true" >> "$SUPERVISOR_CONF"
            echo "autorestart=true" >> "$SUPERVISOR_CONF"
            echo "stdout_logfile=/dev/stdout" >> "$SUPERVISOR_CONF"
            echo "stdout_logfile_maxbytes=0" >> "$SUPERVISOR_CONF"
            echo "stderr_logfile=/dev/stderr" >> "$SUPERVISOR_CONF"
            echo "stderr_logfile_maxbytes=0" >> "$SUPERVISOR_CONF"
            echo "priority=10" >> "$SUPERVISOR_CONF"
        fi
        
        # Start supervisor with the modified config
        exec /usr/bin/supervisord -n -c "$SUPERVISOR_CONF"
    else
        echo "ERROR: nginx binary not found. Cannot start web server."
        echo "Listing supervisor config contents:"
        cat "$SUPERVISOR_CONF"
        # Start supervisor anyway (PHP-FPM will run on port 9000)
        exec /usr/bin/supervisord -n -c "$SUPERVISOR_CONF"
    fi
fi

# Fallback if no supervisor config found
exec /usr/bin/supervisord -n

