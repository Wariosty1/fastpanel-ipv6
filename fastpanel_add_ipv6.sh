#!/bin/bash

# Путь к базе данных FastPanel
DB_PATH="/usr/local/fastpanel2/app/db/fastpanel2.db"

# Проверяем, существует ли база данных
if [[ ! -f "$DB_PATH" ]]; then
    echo "❌ Ошибка: База данных FastPanel не найдена."
    exit 1
fi

echo "✅ Найдена база данных FastPanel."

# Отключаем обработку статики в FastPanel (меняем `static_file_handler` на 0)
sqlite3 "$DB_PATH" "UPDATE site SET static_file_handler = 0;"

echo "✅ Nginx для статики отключен в базе данных FastPanel."

# Добавляем событие в `queue_event`, чтобы FastPanel обработал изменения
sqlite3 "$DB_PATH" "
INSERT INTO queue_event (id, domain, uuid, type, category, action, priority, user, user_class, user_id, status, created_by, ip, details, created_at, updated_at) 
VALUES (
    (SELECT COALESCE(MAX(id), 0) + 1 FROM queue_event), 
    'fastpanel', 
    '$(uuidgen)', 'panel.job', 'PANEL', 'UPDATING', 
    1, 'fastuser', 'FVPS\\UserBundle\\Entity\\FpUser', 1, 
    'SUCCESS', 78, '', '', datetime('now'), datetime('now')
);
"

echo "✅ FastPanel получил команду обновления."

# Перезапускаем FastPanel, чтобы изменения вступили в силу
systemctl restart fastpanel2
echo "✅ FastPanel принудительно обновлён."

