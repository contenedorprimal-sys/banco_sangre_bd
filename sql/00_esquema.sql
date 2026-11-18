-- ============================================================================
-- PROYECTO: BANCO DE SANGRE
-- Archivo 00 · Esquema completo (Unidad 1)
-- Motor: MySQL 8.0+ (probado en MySQL 8.0). En MariaDB puede haber diferencias.
--
-- Este script crea la base de datos y las tablas relacionadas del caso.
-- Ejecuta primero 00_esquema.sql y después 01_datos_demo.sql.
--
-- Orden recomendado:
--   00_esquema.sql  -> estructura
--   01_datos_demo.sql -> datos de prueba
--   02_unidad2_espacio_particiones_eventos.sql
--   03_unidad3_seguridad_monitoreo_auditoria.sql
--   04_unidad4_respaldo_recuperacion.sql
--   05_unidad5_afinacion.sql
-- ============================================================================

DROP DATABASE IF EXISTS banco_sangre;
CREATE DATABASE banco_sangre
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_spanish_ci;

USE banco_sangre;

-- ----------------------------------------------------------------------------
-- 1. DONANTES
-- Personas que donan. No se guarda diagnóstico clínico aquí: solo los datos
-- necesarios para contactar, verificar elegibilidad y clasificar la sangre.
-- ----------------------------------------------------------------------------
CREATE TABLE donantes (
  id_donante        INT AUTO_INCREMENT PRIMARY KEY,
  nombre            VARCHAR(60)  NOT NULL,
  apellido_paterno  VARCHAR(60)  NOT NULL,
  apellido_materno  VARCHAR(60),
  fecha_nacimiento  DATE          NOT NULL,
  sexo              ENUM('F','M','X') NOT NULL,
  tipo_sangre       ENUM('A','B','AB','O') NOT NULL,
  factor_rh         ENUM('+','-') NOT NULL,
  telefono          VARCHAR(20),
  correo            VARCHAR(120) UNIQUE,
  direccion         VARCHAR(160),
  fecha_registro    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  activo            TINYINT NOT NULL DEFAULT 1,
  -- MySQL 8 no permite CURRENT_DATE dentro de un CHECK (no es determinista).
  -- La regla "no puede ser futura" se valida en la aplicación o con un trigger.
  CONSTRAINT chk_donante_nacimiento CHECK (fecha_nacimiento >= '1900-01-01')
) ENGINE=InnoDB;

CREATE INDEX idx_donantes_tipo ON donantes (tipo_sangre, factor_rh);
CREATE INDEX idx_donantes_activo ON donantes (activo);

-- ----------------------------------------------------------------------------
-- 2. DONACIONES
-- Cada extracción de sangre. Una donación puede originar varias unidades
-- (glóbulos rojos, plasma, plaquetas...).
-- ----------------------------------------------------------------------------
CREATE TABLE donaciones (
  id_donacion       INT AUTO_INCREMENT PRIMARY KEY,
  id_donante        INT NOT NULL,
  fecha_donacion    DATETIME NOT NULL,
  tipo_donacion     ENUM('voluntaria','reposicion','autologa') NOT NULL DEFAULT 'voluntaria',
  lugar             VARCHAR(80),
  peso_kg           DECIMAL(5,2),
  hemoglobina       DECIMAL(4,2),
  presion_arterial  VARCHAR(12),
  estado            ENUM('registrada','apta','rechazada') NOT NULL DEFAULT 'registrada',
  observaciones     VARCHAR(255),
  CONSTRAINT fk_donacion_donante
    FOREIGN KEY (id_donante) REFERENCES donantes (id_donante)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT chk_donacion_peso CHECK (peso_kg IS NULL OR peso_kg > 0)
) ENGINE=InnoDB;

CREATE INDEX idx_donaciones_fecha ON donaciones (fecha_donacion);
CREATE INDEX idx_donaciones_donante ON donaciones (id_donante, fecha_donacion);

-- ----------------------------------------------------------------------------
-- 3. UNIDADES DE SANGRE
-- El inventario real. Cada unidad es trazable por código de barras.
-- La fecha de vencimiento depende del componente:
--   sangre total / glóbulos rojos: 35-42 días
--   plasma: hasta 1 año congelado
--   plaquetas: 5-7 días
-- ----------------------------------------------------------------------------
CREATE TABLE unidades_sangre (
  id_unidad         INT AUTO_INCREMENT PRIMARY KEY,
  id_donacion       INT NOT NULL,
  codigo_barras     VARCHAR(40) NOT NULL UNIQUE,
  tipo_componente   ENUM('sangre_total','globulos_rojos','plasma','plaquetas','crioprecipitado') NOT NULL,
  grupo_abo         ENUM('A','B','AB','O') NOT NULL,
  factor_rh         ENUM('+','-') NOT NULL,
  volumen_ml        INT NOT NULL,
  fecha_extraccion  DATE NOT NULL,
  fecha_vencimiento DATE NOT NULL,
  estado            ENUM('disponible','reservada','despachada','vencida','descartada')
                    NOT NULL DEFAULT 'disponible',
  ubicacion         VARCHAR(40),
  CONSTRAINT fk_unidad_donacion
    FOREIGN KEY (id_donacion) REFERENCES donaciones (id_donacion)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT chk_unidad_volumen CHECK (volumen_ml > 0),
  CONSTRAINT chk_unidad_fechas CHECK (fecha_vencimiento >= fecha_extraccion)
) ENGINE=InnoDB;

