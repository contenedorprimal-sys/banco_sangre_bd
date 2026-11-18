-- ============================================================================
-- PROYECTO: BANCO DE SANGRE
-- Archivo 04 · Unidad 4
-- Plan de recuperación de desastres, respaldos y restauración.
--
-- Este archivo documenta el procedimiento. Los comandos de shell se ejecutan
-- fuera de MySQL Workbench (ver 04_respaldo_incremental.sh).
-- ============================================================================

USE banco_sangre;

-- ============================================================================
-- PARTE A · REQUERIMIENTOS DE RECUPERACIÓN
-- ============================================================================
-- RTO (Recovery Time Objective): 30 minutos.
--   Justificación: un hospital no puede esperar horas por componentes
--   críticos; hay cirugías y urgencias en curso.
--
-- RPO (Recovery Point Objective): 15 minutos.
--   Justificación: como máximo se tolera perder 15 minutos de capturas
--   (donaciones, pruebas, salidas). Con binlog + incremental cada 15 min
--   se cumple.
--
-- Estrategia:
--   - Respaldo lógico completo diario a las 02:00 (mysqldump).
--   - Respaldo incremental del binlog cada 15 minutos.
--   - Copia externa (off-site) cifrada.
--   - Restauración probada cada trimestre.
--   - Retención: 30 días completos, 12 meses mensuales, 7 años auditoría.
-- ============================================================================

-- ============================================================================
-- PARTE B · RESPALDO LÓGICO COMPLETO
-- ============================================================================
-- Ejecutar en terminal (no dentro de Workbench):
--
-- mysqldump \
--   --host=127.0.0.1 \
--   --user=dba_sangre \
--   --password \
--   --single-transaction \
--   --routines \
--   --triggers \
--   --events \
--   --set-gtid-purged=OFF \
--   --databases banco_sangre \
--   > /respaldo/banco_sangre_completo_$(date +%Y%m%d_%H%M).sql
--
-- --single-transaction: consistencia sin bloquear la operación (InnoDB).
-- --routines/--triggers/--events: incluye procedimientos, triggers y eventos.
-- --databases: guarda el CREATE DATABASE y el USE.
--
-- Verificación del respaldo:
--   gzip -c /respaldo/banco_sangre_completo_*.sql | sha256sum > respaldo.sha256
--   ls -lh /respaldo/
--
-- ============================================================================
-- PARTE C · RESPALDO INCREMENTAL CON BINLOG
-- ============================================================================
-- 1. Confirmar que el binlog está activo:
SHOW VARIABLES WHERE Variable_name IN (
  'log_bin', 'binlog_format', 'binlog_expire_logs_seconds', 'server_id'
);

-- 2. Ver los archivos de binlog disponibles:
SHOW BINARY LOGS;

-- 3. Guardar la posición antes de una ventana de cambios.
--    En MySQL 8.4+ cambió a SHOW BINARY LOG STATUS.
SHOW MASTER STATUS;
-- SHOW BINARY LOG STATUS;  -- MySQL 8.4+

-- 4. Copiar los binlogs a un directorio seguro (en terminal):
--    mysqlbinlog --read-from-remote-server \
--      --host=127.0.0.1 --user=dba_sangre --password \
--      --raw --stop-never mysql-bin.000001 \
--      --result-file=/respaldo/binlog/
--
-- 5. Para restaurar hasta un punto exacto:
--    mysqlbinlog --start-datetime="2026-11-01 00:00:00" \
--                --stop-datetime="2026-11-01 12:00:00" \
--      /respaldo/binlog/mysql-bin.000001 \
--      | mysql --user=dba_sangre --password banco_sangre

-- ============================================================================
-- PARTE D · SIMULACIÓN DE PÉRDIDA Y RESTAURACIÓN
-- ============================================================================
-- Escenario: alguien borra por error las unidades del despacho en tránsito.
-- PASO 1: registrar el estado previo.
SELECT COUNT(*) AS unidades_antes FROM unidades_sangre;
SELECT COUNT(*) AS despachos_antes FROM despachos;

-- PASO 2: simular el error (en una transacción, para poder deshacer).
START TRANSACTION;
DELETE FROM despacho_detalle WHERE id_despacho = 3;
DELETE FROM unidades_sangre WHERE id_unidad IN (11, 12);
SELECT COUNT(*) AS unidades_despues_del_error FROM unidades_sangre;
ROLLBACK; -- en el simulacro no se pierde nada

-- En un incidente real NO se hace ROLLBACK: se restaura desde el respaldo.
-- PASO 3: restaurar el respaldo completo (terminal):
--   mysql --user=dba_sangre --password < /respaldo/banco_sangre_completo_20261101_0200.sql
--
-- PASO 4: aplicar binlog hasta el minuto anterior al borrado:
--   mysqlbinlog --stop-datetime="2026-11-01 11:59:00" \
--     /respaldo/binlog/mysql-bin.000123 | mysql --user=dba_sangre --password banco_sangre
--
-- PASO 5: validar integridad y conteos.
SELECT COUNT(*) AS unidades_restauradas FROM unidades_sangre;
SELECT COUNT(*) AS despachos_restaurados FROM despachos;

-- PASO 6: comprobar que no hay huérfanos.
SELECT dd.id_despacho, dd.id_unidad
FROM despacho_detalle dd
LEFT JOIN despachos d ON d.id_despacho = dd.id_despacho
LEFT JOIN unidades_sangre u ON u.id_unidad = dd.id_unidad
WHERE d.id_despacho IS NULL OR u.id_unidad IS NULL;

-- ============================================================================
-- PARTE E · CHECKLIST DE VERIFICACIÓN
-- ============================================================================
-- [ ] El respaldo completo termina sin errores y pesa un tamaño razonable.
-- [ ] El archivo se puede abrir y contiene CREATE TABLE.
-- [ ] El checksum coincide con el del servidor de respaldo.
-- [ ] La restauración en un servidor limpio reproduce los conteos.
-- [ ] Los triggers y eventos existen después de restaurar.
-- [ ] El binlog permite recuperar hasta el minuto del incidente.
-- [ ] El tiempo real de restauración es <= RTO (30 min).
-- [ ] El punto de recuperación es <= RPO (15 min).
-- ============================================================================
