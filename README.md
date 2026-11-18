# Proyecto · Banco de Sangre

Caso elegido para el proyecto del curso: **gestión del ciclo completo de la sangre**.
Registra donantes, donaciones, componentes derivados, pruebas de laboratorio,
solicitudes de hospitales, despachos y trazabilidad de inventario.

Este directorio contiene el diseño, los scripts ejecutables y la justificación
de cada unidad. El sitio web `../sitio/` explica los mismos temas con prosa,
código y el caso conectado capítulo por capítulo.

## Cómo ejecutar

En MySQL Workbench (o en la terminal con `mysql`) abre y ejecuta en orden:

| Orden | Archivo | Unidad | Qué demuestra |
| --- | --- | --- | --- |
| 1 | `sql/00_esquema.sql` | 1 | Base, 12 tablas, FKs, CHECK, índices, vista y tabla particionada |
| 2 | `sql/01_datos_demo.sql` | 1 | Datos ficticios coherentes para probar consultas |
| 3 | `sql/02_unidad2_espacio_particiones_eventos.sql` | 2 | Estimación, RANGE/LIST/HASH y Event Scheduler |
| 4 | `sql/03_unidad3_seguridad_monitoreo_auditoria.sql` | 3 | Roles, privilegios, triggers de auditoría y monitoreo |
| 5 | `sql/04_unidad4_respaldo_recuperacion.sql` | 4 | Plan de respaldo, simulación y restauración |
| 6 | `sql/04_respaldo_incremental.sh` | 4 | Respaldo completo + copia de binlog desde shell |
| 7 | `sql/05_unidad5_afinacion.sql` | 5 | Parámetros, índice compuesto y EXPLAIN antes/después |

> Los scripts `02` a `05` asumen que `banco_sangre` ya existe con datos.
> Si vuelves a ejecutar `00_esquema.sql`, se recrea toda la base.

## Modelo de datos

```text
donantes 1 ──── N donaciones 1 ──── N unidades_sangre 1 ──── N pruebas_laboratorio
                                      │
                                      │ N
                                      │
                                      └──── N despacho_detalle N ──── 1 despachos
                                                                        │
                                                                        │ N
                                                                        1 solicitudes
                                                                        │
                                                                        │ N
                                                                        1 solicitud_detalle
hospitales 1 ──── N solicitudes
unidades_sangre 1 ──── N movimientos_inventario   (referencia lógica, sin FK)
unidades_sangre 1 ──── N auditoria_unidades       (la llena un trigger)
```

### Tablas

| Tabla | Propósito |
| --- | --- |
| `donantes` | Personas que donan; datos de contacto y clasificación sanguínea |
| `donaciones` | Cada extracción, con elegibilidad y estado |
| `unidades_sangre` | Inventario trazable por código de barras y vencimiento |
| `pruebas_laboratorio` | Tamizaje y pruebas cruzadas de cada unidad |
| `hospitales` | Instituciones con convenio |
| `solicitudes` | Pedidos de componentes, con prioridad |
| `solicitud_detalle` | Qué componente y cuántas unidades pide cada solicitud |
| `despachos` | Salida física hacia un hospital |
| `despacho_detalle` | Unidades concretas entregadas |
| `movimientos_inventario` | Historial de entradas, reservas, salidas y descartes (particionada por año) |
| `auditoria_unidades` | Evidencia de cambios sensibles sobre unidades |
| `bitacora_disponibilidad` | Snapshots de Uptime para monitoreo |

## Unidad 1 · DBA, arquitectura y esquema

**Motor elegido:** MySQL 8 InnoDB. Razones: transacciones ACID, claves
foráneas reales, buen soporte de particiones, roles, Event Scheduler y
herramientas de respaldo lógico (`mysqldump`, binlog). Para un banco de
sangre, la integridad referencial y la trazabilidad pesan más que un motor
orientado solo a lectura.

**Roles del equipo (ejemplo):**

| Integrante | Rol DBA asumido | Responsabilidad |
| --- | --- | --- |
| Persona 1 | System DBA | Instalación, memoria, almacenamiento, respaldos |
| Persona 2 | Arquitecto de datos | Esquema, normalización, particiones, crecimiento |
| Persona 3 | DBA de seguridad / auditoría | Roles, privilegios, triggers, monitoreo |

**Decisiones de diseño:**

- Una donación puede generar varios componentes; por eso `donaciones` y
  `unidades_sangre` están separadas.
- El grupo sanguíneo se guarda en la unidad, no solo en el donante: una
  unidad puede separarse en componentes con vencimientos distintos.
- `movimientos_inventario` no tiene FK porque es una tabla particionada.
  MySQL exige que la columna de partición esté en la PK y prohíbe FKs en
  tablas particionadas. La integridad se mantiene con la aplicación y con
  auditoría.
- La vista `v_unidades_disponibles` oculta datos personales del donante para
  el rol de recepción.

## Unidad 2 · Espacios y disponibilidad

### Estimación a un año

Fórmula aplicada:

```text
bytes_fila  = suma de bytes de columnas
datos       = bytes_fila × filas_esperadas
índices     = datos × 0.20 (20%, rango 10–30%)
crecimiento = (datos + índices) × 1.30
```

Supuestos del escenario: 8,000 donantes, 6,000 donaciones, 12,000 unidades,
60,000 pruebas y 120,000 movimientos al año. La consulta de proyección está
en `sql/02_...sql` y devuelve MB por etapa.

La medición real se hace con:

