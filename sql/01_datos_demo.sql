-- ============================================================================
-- PROYECTO: BANCO DE SANGRE
-- Archivo 01 · Datos de demostración
-- Requiere haber ejecutado 00_esquema.sql
-- ============================================================================

USE banco_sangre;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE despacho_detalle;
TRUNCATE TABLE despachos;
TRUNCATE TABLE solicitud_detalle;
TRUNCATE TABLE solicitudes;
TRUNCATE TABLE pruebas_laboratorio;
TRUNCATE TABLE movimientos_inventario;
TRUNCATE TABLE unidades_sangre;
TRUNCATE TABLE donaciones;
TRUNCATE TABLE donantes;
TRUNCATE TABLE hospitales;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- Donantes (datos ficticios)
-- ----------------------------------------------------------------------------
INSERT INTO donantes
  (id_donante, nombre, apellido_paterno, apellido_materno, fecha_nacimiento, sexo, tipo_sangre, factor_rh, telefono, correo, direccion, fecha_registro, activo)
VALUES
  (1, 'Ana Sofía',   'Ramírez',  'López',   '1992-04-18', 'F', 'O',  '+', '5512345601', 'ana.ramirez@example.com',   'Av. Universidad 120, CDMX',        '2024-01-10 09:15:00', 1),
  (2, 'Luis Fernando','Cruz',    'Mendoza', '1988-11-02', 'M', 'A',  '+', '5512345602', 'luis.cruz@example.com',     'Calle Hidalgo 45, Puebla',         '2024-02-22 10:40:00', 1),
  (3, 'María Elena', 'Gómez',    'Santos',  '1995-07-30', 'F', 'B',  '-', '5512345603', 'maria.gomez@example.com',   'Av. Reforma 890, CDMX',            '2024-03-05 08:05:00', 1),
  (4, 'Jorge',       'Hernández','Ríos',    '1985-01-14', 'M', 'AB', '+', '5512345604', 'jorge.hernandez@example.com','Calle Morelos 210, Guadalajara',    '2024-04-19 16:30:00', 1),
  (5, 'Valeria',     'Torres',   'Núñez',   '1998-09-09', 'F', 'O',  '-', '5512345605', 'valeria.torres@example.com', 'Av. Juárez 33, Monterrey',         '2024-05-23 11:20:00', 1),
  (6, 'Ricardo',     'Aguilar',  'Pérez',   '1980-12-25', 'M', 'A',  '-', '5512345606', 'ricardo.aguilar@example.com','Calle 5 de Mayo 77, Querétaro',    '2024-06-11 14:00:00', 1),
  (7, 'Daniela',     'Flores',   'Vargas',  '2000-03-17', 'F', 'B',  '+', '5512345607', 'daniela.flores@example.com', 'Av. Insurgentes 450, CDMX',        '2024-07-08 09:50:00', 1),
  (8, 'Héctor',      'Medina',   'Castillo','1975-06-06', 'M', 'O',  '+', '5512345608', 'hector.medina@example.com',  'Calle Independencia 12, Toluca',   '2024-08-14 17:10:00', 0);

-- ----------------------------------------------------------------------------
-- Donaciones
-- ----------------------------------------------------------------------------
INSERT INTO donaciones
  (id_donacion, id_donante, fecha_donacion, tipo_donacion, lugar, peso_kg, hemoglobina, presion_arterial, estado, observaciones)
