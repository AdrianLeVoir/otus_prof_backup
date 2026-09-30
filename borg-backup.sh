#!/bin/bash
# hw16: удалённый бэкап /etc по borgbackup с логированием в syslog
set -o pipefail

export BORG_PASSPHRASE='Otus1234'
REPO="borg@192.168.1.157:/var/backup/"
TARGET="/etc"
TAG="borg-backup"

exec > >(logger -t "$TAG") 2>&1

echo "=== start backup: $(date -Is) ==="

borg create --stats --compression zstd "${REPO}::etc-{now:%Y-%m-%d_%H:%M:%S}" "$TARGET" \
    || { echo "ERROR: borg create failed"; exit 1; }

borg check "$REPO" \
    || echo "WARN: borg check failed"

borg prune --stats \
    --keep-daily 90 \
    --keep-monthly 12 \
    --keep-yearly 1 \
    "$REPO" \
    || echo "WARN: borg prune failed"

echo "=== done: $(date -Is) ==="
