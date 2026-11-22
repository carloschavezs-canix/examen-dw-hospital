/*
  02 - CONSULTAS DE ORIGEN DE LOS DATA FLOWS SILVER
  Cada bloque se pega en: Data Flow > Origen > Opciones de origen > Entrada: Consulta.
  Leen de bronze, limpian y devuelven las columnas exactas de las tablas silver del magister.
  Orden de carga (por las FK): patients -> admissions -> diagnoses -> billing.
*/

-- ===== 1. df_silver_patients =====
SELECT
    p.patient_id,
    p.full_name,
    p.gender,
    p.date_of_birth,
    p.phone,
    p.email,
    p.address,
    p.insurance_provider
FROM (
    SELECT
        n.*,
        MIN(n.patient_id) OVER (PARTITION BY LOWER(n.full_name),
            COALESCE(CONVERT(VARCHAR(10), n.date_of_birth, 23), CAST(n.patient_id AS VARCHAR(10)))) AS patient_id_maestro
    FROM (
        SELECT
            TRY_CAST(LTRIM(RTRIM(b.patient_id)) AS INT) AS patient_id,
            LTRIM(RTRIM(b.full_name)) AS full_name,
            CASE UPPER(LTRIM(RTRIM(b.gender)))
                WHEN 'M' THEN 'M' WHEN 'MALE' THEN 'M'
                WHEN 'F' THEN 'F' WHEN 'FEMALE' THEN 'F'
            END AS gender,
            CASE
                WHEN f.fnac < '1900-01-01' THEN NULL
                WHEN f.fnac > CAST(GETDATE() AS DATE) AND LTRIM(RTRIM(b.date_of_birth)) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
                     THEN DATEADD(YEAR, -100, f.fnac)
                WHEN f.fnac > CAST(GETDATE() AS DATE) THEN NULL
                ELSE f.fnac
            END AS date_of_birth,
            CASE
                WHEN t.tel NOT LIKE '%[^0-9]%' AND LEN(t.tel) = 10 THEN t.tel
                WHEN t.tel NOT LIKE '%[^0-9]%' AND LEN(t.tel) = 11 AND LEFT(t.tel, 1) = '1' THEN RIGHT(t.tel, 10)
            END AS phone,
            CASE WHEN e.mail LIKE '_%@_%._%' THEN e.mail END AS email,
            LTRIM(RTRIM(b.address)) AS address,
            CASE
                WHEN s.seg LIKE 'AETNA%'                 THEN N'Aetna'
                WHEN s.seg LIKE 'BLUECROSS%'             THEN N'BlueCross'
                WHEN s.seg LIKE 'CIGNA%'                 THEN N'Cigna'
                WHEN s.seg = 'MEDICAID'                  THEN N'Medicaid'
                WHEN s.seg = 'MEDICARE'                  THEN N'Medicare'
                WHEN s.seg LIKE 'UNITED%' OR s.seg = 'UHC' THEN N'UnitedHealth'
                WHEN s.seg LIKE 'SELF%'                  THEN N'Self-Pay'
            END AS insurance_provider
        FROM bronze.patients b
        CROSS APPLY (SELECT silver.fn_Fecha(b.date_of_birth) AS fnac) f
        CROSS APPLY (SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(b.phone, ''))),
                            '(', ''), ')', ''), '-', ''), '.', ''), ' ', ''), '+', '') AS tel) t
        CROSS APPLY (SELECT LOWER(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(b.email)),
                            ' at ', '@'), ',com', '.com'), 'gmial.', 'gmail.')) AS mail) e
        CROSS APPLY (SELECT UPPER(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(ISNULL(b.insurance_provider, ''))),
                            ' ', ''), '-', ''), '.', '')) AS seg) s
    ) n
    WHERE n.patient_id IS NOT NULL AND n.full_name <> N''
) p
WHERE p.patient_id = p.patient_id_maestro;

-- ===== 2. df_silver_admissions =====
SELECT
    a.admission_id,
    sp.patient_id,
    a.admission_date,
    CASE WHEN a.discharge_date < a.admission_date THEN NULL ELSE a.discharge_date END AS discharge_date,
    a.department,
    a.attending_doctor_id