VALUES
  (1, 1, '2026-08-03 09:30:00', 'voluntaria', 'Unidad Móvil Centro',    64.50, 14.20, '110/70', 'apta',      NULL),
  (2, 2, '2026-08-10 10:15:00', 'voluntaria', 'Banco Central',          82.00, 15.10, '120/80', 'apta',      NULL),
  (3, 3, '2026-08-17 08:45:00', 'reposicion', 'Banco Central',          58.00, 13.40, '105/65', 'apta',      'Reposición familiar'),
  (4, 4, '2026-09-01 11:00:00', 'voluntaria', 'Unidad Móvil Norte',     90.00, 16.00, '130/85', 'apta',      NULL),
  (5, 5, '2026-09-12 09:10:00', 'voluntaria', 'Banco Central',          55.00, 12.90, '100/60', 'rechazada', 'Hemoglobina baja'),
  (6, 6, '2026-09-25 15:20:00', 'autologa',   'Hospital Ángeles',       78.00, 14.80, '125/75', 'apta',      'Cirugía programada'),
  (7, 7, '2026-10-02 08:30:00', 'voluntaria', 'Unidad Móvil Centro',    61.00, 13.80, '115/70', 'apta',      NULL),
  (8, 8, '2026-10-14 10:05:00', 'voluntaria', 'Banco Central',          88.00, 15.40, '135/88', 'registrada', 'Pendiente de tamizaje');

-- ----------------------------------------------------------------------------
-- Unidades derivadas
-- Vencimientos: glóbulos rojos ~42 días, plasma ~365, plaquetas ~7.
-- Se incluyen unidades disponibles, una reservada, varias despachadas, una
-- vencida y una descartada por tamizaje positivo.
-- ----------------------------------------------------------------------------
INSERT INTO unidades_sangre
  (id_unidad, id_donacion, codigo_barras, tipo_componente, grupo_abo, factor_rh, volumen_ml, fecha_extraccion, fecha_vencimiento, estado, ubicacion)
VALUES
  (1,  1, 'GR-2026-0001', 'globulos_rojos', 'O',  '+', 280, '2026-08-03', '2026-09-14', 'despachada', 'Hospital Ángeles'),
  (2,  1, 'PL-2026-0001', 'plasma',         'O',  '+', 220, '2026-08-03', '2027-08-03', 'despachada', 'Hospital General'),
  (3,  2, 'GR-2026-0002', 'globulos_rojos', 'A',  '+', 300, '2026-08-10', '2026-09-21', 'despachada', 'Hospital Ángeles'),
  (4,  2, 'PQ-2026-0001', 'plaquetas',      'A',  '+', 180, '2026-08-10', '2026-08-17', 'descartada', 'Cuarto frío 2'),
  (5,  3, 'GR-2026-0003', 'globulos_rojos', 'B',  '-', 270, '2026-08-17', '2026-09-28', 'disponible', 'Refrigerador 1'),
  (6,  3, 'PL-2026-0002', 'plasma',         'B',  '-', 210, '2026-08-17', '2027-08-17', 'disponible', 'Congelador B'),
  (7,  4, 'GR-2026-0004', 'globulos_rojos', 'AB', '+', 290, '2026-09-01', '2026-10-13', 'vencida',    'Refrigerador 2'),
  (8,  4, 'CR-2026-0001', 'crioprecipitado','AB', '+', 60,  '2026-09-01', '2027-09-01', 'disponible', 'Congelador A'),
  (9,  6, 'GR-2026-0005', 'globulos_rojos', 'A',  '-', 285, '2026-09-25', '2026-11-06', 'reservada',  'Refrigerador 1'),
  (10, 6, 'PL-2026-0003', 'plasma',         'A',  '-', 215, '2026-09-25', '2027-09-25', 'disponible', 'Congelador B'),
  (11, 7, 'GR-2026-0006', 'globulos_rojos', 'B',  '+', 275, '2026-10-02', '2026-11-13', 'despachada', 'Hospital General'),
  (12, 7, 'PQ-2026-0002', 'plaquetas',      'B',  '+', 190, '2026-10-02', '2026-10-09', 'despachada', 'Hospital General'),
  (13, 8, 'ST-2026-0001', 'sangre_total',   'O',  '+', 450, '2026-10-14', '2026-11-25', 'disponible', 'Cuarto frío 1'),
  (14, 8, 'PL-2026-0004', 'plasma',         'O',  '+', 225, '2026-10-14', '2027-10-14', 'disponible', 'Congelador A');

