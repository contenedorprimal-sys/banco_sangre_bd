-- ============================================================================
-- PROYECTO: BANCO DE SANGRE
-- Archivo 02 · Unidad 2
-- Espacios, particiones y automatización.
--
-- Requiere: 00_esquema.sql y 01_datos_demo.sql
-- ============================================================================

USE banco_sangre;

-- ============================================================================
-- PARTE A · ESTIMACIÓN DE ESPACIO A UN AÑO
-- ============================================================================
-- Regla de clase:
--   bytes_fila = suma de bytes de columnas
--   datos      = bytes_fila * filas_esperadas
--   índices    = +10% a +30% (aquí usamos 20%)
--   crecimiento= *1.20 a *1.30
--
-- Tamaños de referencia:
--   INT = 4, BIGINT = 8, DATE = 3, DATETIME = 8, TINYINT = 1
--   DECIMAL(p,s) ≈ p/2 + 1 (aprox.), ENUM = 1 o 2
--   VARCHAR(n) = n bytes en el peor caso (estimación conservadora)
-- ============================================================================

-- Proyección manual con variables. Cambia los valores para simular otro año.
SET @filas_donantes     = 8000;   -- 8 mil donantes nuevos al año
SET @bytes_donantes     = 60 + 60 + 60 + 3 + 2 + 2 + 20 + 120 + 160 + 8 + 1;
SET @filas_donaciones   = 6000;   -- 6 mil donaciones al año
SET @bytes_donaciones   = 4 + 4 + 8 + 2 + 80 + 5 + 4 + 12 + 2 + 255;
SET @filas_unidades     = 12000;  -- cada donación genera ~2 componentes
SET @bytes_unidades     = 4 + 4 + 40 + 2 + 2 + 2 + 4 + 3 + 3 + 2 + 40;
SET @filas_pruebas      = 60000;  -- ~5 pruebas por unidad
SET @bytes_pruebas      = 4 + 4 + 2 + 2 + 8 + 80 + 255;
SET @filas_movimientos  = 120000; -- el historial crece más rápido
SET @bytes_movimientos  = 8 + 4 + 2 + 8 + 80 + 255;

SELECT
  'donantes' AS tabla,
  @filas_donantes AS filas,
  @bytes_donantes AS bytes_fila,
  ROUND(@filas_donantes * @bytes_donantes / 1024 / 1024, 2) AS datos_mb,
  ROUND(@filas_donantes * @bytes_donantes * 1.20 / 1024 / 1024, 2) AS con_indices_mb,
  ROUND(@filas_donantes * @bytes_donantes * 1.20 * 1.30 / 1024 / 1024, 2) AS con_margen_mb
UNION ALL
SELECT 'donaciones', @filas_donaciones, @bytes_donaciones,
  ROUND(@filas_donaciones * @bytes_donaciones / 1024 / 1024, 2),
  ROUND(@filas_donaciones * @bytes_donaciones * 1.20 / 1024 / 1024, 2),
  ROUND(@filas_donaciones * @bytes_donaciones * 1.20 * 1.30 / 1024 / 1024, 2)
UNION ALL
SELECT 'unidades_sangre', @filas_unidades, @bytes_unidades,
  ROUND(@filas_unidades * @bytes_unidades / 1024 / 1024, 2),
  ROUND(@filas_unidades * @bytes_unidades * 1.20 / 1024 / 1024, 2),
  ROUND(@filas_unidades * @bytes_unidades * 1.20 * 1.30 / 1024 / 1024, 2)
UNION ALL
SELECT 'pruebas_laboratorio', @filas_pruebas, @bytes_pruebas,
  ROUND(@filas_pruebas * @bytes_pruebas / 1024 / 1024, 2),
  ROUND(@filas_pruebas * @bytes_pruebas * 1.20 / 1024 / 1024, 2),
  ROUND(@filas_pruebas * @bytes_pruebas * 1.20 * 1.30 / 1024 / 1024, 2)
UNION ALL
SELECT 'movimientos_inventario', @filas_movimientos, @bytes_movimientos,
  ROUND(@filas_movimientos * @bytes_movimientos / 1024 / 1024, 2),
  ROUND(@filas_movimientos * @bytes_movimientos * 1.20 / 1024 / 1024, 2),
  ROUND(@filas_movimientos * @bytes_movimientos * 1.20 * 1.30 / 1024 / 1024, 2);

-- Lectura real del espacio ocupado (la consulta que sí pide el examen).
SELECT
  table_name AS tabla,
  table_rows AS filas_estimadas,
  ROUND(data_length / 1024 / 1024, 3)  AS datos_mb,
  ROUND(index_length / 1024 / 1024, 3) AS indices_mb,
  ROUND((data_length + index_length) / 1024 / 1024, 3) AS total_mb,
  ROUND(index_length / NULLIF(data_length + index_length, 0) * 100, 2) AS pct_indices
FROM information_schema.TABLES
WHERE table_schema = 'banco_sangre'
  AND table_type = 'BASE TABLE'
ORDER BY (data_length + index_length) DESC;

-- Tamaño total por base de datos.
SELECT
  table_schema AS base,
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES
GROUP BY table_schema
ORDER BY total_mb DESC;

-- ============================================================================
-- PARTE B · FRAGMENTACIÓN / PARTICIONES
-- ============================================================================

-- B.1 RANGE por año: movimientos_inventario ya nace particionada en 00_esquema.
-- Comprobamos que existe y en qué partición cae cada fila.
SELECT
  partition_name,
  partition_method,
  partition_expression,
  table_rows AS filas_estimadas
