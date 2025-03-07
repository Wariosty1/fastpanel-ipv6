#!/bin/bash

SCRIPT_PATH="/usr/local/bin/fastpanel_add_ipv6.sh"
CRON_JOB="*/15 * * * * /usr/local/bin/fastpanel_add_ipv6.sh > /var/log/fastpanel_ipv6.log 2>&1"

echo "🔄 Создаём или обновляем скрипт для добавления IPv6 и отключения Nginx для статики..."

cat <<EOF > $SCRIPT_PATH
#!/bin/bash

# Определяем текущий IPv4 и IPv6 сервера
IPV4=\$(curl -s https://api4.ipify.org)
IPV6=\$(curl -s https://api6.ipify.org)

if [[ -z "\$IPV4" ]]; then
    echo "❌ Ошибка: Не удалось определить IPv4. Проверьте интернет-соединение."
    exit 1
fi

if [[ -z "\$IPV6" ]]; then
    echo "❌ Ошибка: Не удалось определить IPv6. Возможно, сервер не поддерживает IPv6."
    exit 1
fi

echo "✅ Обнаружен IPv4: \$IPV4"
echo "✅ Обнаружен IPv6: \$IPV6"

# Путь к базе данных FastPanel 2
DB_PATH="/usr/local/fastpanel2/app/db/fastpanel2.db"

# Проверяем наличие базы данных
if [[ ! -f "\$DB_PATH" ]]; then
    echo "❌ Ошибка: База данных FastPanel 2 не найдена (\$DB_PATH)."
    exit 1
fi

echo "🔄 Обновляем базу данных FastPanel 2..."

# Удаляем только старые IPv6-адреса (не трогаем IPv4!)
sqlite3 "\$DB_PATH" "DELETE FROM ips WHERE ip LIKE '%:%';"

# Добавляем IPv6 только если его ещё нет
sqlite3 "\$DB_PATH" "
INSERT INTO ips (id, ip, virtualhost_id)
SELECT (SELECT COALESCE(MAX(id), 0) FROM ips) + ROW_NUMBER() OVER (), '\$IPV6', id 
FROM site WHERE id NOT IN (SELECT virtualhost_id FROM ips WHERE ip LIKE '%:%');
"

echo "✅ IPv6-адреса успешно добавлены в FastPanel 2."

# Получаем список сайтов (virtualhost_id), у которых добавлен IPv6
SITES=\$(sqlite3 "\$DB_PATH" "SELECT DISTINCT virtualhost_id FROM ips WHERE ip LIKE '%:%';")

# Применяем изменения для каждого сайта
for SITE_ID in \$SITES; do
    echo "🔄 Применяем изменения для сайта ID: \$SITE_ID"

    UUID=\$(uuidgen)
    sqlite3 "\$DB_PATH" "
    INSERT INTO queue_event (id, domain, uuid, type, category, action, priority, user, user_class, user_id, status, created_by, ip, details, created_at, updated_at) 
    VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM queue_event), (SELECT domain FROM site WHERE id = \$SITE_ID), '\$UUID', 'virtualhost.job', 'VIRTUALHOST', 'UPDATING', 1, 'fastuser', 'FVPS\\UserBundle\\Entity\\FpUser', 1, 'SUCCESS', 78, '\$IPV4', '', datetime('now'), datetime('now'));
    "

    echo "✅ Изменения добавлены в очередь для сайта ID: \$SITE_ID"
done

echo "🔄 Принудительно обновляем FastPanel..."
systemctl restart fastpanel2
echo "✅ FastPanel принудительно обновлён."

# Ждём 5 секунд, чтобы FastPanel обработал изменения
sleep 5

# Определяем директории конфигураций Nginx
NGINX_DIRS=(
    "/etc/nginx/fastpanel2-available"
    "/etc/nginx/fastpanel2-sites"
)

echo "🔄 Добавляем IPv6 в конфигурацию Nginx..."
for DIR in "\${NGINX_DIRS[@]}"; do
    if [[ ! -d "\$DIR" ]]; then
        continue
    fi

    for CONFIG_FILE in "\$DIR"/*.conf; do
        if [[ ! -f "\$CONFIG_FILE" ]]; then
            continue
        fi

        # Проверяем, есть ли уже конкретный IPv6 в конфиге
        if grep -q "listen [\$IPV6]:80;" "\$CONFIG_FILE" || grep -q "listen [\$IPV6]:443 ssl;" "\$CONFIG_FILE"; then
            echo "⚠️ IPv6 уже присутствует в \$(basename "\$CONFIG_FILE"), пропускаем"
            continue
        fi

        echo "✍️ Добавляем IPv6 в конфиг: \$(basename "\$CONFIG_FILE")"
        
        # Заменяем listen [::] на конкретный IPv6-адрес
        sed -i "/listen 80;/a\    listen [\$IPV6]:80;" "\$CONFIG_FILE"
        sed -i "/listen .*443 ssl;/a\    listen [\$IPV6]:443 ssl;" "\$CONFIG_FILE"
    done
done

echo "✅ IPv6 успешно добавлен в конфигурации Nginx."

# Перезапускаем сервисы
if nginx -t; then
    echo "✅ Конфигурация Nginx корректна, перезапускаем..."
    systemctl restart nginx
else
    echo "❌ Ошибка в конфигурации Nginx! Проверьте ошибки перед перезапуском."
fi

echo "🔄 Отключаем Nginx для статики..."
sqlite3 "\$DB_PATH" "UPDATE site SET static_file_handler = 0;"
echo "✅ FastPanel успешно настроен!"

echo "🔄 Ограничиваем лог до 200 строк..."
LOG_FILE="/var/log/fastpanel_ipv6.log"

# Если файл не существует — создаём
if [[ ! -f "\$LOG_FILE" ]]; then
    touch "\$LOG_FILE"
    echo "✅ Лог-файл создан: \$LOG_FILE"
fi

tail -n 200 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"
echo "✅ Очистка логов завершена."
EOF

chmod +x $SCRIPT_PATH
(crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH" || (echo "$CRON_JOB" && echo "$CRON_JOB")) | crontab -

echo "✅ Установка завершена!"