-- ----------------------------------------------------------------------------
-- Pruebas de laboratorio
-- ----------------------------------------------------------------------------
INSERT INTO pruebas_laboratorio (id_unidad, tipo_prueba, resultado, fecha_prueba, responsable, observaciones)
VALUES
  (1, 'VIH', 'negativo', '2026-08-03 12:00:00', 'QFB Laura Méndez', NULL),
  (1, 'HBV', 'negativo', '2026-08-03 12:00:00', 'QFB Laura Méndez', NULL),
  (1, 'HCV', 'negativo', '2026-08-03 12:00:00', 'QFB Laura Méndez', NULL),
  (2, 'VIH', 'negativo', '2026-08-03 12:00:00', 'QFB Laura Méndez', NULL),
  (2, 'grupo_sanguineo', 'negativo', '2026-08-03 11:30:00', 'QFB Laura Méndez', 'O positivo'),
  (3, 'VIH', 'negativo', '2026-08-10 13:00:00', 'QFB Pedro Ruiz',   NULL),
  (3, 'HBV', 'negativo', '2026-08-10 13:00:00', 'QFB Pedro Ruiz',   NULL),
  (4, 'HCV', 'positivo', '2026-08-10 13:00:00', 'QFB Pedro Ruiz',   'Unidad descartada'),
  (5, 'VIH', 'negativo', '2026-08-17 12:10:00', 'QFB Laura Méndez', NULL),
  (6, 'sifilis', 'negativo', '2026-08-17 12:10:00', 'QFB Laura Méndez', NULL),
  (7, 'chagas', 'pendiente', '2026-09-01 15:00:00', 'QFB Pedro Ruiz',  'Pendiente de confirmación'),
  (9, 'VIH', 'negativo', '2026-09-25 17:00:00', 'QFB Laura Méndez', NULL);

-- ----------------------------------------------------------------------------
-- Hospitales
-- ----------------------------------------------------------------------------
INSERT INTO hospitales (id_hospital, nombre, contacto, telefono, correo, direccion, convenio)
VALUES
  (1, 'Hospital General de Zona',   'Dra. Patria Solís', '5555001100', 'banco@hgz.example.com',    'Av. Salud 100, CDMX',        'activo'),
  (2, 'Hospital Ángeles',           'Dr. Mario Lara',    '5555002200', 'transfusion@angeles.example.com', 'Av. Reforma 500, CDMX', 'activo'),
  (3, 'Clínica del Valle',          'Lic. Sofía Reyes',  '5555003300', 'compras@clinicavalle.example.com', 'Calle Valle 20, Puebla', 'activo'),
  (4, 'Hospital Infantil Norte',    'Dra. Elena Ruiz',   '5555004400', 'urgencias@hin.example.com', 'Av. Norte 88, Monterrey',   'suspendido');

-- ----------------------------------------------------------------------------
-- Solicitudes y su detalle
-- ----------------------------------------------------------------------------
INSERT INTO solicitudes (id_solicitud, id_hospital, fecha_solicitud, prioridad, estado, observaciones)
VALUES
  (1, 1, '2026-08-04 08:00:00', 'urgente',    'surtida',   'Cirugía de trauma'),
  (2, 2, '2026-08-11 10:30:00', 'programada', 'surtida',   'Reposición de inventario'),
  (3, 1, '2026-10-03 07:45:00', 'urgente',    'parcial',   'Paciente con hemorragia'),
  (4, 3, '2026-10-15 11:15:00', 'programada', 'pendiente', 'Solicitud mensual'),
  (5, 2, '2026-10-20 16:40:00', 'urgente',    'pendiente', 'Trasplante programado'),
  (6, 4, '2026-10-21 09:00:00', 'programada', 'cancelada', 'Convenio suspendido');

INSERT INTO solicitud_detalle (id_detalle, id_solicitud, tipo_componente, grupo_abo, factor_rh, cantidad)
VALUES
  (1, 1, 'globulos_rojos', 'O',  '+', 1),
  (2, 1, 'plasma',         'O',  '+', 1),
  (3, 2, 'globulos_rojos', 'A',  '+', 1),
  (5, 3, 'globulos_rojos', 'B',  '+', 1),
  (6, 3, 'plaquetas',      'B',  '+', 1),
  (7, 4, 'globulos_rojos', 'O',  '-', 2),
  (8, 4, 'plasma',         'O',  '-', 2),
  (9, 5, 'globulos_rojos', 'A',  '-', 1),
  (10, 5, 'plaquetas',     'A',  '-', 2);

