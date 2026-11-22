/*
  06 - VALIDACION GOLD (control de calidad)
  Ejecutar despues de correr el pipeline pl_gold_etl_hospital. La columna ok debe decir SI en todas las filas.
*/
SELECT tabla, filas, esperado, CASE WHEN filas = esperado THEN 'SI' ELSE 'NO' END AS ok
FROM (
    SELECT 'dim_fecha' AS tabla, (SELECT COUNT(*) FROM gold.dim_fecha) AS filas,
           (SELECT COUNT(*) FROM (SELECT admission_date AS f FROM silver.admissions
                                  UNION SELECT discharge_date FROM silver.admissions WHERE discharge_date IS NOT NULL
                                  UNION SELECT payment_date FROM silver.billing WHERE payment_date IS NOT NULL) x) AS esperado
    UNION ALL SELECT 'dim_paciente',       (SELECT COUNT(*) FROM gold.dim_paciente),       (SELECT COUNT(*) FROM silver.patients)
    UNION ALL SELECT 'dim_departamento',   (SELECT COUNT(*) FROM gold.dim_departamento),   (SELECT COUNT(DISTINCT department) FROM silver.admissions)
    UNION ALL SELECT 'dim_diagnostico',    (SELECT COUNT(*) FROM gold.dim_diagnostico),
              (SELECT COUNT(*) FROM (SELECT DISTINCT LEFT(icd_code, CHARINDEX(',', icd_code + ',') - 1) AS c, ISNULL(severity, 'Sin especificar') AS s FROM silver.diagnoses) x) + 1
    UNION ALL SELECT 'dim_servicio_cargo', (SELECT COUNT(*) FROM gold.dim_servicio_cargo),
              (SELECT COUNT(*) FROM (SELECT DISTINCT charge_type, payment_status FROM silver.billing) x)
    UNION ALL SELECT 'fact_admisiones',    (SELECT COUNT(*) FROM gold.fact_admisiones),    (SELECT COUNT(*) FROM silver.admissions)
    UNION ALL SELECT 'fact_facturacion',   (SELECT COUNT(*) FROM gold.fact_facturacion),   (SELECT COUNT(*) FROM silver.billing)
) v;

-- Los montos deben cuadrar (las dos columnas iguales)
SELECT (SELECT SUM(amount) FROM silver.billing)               AS monto_silver,
       (SELECT SUM(monto_facturado) FROM gold.fact_facturacion) AS monto_gold;
