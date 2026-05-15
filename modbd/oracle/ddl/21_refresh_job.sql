-- =============================================================================
-- 21_refresh_job.sql
-- Job DBMS_SCHEDULER care refresh-ueaza FAST cele 7 MV-uri replicate la fiecare
-- 60 secunde. Acopera cerinta 'sincronizare relatii replicate' (1p).
-- =============================================================================

BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESH_MVS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[BEGIN
      DBMS_MVIEW.REFRESH(
        'MV_CLIENTI,MV_ZONE,MV_ITEMS_CORE,MV_BRANDS,MV_ITEMS_CATEGORY,MV_ITEMS_TYPE,MV_ITEMS_SEASONS',
        method => 'FFFFFFF',
        atomic_refresh => FALSE);
    END;]',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=SECONDLY;INTERVAL=60',
    enabled         => TRUE,
    comments        => 'Refresh FAST al MV-urilor replicate la 60s'
  );
END;
/
