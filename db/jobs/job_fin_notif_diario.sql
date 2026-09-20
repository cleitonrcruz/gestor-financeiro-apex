begin
  dbms_scheduler.create_job(
    job_name        => 'JOB_FIN_NOTIF_DIARIO',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN admin.pkg_fin_notif.gerar_todos; END;',
    start_date      => SYSTIMESTAMP AT TIME ZONE 'America/Sao_Paulo',
    repeat_interval => 'FREQ=DAILY;BYHOUR=6;BYMINUTE=0;BYSECOND=0',
    enabled         => TRUE,
    comments        => 'Gera notificacoes de vencimento/atraso + push + email (BRT). Hora controlada por cfg_app_preferencias.email_hora_disparo.');
end;
/