CREATE INDEX idx_unidades_disponibilidad
  ON unidades_sangre (estado, tipo_componente, fecha_vencimiento);
CREATE INDEX idx_unidades_grupo
  ON unidades_sangre (grupo_abo, factor_rh, estado);

-- ----------------------------------------------------------------------------
-- 4. PRUEBAS DE LABORATORIO
-- Tamizaje obligatorio: VIH, hepatitis B y C, sífilis, Chagas, grupo
-- sanguíneo y pruebas cruzadas. Una unidad no debe despacharse sin resultado.
-- ----------------------------------------------------------------------------
CREATE TABLE pruebas_laboratorio (
  id_prueba      INT AUTO_INCREMENT PRIMARY KEY,
  id_unidad      INT NOT NULL,
  tipo_prueba    ENUM('VIH','HBV','HCV','sifilis','chagas','grupo_sanguineo','pruebas_cruzadas') NOT NULL,
  resultado      ENUM('negativo','positivo','pendiente') NOT NULL DEFAULT 'pendiente',
  fecha_prueba   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responsable    VARCHAR(80),
  observaciones  VARCHAR(255),
  CONSTRAINT fk_prueba_unidad
    FOREIGN KEY (id_unidad) REFERENCES unidades_sangre (id_unidad)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_pruebas_unidad ON pruebas_laboratorio (id_unidad, tipo_prueba);
CREATE INDEX idx_pruebas_resultado ON pruebas_laboratorio (resultado, tipo_prueba);

-- ----------------------------------------------------------------------------
-- 5. HOSPITALES
-- Clientes institucionales que solicitan componentes.
-- ----------------------------------------------------------------------------
CREATE TABLE hospitales (
  id_hospital  INT AUTO_INCREMENT PRIMARY KEY,
  nombre       VARCHAR(120) NOT NULL,
  contacto     VARCHAR(80),
  telefono     VARCHAR(20),
  correo       VARCHAR(120),
  direccion    VARCHAR(160),
  convenio     ENUM('activo','suspendido') NOT NULL DEFAULT 'activo'
) ENGINE=InnoDB;

CREATE INDEX idx_hospitales_convenio ON hospitales (convenio);

-- ----------------------------------------------------------------------------
-- 6. SOLICITUDES
-- Pedido de un hospital. La prioridad cambia el orden de atención.
-- ----------------------------------------------------------------------------
CREATE TABLE solicitudes (
  id_solicitud     INT AUTO_INCREMENT PRIMARY KEY,
  id_hospital      INT NOT NULL,
  fecha_solicitud  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  prioridad        ENUM('urgente','programada') NOT NULL DEFAULT 'programada',
  estado           ENUM('pendiente','parcial','surtida','cancelada') NOT NULL DEFAULT 'pendiente',
  observaciones    VARCHAR(255),
  CONSTRAINT fk_solicitud_hospital
    FOREIGN KEY (id_hospital) REFERENCES hospitales (id_hospital)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_solicitudes_estado ON solicitudes (estado, prioridad, fecha_solicitud);
CREATE INDEX idx_solicitudes_hospital ON solicitudes (id_hospital, fecha_solicitud);

-- ----------------------------------------------------------------------------
-- 7. DETALLE DE SOLICITUD
-- Qué componentes pide cada solicitud y en qué cantidad.
-- ----------------------------------------------------------------------------
CREATE TABLE solicitud_detalle (
  id_detalle       INT AUTO_INCREMENT PRIMARY KEY,
  id_solicitud     INT NOT NULL,
  tipo_componente  ENUM('sangre_total','globulos_rojos','plasma','plaquetas','crioprecipitado') NOT NULL,
  grupo_abo        ENUM('A','B','AB','O') NOT NULL,
  factor_rh        ENUM('+','-') NOT NULL,
  cantidad         INT NOT NULL,
  CONSTRAINT fk_detalle_solicitud
    FOREIGN KEY (id_solicitud) REFERENCES solicitudes (id_solicitud)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT chk_detalle_cantidad CHECK (cantidad > 0)
) ENGINE=InnoDB;

CREATE INDEX idx_solicitud_detalle ON solicitud_detalle (id_solicitud);
CREATE INDEX idx_solicitud_componente ON solicitud_detalle (tipo_componente, grupo_abo, factor_rh);

-- ----------------------------------------------------------------------------
-- 8. DESPACHOS
-- Salida física de unidades hacia un hospital. Cierra el ciclo de trazabilidad.
-- ----------------------------------------------------------------------------
CREATE TABLE despachos (
  id_despacho      INT AUTO_INCREMENT PRIMARY KEY,
  id_solicitud     INT NOT NULL,
  fecha_despacho   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responsable      VARCHAR(80),
  destino          VARCHAR(160),
  estado           ENUM('preparando','en_transito','entregado','cancelado') NOT NULL DEFAULT 'preparando',
  CONSTRAINT fk_despacho_solicitud
    FOREIGN KEY (id_solicitud) REFERENCES solicitudes (id_solicitud)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_despachos_fecha ON despachos (fecha_despacho);
CREATE INDEX idx_despachos_estado ON despachos (estado);

-- ----------------------------------------------------------------------------
-- 9. DETALLE DE DESPACHO
-- Une una salida con las unidades concretas que se entregaron.
-- ----------------------------------------------------------------------------
CREATE TABLE despacho_detalle (
  id_despacho  INT NOT NULL,
  id_unidad    INT NOT NULL,
  PRIMARY KEY (id_despacho, id_unidad),
  CONSTRAINT fk_despacho_detalle_despacho
    FOREIGN KEY (id_despacho) REFERENCES despachos (id_despacho)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_despacho_detalle_unidad
    FOREIGN KEY (id_unidad) REFERENCES unidades_sangre (id_unidad)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 10. MOVIMIENTOS DE INVENTARIO (tabla particionada)
-- Registro histórico de todo cambio de estado. Crece sin parar: es la
-- candidata natural a particionar por año.
--
-- Regla de MySQL: la columna de partición (fecha_movimiento) debe formar
-- parte de la PRIMARY KEY y la tabla NO puede tener FOREIGN KEY.
-- Por eso id_unidad queda como referencia lógica, no como FK física.
-- ----------------------------------------------------------------------------
CREATE TABLE movimientos_inventario (
  id_movimiento    BIGINT NOT NULL AUTO_INCREMENT,
  id_unidad        INT NOT NULL,
  tipo_movimiento  ENUM('entrada','reserva','liberacion','salida','descarte','vencimiento','ajuste') NOT NULL,
  fecha_movimiento DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario          VARCHAR(80),
  motivo           VARCHAR(255),
  PRIMARY KEY (id_movimiento, fecha_movimiento)
) ENGINE=InnoDB
PARTITION BY RANGE (YEAR(fecha_movimiento)) (
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION p2025 VALUES LESS THAN (2026),
  PARTITION p2026 VALUES LESS THAN (2027),
  PARTITION p2027 VALUES LESS THAN (2028),
  PARTITION pmax  VALUES LESS THAN MAXVALUE
);

CREATE INDEX idx_movimientos_unidad ON movimientos_inventario (id_unidad, fecha_movimiento);
CREATE INDEX idx_movimientos_tipo ON movimientos_inventario (tipo_movimiento, fecha_movimiento);

-- ----------------------------------------------------------------------------
-- 11. AUDITORÍA
-- Guarda quién cambió qué y cuándo sobre unidades_sangre. Se llena con
-- triggers (ver 03_unidad3_seguridad_monitoreo_auditoria.sql).
-- ----------------------------------------------------------------------------
CREATE TABLE auditoria_unidades (
  id_auditoria     BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_unidad        INT NOT NULL,
  accion           ENUM('INSERT','UPDATE','DELETE') NOT NULL,
  usuario          VARCHAR(80) NOT NULL,
  fecha            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  datos_anteriores JSON,
  datos_nuevos     JSON
) ENGINE=InnoDB;

CREATE INDEX idx_auditoria_unidad ON auditoria_unidades (id_unidad, fecha);
CREATE INDEX idx_auditoria_fecha ON auditoria_unidades (fecha);

-- ----------------------------------------------------------------------------
-- 12. BITÁCORA DE DISPONIBILIDAD
-- La llena un evento cada hora con el Uptime del servidor.
-- ----------------------------------------------------------------------------
CREATE TABLE bitacora_disponibilidad (
  id_registro      BIGINT AUTO_INCREMENT PRIMARY KEY,
  fecha_registro   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  uptime_seg       BIGINT NOT NULL
) ENGINE=InnoDB;

CREATE INDEX idx_bitacora_fecha ON bitacora_disponibilidad (fecha_registro);

-- ----------------------------------------------------------------------------
-- 13. VISTA PÚBLICA DE INVENTARIO
-- Lo que puede ver recepción de hospital: NO datos personales del donante.
-- ----------------------------------------------------------------------------
CREATE VIEW v_unidades_disponibles AS
SELECT
  u.id_unidad,
  u.codigo_barras,
  u.tipo_componente,
  u.grupo_abo,
  u.factor_rh,
  u.volumen_ml,
  u.fecha_vencimiento,
  DATEDIFF(u.fecha_vencimiento, CURRENT_DATE) AS dias_para_vencer
FROM unidades_sangre u
WHERE u.estado = 'disponible'
  AND u.fecha_vencimiento >= CURRENT_DATE;

-- ----------------------------------------------------------------------------
-- Verificación rápida de la estructura
-- ----------------------------------------------------------------------------
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'banco_sangre'
ORDER BY table_type, table_name;
