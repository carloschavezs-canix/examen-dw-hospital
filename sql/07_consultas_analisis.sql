/*
  07 - CONSULTAS DE ANALISIS SOBRE GOLD (capturas para el informe)
*/

-- 1. Admisiones y estancia promedio por departamento
SELECT d.nombre_departamento,
       SUM(f.conteo_admisiones) AS admisiones,
       CAST(AVG(CAST(f.dias_estancia AS DECIMAL(10,2))) AS DECIMAL(10,1)) AS dias_estancia_promedio
FROM gold.fact_admisiones f
JOIN gold.dim_departamento d ON d.departamento_key = f.departamento_key
GROUP BY d.nombre_departamento
ORDER BY admisiones DESC;

-- 2. Admisiones por anio y trimestre
SELECT t.anio, t.trimestre_nombre, SUM(f.conteo_admisiones) AS admisiones
FROM gold.fact_admisiones f
JOIN gold.dim_fecha t ON t.fecha_key = f.fecha_ingreso_key
GROUP BY t.anio, t.trimestre_nombre
ORDER BY t.anio, t.trimestre_nombre;

-- 3. Diagnosticos principales por severidad
SELECT g.codigo_icd, g.descripcion_patologia, g.nivel_severidad, SUM(f.conteo_admisiones) AS admisiones
FROM gold.fact_admisiones f
JOIN gold.dim_diagnostico g ON g.diagnostico_key = f.diagnostico_key
GROUP BY g.codigo_icd, g.descripcion_patologia, g.nivel_severidad
ORDER BY admisiones DESC;

-- 4. Facturacion por tipo de cargo y estado de pago
SELECT s.tipo_cargo, s.estado_pago, SUM(f.conteo_transacciones) AS transacciones, SUM(f.monto_facturado) AS monto
FROM gold.fact_facturacion f
JOIN gold.dim_servicio_cargo s ON s.servicio_cargo_key = f.servicio_cargo_key
GROUP BY s.tipo_cargo, s.estado_pago
ORDER BY s.tipo_cargo, monto DESC;

-- 5. Monto facturado por seguro
SELECT p.proveedor_seguro, SUM(f.monto_facturado) AS monto, SUM(f.conteo_transacciones) AS transacciones
FROM gold.fact_facturacion f
JOIN gold.dim_paciente p ON p.paciente_key = f.paciente_key
GROUP BY p.proveedor_seguro
ORDER BY monto DESC;

-- 6. Admisiones por rango etario y genero
SELECT p.rango_etario, p.genero, SUM(f.conteo_admisiones) AS admisiones
FROM gold.fact_admisiones f
JOIN gold.dim_paciente p ON p.paciente_key = f.paciente_key
GROUP BY p.rango_etario, p.genero
ORDER BY p.rango_etario, p.genero;

-- 7. Monto facturado por departamento y mes de pago
SELECT d.nombre_departamento, t.anio, t.mes, t.mes_nombre, SUM(f.monto_facturado) AS monto
FROM gold.fact_facturacion f
JOIN gold.dim_departamento d ON d.departamento_key = f.departamento_key
JOIN gold.dim_fecha t        ON t.fecha_key = f.fecha_pago_key
GROUP BY d.nombre_departamento, t.anio, t.mes, t.mes_nombre
ORDER BY t.anio, t.mes, d.nombre_departamento;
