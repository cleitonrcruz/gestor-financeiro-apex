begin
  dbms_scheduler.create_job(
    job_name        => 'JOB_CLEANUP_DADOS_ANTIGOS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'DECLARE l1 NUMBER; l2 NUMBER; l3 NUMBER; l4 NUMBER; BEGIN admin.pkg_manutencao.cleanup_dados_antigos(l1, l2, l3, l4); END;',
    start_date      => SYSTIMESTAMP AT TIME ZONE 'America/Sao_Paulo',
    repeat_interval => 'FREQ=DAILY; BYHOUR=3; BYMINUTE=0',
    enabled         => TRUE,
    comments        => 'Limpa logs/notif/anexos antigos baseado em cfg_app_preferencias.');
end;
/