FROM (
    SELECT
        TRY_CAST(LTRIM(RTRIM(b.admission_id)) AS INT) AS admission_id,
        TRY_CAST(LTRIM(RTRIM(b.patient_id)) AS INT)   AS patient_id_origen,
        silver.fn_Fecha(b.admission_date) AS admission_date,
        silver.fn_Fecha(b.discharge_date) AS discharge_date,
        CASE
            WHEN d.dep LIKE 'CARD%'                        THEN N'Cardiology'
            WHEN d.dep LIKE 'EMER%' OR d.dep = 'ER'        THEN N'Emergency'
            WHEN d.dep LIKE 'GEN%'                         THEN N'General Surgery'
            WHEN d.dep LIKE 'NEU%' OR d.dep LIKE 'NUE%'    THEN N'Neurology'
            WHEN d.dep LIKE 'ONC%'                         THEN N'Oncology'
            WHEN d.dep LIKE 'ORTH%'                        THEN N'Orthopedics'
            WHEN d.dep LIKE 'PED%' OR d.dep LIKE 'PAED%'   THEN N'Pediatrics'
            ELSE N'Unspecified'
        END AS department,
        TRY_CAST(LTRIM(RTRIM(b.attending_doctor_id)) AS INT) AS attending_doctor_id
    FROM bronze.admissions b
    CROSS APPLY (SELECT UPPER(REPLACE(LTRIM(RTRIM(ISNULL(b.department, ''))), ' ', '')) AS dep) d
) a
JOIN (
    SELECT
        TRY_CAST(LTRIM(RTRIM(patient_id)) AS INT) AS patient_id_origen,
        MIN(TRY_CAST(LTRIM(RTRIM(patient_id)) AS INT)) OVER (PARTITION BY LOWER(LTRIM(RTRIM(full_name))),
            COALESCE(CONVERT(VARCHAR(10), silver.fn_Fecha(date_of_birth), 23), LTRIM(RTRIM(patient_id)))) AS patient_id_maestro
    FROM bronze.patients
) m ON m.patient_id_origen = a.patient_id_origen
JOIN silver.patients sp ON sp.patient_id = m.patient_id_maestro
WHERE a.admission_id IS NOT NULL
  AND a.admission_date IS NOT NULL
  AND a.attending_doctor_id IS NOT NULL;

-- ===== 3. df_silver_diagnoses =====
SELECT
    d.diagnosis_id,
    d.admission_id,
    d.icd_code,
    d.diagnosis_description,
    d.severity
FROM (
    SELECT
        TRY_CAST(LTRIM(RTRIM(b.diagnosis_id)) AS INT) AS diagnosis_id,
        TRY_CAST(LTRIM(RTRIM(b.admission_id)) AS INT) AS admission_id,
        (SELECT STRING_AGG(silver.fn_ICD(s.value), ', ') WITHIN GROUP (ORDER BY s.ordinal)
         FROM STRING_SPLIT(b.icd_code, ',', 1) s
         WHERE silver.fn_ICD(s.value) IS NOT NULL) AS icd_code,
        LTRIM(RTRIM(b.diagnosis_description)) AS diagnosis_description,
        CASE UPPER(LTRIM(RTRIM(b.severity)))
            WHEN 'MILD'     THEN 'Mild'
            WHEN 'MODERATE' THEN 'Moderate'
            WHEN 'SEVERE'   THEN 'Severe'
            WHEN 'CRITICAL' THEN 'Critical'
        END AS severity
    FROM bronze.diagnoses b
) d
WHERE d.diagnosis_id IS NOT NULL
  AND d.icd_code IS NOT NULL
  AND EXISTS (SELECT 1 FROM silver.admissions a WHERE a.admission_id = d.admission_id);

-- ===== 4. df_silver_billing =====
SELECT
    f.billing_id,
    f.admission_id,
    f.charge_type,
    f.amount,
    f.payment_status,
    f.payment_date
FROM (
    SELECT
        TRY_CAST(LTRIM(RTRIM(b.billing_id)) AS INT)   AS billing_id,
        TRY_CAST(LTRIM(RTRIM(b.admission_id)) AS INT) AS admission_id,
        CASE UPPER(LTRIM(RTRIM(b.charge_type)))
            WHEN 'SURGERY'      THEN 'Surgery'
            WHEN 'MEDICATION'   THEN 'Medication'
            WHEN 'IMAGING'      THEN 'Imaging'
            WHEN 'ROOM'         THEN 'Room'
            WHEN 'CONSULTATION' THEN 'Consultation'
            WHEN 'LAB TEST'     THEN 'Lab Test'
            ELSE 'Unspecified'
        END AS charge_type,
        CAST(ROUND(TRY_CAST(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(b.amount))),
            'USD', ''), '$', ''), ',', ''), ' ', '') AS DECIMAL(18,6)), 2) AS DECIMAL(12,2)) AS amount,
        CASE UPPER(LTRIM(RTRIM(b.payment_status)))
            WHEN 'PAID'    THEN 'Paid'
            WHEN 'PENDING' THEN 'Pending'
            WHEN 'UNPAID'  THEN 'Unpaid'
            WHEN 'OVERDUE' THEN 'Overdue'
            ELSE 'Unspecified'
        END AS payment_status,
        silver.fn_Fecha(b.payment_date) AS payment_date
    FROM bronze.billing b
) f
WHERE f.billing_id IS NOT NULL
  AND f.amount IS NOT NULL
  AND f.amount <= 20000
  AND EXISTS (SELECT 1 FROM silver.admissions a WHERE a.admission_id = f.admission_id);
