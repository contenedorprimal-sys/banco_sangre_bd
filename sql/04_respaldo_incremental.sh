#!/usr/bin/env bash
# ============================================================================
# PROYECTO: BANCO DE SANGRE · Unidad 4
# Respaldo completo + copia del binlog.
#
# Uso:
#   chmod +x 04_respaldo_incremental.sh
#   ./04_respaldo_incremental.sh
#
# Requisitos:
#   - mysql-client / mysqldump instalados (mysqlbinlog para copiar el binlog)
#   - variable MYSQL_PWD o archivo ~/.my.cnf para no escribir la contraseña
#   - usuario con privilegios RELOAD, REPLICATION CLIENT y SELECT
# ============================================================================

set -euo pipefail

DB="${DB:-banco_sangre}"
USER="${DB_USER:-dba_sangre}"
HOST="${DB_HOST:-127.0.0.1}"
DEST="${BACKUP_DIR:-/respaldo/banco_sangre}"
STAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$DEST/completos" "$DEST/binlogs"

echo "== 1/3 Respaldo completo =="
mysqldump \
  --host="$HOST" \
  --user="$USER" \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  --set-gtid-purged=OFF \
  --databases "$DB" \
  > "$DEST/completos/${DB}_${STAMP}.sql"

gzip -f "$DEST/completos/${DB}_${STAMP}.sql"
sha256sum "$DEST/completos/${DB}_${STAMP}.sql.gz" > "$DEST/completos/${DB}_${STAMP}.sha256"

echo "== 2/3 Copia del binlog actual =="
BINLOG_FILE="$(mysql --host="$HOST" --user="$USER" -N -e 'SHOW BINARY LOG STATUS' 2>/dev/null | awk 'NF{print $1; exit}')" || BINLOG_FILE=""
if [ -z "$BINLOG_FILE" ]; then
  BINLOG_FILE="$(mysql --host="$HOST" --user="$USER" -N -e 'SHOW MASTER STATUS' | awk 'NF{print $1; exit}')"
fi
if [ -n "$BINLOG_FILE" ] && command -v mysqlbinlog >/dev/null 2>&1; then
  mysqlbinlog --read-from-remote-server \
    --host="$HOST" --user="$USER" \
    --raw "$BINLOG_FILE" \
    --result-file="$DEST/binlogs/${BINLOG_FILE}.${STAMP}"
elif [ -n "$BINLOG_FILE" ]; then
  echo "AVISO: mysqlbinlog no está instalado; se omite la copia del binlog." >&2
fi

echo "== 3/3 Resumen =="
ls -lh "$DEST/completos" "$DEST/binlogs"
echo "Respaldo terminado: $STAMP"
