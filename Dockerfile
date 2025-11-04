# Use the official Invoice Ninja image (includes PHP, Nginx, Supervisor, cron)
FROM invoiceninja/invoiceninja:5

# Optional: if you'll customize templates, languages, designs, etc, copy only what you change:
# COPY ./resources/lang /var/www/app/resources/lang
# COPY ./resources/views /var/www/app/resources/views

# Expose the web port the base image serves on
EXPOSE 9000

# The base image already runs nginx+php-fpm+cron via supervisord

