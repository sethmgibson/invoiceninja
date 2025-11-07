# Invoice Ninja Railway Deployment

## Architecture Overview

This deployment runs Invoice Ninja v5 on Railway with the following services:

### Services

1. **Web Service** (`web` or `invoiceninja`)
   - Runs Nginx + PHP-FPM on Railway's assigned PORT (default: 80)
   - Serves the Laravel application and client portal
   - Has a Railway volume mounted to `/var/www/app/storage`
   - Runs pre-deploy migrations via `railway-deploy.sh`

2. **Worker Service** (`worker`)
   - Processes Laravel queue jobs
   - Connects to Redis and MySQL via private hostnames
   - No volume needed (stateless)

3. **Scheduler Service** (`scheduler`)
   - Runs `php artisan schedule:run` every 5+ minutes via Railway Cron
   - Handles recurring tasks (reminders, cleanups, etc.)
   - No volume needed (stateless)

### Infrastructure

- **Database**: Railway MySQL (private hostname)
- **Cache/Queue**: Railway Redis (private hostname)
- **Volume**: Mounted to `/var/www/app/storage` on web service only

## Storage Structure

The volume at `/var/www/app/storage` contains:

```
storage/
├── app/
│   └── public/          # Public uploads (logos, documents)
│       └── health.txt   # Health check test file (auto-created)
├── framework/
│   ├── cache/
│   ├── sessions/
│   └── views/
└── logs/
```

The `public/storage` symlink points to `storage/app/public` (created automatically on startup).

## Fixed Issues

### 1. Storage Symlink & File Serving

**Problem**: Logo uploads showed "directory index forbidden" errors.

**Solution**:
- Added symlink verification and auto-repair in `docker-entrypoint.sh`
- Added explicit nginx `location /storage/` block with `alias` directive
- Prevents directory listing with `autoindex off`
- Serves files directly via `try_files $uri =404`

### 2. Email Template Null Errors

**Problem**: Template saves failed with `strlen(null)` warnings.

**Solution**:
- Clear all Laravel caches on startup (config, cache, view, route)
- Rebuild optimized config cache after clearing
- Ensures APP_URL and HTTPS settings are applied correctly

### 3. File Permissions

**Problem**: Uploaded files couldn't be written or read.

**Solution**:
- Set ownership to www-data/nginx/1000:1000 (detects correct user)
- Apply 775 permissions to storage tree
- Fallback to 777 if chown fails (Railway volume constraints)

### 4. Nginx Buffering Warnings

**Problem**: Large responses caused "buffered to temporary file" warnings.

**Solution**:
- Increased `fastcgi_buffers` to 16 16k
- Increased `fastcgi_buffer_size` to 32k
- Increased timeouts to 300s for long operations
- These warnings are benign but now minimized

## Environment Variables

### Required Variables

```bash
# Application
APP_URL=https://portal.aevumvector.com
APP_KEY=base64:...  # Generate with: php artisan key:generate --show
APP_ENV=production
APP_DEBUG=false
LOG_CHANNEL=stderr

# HTTPS/Proxy (for Railway)
REQUIRE_HTTPS=true
TRUSTED_PROXIES=*
SESSION_SECURE_COOKIE=true

# Database (use Railway private hostname)
DB_CONNECTION=mysql
DB_HOST=${{MySQL.MYSQL_PRIVATE_HOST}}
DB_PORT=${{MySQL.MYSQL_PORT}}
DB_DATABASE=${{MySQL.MYSQL_DATABASE}}
DB_USERNAME=${{MySQL.MYSQL_USER}}
DB_PASSWORD=${{MySQL.MYSQL_PASSWORD}}

# Redis (use Railway private hostname)
REDIS_HOST=${{Redis.REDIS_PRIVATE_HOST}}
REDIS_PORT=${{Redis.REDIS_PORT}}
REDIS_PASSWORD=${{Redis.REDIS_PASSWORD}}
CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis

# Storage
FILESYSTEM_DISK=public

# SMTP (already configured and working)
MAIL_MAILER=smtp
MAIL_HOST=...
MAIL_PORT=587
MAIL_USERNAME=...
MAIL_PASSWORD=...
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=...
MAIL_FROM_NAME="Aevum Vector"

# License (whitelabel already applied)
IN_LICENSE_KEY=...
```

### Service-Specific Commands

#### Web Service
- **Build Command**: (none, using pre-built image)
- **Start Command**: `/usr/local/bin/docker-entrypoint.sh`
- **Pre-Deploy**: `./railway-deploy.sh` (runs migrations)
- **Health Check**: `https://portal.aevumvector.com/health`

