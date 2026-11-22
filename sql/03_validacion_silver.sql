/*
  03 - VALIDACION SILVER (control de calidad)
  Ejecutar despues de correr el pipeline pl_silver_hospital. La columna ok debe decir SI en todas las filas.
*/
SELECT tabla, bronze, silver, esperado, CASE WHEN silver = esperado THEN 'SI' ELSE 'NO' END AS ok
FROM (
    SELECT 'patients' AS tabla, (SELECT COUNT(*) FROM bronze.patients) AS bronze, (SELECT COUNT(*) FROM silver.patients) AS silver, 1000 AS esperado
    UNION ALL SELECT 'admissions', (SELECT COUNT(*) FROM bronze.admissions), (SELECT COUNT(*) FROM silver.admissions), 1689
    UNION ALL SELECT 'diagnoses',  (SELECT COUNT(*) FROM bronze.diagnoses),  (SELECT COUNT(*) FROM silver.diagnoses),  1991
    UNION ALL SELECT 'billing',    (SELECT COUNT(*) FROM bronze.billing),    (SELECT COUNT(*) FROM silver.billing),    1925
) v;

/* Por que se quitaron filas (para el informe) */
SELECT 'patients: duplicados (mismo nombre y fecha de nacimiento)' AS motivo,
       (SELECT COUNT(*) FROM bronze.patients) - (SELECT COUNT(*) FROM silver.patients) AS filas
UNION ALL SELECT 'admissions: sin fecha de admision',
       (SELECT COUNT(*) FROM bronze.admissions WHERE silver.fn_Fecha(admission_date) IS NULL)
UNION ALL SELECT 'admissions: paciente que no existe',
       (SELECT COUNT(*) FROM bronze.admissions b WHERE silver.fn_Fecha(b.admission_date) IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM silver.admissions a WHERE a.admission_id = TRY_CAST(b.admission_id AS INT)))
UNION ALL SELECT 'diagnoses: admision que no existe en silver',
       (SELECT COUNT(*) FROM bronze.diagnoses b WHERE NOT EXISTS (SELECT 1 FROM silver.admissions a WHERE a.admission_id = TRY_CAST(b.admission_id AS INT)))
UNION ALL SELECT 'billing: admision que no existe en silver',
       (SELECT COUNT(*) FROM bronze.billing b WHERE NOT EXISTS (SELECT 1 FROM silver.admissions a WHERE a.admission_id = TRY_CAST(b.admission_id AS INT)))
UNION ALL SELECT 'billing: monto vacio o mayor a 20.000',
       (SELECT COUNT(*) FROM bronze.billing b WHERE EXISTS (SELECT 1 FROM silver.admissions a WHERE a.admission_id = TRY_CAST(b.admission_id AS INT))
          AND NOT EXISTS (SELECT 1 FROM silver.billing s WHERE s.billing_id = TRY_CAST(b.billing_id AS INT)));