INSERT INTO despachos (id_despacho, id_solicitud, fecha_despacho, responsable, destino, estado)
VALUES
  (1, 1, '2026-08-04 09:20:00', 'Lic. Carlos Nava', 'Hospital General de Zona',  'entregado'),
  (2, 2, '2026-08-11 12:00:00', 'Lic. Carlos Nava', 'Hospital Ángeles',          'entregado'),
  (3, 3, '2026-10-03 08:10:00', 'Lic. Ana Prado',   'Hospital General de Zona',  'en_transito'),
  (4, 4, '2026-10-16 10:00:00', 'Lic. Ana Prado',   'Clínica del Valle',         'preparando');

INSERT INTO despacho_detalle (id_despacho, id_unidad)
VALUES
  (1, 1),
  (1, 2),
  (2, 3),
  (3, 11),
  (3, 12);

-- ----------------------------------------------------------------------------
-- Movimientos de inventario
-- ----------------------------------------------------------------------------
INSERT INTO movimientos_inventario
  (id_unidad, tipo_movimiento, fecha_movimiento, usuario, motivo)
VALUES
  (1,  'entrada',      '2026-08-03 12:30:00', 'sistema', 'Alta de unidad derivada'),
  (2,  'entrada',      '2026-08-03 12:30:00', 'sistema', 'Alta de unidad derivada'),
  (1,  'salida',       '2026-08-04 09:20:00', 'carlos.nava', 'Despacho solicitud 1'),
  (2,  'salida',       '2026-08-04 09:20:00', 'carlos.nava', 'Despacho solicitud 1'),
  (3,  'entrada',      '2026-08-10 13:20:00', 'sistema', 'Alta de unidad derivada'),
  (4,  'entrada',      '2026-08-10 13:20:00', 'sistema', 'Alta de unidad derivada'),
  (4,  'descarte',     '2026-08-11 08:00:00', 'pedro.ruiz', 'Prueba HCV positiva'),
  (3,  'salida',       '2026-08-11 12:00:00', 'carlos.nava', 'Despacho solicitud 2'),
  (11, 'salida',       '2026-10-03 08:10:00', 'ana.prado', 'Despacho solicitud 3'),
  (12, 'salida',       '2026-10-03 08:10:00', 'ana.prado', 'Despacho solicitud 3'),
  (9,  'reserva',      '2026-10-20 16:45:00', 'ana.prado', 'Reserva solicitud urgente 5'),
  (13, 'entrada',      '2026-10-14 12:00:00', 'sistema', 'Alta de unidad derivada'),
  (14, 'entrada',      '2026-10-14 12:00:00', 'sistema', 'Alta de unidad derivada');

-- ----------------------------------------------------------------------------
-- Verificación de conteos
-- ----------------------------------------------------------------------------
SELECT 'donantes' AS tabla, COUNT(*) AS registros FROM donantes
UNION ALL SELECT 'donaciones', COUNT(*) FROM donaciones
UNION ALL SELECT 'unidades_sangre', COUNT(*) FROM unidades_sangre
UNION ALL SELECT 'pruebas_laboratorio', COUNT(*) FROM pruebas_laboratorio
UNION ALL SELECT 'hospitales', COUNT(*) FROM hospitales
UNION ALL SELECT 'solicitudes', COUNT(*) FROM solicitudes
UNION ALL SELECT 'solicitud_detalle', COUNT(*) FROM solicitud_detalle
UNION ALL SELECT 'despachos', COUNT(*) FROM despachos
UNION ALL SELECT 'despacho_detalle', COUNT(*) FROM despacho_detalle
UNION ALL SELECT 'movimientos_inventario', COUNT(*) FROM movimientos_inventario;
