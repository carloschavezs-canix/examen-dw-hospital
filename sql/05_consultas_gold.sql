/*
  05 - CONSULTAS DE ORIGEN DE LOS DATA FLOWS GOLD
  Cada bloque se pega en: Data Flow > Origen > Opciones de origen > Entrada: Consulta.
  Las dimensiones leen silver; los hechos leen silver y buscan las claves en las dimensiones gold ya cargadas.
  Orden de carga: dimensiones primero, hechos al final.
*/

-- ===== 1. df_gold_dim_fecha =====
SELECT
    CONVERT(INT, CONVERT(CHAR(8), f.fecha, 112)) AS fecha_key,
    f.fecha AS fecha_completa,
    CAST(YEAR(f.fecha) AS SMALLINT) AS anio,
    CAST(DATEPART(QUARTER, f.fecha) AS TINYINT) AS trimestre,
    CAST('T' + CAST(DATEPART(QUARTER, f.fecha) AS VARCHAR(1)) AS VARCHAR(10)) AS trimestre_nombre,
    CAST(MONTH(f.fecha) AS TINYINT) AS mes,
    CAST(CHOOSE(MONTH(f.fecha), 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
                'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre') AS VARCHAR(20)) AS mes_nombre,
    CAST(CHOOSE(MONTH(f.fecha), 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
                'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic') AS CHAR(3)) AS mes_corto,
    CAST(DATEPART(ISO_WEEK, f.fecha) AS TINYINT) AS semana_anio,
    CAST(DAY(f.fecha) AS TINYINT) AS dia_mes,
    CAST((DATEDIFF(DAY, '19000101', f.fecha) % 7) + 1 AS TINYINT) AS dia_semana,
    CAST(CHOOSE((DATEDIFF(DAY, '19000101', f.fecha) % 7) + 1,
                'Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado', 'Domingo') AS VARCHAR(20)) AS dia_nombre,
    CAST(CASE WHEN (DATEDIFF(DAY, '19000101', f.fecha) % 7) >= 5 THEN 1 ELSE 0 END AS BIT) AS es_fin_de_semana
FROM (
    SELECT admission_date AS fecha FROM silver.admissions
    UNION
    SELECT discharge_date FROM silver.admissions WHERE discharge_date IS NOT NULL
    UNION
    SELECT payment_date FROM silver.billing WHERE payment_date IS NOT NULL
) f;

-- ===== 2. df_gold_dim_paciente =====
SELECT
    p.patient_id AS patient_id_bk,
    p.full_name AS nombre_completo,
    CAST(CASE p.gender WHEN 'M' THEN 'Masculino' WHEN 'F' THEN 'Femenino' ELSE 'Otro' END AS VARCHAR(20)) AS genero,
    p.date_of_birth AS fecha_nacimiento,
    CAST(CASE
        WHEN e.edad IS NULL THEN 'Sin dato'
        WHEN e.edad <= 18 THEN '0-18'
        WHEN e.edad <= 35 THEN '19-35'
        WHEN e.edad <= 60 THEN '36-60'
        ELSE '60+'
    END AS VARCHAR(50)) AS rango_etario,
    p.email AS correo_electronico,
    p.address AS direccion,
    ISNULL(p.insurance_provider, N'Sin seguro') AS proveedor_seguro
FROM silver.patients p
CROSS APPLY (
    SELECT DATEDIFF(YEAR, p.date_of_birth, GETDATE())
         - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, p.date_of_birth, GETDATE()), p.date_of_birth) > GETDATE()
                THEN 1 ELSE 0 END AS edad
) e;

-- ===== 3. df_gold_dim_departamento =====
SELECT DISTINCT department AS nombre_departamento
FROM silver.admissions;

-- ===== 4. df_gold_dim_diagnostico =====
SELECT
    x.codigo_icd,
    ISNULL(r.descripcion, N'Codigo ' + x.codigo_icd) AS descripcion_patologia,
    x.nivel_severidad
