#!/bin/bash

SCRIPT_PATH="/usr/local/bin/fastpanel_add_ipv6.sh"
CRON_JOB="*/15 * * * * /usr/local/bin/fastpanel_add_ipv6.sh > /var/log/fastpanel_ipv6.log 2>&1"

echo "🔄 Создаём скрипт для добавления IPv6 и отключения Nginx для статики..."
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
SELECT (SELECT MAX(id) FROM ips) + ROW_NUMBER() OVER (), '\$IPV6', id 
FROM site WHERE id NOT IN (SELECT virtualhost_id FROM ips WHERE ip LIKE '%:%');
"

echo "✅ IPv6-адреса успешно добавлены в FastPanel 2."

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

# Проверяем конфигурацию перед перезапуском
echo "🔄 Проверяем конфигурацию Nginx..."
if nginx -t; then
    echo "✅ Конфигурация Nginx корректна, перезапускаем..."
    systemctl restart fastpanel2
    systemctl restart nginx
    echo "✅ Настройка завершена. IPv4 + IPv6 теперь активны для всех сайтов в FastPanel."
else
    echo "❌ Ошибка в конфигурации Nginx! Проверьте ошибки перед перезапуском."
fi

# 🔄 Отключаем Nginx для статических файлов
echo "🔄 Отключаем Nginx для статических файлов на всех сайтах..."
sqlite3 "\$DB_PATH" "UPDATE site SET static_file_handler = 0;"
echo "✅ Nginx для статических файлов отключен для всех сайтов."

# Перезапускаем FastPanel
echo "🔄 Перезапускаем FastPanel..."
systemctl restart fastpanel2
echo "✅ FastPanel успешно перезапущен!"

echo "🎉 Готово! Все сайты работают через PHP."

# Ограничиваем лог до 200 строк
LOG_FILE="/var/log/fastpanel_ipv6.log"
echo "🔄 Ограничиваем лог до 200 строк..."
tail -n 200 "\$LOG_FILE" > "\$LOG_FILE.tmp" && mv "\$LOG_FILE.tmp" "\$LOG_FILE"

echo "✅ Очистка логов завершена."
EOF

echo "✅ Скрипт создан: $SCRIPT_PATH"

# Делаем скрипт исполняемым
chmod +x $SCRIPT_PATH
echo "✅ Выданы права на выполнение"

# Добавляем скрипт в cron (если его ещё нет)
(crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH" || echo "$CRON_JOB") | crontab -

echo "✅ Скрипт добавлен в cron: каждые 15 минут"

# Проверяем, записался ли он
echo "🔄 Проверяем крон..."
crontab -l | grep fastpanel_add_ipv6.sh

echo "🎉 Установка завершена!"

