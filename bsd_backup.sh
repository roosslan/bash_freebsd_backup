#!/bin/sh

BACKUP_DIR=/var/backups/confluence
BACKUP_FILE="$(hostname)-$(date +%Y-%m-%dT%H:%M:%S).tar.gz"
BACKUP_PATHS="/usr/local/confluence/
/usr/local/etc/"

# Expand wildcards and remove invalid (non-existent) paths from the list
VALID_PATHS=''
for CONFIG_PATH in $BACKUP_PATHS; do
        if [ -e "$CONFIG_PATH" ]; then
                VALID_PATHS="$VALID_PATHS$CONFIG_PATH
"
        fi
done


echo 'Backing up Confluence files...'

echo -n "$VALID_PATHS" | tar -czf "$BACKUP_DIR/$BACKUP_FILE" -T -

if [ -e "$BACKUP_DIR/$BACKUP_FILE" ] && [ -s "$BACKUP_DIR/$BACKUP_FILE" ]; then
        chmod 640 "$BACKUP_DIR/$BACKUP_FILE"
        echo "Saved to: $BACKUP_DIR/$BACKUP_FILE"
else
        echo 'Error creating backup!'
fi

# uploading tar.gz file to NAS using scp certificates
scp -i /path/to/id_rsa $BACKUP_DIR/$BACKUP_FILE username@remote_host:/confluence/$BACKUP_FILE

# Deleting files older than 30 days
find /var/backups/confluence -type f -mtime +30d -delete

exit 0