FROM (
    SELECT DISTINCT
        CAST(LTRIM(RTRIM(LEFT(icd_code, CHARINDEX(',', icd_code + ',') - 1))) AS VARCHAR(50)) AS codigo_icd,
        CAST(ISNULL(severity, 'Sin especificar') AS VARCHAR(50)) AS nivel_severidad
    FROM silver.diagnoses
    UNION
    SELECT 'SIN-DX', 'Sin especificar'
) x
LEFT JOIN (VALUES
    ('C50.911',  N'Tumor maligno de mama derecha'),
    ('E11.9',    N'Diabetes tipo 2 sin complicaciones'),
    ('F32.9',    N'Episodio depresivo mayor, no especificado'),
    ('I10',      N'Hipertension esencial (primaria)'),
    ('J45.909',  N'Asma no especificada, sin complicaciones'),
    ('K21.9',    N'Reflujo gastroesofagico sin esofagitis'),
    ('M54.5',    N'Dolor lumbar'),
    ('N39.0',    N'Infeccion de vias urinarias'),
    ('R51',      N'Cefalea'),
    ('S72.001A', N'Fractura del cuello del femur derecho, primera atencion'),
    ('SIN-DX',   N'Sin diagnostico registrado')
) r (codigo_icd, descripcion) ON r.codigo_icd = x.codigo_icd;

-- ===== 5. df_gold_dim_servicio_cargo =====
SELECT DISTINCT
    charge_type AS tipo_cargo,
    payment_status AS estado_pago
FROM silver.billing;

-- ===== 6. df_gold_fact_admisiones =====
SELECT
    a.admission_id AS admission_id_bk,
    dp.paciente_key,
    dd.departamento_key,
    ISNULL(dg.diagnostico_key, sd.diagnostico_key) AS diagnostico_key,
    CONVERT(INT, CONVERT(CHAR(8), a.admission_date, 112)) AS fecha_ingreso_key,
    CONVERT(INT, CONVERT(CHAR(8), a.discharge_date, 112)) AS fecha_alta_key,
    a.attending_doctor_id AS medico_id,
    DATEDIFF(DAY, a.admission_date, a.discharge_date) AS dias_estancia,
    1 AS conteo_admisiones
FROM silver.admissions a
JOIN gold.dim_paciente dp     ON dp.patient_id_bk = a.patient_id
JOIN gold.dim_departamento dd ON dd.nombre_departamento = a.department
LEFT JOIN (
    SELECT
        admission_id,
        CAST(LTRIM(RTRIM(LEFT(icd_code, CHARINDEX(',', icd_code + ',') - 1))) AS VARCHAR(50)) AS codigo_icd,
        CAST(ISNULL(severity, 'Sin especificar') AS VARCHAR(50)) AS nivel_severidad,
        ROW_NUMBER() OVER (PARTITION BY admission_id
                           ORDER BY CASE severity WHEN 'Critical' THEN 1 WHEN 'Severe' THEN 2
                                                  WHEN 'Moderate' THEN 3 WHEN 'Mild' THEN 4 ELSE 5 END,
                                    diagnosis_id) AS rn
    FROM silver.diagnoses
) pr ON pr.admission_id = a.admission_id AND pr.rn = 1
LEFT JOIN gold.dim_diagnostico dg ON dg.codigo_icd = pr.codigo_icd AND dg.nivel_severidad = pr.nivel_severidad
CROSS JOIN (SELECT diagnostico_key FROM gold.dim_diagnostico WHERE codigo_icd = 'SIN-DX') sd;

-- ===== 7. df_gold_fact_facturacion =====
SELECT
    b.billing_id AS billing_id_bk,
    b.admission_id AS admission_id_bk,
    dp.paciente_key,
    dd.departamento_key,
    ds.servicio_cargo_key,
    CONVERT(INT, CONVERT(CHAR(8), b.payment_date, 112)) AS fecha_pago_key,
    b.amount AS monto_facturado,
    1 AS conteo_transacciones
FROM silver.billing b
JOIN silver.admissions a        ON a.admission_id = b.admission_id
JOIN gold.dim_paciente dp       ON dp.patient_id_bk = a.patient_id
JOIN gold.dim_departamento dd   ON dd.nombre_departamento = a.department
JOIN gold.dim_servicio_cargo ds ON ds.tipo_cargo = b.charge_type AND ds.estado_pago = b.payment_status;
