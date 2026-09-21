CREATE OR REPLACE PACKAGE       pkg_manutencao AS
  PROCEDURE cleanup_dados_antigos(
    p_logs_audit_del      OUT NUMBER,
    p_log_auth_del        OUT NUMBER,
    p_notif_del           OUT NUMBER,
    p_anexos_del          OUT NUMBER
  );

  PROCEDURE truncate_logs(p_total OUT NUMBER);

  PROCEDURE test_cleanup_marcadores(
    p_lancamentos OUT NUMBER,
    p_dividas     OUT NUMBER,
    p_categorias  OUT NUMBER,
    p_origens     OUT NUMBER,
    p_usuarios    OUT NUMBER,
    p_notif       OUT NUMBER,
    p_pluggy_conn OUT NUMBER,
    p_anexos      OUT NUMBER
  );
END pkg_manutencao;
/

CREATE OR REPLACE PACKAGE BODY       pkg_manutencao AS

  PROCEDURE cleanup_dados_antigos(
    p_logs_audit_del      OUT NUMBER,
    p_log_auth_del        OUT NUMBER,
    p_notif_del           OUT NUMBER,
    p_anexos_del          OUT NUMBER
  ) IS
    l_dias        NUMBER;
    l_cut         TIMESTAMP;
    l_total       NUMBER;
    PROCEDURE clean_log_table(p_tab VARCHAR2, p_col VARCHAR2, p_cut TIMESTAMP, p_count IN OUT NUMBER) IS
    BEGIN
      EXECUTE IMMEDIATE 'DELETE FROM admin.'||p_tab||' WHERE '||p_col||' < :1' USING p_cut;
      p_count := p_count + SQL%ROWCOUNT;
    END;
  BEGIN
    p_logs_audit_del := 0;
    p_log_auth_del   := 0;
    p_notif_del      := 0;
    p_anexos_del     := 0;

    BEGIN l_dias := TO_NUMBER(admin.f_app_pref('cleanup_logs_dias')); EXCEPTION WHEN OTHERS THEN l_dias := NULL; END;
    IF l_dias IS NULL OR l_dias <= 0 THEN l_dias := 180; END IF;
    l_cut := admin.f_now_brt - NUMTODSINTERVAL(l_dias, 'DAY');
    l_total := 0;
    clean_log_table('LOG_CFG_APP_PREFERENCIAS',     'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_CFG_CATEGORIAS',           'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_CFG_ORIGENS',              'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_CFG_USUARIOS_AUTORIZADOS', 'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_DIVIDAS',              'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_DIVIDAS_PARCELAS',     'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_LANCAMENTOS',          'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_LANCAMENTOS_ANEXOS',   'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_NOTIFICACOES',         'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_PLUGGY_ACCOUNTS',      'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_PLUGGY_CONNECTIONS',   'OPERADO_EM', l_cut, l_total);
    clean_log_table('LOG_FIN_PLUGGY_TRANS',         'OPERADO_EM', l_cut, l_total);
    p_logs_audit_del := l_total;

    BEGIN l_dias := TO_NUMBER(admin.f_app_pref('cleanup_log_auth_dias')); EXCEPTION WHEN OTHERS THEN l_dias := NULL; END;
    IF l_dias IS NULL OR l_dias <= 0 THEN l_dias := 180; END IF;
    l_cut := admin.f_now_brt - NUMTODSINTERVAL(l_dias, 'DAY');
    DELETE FROM admin.log_auth_eventos WHERE ts < l_cut;
    p_log_auth_del := SQL%ROWCOUNT;
    -- o registro da API segue a mesma retencao do log de autenticacao
    DELETE FROM admin.log_api_chamadas WHERE ts < l_cut;
    p_log_auth_del := p_log_auth_del + SQL%ROWCOUNT;

    BEGIN l_dias := TO_NUMBER(admin.f_app_pref('cleanup_notif_dias')); EXCEPTION WHEN OTHERS THEN l_dias := NULL; END;
    IF l_dias IS NULL OR l_dias <= 0 THEN l_dias := 60; END IF;
    l_cut := admin.f_now_brt - NUMTODSINTERVAL(l_dias, 'DAY');
    DELETE FROM admin.fin_notificacoes WHERE lido_em IS NOT NULL AND lido_em < l_cut;
    p_notif_del := SQL%ROWCOUNT;

    BEGIN l_dias := TO_NUMBER(admin.f_app_pref('cleanup_anexos_lanc_excluidos_dias')); EXCEPTION WHEN OTHERS THEN l_dias := NULL; END;
    IF l_dias IS NULL OR l_dias < 0 THEN l_dias := 30; END IF;

    IF l_dias > 0 THEN
      l_cut := admin.f_now_brt - NUMTODSINTERVAL(l_dias, 'DAY');
      DELETE FROM admin.fin_lancamentos_anexos a
       WHERE EXISTS (SELECT 1 FROM admin.fin_lancamentos l
                      WHERE l.id = a.lancamento_id AND l.ativo = 'N' AND l.updated_on < l_cut);
      p_anexos_del := SQL%ROWCOUNT;
    END IF;

    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
  END cleanup_dados_antigos;

  PROCEDURE truncate_logs(p_total OUT NUMBER) IS
    PROCEDURE trunc_count(p_tab VARCHAR2, p_total IN OUT NUMBER) IS
      l_count NUMBER;
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM admin.'||p_tab INTO l_count;
      p_total := p_total + l_count;
      EXECUTE IMMEDIATE 'TRUNCATE TABLE admin.'||p_tab;
    END;
  BEGIN
    p_total := 0;
    trunc_count('LOG_AUTH_EVENTOS',             p_total);
    trunc_count('LOG_CFG_APP_PREFERENCIAS',     p_total);
    trunc_count('LOG_CFG_CATEGORIAS',           p_total);
    trunc_count('LOG_CFG_ORIGENS',              p_total);
    trunc_count('LOG_CFG_USUARIOS_AUTORIZADOS', p_total);
    trunc_count('LOG_FIN_DIVIDAS',              p_total);
    trunc_count('LOG_FIN_DIVIDAS_PARCELAS',     p_total);
    trunc_count('LOG_FIN_LANCAMENTOS',          p_total);
    trunc_count('LOG_FIN_LANCAMENTOS_ANEXOS',   p_total);
    trunc_count('LOG_FIN_NOTIFICACOES',         p_total);
    trunc_count('LOG_FIN_PLUGGY_ACCOUNTS',      p_total);
    trunc_count('LOG_FIN_PLUGGY_CONNECTIONS',   p_total);
    trunc_count('LOG_FIN_PLUGGY_TRANS',         p_total);
  END truncate_logs;

  PROCEDURE test_cleanup_marcadores(
    p_lancamentos OUT NUMBER,
    p_dividas     OUT NUMBER,
    p_categorias  OUT NUMBER,
    p_origens     OUT NUMBER,
    p_usuarios    OUT NUMBER,
    p_notif       OUT NUMBER,
    p_pluggy_conn OUT NUMBER,
    p_anexos      OUT NUMBER
  ) IS
  BEGIN
    p_lancamentos := 0; p_dividas := 0; p_categorias := 0; p_origens := 0;
    p_usuarios := 0; p_notif := 0; p_pluggy_conn := 0; p_anexos := 0;

    DELETE FROM admin.fin_lancamentos_anexos a
     WHERE EXISTS (SELECT 1 FROM admin.fin_lancamentos l
                    WHERE l.id = a.lancamento_id AND l.descricao LIKE 'TEST_S%');
    p_anexos := SQL%ROWCOUNT;

    DELETE FROM admin.fin_lancamentos WHERE descricao LIKE 'TEST_S%';
    p_lancamentos := SQL%ROWCOUNT;

    DELETE FROM admin.fin_dividas_parcelas dp
     WHERE EXISTS (SELECT 1 FROM admin.fin_dividas d
                    WHERE d.id = dp.divida_id AND d.descricao LIKE 'TEST_S%');
    DELETE FROM admin.fin_dividas WHERE descricao LIKE 'TEST_S%';
    p_dividas := SQL%ROWCOUNT;

    DELETE FROM admin.cfg_categorias WHERE nome LIKE 'TEST_S%';
    p_categorias := SQL%ROWCOUNT;

    DELETE FROM admin.cfg_origens WHERE nome LIKE 'TEST_S%';
    p_origens := SQL%ROWCOUNT;

    DELETE FROM admin.cfg_usuarios_autorizados WHERE email LIKE 'test_%@dummy.local';
    p_usuarios := SQL%ROWCOUNT;

    DELETE FROM admin.fin_notificacoes WHERE titulo LIKE 'TEST_S%';
    p_notif := SQL%ROWCOUNT;

    DELETE FROM admin.fin_pluggy_trans t
     WHERE EXISTS (SELECT 1 FROM admin.fin_pluggy_accounts a
                     JOIN admin.fin_pluggy_connections c ON c.id = a.connection_id
                    WHERE a.id = t.account_id AND c.pluggy_item_id LIKE 'TEST_%');
    DELETE FROM admin.fin_pluggy_accounts a
     WHERE EXISTS (SELECT 1 FROM admin.fin_pluggy_connections c
                    WHERE c.id = a.connection_id AND c.pluggy_item_id LIKE 'TEST_%');
    DELETE FROM admin.fin_pluggy_connections WHERE pluggy_item_id LIKE 'TEST_%';
    p_pluggy_conn := SQL%ROWCOUNT;

    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    apex_debug.error('pkg_manutencao.test_cleanup_marcadores falhou: '||SQLERRM);
    RAISE;
  END test_cleanup_marcadores;

END pkg_manutencao;
/
