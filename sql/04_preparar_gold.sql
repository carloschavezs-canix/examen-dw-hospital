/*
  04 - PREPARAR GOLD (ejecutar UNA vez en el Editor de consultas de dw_hospital)
  Copiar todo y Ejecutar. No tiene GO.
  Crea gold.usp_limpiar_gold: el pipeline ETL lo llama al inicio para vaciar gold y volver a cargar.
  (Las dimensiones no pueden usar "Truncar" en el receptor porque los hechos tienen FK hacia ellas.)
  Las tablas gold ya las creo el Terraform del magister (3_gold.sql).
*/
EXEC(N'
CREATE OR ALTER PROCEDURE gold.usp_limpiar_gold
AS
BEGIN
    SET NOCOUNT ON;
    -- primero los hechos, despues las dimensiones
    DELETE FROM gold.fact_facturacion;
    DELETE FROM gold.fact_admisiones;
    DELETE FROM gold.dim_servicio_cargo;
    DELETE FROM gold.dim_diagnostico;
    DELETE FROM gold.dim_departamento;
    DELETE FROM gold.dim_paciente;
    DELETE FROM gold.dim_fecha;
    -- las claves autoincrementables vuelven a empezar en 1 (solo si la tabla ya tuvo filas)
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(''gold.dim_paciente'')) IS NOT NULL
        DBCC CHECKIDENT (''gold.dim_paciente'', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(''gold.dim_departamento'')) IS NOT NULL
        DBCC CHECKIDENT (''gold.dim_departamento'', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(''gold.dim_diagnostico'')) IS NOT NULL
        DBCC CHECKIDENT (''gold.dim_diagnostico'', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(''gold.dim_servicio_cargo'')) IS NOT NULL
        DBCC CHECKIDENT (''gold.dim_servicio_cargo'', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(''gold.fact_admisiones'')) IS NOT NULL
        DBCC CHECKIDENT (''gold.fact_admisiones'', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(''gold.fact_facturacion'')) IS NOT NULL
        DBCC CHECKIDENT (''gold.fact_facturacion'', RESEED, 0) WITH NO_INFOMSGS;
END');

SELECT 'listo' AS estado, OBJECT_ID('gold.usp_limpiar_gold') AS sp_limpiar_gold;