#### Worker Service
- **Start Command**: `php artisan queue:work redis --tries=3 --timeout=300`
- **Pre-Deploy**: (none)

#### Scheduler Service
- **Cron Schedule**: `*/5 * * * *` (every 5 minutes)
- **Cron Command**: `php artisan schedule:run`

## Verification Steps

After deployment, verify the following:

### 1. Health Check
```bash
curl https://portal.aevumvector.com/health
# Expected: "nginx is running"
```

### 2. Storage Health Check
```bash
curl https://portal.aevumvector.com/storage/health.txt
# Expected: "Storage is healthy and accessible"
```

### 3. Logo Upload
1. Navigate to Settings → Company Details → Logo
2. Upload a company logo
3. Verify the uploaded logo displays in the portal
4. Check the logo's direct URL returns 200 (not 403/404)

### 4. Email Template Saving
1. Navigate to Settings → Email Settings → Templates
2. Edit any template (e.g., Invoice)
3. Modify subject/body with variables (e.g., `$client.name`)
4. Save the template
5. Verify no errors and preview renders correctly

### 5. Queue & Scheduler
```bash
# Check worker logs
railway logs --service worker

# Check scheduler logs  
railway logs --service scheduler

# Should see jobs processing and schedule running every 5 min
```

## Port Configuration

- **HTTP_PORT**: Set automatically by Railway via `$PORT` env var (typically 80 internally)
- **PHP-FPM**: Listens on 127.0.0.1:9000 (internal only, not exposed)
- **External**: Railway proxy exposes HTTPS on standard port 443 at custom domain

**Note**: User mentioned "port 9000" but that's PHP-FPM's internal port, not the HTTP port. Railway's proxy handles HTTPS termination and forwards to the container's `$PORT`.

## Troubleshooting

### Symlink Not Created
Check logs for the startup verification:
```bash
railway logs --service web | grep "symlink"
```

Should show:
```
✓ Symlink exists: public/storage -> /var/www/app/storage/app/public
✓ Symlink target is accessible
```

### Storage Files Return 404
1. Verify the volume is mounted: `railway volumes`
2. Check file exists: `railway run ls -la /var/www/app/storage/app/public/`
3. Check nginx config: `railway run cat /etc/nginx/nginx.conf`

### Template Null Errors Persist
1. Force cache clear: `railway run php artisan config:clear`
2. Force cache rebuild: `railway run php artisan config:cache`
3. Restart the service: `railway up --service web`

### Permission Denied
Check the ownership in logs:
```bash
railway logs --service web | grep "ownership"
```

If chown failed, the script falls back to chmod 777. If that also fails, the volume may have issues.

## Maintenance

### Clearing Caches Manually
```bash
railway run --service web php artisan config:clear
railway run --service web php artisan cache:clear
railway run --service web php artisan view:clear
```

### Checking Storage Contents
```bash
railway run --service web ls -la /var/www/app/storage/app/public/
```

### Forcing Symlink Recreation
```bash
railway run --service web rm -f /var/www/app/public/storage
railway run --service web php artisan storage:link
```

## Deployment Process

1. **Push code changes** to git repository
2. **Railway auto-deploys** on push (or manual deploy)
3. **Pre-deploy script** runs migrations (web service only)
4. **Entrypoint script** runs on container start:
   - Fixes storage permissions
   - Clears stale caches
   - Creates storage subdirectories
   - Recreates symlink if broken
   - Creates health.txt test file
   - Rebuilds optimized caches
   - Starts Nginx + PHP-FPM via Supervisor

## Benign Warnings

These warnings can be safely ignored:

- `an upstream response is buffered to a temporary file` - Large responses being handled correctly
- `chown failed, attempting chmod 777 as fallback` - Permissions set via chmod instead (still works)

## No Object Storage

This deployment uses the Railway volume for persistence, **not** S3/R2. All uploaded files stay on the volume at `/var/www/app/storage/app/public/`.

If you need to migrate to object storage in the future, set:
```bash
FILESYSTEM_DISK=s3
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=...
AWS_BUCKET=...
AWS_ENDPOINT=...  # For R2/compatible storage
```

## Support

- Invoice Ninja Docs: https://invoiceninja.github.io/
- Railway Docs: https://docs.railway.app/
- Storage Issues: Check symlink and nginx alias configuration
- Template Issues: Clear caches and verify APP_URL is correct

