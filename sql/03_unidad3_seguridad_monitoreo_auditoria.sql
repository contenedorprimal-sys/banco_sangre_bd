-- ============================================================================
-- PROYECTO: BANCO DE SANGRE
-- Archivo 03 · Unidad 3
-- Roles, privilegios, monitoreo y auditoría.
--
-- Requiere: 00_esquema.sql y 01_datos_demo.sql
-- ============================================================================

USE banco_sangre;

-- ============================================================================
-- PARTE A · ROLES Y MÍNIMO PRIVILEGIO
-- ============================================================================
-- Tres perfiles reales del banco de sangre:
--   laboratorio  -> captura pruebas, actualiza resultados, consulta unidades
--   recepcion    -> consulta inventario y crea solicitudes de hospitales
--   auditor      -> solo lectura sobre auditoría y bitácoras
--   dba          -> administración completa
-- ============================================================================

DROP ROLE IF EXISTS rol_laboratorio;
DROP ROLE IF EXISTS rol_recepcion;
DROP ROLE IF EXISTS rol_auditor;
DROP ROLE IF EXISTS rol_dba_sangre;

CREATE ROLE rol_laboratorio;
CREATE ROLE rol_recepcion;
CREATE ROLE rol_auditor;
CREATE ROLE rol_dba_sangre;

-- Laboratorio: no puede borrar unidades ni cambiar donantes.
GRANT SELECT, INSERT, UPDATE ON banco_sangre.pruebas_laboratorio TO rol_laboratorio;
GRANT SELECT, UPDATE ON banco_sangre.unidades_sangre TO rol_laboratorio;
GRANT SELECT ON banco_sangre.donaciones TO rol_laboratorio;
GRANT SELECT ON banco_sangre.v_unidades_disponibles TO rol_laboratorio;

-- Recepción de hospital: solo ve inventario disponible y captura solicitudes.
GRANT SELECT ON banco_sangre.v_unidades_disponibles TO rol_recepcion;
GRANT SELECT, INSERT ON banco_sangre.solicitudes TO rol_recepcion;
GRANT SELECT, INSERT ON banco_sangre.solicitud_detalle TO rol_recepcion;
GRANT SELECT ON banco_sangre.hospitales TO rol_recepcion;

-- Auditor: lectura de evidencia, sin tocar la operación.
GRANT SELECT ON banco_sangre.auditoria_unidades TO rol_auditor;
GRANT SELECT ON banco_sangre.bitacora_disponibilidad TO rol_auditor;

-- DBA: control total del esquema.
GRANT ALL PRIVILEGES ON banco_sangre.* TO rol_dba_sangre;

-- Usuarios de ejemplo. En producción: contraseñas gestionadas y rotadas.
DROP USER IF EXISTS 'lab_user'@'localhost';
DROP USER IF EXISTS 'recepcion_user'@'localhost';
DROP USER IF EXISTS 'auditor_user'@'localhost';
DROP USER IF EXISTS 'dba_sangre'@'localhost';

CREATE USER 'lab_user'@'localhost' IDENTIFIED BY 'Lab#2026';
CREATE USER 'recepcion_user'@'localhost' IDENTIFIED BY 'Rec#2026';
CREATE USER 'auditor_user'@'localhost' IDENTIFIED BY 'Aud#2026';
CREATE USER 'dba_sangre'@'localhost' IDENTIFIED BY 'Dba#2026';

GRANT rol_laboratorio TO 'lab_user'@'localhost';
GRANT rol_recepcion   TO 'recepcion_user'@'localhost';
GRANT rol_auditor     TO 'auditor_user'@'localhost';
GRANT rol_dba_sangre  TO 'dba_sangre'@'localhost';

SET DEFAULT ROLE ALL TO
  'lab_user'@'localhost',
  'recepcion_user'@'localhost',
  'auditor_user'@'localhost',
  'dba_sangre'@'localhost';

-- Comprobación: qué puede hacer cada usuario.
SHOW GRANTS FOR 'lab_user'@'localhost';
SHOW GRANTS FOR 'recepcion_user'@'localhost';
SHOW GRANTS FOR 'auditor_user'@'localhost';

-- ============================================================================
-- PARTE B · AUDITORÍA CON TRIGGERS
-- ============================================================================
-- La operación sensible es cambiar el estado de una unidad: de disponible a
-- despachada, vencida o descartada. Sin evidencia no hay trazabilidad.
-- ============================================================================

DROP TRIGGER IF EXISTS trg_unidades_after_insert;
DROP TRIGGER IF EXISTS trg_unidades_after_update;
DROP TRIGGER IF EXISTS trg_unidades_after_delete;

DELIMITER $$

CREATE TRIGGER trg_unidades_after_insert
AFTER INSERT ON unidades_sangre
FOR EACH ROW
BEGIN
  INSERT INTO auditoria_unidades
    (id_unidad, accion, usuario, datos_anteriores, datos_nuevos)
  VALUES (
    NEW.id_unidad,
    'INSERT',
    CURRENT_USER(),
    NULL,
    JSON_OBJECT(
      'codigo_barras', NEW.codigo_barras,
      'tipo_componente', NEW.tipo_componente,
      'grupo_abo', NEW.grupo_abo,
      'factor_rh', NEW.factor_rh,
      'estado', NEW.estado
    )
  );
