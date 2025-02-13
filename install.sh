#!/bin/bash

# Устанавливаем скрипт в нужную директорию
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="fastpanel_add_ipv6.sh"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

echo "🔄 Устанавливаем скрипт..."

# Загружаем скрипт
curl -o "$SCRIPT_PATH" https://raw.githubusercontent.com/Wariosty1/fastpanel-ipv6/main/$SCRIPT_NAME

# Даем права на выполнение
chmod +x "$SCRIPT_PATH"

# Добавляем в crontab (каждые 15 минут)
(crontab -l 2>/dev/null; echo "*/15 * * * * $SCRIPT_PATH") | crontab -

echo "✅ Установка завершена! Скрипт запустится каждые 15 минут."
