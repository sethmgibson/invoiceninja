#!/bin/bash
# Verification script to test Invoice Ninja deployment on Railway
# Run this after deployment to verify all fixes are working

set -e

APP_URL="${APP_URL:-https://portal.aevumvector.com}"
FAILED=0

echo "======================================"
echo "Invoice Ninja Deployment Verification"
echo "Testing: $APP_URL"
echo "======================================"
echo ""

# Test 1: Nginx health check
echo "Test 1: Nginx Health Check"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/health" || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ PASS: Nginx is running (HTTP $HTTP_CODE)"
else
    echo "✗ FAIL: Nginx health check failed (HTTP $HTTP_CODE)"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 2: Storage health file
echo "Test 2: Storage Health File"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/storage/health.txt" || echo "000")
CONTENT=$(curl -s "$APP_URL/storage/health.txt" 2>/dev/null || echo "")
if [ "$HTTP_CODE" = "200" ] && echo "$CONTENT" | grep -q "healthy"; then
    echo "✓ PASS: Storage is accessible (HTTP $HTTP_CODE)"
    echo "  Content: $CONTENT"
else
    echo "✗ FAIL: Storage health file not accessible (HTTP $HTTP_CODE)"
    echo "  Content: $CONTENT"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 3: Main application
echo "Test 3: Main Application"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL" || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✓ PASS: Application is responding (HTTP $HTTP_CODE)"
else
    echo "✗ FAIL: Application not responding correctly (HTTP $HTTP_CODE)"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 4: Client portal
echo "Test 4: Client Portal"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/client/login" || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✓ PASS: Client portal is accessible (HTTP $HTTP_CODE)"
else
    echo "✗ FAIL: Client portal not accessible (HTTP $HTTP_CODE)"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 5: Check for directory listing (should be forbidden)
echo "Test 5: Directory Listing Prevention"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL/storage/" || echo "000")
if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "✓ PASS: Directory listing is blocked (HTTP $HTTP_CODE)"
else
    echo "⚠ WARNING: Directory listing may be enabled (HTTP $HTTP_CODE)"
    # Don't fail on this, just warn
fi
echo ""

# Summary
echo "======================================"
if [ $FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    echo ""
    echo "Next steps:"
    echo "1. Log in to Invoice Ninja admin panel"
    echo "2. Test logo upload: Settings → Company Details → Logo"
    echo "3. Test template save: Settings → Email Settings → Templates"
    echo "4. Verify queue worker: railway logs --service worker"
    echo "5. Verify scheduler: railway logs --service scheduler"
else
    echo "✗ $FAILED TESTS FAILED"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check logs: railway logs --service web"
    echo "2. Verify symlink: railway run ls -la /var/www/app/public/storage"
    echo "3. Check storage: railway run ls -la /var/www/app/storage/app/public/"
    echo "4. Review: cat RAILWAY_DEPLOYMENT.md"
    exit 1
fi
echo "======================================"