END$$

CREATE TRIGGER trg_unidades_after_update
AFTER UPDATE ON unidades_sangre
FOR EACH ROW
BEGIN
  INSERT INTO auditoria_unidades
    (id_unidad, accion, usuario, datos_anteriores, datos_nuevos)
  VALUES (
    NEW.id_unidad,
    'UPDATE',
    CURRENT_USER(),
    JSON_OBJECT(
      'estado', OLD.estado,
      'ubicacion', OLD.ubicacion,
      'fecha_vencimiento', OLD.fecha_vencimiento
    ),
    JSON_OBJECT(
      'estado', NEW.estado,
      'ubicacion', NEW.ubicacion,
      'fecha_vencimiento', NEW.fecha_vencimiento
    )
  );
END$$

CREATE TRIGGER trg_unidades_after_delete
AFTER DELETE ON unidades_sangre
FOR EACH ROW
BEGIN
  INSERT INTO auditoria_unidades
    (id_unidad, accion, usuario, datos_anteriores, datos_nuevos)
  VALUES (
    OLD.id_unidad,
    'DELETE',
    CURRENT_USER(),
    JSON_OBJECT(
      'codigo_barras', OLD.codigo_barras,
      'tipo_componente', OLD.tipo_componente,
      'estado', OLD.estado
    ),
    NULL
  );
END$$

DELIMITER ;

-- Prueba controlada de auditoría (no borra nada).
UPDATE unidades_sangre
SET estado = 'reservada'
WHERE id_unidad = 8;

UPDATE unidades_sangre
SET estado = 'disponible'
WHERE id_unidad = 8;

SELECT id_auditoria, id_unidad, accion, usuario, fecha,
       datos_anteriores, datos_nuevos
FROM auditoria_unidades
ORDER BY id_auditoria DESC
LIMIT 5;

-- ============================================================================
-- PARTE C · MONITOREO BÁSICO
-- ============================================================================

-- C.1 Estado general del servidor.
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME IN (
  'Uptime',
  'Threads_connected',
  'Threads_running',
  'Questions',
  'Slow_queries',
  'Aborted_connects',
  'Innodb_buffer_pool_read_requests',
  'Innodb_buffer_pool_reads'
);

-- C.2 Consultas activas (performance_schema desde MySQL 8.0.22).
SELECT id, user, host, db, command, time, state, LEFT(info, 120) AS consulta
FROM performance_schema.processlist
WHERE command <> 'Sleep'
ORDER BY time DESC;

-- C.3 Eventos programados y su último estado.
SELECT event_schema, event_name, status, interval_value, interval_field,
       last_executed, last_altered
FROM information_schema.events
WHERE event_schema = 'banco_sangre';

-- C.4 Espacio y crecimiento por tabla.
SELECT
  table_name,
  table_rows,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb,
  ROUND(index_length / NULLIF(data_length + index_length, 0) * 100, 2) AS pct_indices
FROM information_schema.tables
WHERE table_schema = 'banco_sangre'
ORDER BY (data_length + index_length) DESC;

-- C.5 Consultas más costosas (MySQL 8 performance_schema).
-- Los timers están en picosegundos: 1 s = 1e12 y 1 ms = 1e9.
SELECT
  DIGEST_TEXT,
  COUNT_STAR AS ejecuciones,
  ROUND(SUM_TIMER_WAIT / 1000000000000, 3) AS segundos_totales,
  ROUND(AVG_TIMER_WAIT / 1000000000, 3) AS ms_promedio
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME = 'banco_sangre'
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- C.6 Disponibilidad observada a partir de la bitácora.
-- Uptime siempre crece; un salto negativo o un hueco > 1 hora sugiere reinicio
-- o caída. Esta consulta marca los huecos entre snapshots.
SELECT
  fecha_registro,
  uptime_seg,
  TIMESTAMPDIFF(MINUTE,
    LAG(fecha_registro) OVER (ORDER BY fecha_registro),
    fecha_registro) AS minutos_desde_anterior
FROM bitacora_disponibilidad
ORDER BY fecha_registro DESC
LIMIT 20;

-- ============================================================================
-- PARTE D · PROBLEMA DE DISPONIBILIDAD Y MITIGACIÓN
-- ============================================================================
-- Problema elegido: punto único de falla (SPOF) del servidor MySQL.
--
-- Mitigación documentada:
--   1. Réplica asíncrona para lectura y respaldo caliente.
--   2. InnoDB Cluster (Group Replication + Router) para failover automático.
--   3. Respaldos completos diarios + binlog cada 15 minutos.
--   4. Monitoreo del Uptime y alertas si no hay snapshots en 70 minutos.
--   5. Ensayo de failover trimestral (no basta con configurarlo).
--
-- Métricas objetivo del banco de sangre:
--   Disponibilidad 99.9% -> ~8.77 h de caída al año.
--   RTO 30 min, RPO 15 min.
-- ============================================================================
