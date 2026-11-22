/*
  01 - PREPARAR SILVER (ejecutar UNA vez en el Editor de consultas de dw_hospital)
  Copiar todo y Ejecutar. No tiene GO.
  Crea:
  - silver.fn_Fecha: convierte fechas en 5 formatos (2024-07-28, 07-27-24, 07/27/2024, 13-Jul-2024, July 13, 2024) a DATE
  - silver.fn_ICD:   limpia codigos ICD-10 (M54-5, M545, " m54.5 " -> M54.5)
  - silver.usp_limpiar_silver: vacia las tablas silver antes de cada carga (el pipeline lo llama primero)
  Las tablas silver ya las creo el Terraform del magister (2_silver.sql).
*/
EXEC(N'
CREATE OR ALTER FUNCTION silver.fn_Fecha (@valor NVARCHAR(200))
RETURNS DATE
AS
BEGIN
    DECLARE @x NVARCHAR(200) = LTRIM(RTRIM(@valor));
    IF @x IS NULL OR @x = N'''' RETURN NULL;
    RETURN CASE
        WHEN @x LIKE N''[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]''  THEN TRY_CONVERT(DATE, @x, 23)
        WHEN @x LIKE N''[0-9][0-9]-[0-9][0-9]-[0-9][0-9]''            THEN TRY_CONVERT(DATE, @x, 10)
        WHEN @x LIKE N''[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]''  THEN TRY_CONVERT(DATE, @x, 101)
        WHEN @x LIKE N''[0-9][0-9]-[A-Za-z][A-Za-z][A-Za-z]-[0-9][0-9][0-9][0-9]''
                                                                    THEN TRY_CONVERT(DATE, REPLACE(@x, N''-'', N'' ''), 106)
        ELSE TRY_PARSE(@x AS DATE USING ''en-US'')
    END;
END');

EXEC(N'
CREATE OR ALTER FUNCTION silver.fn_ICD (@valor NVARCHAR(200))
RETURNS VARCHAR(20)
AS
BEGIN
    DECLARE @x NVARCHAR(200) = UPPER(REPLACE(LTRIM(RTRIM(@valor)), N''-'', N''.''));
    IF @x IS NULL OR @x = N'''' RETURN NULL;
    IF CHARINDEX(N''.'', @x) = 0 AND LEN(@x) > 3 SET @x = STUFF(@x, 4, 0, N''.'');
    RETURN CAST(@x AS VARCHAR(20));
END');

EXEC(N'
CREATE OR ALTER PROCEDURE silver.usp_limpiar_silver
AS
BEGIN
    SET NOCOUNT ON;
    -- orden por las FK: primero las hijas
    DELETE FROM silver.billing;
    DELETE FROM silver.diagnoses;
    DELETE FROM silver.admissions;
    DELETE FROM silver.patients;
END');

SELECT 'listo' AS estado,
       OBJECT_ID('silver.fn_Fecha') AS fn_fecha,
       OBJECT_ID('silver.fn_ICD') AS fn_icd,
       OBJECT_ID('silver.usp_limpiar_silver') AS sp_limpiar;