FROM information_schema.PARTITIONS
WHERE table_schema = 'banco_sangre'
  AND table_name = 'movimientos_inventario'
ORDER BY partition_ordinal_position;

-- El optimizador solo toca la partición del año filtrado.
EXPLAIN
SELECT COUNT(*) AS movimientos_2026
FROM movimientos_inventario
WHERE fecha_movimiento >= '2026-01-01'
  AND fecha_movimiento <  '2027-01-01';

-- B.2 LIST por categoría: copia de solicitudes sin FK.
-- Las tablas particionadas NO pueden tener FOREIGN KEY, por eso es una copia.
-- LIST COLUMNS no acepta ENUM: el estado se guarda como VARCHAR.
DROP TABLE IF EXISTS solicitudes_list;
CREATE TABLE solicitudes_list (
  id_solicitud     INT NOT NULL,
  id_hospital      INT NOT NULL,
  fecha_solicitud  DATETIME NOT NULL,
  prioridad        ENUM('urgente','programada') NOT NULL,
  estado           VARCHAR(10) NOT NULL,
  PRIMARY KEY (id_solicitud, estado)
) ENGINE=InnoDB
PARTITION BY LIST COLUMNS(estado) (
  PARTITION p_pendiente VALUES IN ('pendiente'),
  PARTITION p_parcial   VALUES IN ('parcial'),
  PARTITION p_surtida   VALUES IN ('surtida'),
  PARTITION p_cancelada VALUES IN ('cancelada')
);

INSERT INTO solicitudes_list
SELECT id_solicitud, id_hospital, fecha_solicitud, prioridad, estado
FROM solicitudes;

EXPLAIN
SELECT * FROM solicitudes_list WHERE estado = 'pendiente';

-- B.3 HASH: reparto uniforme sin criterio de negocio.
DROP TABLE IF EXISTS pruebas_hash;
CREATE TABLE pruebas_hash (
  id_prueba    INT NOT NULL,
  id_unidad    INT NOT NULL,
  tipo_prueba  ENUM('VIH','HBV','HCV','sifilis','chagas','grupo_sanguineo','pruebas_cruzadas') NOT NULL,
  resultado    ENUM('negativo','positivo','pendiente') NOT NULL,
  fecha_prueba DATETIME NOT NULL,
  PRIMARY KEY (id_prueba, id_unidad)
) ENGINE=InnoDB
PARTITION BY HASH(id_unidad)
PARTITIONS 4;

INSERT INTO pruebas_hash
SELECT id_prueba, id_unidad, tipo_prueba, resultado, fecha_prueba
FROM pruebas_laboratorio;

SELECT
  partition_name,
  table_rows
FROM information_schema.PARTITIONS
WHERE table_schema = 'banco_sangre'
  AND table_name = 'pruebas_hash'
ORDER BY partition_ordinal_position;

-- ============================================================================
-- PARTE C · AUTOMATIZACIÓN CON EVENT SCHEDULER
-- ============================================================================

SET GLOBAL event_scheduler = ON;
SHOW VARIABLES LIKE 'event_scheduler';

-- C.1 Marcar unidades vencidas cada día a las 03:00.
DROP EVENT IF EXISTS ev_marcar_vencidas;
CREATE EVENT ev_marcar_vencidas
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 3 HOUR)
DO
  UPDATE unidades_sangre
  SET estado = 'vencida'
  WHERE estado = 'disponible'
    AND fecha_vencimiento < CURRENT_DATE;

-- C.2 Registrar el movimiento de vencimiento una sola vez por unidad.
DROP EVENT IF EXISTS ev_registrar_vencimientos;
CREATE EVENT ev_registrar_vencimientos
ON SCHEDULE EVERY 1 DAY
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 4 HOUR)
DO
  INSERT INTO movimientos_inventario (id_unidad, tipo_movimiento, usuario, motivo)
  SELECT u.id_unidad, 'vencimiento', 'event_scheduler', 'Marcado automático por fecha'
  FROM unidades_sangre u
  WHERE u.estado = 'vencida'
    AND NOT EXISTS (
      SELECT 1 FROM movimientos_inventario m
      WHERE m.id_unidad = u.id_unidad
        AND m.tipo_movimiento = 'vencimiento'
    );

-- C.3 Bitácora de Uptime cada hora (monitoreo de disponibilidad).
DROP EVENT IF EXISTS ev_bitacora_uptime;
CREATE EVENT ev_bitacora_uptime
ON SCHEDULE EVERY 1 HOUR
STARTS CURRENT_TIMESTAMP
DO
  INSERT INTO bitacora_disponibilidad (fecha_registro, uptime_seg)
  SELECT NOW(), VARIABLE_VALUE
  FROM performance_schema.global_status
  WHERE VARIABLE_NAME = 'Uptime';

-- C.4 Purgar auditoría vieja cada mes.
DROP EVENT IF EXISTS ev_purgar_auditoria;
CREATE EVENT ev_purgar_auditoria
ON SCHEDULE EVERY 1 MONTH
STARTS (TIMESTAMP(CURRENT_DATE) + INTERVAL 1 MONTH)
DO
  DELETE FROM auditoria_unidades
  WHERE fecha < NOW() - INTERVAL 12 MONTH;

SHOW EVENTS FROM banco_sangre;

-- Ejecuta una vez el snapshot para no esperar la hora.
INSERT INTO bitacora_disponibilidad (fecha_registro, uptime_seg)
SELECT NOW(), VARIABLE_VALUE
FROM performance_schema.global_status
WHERE VARIABLE_NAME = 'Uptime';

SELECT * FROM bitacora_disponibilidad ORDER BY id_registro DESC LIMIT 5;
