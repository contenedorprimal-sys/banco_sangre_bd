-- ============================================================================
-- PROYECTO: BANCO DE SANGRE
-- Archivo 05 · Unidad 5
-- Afinación: parámetros, índices y medición antes/después.
--
-- Requiere: 00_esquema.sql y 01_datos_demo.sql
-- ============================================================================

USE banco_sangre;

-- ============================================================================
-- PARTE A · TRES PARÁMETROS RELEVANTES
-- ============================================================================
-- 1. innodb_buffer_pool_size
--    Es la memoria que InnoDB dedica a cachear páginas de datos e índices.
--    Regla práctica: 50-70% de la RAM del servidor dedicado a MySQL.
--    Es la mejora más grande y más barata antes de tocar consultas.
SELECT @@innodb_buffer_pool_size AS buffer_pool_bytes,
       ROUND(@@innodb_buffer_pool_size / 1024 / 1024 / 1024, 2) AS buffer_pool_gb;

-- 2. innodb_log_file_size
--    Tamaño de los redo logs. Más grande = menos checkpoints y mejor
--    escritura sostenida; más pequeño = recuperación más rápida.
SELECT @@innodb_log_file_size AS log_file_bytes,
       ROUND(@@innodb_log_file_size / 1024 / 1024, 2) AS log_file_mb;

-- 3. max_connections
--    Conexiones simultáneas. Subirlo sin memoria disponible solo mueve el
--    problema: cada conexión consume buffers privados.
SELECT @@max_connections AS max_conexiones,
       @@thread_cache_size AS thread_cache;

-- Parámetros de diagnóstico que conviene dejar activos:
SELECT @@slow_query_log AS slow_log,
       @@long_query_time AS segundos_consulta_lenta,
       @@log_queries_not_using_indexes AS log_sin_indices;

-- ============================================================================
-- PARTE B · CONSULTA CRÍTICA
-- ============================================================================
-- Caso: recepción necesita saber qué unidades O+ están disponibles y cuál
-- vence primero. Es la consulta que más se ejecuta en el mostrador.
-- ============================================================================

-- B.1 Antes: eliminar el índice específico si existe (MySQL no tiene
-- DROP INDEX IF EXISTS; se comprueba en information_schema).
SET @drop_idx = (
  SELECT IF(COUNT(*) > 0,
    'DROP INDEX idx_unidades_o_positivo ON unidades_sangre',
    'SELECT 1')
  FROM information_schema.statistics
  WHERE table_schema = 'banco_sangre'
    AND table_name = 'unidades_sangre'
    AND index_name = 'idx_unidades_o_positivo'
);
PREPARE stmt_drop FROM @drop_idx;
EXECUTE stmt_drop;
DEALLOCATE PREPARE stmt_drop;

EXPLAIN
SELECT id_unidad, codigo_barras, tipo_componente, fecha_vencimiento
FROM unidades_sangre
WHERE estado = 'disponible'
  AND grupo_abo = 'O'
  AND factor_rh = '+'
ORDER BY fecha_vencimiento ASC;

-- B.2 Crear un índice compuesto en el orden de la consulta:
--     igualdad (grupo, rh, estado) + orden (fecha_vencimiento).
CREATE INDEX idx_unidades_o_positivo
  ON unidades_sangre (grupo_abo, factor_rh, estado, fecha_vencimiento);

-- B.3 Después: revisar que el plan use el índice y evite filesort.
EXPLAIN
SELECT id_unidad, codigo_barras, tipo_componente, fecha_vencimiento
FROM unidades_sangre
WHERE estado = 'disponible'
  AND grupo_abo = 'O'
  AND factor_rh = '+'
ORDER BY fecha_vencimiento ASC;

-- MySQL 8 permite medir el plan real:
EXPLAIN ANALYZE
SELECT id_unidad, codigo_barras, tipo_componente, fecha_vencimiento
FROM unidades_sangre
WHERE estado = 'disponible'
  AND grupo_abo = 'O'
  AND factor_rh = '+'
ORDER BY fecha_vencimiento ASC;

-- ============================================================================
-- PARTE C · MEDICIÓN ANTES / DESPUÉS
-- ============================================================================
-- MySQL 8.0 tiene SHOW PROFILES, pero está deprecado y desaparece en 8.4.
-- La medición portable es EXPLAIN ANALYZE (arriba) o NOW(6) alrededor de la
-- consulta, como se muestra a continuación.
SET @inicio = NOW(6);

SELECT COUNT(*) INTO @total
FROM unidades_sangre
WHERE estado = 'disponible'
  AND grupo_abo = 'O'
  AND factor_rh = '+';

SET @fin = NOW(6);
SELECT @total AS filas,
       TIMESTAMPDIFF(MICROSECOND, @inicio, @fin) / 1000 AS milisegundos;

-- ============================================================================
-- PARTE D · OTRAS CONSULTAS QUE SE BENEFICIAN DE ÍNDICES
-- ============================================================================

-- D.1 Solicitudes urgentes pendientes (índice estado+prioridad+fecha ya existe).
EXPLAIN
SELECT id_solicitud, id_hospital, fecha_solicitud
FROM solicitudes
WHERE estado = 'pendiente' AND prioridad = 'urgente'
ORDER BY fecha_solicitud ASC;

-- D.2 Pruebas pendientes por unidad (índice id_unidad+tipo_prueba ya existe).
EXPLAIN
SELECT id_prueba, id_unidad, tipo_prueba
FROM pruebas_laboratorio
WHERE id_unidad = 9 AND resultado = 'pendiente';

-- D.3 Índice que NO conviene: columnas con muy poca selectividad.
--     Un índice sobre `sexo` en donantes casi no ayuda: hay dos valores.
--     El optimizador terminaría leyendo media tabla de todas formas.
-- CREATE INDEX idx_sexo_malo ON donantes (sexo);  -- ejemplo didáctico: no crear

-- ============================================================================
-- PARTE E · MANTENIMIENTO
-- ============================================================================
-- Actualizar estadísticas para que el optimizador elija bien.
ANALYZE TABLE unidades_sangre, solicitudes, pruebas_laboratorio;

-- Revisar el tamaño de tablas e índices después del cambio.
SELECT
  table_name,
  table_rows,
  ROUND((data_length + index_length) / 1024 / 1024, 3) AS total_mb,
  ROUND(index_length / NULLIF(data_length + index_length, 0) * 100, 2) AS pct_indices
FROM information_schema.tables
WHERE table_schema = 'banco_sangre'
ORDER BY (data_length + index_length) DESC;

-- ============================================================================
-- PARTE F · CONCLUSIÓN DEL ANTES/DESPUÉS
-- ============================================================================
-- Antes: el plan podía usar idx_unidades_disponibilidad y luego ordenar con
-- filesort porque la columna de orden no seguía el orden del índice.
-- Después: idx_unidades_o_positivo cubre igualdad + orden; el plan muestra
-- ref/range sobre el índice y desaparece el filesort.
--
-- Medición esperada en el conjunto de demo (14 filas):
--   antes  ~0.4 ms
--   después~0.2 ms
-- La diferencia real se nota con millones de filas; con 14 filas el
-- optimizador puede elegir un table scan aunque el índice exista.
-- ============================================================================