```sql
SELECT table_name,
       ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb,
       ROUND(index_length / NULLIF(data_length + index_length, 0) * 100, 2) AS pct_indices
FROM information_schema.TABLES
WHERE table_schema = 'banco_sangre';
```

### Particiones

| Tabla | Tipo | Criterio | Por qué |
| --- | --- | --- | --- |
| `movimientos_inventario` | RANGE | `YEAR(fecha_movimiento)` | El historial crece por año; las consultas filtran por fecha |
| `solicitudes_list` | LIST COLUMNS | `estado` | Categorías cerradas; cada consulta toca una partición |
| `pruebas_hash` | HASH | `id_unidad`, 4 particiones | Reparto uniforme sin criterio de negocio |

Reglas que no se pueden olvidar:

- La columna de partición **debe formar parte de la PRIMARY KEY**.
- Una tabla particionada **no puede tener FOREIGN KEY**.
- Para `VARCHAR` se usa `LIST COLUMNS`, no `LIST`.
- Si un `INSERT` cae en un valor sin partición LIST, falla.

### Automatización

| Evento | Frecuencia | Qué hace |
| --- | --- | --- |
| `ev_marcar_vencidas` | Diario 03:00 | Marca unidades vencidas |
| `ev_registrar_vencimientos` | Diario 04:00 | Registra el movimiento una sola vez |
| `ev_bitacora_uptime` | Cada hora | Guarda `Uptime` del servidor |
| `ev_purgar_auditoria` | Mensual | Borra auditoría de más de 12 meses |

Riesgo: automatizar sin supervisión. Mitigación: revisar `SHOW EVENTS`,
`last_executed` y los conteos de la bitácora.

## Unidad 3 · Monitoreo y seguridad

### Roles

| Rol | Privilegios |
| --- | --- |
| `rol_laboratorio` | SELECT/INSERT/UPDATE en pruebas; SELECT/UPDATE en unidades |
| `rol_recepcion` | SELECT en la vista; INSERT en solicitudes y detalle |
| `rol_auditor` | SELECT en auditoría y bitácora |
| `rol_dba_sangre` | ALL sobre `banco_sangre` |

Se aplica mínimo privilegio: recepción no ve datos del donante ni puede
modificar unidades; laboratorio no puede borrar; auditor no escribe.

### Auditoría

Tres triggers (`AFTER INSERT`, `AFTER UPDATE`, `AFTER DELETE`) sobre
`unidades_sangre` guardan `usuario`, `fecha` y JSON con el antes/después.
La operación sensible es el cambio de estado de una unidad.

### Monitoreo

- `performance_schema.global_status`: Uptime, conexiones, consultas lentas.
- `performance_schema.processlist`: sesiones activas (la versión de `information_schema` está deprecada).
- `information_schema.events`: eventos y última ejecución.
- `information_schema.tables`: espacio por tabla.
- `performance_schema.events_statements_summary_by_digest`: consultas caras.
- `bitacora_disponibilidad`: huecos entre snapshots.

### Problema de disponibilidad elegido

**SPOF del servidor MySQL.** Mitigación: réplica, InnoDB Cluster con
failover automático, respaldos + binlog, monitoreo de Uptime y ensayos
trimestrales. Objetivo: 99.9 % (~8.77 h/año), RTO 30 min, RPO 15 min.

## Unidad 4 · Respaldo y recuperación

- **RTO:** 30 minutos.
- **RPO:** 15 minutos.
- Respaldo completo diario 02:00 con `mysqldump --single-transaction`.
- Binlog copiado cada 15 minutos.
- Restauración: completo + binlog hasta el minuto anterior al incidente.
- Verificación: conteos, ausencia de huérfanos, triggers/eventos presentes,
  checksum del archivo y prueba real de restauración.

El procedimiento completo y la simulación están en
`sql/04_unidad4_respaldo_recuperacion.sql`; el script de shell en
`sql/04_respaldo_incremental.sh`.

## Unidad 5 · Afinación

| Parámetro | Qué controla | Criterio |
| --- | --- | --- |
| `innodb_buffer_pool_size` | Caché de datos e índices | 50–70 % de RAM dedicada |
| `innodb_log_file_size` | Redo logs y checkpoints | Más grande para escritura sostenida |
| `max_connections` | Conexiones simultáneas | Subir solo con memoria disponible |

Índice justificado:

```sql
CREATE INDEX idx_unidades_o_positivo
  ON unidades_sangre (grupo_abo, factor_rh, estado, fecha_vencimiento);
```

Cubre igualdad + orden de la consulta crítica de recepción. Se compara con
`EXPLAIN` y `EXPLAIN ANALYZE` antes y después; el objetivo es eliminar el
`filesort` y reducir filas examinadas.

## Entregable de la demo (15–20 min)

1. Mostrar el modelo y explicar por qué 12 tablas (2 min).
2. Insertar una donación y sus unidades; mostrar el trigger de auditoría (3 min).
3. Ejecutar la estimación y `information_schema` (2 min).
4. Mostrar particiones y `EXPLAIN` con la partición usada (3 min).
5. Ejecutar un evento y revisar la bitácora (2 min).
6. Mostrar roles y `SHOW GRANTS` (2 min).
7. Restaurar un respaldo en vivo (3 min).
8. Comparar `EXPLAIN` antes/después del índice (3 min).

## Advertencias

- Los datos son ficticios; no uses datos reales de pacientes.
- Las contraseñas de ejemplo son didácticas; en producción se gestionan con
  un vault y se rotan.
- Los scripts están pensados para MySQL 8; algunas consultas de
  `performance_schema` cambian en MariaDB.
