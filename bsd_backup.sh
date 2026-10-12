#!/bin/sh
#
# Резервное копирование Confluence на FreeBSD: дамп базы + файлы,
# выгрузка на NAS по scp и удаление старых локальных копий.
#
# Коды выхода:
#   0 - успех
#   1 - ошибка настройки (нет директории, утилиты, путей)
#   2 - ошибка дампа базы
#   3 - ошибка создания архива
#   4 - ошибка выгрузки на NAS

set -u
umask 077

# --- Настройки ---

BACKUP_DIR=/var/backups/confluence
KEEP_DAYS=30

# Директории и файлы для архива (по одному на строку, шаблоны раскрываются)
BACKUP_PATHS="/var/db/confluence-home
/usr/local/confluence/conf
/usr/local/etc
/etc"

# База данных: postgresql или mysql
DB_TYPE=postgresql
DB_NAME=confluence
DB_USER=confluence
DB_HOST=localhost
# Пароль задавать в ~/.pgpass (PostgreSQL) или ~/.my.cnf (MySQL)

# Выгрузка на NAS
SSH_KEY=/root/.ssh/backup_ed25519
REMOTE_TARGET="backup@nas.example:/confluence/"

# --- Вспомогательные функции ---

log() {
	logger -t confluence-backup "$*"
	echo "$*" >&2
}

fail() {
	code=$1
	shift
	log "ОШИБКА: $*"
	exit "$code"
}

# --- Подготовка ---

STAMP=$(date +%Y%m%d-%H%M%S)
NAME="$(hostname -s)-$STAMP"
DB_FILE="$BACKUP_DIR/$NAME.db.gz"
ARCHIVE_FILE="$BACKUP_DIR/$NAME.tar.gz"

mkdir -p "$BACKUP_DIR" || fail 1 "не удалось создать $BACKUP_DIR"

# Раскрыть шаблоны и отбросить несуществующие пути
VALID_PATHS=''
OLD_IFS=$IFS
IFS='
'
for CONFIG_PATH in $BACKUP_PATHS; do
	if [ -e "$CONFIG_PATH" ]; then
		VALID_PATHS="$VALID_PATHS$CONFIG_PATH
"
	else
		log "пропущен несуществующий путь: $CONFIG_PATH"
	fi
done
IFS=$OLD_IFS

[ -n "$VALID_PATHS" ] || fail 1 "ни один путь из BACKUP_PATHS не существует"

# --- Дамп базы ---

log "Дамп базы $DB_NAME ($DB_TYPE)..."

# Код выхода дампа сохраняется через файл, т.к. в sh нет pipefail
DUMP_RC_FILE="$BACKUP_DIR/.dump_rc.$$"
case "$DB_TYPE" in
postgresql)
	command -v pg_dump >/dev/null || fail 1 "pg_dump не найден"
	{ pg_dump -h "$DB_HOST" -U "$DB_USER" -w "$DB_NAME"; echo $? > "$DUMP_RC_FILE"; } \
		| gzip > "$DB_FILE"
	;;
mysql)
	command -v mysqldump >/dev/null || fail 1 "mysqldump не найден"
	{ mysqldump -h "$DB_HOST" -u "$DB_USER" --single-transaction "$DB_NAME"; echo $? > "$DUMP_RC_FILE"; } \
		| gzip > "$DB_FILE"
	;;
*)
	fail 1 "неизвестный DB_TYPE: $DB_TYPE"
	;;
esac
GZIP_RC=$?
DUMP_RC=$(cat "$DUMP_RC_FILE" 2>/dev/null || echo 1)
rm -f "$DUMP_RC_FILE"

if [ "$DUMP_RC" -ne 0 ] || [ "$GZIP_RC" -ne 0 ] || [ ! -s "$DB_FILE" ]; then
	rm -f "$DB_FILE"
	fail 2 "дамп базы не создан (dump=$DUMP_RC, gzip=$GZIP_RC)"
fi
log "Дамп сохранён: $DB_FILE"

# --- Архив файлов ---

log 'Архивирование файлов Confluence...'

if ! printf '%s' "$VALID_PATHS" | tar -czf "$ARCHIVE_FILE" -T - || [ ! -s "$ARCHIVE_FILE" ]; then
	rm -f "$ARCHIVE_FILE"
	fail 3 "архив не создан"
fi
log "Архив сохранён: $ARCHIVE_FILE"

# --- Выгрузка на NAS ---

log "Выгрузка на $REMOTE_TARGET..."

scp -q -o BatchMode=yes -i "$SSH_KEY" "$DB_FILE" "$ARCHIVE_FILE" "$REMOTE_TARGET" \
	|| fail 4 "выгрузка на NAS не удалась, локальные копии сохранены"

# --- Удаление старых копий (только после успешного бэкапа) ---

find "$BACKUP_DIR" -type f \( -name '*.tar.gz' -o -name '*.db.gz' \) \
	-mtime +"$KEEP_DAYS" -delete

log "Резервное копирование завершено: $NAME"
exit 0
