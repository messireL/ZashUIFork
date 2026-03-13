# UI Mihomo/Ultra — перенос в новый чат

Проект: UI Mihomo/Ultra (форк Zashboard UI)
Репозиторий: messireL/ZashUIFork
Линейка версий: 1.1.x
Текущая версия архива: v1.1.91

Ключевые особенности:
- отдельные пункты меню: Прокси и Прокси-провайдеры
- multi-cloud backup через rclone и router-agent
- cloud remotes из одного rclone.config через RCLONE_REMOTES
- cron backup на роутере работает через /opt/var/spool/cron/crontabs/root
- трафик Сегодня у провайдеров ещё требует дальнейшей доработки/проверки

Что важно не ломать:
- рабочую логику активности провайдеров
- крестик у провайдера — только disconnect active sessions
- cloud/local restore backup
- поддержку RCLONE_CONFIG, RCLONE_REMOTES, RCLONE_PATH

Отложенные задачи:
- разобраться с отображением архивов в облачном проводнике
- довести подсчёт трафика Сегодня у прокси-провайдеров
- при желании добавить диаграмму трафика в стиле Netcraze UI, но не завязывать её только на стандартный источник Netcraze, потому что трафик через XKeen там не виден
