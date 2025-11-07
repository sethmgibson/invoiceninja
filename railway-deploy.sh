#!/bin/sh
# Railway deployment script for Invoice Ninja services
# This script handles pre-deploy tasks based on the service type

set -e

SERVICE_TYPE="${RAILWAY_SERVICE_NAME:-web}"

echo "======================================"
echo "Railway Deploy Script"
echo "Service: $SERVICE_TYPE"
echo "======================================"

# Only run migrations on the main web service to avoid conflicts
if [ "$SERVICE_TYPE" = "web" ] || [ "$SERVICE_TYPE" = "invoiceninja" ] || [ -z "$RAILWAY_SERVICE_NAME" ]; then
    echo "Running database migrations..."
    php artisan migrate --force --no-interaction
    echo "✓ Migrations complete"
else
    echo "Skipping migrations (not main web service)"
fi

echo "✓ Pre-deploy tasks complete"

