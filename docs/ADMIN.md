# Руководство системного администратора

## Назначение модуля
Модуль разворачивает локальный офлайн-портал авторизации для посетителей магазина с управлением через страницу `http://10.0.0.1/admin` и интеграцией с NoDogSplash.

## Требования окружения
* OpenWrt 24.10.x.
* Доступ к `opkg` для установки зависимостей: `nodogsplash`, `uhttpd`, `coreutils-date` (для расширенного `date`), модуль CGI для `uhttpd` (входит в основной пакет), `cron` (busybox).
* Права `root`.

## Установка

1. Скопируйте содержимое репозитория на роутер (например, в `/root/wifi_auth`).
2. Запустите установщик:
   ```sh
   sh installer/install.sh
   ```
3. Скрипт проверит и доустановит зависимости, остановит `nodogsplash`, развернёт файлы портала и пропишет cron-задание.
4. После успешного завершения настройте параметры в админке и включите портал авторизации.

### Быстрая установка напрямую из GitHub

Если нужно быстро развернуть только веб-портал и CGI-скрипты (без дополнительных проверок зависимостей), воспользуйтесь облегчённым установщиком `install_portal_minimal.sh`. Он скачивает актуальные HTML/CGI-файлы из ветки `main` и настраивает `uhttpd` и cron.

```sh
cd /tmp
wget -O install_portal.sh \
  "https://raw.githubusercontent.com/DoNBaLooN/pvzrouter/main/installer/install_portal_minimal.sh"
sh install_portal.sh
```

Скрипт можно запустить с переменными окружения, чтобы переопределить пути по умолчанию. Например, чтобы установить портал в `/mnt/router/www` и хранить конфигурацию в `/overlay/etc/config/wifi_auth`:

```sh
WWW_DIR=/mnt/router/www \
CONFIG_PATH=/overlay/etc/config/wifi_auth \
sh install_portal.sh
```

После завершения обновите конфигурацию через админ-панель и перезапустите `uhttpd`, если этого не сделал скрипт.

Повторный запуск `install.sh` безопасен: существующие файлы резервируются с суффиксом `.bak` и настройки UCI обновляются только для отсутствующих опций.

## Структура, разворачиваемая установщиком
```
/www/
  index.html
  success.html
  admin.html
  css/wifi_auth.css
  cgi-bin/
    wifi_auth.sh
    update_code.sh
    clear_sessions.sh
    session_check.sh
    nds_control.sh
    admin_mac.sh
    admin_portal.sh
    metrics.sh
/etc/config/wifi_auth
/tmp/active_sessions.txt
```

## Интеграция с NoDogSplash
* При установке сервис останавливается и отключается из автозапуска.
* Кнопка «Включить/Выключить портал» в админке синхронизирует состояние `nds_enabled` в UCI и выполняет `start/stop + enable/disable`.
* Дополнительные команды отправляются через `nodogsplashctl` (или `ndsctl` как запасной вариант).

## Cron и очистка сессий
* В `/etc/crontabs/root` добавляется строка `*/5 * * * * /www/cgi-bin/session_check.sh >/dev/null 2>&1`.
* Скрипт `session_check.sh` удаляет просроченные записи из `/tmp/active_sessions.txt` и вызывает `nodogsplashctl deauth` для клиентов.
* Администраторские MAC-адреса (из `wifi_auth.portal.admin_mac_whitelist`) не затрагиваются.

## HTTP Basic Auth
* Параметры хранятся в UCI (`basic_auth_enabled`, `basic_auth_user`, `basic_auth_password`).
* При включении создаётся файл `/etc/httpd-wifi-auth.users`. Значение `basic_auth_password` должно содержать строку вида `user:$p$hash`, совместимую с `uhttpd` (например, созданную командой `uhttpd -m <пароль>`).
* Отключение опции удаляет файл и настройки авторизации.

## Логи и диагностика
* Все операции скриптов пишут в syslog с тегом `wifi_auth` (`logread -e wifi_auth`).
* Метрики Prometheus доступны по `http://10.0.0.1/cgi-bin/metrics.sh`.
* Временное состояние клиентов хранится в `/tmp/active_sessions.txt` (формат: `MAC|expiry_epoch|ip|created_epoch`).

## Обновление модуля
1. Перенесите свежие файлы поверх существующих.
2. Запустите `installer/install.sh` — он обновит HTML/CGI и повторно применит настройки.
3. Проверите доступность админки и состояние NDS.

## Восстановление после сбоя
* Если пропала авторизация, убедитесь, что сервис `nodogsplash` запущен и включён в автозапуск (`/etc/init.d/nodogsplash {start|enable}`).
* При повреждении `/tmp/active_sessions.txt` можно удалить файл — он будет создан заново при следующем запросе.
* Для отката к предыдущей версии файлов используйте резервные копии `*.bak`, созданные установщиком.

## Безопасность
* Убедитесь, что доступ к `http://10.0.0.1/admin` возможен только из LAN (firewall OpenWrt делает это по умолчанию).
* Рекомендуется включить Basic Auth и использовать отдельную VLAN/Wi-Fi для администраторов.
* Не храните пароли в открытом виде в UCI: используйте хеши.
