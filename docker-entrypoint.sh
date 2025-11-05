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

# Detect PHP-FPM socket or port
FPM_SOCKET=""
if [ -S /var/run/php-fpm/php-fpm.sock ]; then
    FPM_SOCKET="/var/run/php-fpm/php-fpm.sock"
elif [ -S /var/run/php/php-fpm.sock ]; then
    FPM_SOCKET="/var/run/php/php-fpm.sock"
elif [ -S /run/php/php-fpm.sock ]; then
    FPM_SOCKET="/run/php/php-fpm.sock"
elif [ -S /run/php-fpm/www.sock ]; then
    FPM_SOCKET="/run/php-fpm/www.sock"
fi

# Determine fastcgi_pass target
if [ -n "$FPM_SOCKET" ]; then
    FPM_PASS="unix:$FPM_SOCKET"
    echo "Using PHP-FPM socket: $FPM_SOCKET"
else
    FPM_PASS="127.0.0.1:9000"
    echo "Using PHP-FPM TCP: 127.0.0.1:9000"
fi

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
    client_max_body_size 100M;
    
    server {
        listen ${HTTP_PORT} default_server;
        listen [::]:${HTTP_PORT} default_server;
        
        root /var/www/app/public;
        index index.php index.html;
        
        location / {
            try_files \$uri \$uri/ /index.php?\$query_string;
        }
        
        location ~ \.php\$ {
            fastcgi_split_path_info ^(.+\.php)(/.+)\$;
            fastcgi_pass ${FPM_PASS};
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param PATH_INFO \$fastcgi_path_info;
            include fastcgi_params;
        }
        
        location ~ /\.ht {
            deny all;
        }
    }
}
EOF

echo "Nginx will listen on port: $HTTP_PORT"

# Create fastcgi_params if it doesn't exist
if [ ! -f /etc/nginx/fastcgi_params ]; then
    cat > /etc/nginx/fastcgi_params <<'FASTCGI_EOF'
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

fastcgi_param  REDIRECT_STATUS    200;
FASTCGI_EOF
fi

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
            # Create a wrapper script to wait for PHP-FPM
            cat > /usr/local/bin/nginx-wait-start.sh <<'NGINX_WAIT_EOF'
#!/bin/sh
# Wait for PHP-FPM to be ready (max 30 seconds)
for i in $(seq 1 30); do
    if nc -z 127.0.0.1 9000 2>/dev/null || \
       [ -S /var/run/php-fpm/php-fpm.sock ] || \
       [ -S /var/run/php/php-fpm.sock ] || \
       [ -S /run/php/php-fpm.sock ] || \
       [ -S /run/php-fpm/www.sock ]; then
        echo "PHP-FPM is ready, starting nginx"
        break
    fi
    echo "Waiting for PHP-FPM... ($i/30)"
    sleep 1
done

# Start nginx
exec nginx -g 'daemon off;' -c /etc/nginx/nginx.conf
NGINX_WAIT_EOF
            chmod +x /usr/local/bin/nginx-wait-start.sh
            
            echo "" >> "$SUPERVISOR_CONF"
            echo "[program:nginx]" >> "$SUPERVISOR_CONF"
            echo "command=/usr/local/bin/nginx-wait-start.sh" >> "$SUPERVISOR_CONF"
            echo "autostart=true" >> "$SUPERVISOR_CONF"
            echo "autorestart=true" >> "$SUPERVISOR_CONF"
            echo "stdout_logfile=/dev/stdout" >> "$SUPERVISOR_CONF"
            echo "stdout_logfile_maxbytes=0" >> "$SUPERVISOR_CONF"
            echo "stderr_logfile=/dev/stderr" >> "$SUPERVISOR_CONF"
            echo "stderr_logfile_maxbytes=0" >> "$SUPERVISOR_CONF"
            echo "priority=100" >> "$SUPERVISOR_CONF"
            echo "startsecs=0" >> "$SUPERVISOR_CONF"
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

