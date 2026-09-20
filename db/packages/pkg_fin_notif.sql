CREATE OR REPLACE PACKAGE       pkg_fin_notif AS
  PROCEDURE gerar_notificacoes(p_user_id IN NUMBER);
  PROCEDURE gerar_todos;
  PROCEDURE marcar_lida(p_notif_id IN NUMBER, p_user_id IN NUMBER);
  PROCEDURE marcar_nao_lida(p_notif_id IN NUMBER, p_user_id IN NUMBER);
  PROCEDURE marcar_todas_lidas(p_user_id IN NUMBER);
  FUNCTION  qtd_nao_lidas(p_user_id IN NUMBER) RETURN NUMBER;

  PROCEDURE criar_info(
    p_user_id   IN NUMBER,
    p_titulo    IN VARCHAR2,
    p_mensagem  IN VARCHAR2,
    p_link_url  IN VARCHAR2 DEFAULT NULL,
    p_expira_em IN TIMESTAMP DEFAULT NULL,
    p_id        OUT NUMBER
  );

  PROCEDURE atualizar_info(
    p_id        IN NUMBER,
    p_titulo    IN VARCHAR2,
    p_mensagem  IN VARCHAR2,
    p_link_url  IN VARCHAR2,
    p_expira_em IN TIMESTAMP
  );

  PROCEDURE excluir(p_id IN NUMBER);
  PROCEDURE limpar_expiradas;

  PROCEDURE enviar_email(
    p_user_id          IN NUMBER,
    p_template_static  IN VARCHAR2,
    p_placeholders     IN CLOB
  );

-- Job one-off no DBMS_SCHEDULER; enviar_email roda com sessao APEX propria.
  PROCEDURE enviar_email_async(
    p_user_id         IN NUMBER,
    p_template_static IN VARCHAR2,
    p_placeholders    IN CLOB
  );
END pkg_fin_notif;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_FIN_NOTIF" AS

  PROCEDURE log_email(
    p_user_id         IN NUMBER,
    p_template_static IN VARCHAR2,
    p_to              IN VARCHAR2,
    p_from            IN VARCHAR2,
    p_subject         IN VARCHAR2,
    p_html            IN CLOB,
    p_text            IN CLOB,
    p_provider        IN VARCHAR2,
    p_http_status     IN NUMBER,
    p_response_body   IN CLOB,
    p_status          IN VARCHAR2,
    p_erro_msg        IN VARCHAR2
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO admin.fin_email_log (
      user_id, template_static, to_address, from_address, subject,
      html_body, text_body, provider, http_status, response_body,
      status, erro_msg
    ) VALUES (
      p_user_id, p_template_static, p_to, p_from, p_subject,
      p_html, p_text, p_provider, p_http_status, p_response_body,
      p_status, p_erro_msg
    );
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
  END log_email;

  -- Literal de texto para SQL dinamico: aspas dobradas e o todo entre aspas.
  FUNCTION lit(p_txt IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN '''' || REPLACE(p_txt, '''', '''''') || '''';
  END lit;

  PROCEDURE enviar_email_async(
    p_user_id         IN NUMBER,
    p_template_static IN VARCHAR2,
    p_placeholders    IN CLOB
  ) IS
    l_job_name VARCHAR2(128);
    l_action   CLOB;
    l_username admin.cfg_usuarios_autorizados.username%TYPE;
  BEGIN
-- A sessao APEX e so contexto de workspace para o apex_mail. Usa o destinatario e nao um
-- nome fixo: renomear ou excluir a conta fixa derrubaria todo e-mail assincrono.
    BEGIN
      SELECT username INTO l_username
        FROM admin.cfg_usuarios_autorizados WHERE id = p_user_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN
      l_username := 'SCHEDULER';
    END;

    l_job_name := 'EMAIL_'||p_user_id||'_'||TO_CHAR(SYSTIMESTAMP,'YYYYMMDDHH24MISSFF3');
    -- Todo valor entra como literal escapado. Antes o template e os placeholders iam
    -- concatenados crus, e um nome com ]' fechava o q'[ ] e virava PL/SQL rodando como ADMIN.
    l_action :=
      'BEGIN ' ||
      '  apex_session.create_session(p_app_id => 102, p_page_id => 1, p_username => '
      || lit(l_username) || '); ' ||
      '  admin.pkg_fin_notif.enviar_email(p_user_id=>' || TO_CHAR(p_user_id) ||
      ',p_template_static=>' || lit(p_template_static) ||
      ',p_placeholders=>' || lit(DBMS_LOB.SUBSTR(p_placeholders, 3000, 1)) || '); ' ||
      '  COMMIT; ' ||
      'END;';
    -- job_action do scheduler e VARCHAR2(4000). Sem esta checagem o estouro vira erro
    -- generico do scheduler, sem dizer qual template passou do tamanho.
    IF LENGTH(l_action) > 4000 THEN
      raise_application_error(-20050,
        'Bloco do e-mail assincrono passou de 4000 caracteres (' || LENGTH(l_action) ||
        '). Template: ' || p_template_static);
    END IF;

    dbms_scheduler.create_job(
      job_name   => l_job_name,
      job_type   => 'PLSQL_BLOCK',
      job_action => l_action,
      start_date => SYSTIMESTAMP,
      enabled    => TRUE,
      auto_drop  => TRUE
    );
  EXCEPTION
    WHEN OTHERS THEN
      apex_debug.error('pkg_fin_notif.enviar_email_async falhou: user=%s, template=%s, sqlerrm=%s',
                       p_user_id, p_template_static, SQLERRM);
      RAISE;
  END enviar_email_async;

  PROCEDURE enviar_push(p_user_id NUMBER, p_titulo VARCHAR2, p_body VARCHAR2, p_link VARCHAR2) IS
    l_username admin.cfg_usuarios_autorizados.username%TYPE;
    l_app_id   CONSTANT NUMBER := 102;
  BEGIN
    SELECT username INTO l_username FROM admin.cfg_usuarios_autorizados WHERE id = p_user_id;
    IF apex_pwa.has_push_subscription(p_application_id => l_app_id, p_user_name => l_username) THEN
      apex_pwa.send_push_notification(
        p_application_id => l_app_id, p_user_name => l_username,
        p_title => p_titulo, p_body => p_body, p_target_url => p_link
      );
    END IF;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN NULL;
    WHEN OTHERS THEN
      apex_debug.error('pkg_fin_notif.enviar_push falhou: %s', SQLERRM);
  END enviar_push;

  PROCEDURE render_template(
    p_static_id      IN  VARCHAR2,
    p_placeholders   IN  CLOB,
    p_subject        OUT VARCHAR2,
    p_html           OUT CLOB,
    p_text           OUT CLOB
  ) IS
    l_subj      VARCHAR2(2000);
    l_body      CLOB;
    l_wrapper   CLOB;
    l_text_tmpl CLOB;
    l_key       VARCHAR2(200);
    l_val       VARCHAR2(4000);
  BEGIN
    SELECT subject, html_body, html_template, text_template
      INTO l_subj, l_body, l_wrapper, l_text_tmpl
      FROM apex_appl_email_templates
     WHERE application_id = 102 AND static_id = p_static_id;

    apex_json.parse(p_placeholders);

    DECLARE
      l_keys apex_t_varchar2;
    BEGIN
      l_keys := apex_json.get_members('.');
      FOR i IN 1..l_keys.count LOOP
        l_key := l_keys(i);
        l_val := apex_json.get_varchar2(l_key);
        l_subj := REPLACE(l_subj, '&'||l_key||'.', NVL(l_val,''));
        l_body := REPLACE(l_body, '&'||l_key||'.', NVL(l_val,''));
        IF l_text_tmpl IS NOT NULL THEN
          l_text_tmpl := REPLACE(l_text_tmpl, '&'||l_key||'.', NVL(l_val,''));
        END IF;
      END LOOP;
    END;

    IF l_wrapper IS NOT NULL THEN
      p_html := REPLACE(REPLACE(l_wrapper, '#BODY#', l_body), '#TITLE#', l_subj);
    ELSE
      p_html := l_body;
    END IF;

    p_subject := l_subj;
    p_text    := l_text_tmpl;
  END render_template;

  PROCEDURE enviar_resend(
    p_user_id         NUMBER,
    p_template_static VARCHAR2,
    p_to              VARCHAR2,
    p_from            VARCHAR2,
    p_subject         VARCHAR2,
    p_html            CLOB,
    p_text            CLOB
  ) IS
    l_api_key      VARCHAR2(200);
    l_endpoint     VARCHAR2(500);
    l_payload_json JSON;
    l_payload      CLOB;
    l_resp         CLOB;
    l_status       NUMBER;
    l_resultado    VARCHAR2(20);
    l_erro_msg     VARCHAR2(4000);
  BEGIN
    l_api_key  := admin.f_app_pref('email_resend_api_key');
    l_endpoint := admin.f_app_pref('email_resend_endpoint');

    IF l_api_key IS NULL OR l_api_key = 'PREENCHER_VIA_UI_OU_UPDATE' THEN
      log_email(
        p_user_id => p_user_id, p_template_static => p_template_static,
        p_to => p_to, p_from => p_from, p_subject => p_subject,
        p_html => p_html, p_text => p_text,
        p_provider => 'RESEND', p_http_status => NULL, p_response_body => NULL,
        p_status => 'INATIVO', p_erro_msg => 'email_resend_api_key nao configurada'
      );
      RETURN;
    END IF;

    l_payload_json := JSON_OBJECT(
      'from'    VALUE p_from,
      'to'      VALUE JSON_ARRAY(p_to),
      'subject' VALUE p_subject,
      'html'    VALUE p_html,
      'text'    VALUE p_text
      RETURNING JSON
    );
    l_payload := JSON_SERIALIZE(l_payload_json RETURNING CLOB);

    apex_web_service.g_request_headers.delete;
    apex_web_service.g_request_headers(1).name  := 'Authorization';
    apex_web_service.g_request_headers(1).value := 'Bearer ' || l_api_key;
    apex_web_service.g_request_headers(2).name  := 'Content-Type';
    apex_web_service.g_request_headers(2).value := 'application/json';

    BEGIN
      l_resp   := apex_web_service.make_rest_request(
                    p_url => l_endpoint, p_http_method => 'POST', p_body => l_payload
                  );
      l_status := apex_web_service.g_status_code;
    EXCEPTION WHEN OTHERS THEN
      l_status := NULL; l_resp := NULL;
      l_erro_msg := 'EXC HTTP: '||SUBSTR(SQLERRM,1,3900);
    END;

    IF l_erro_msg IS NOT NULL THEN
      l_resultado := 'ERRO';
    ELSIF l_status BETWEEN 200 AND 299 THEN
      l_resultado := 'ENVIADO';
    ELSE
      l_resultado := 'ERRO';
      l_erro_msg  := 'HTTP '||l_status||' resp='||SUBSTR(NVL(l_resp,''),1,3900);
    END IF;

    log_email(
      p_user_id => p_user_id, p_template_static => p_template_static,
      p_to => p_to, p_from => p_from, p_subject => p_subject,
      p_html => p_html, p_text => p_text,
      p_provider => 'RESEND', p_http_status => l_status, p_response_body => l_resp,
      p_status => l_resultado, p_erro_msg => l_erro_msg
    );
  END enviar_resend;

  PROCEDURE enviar_email(
    p_user_id          IN NUMBER,
    p_template_static  IN VARCHAR2,
    p_placeholders     IN CLOB
  ) IS
    l_email     admin.cfg_usuarios_autorizados.email%TYPE;
    l_ativo     admin.cfg_usuarios_autorizados.email_notificacoes_ativo%TYPE;
    l_user_ok   admin.cfg_usuarios_autorizados.ativo%TYPE;
    l_from_addr VARCHAR2(255);
    l_from_name VARCHAR2(255);
    l_from      VARCHAR2(255);
    l_master    VARCHAR2(4);
    l_provider  VARCHAR2(20);
    l_subject   VARCHAR2(2000);
    l_html      CLOB;
    l_text      CLOB;
  BEGIN
    l_master := admin.f_app_pref('email_master_enabled');
    IF NVL(l_master,'N') <> 'S' THEN
      log_email(
        p_user_id => p_user_id, p_template_static => p_template_static,
        p_to => NULL, p_from => NULL, p_subject => NULL, p_html => NULL, p_text => NULL,
        p_provider => admin.f_app_pref('email_provider'),
        p_http_status => NULL, p_response_body => NULL,
        p_status => 'INATIVO', p_erro_msg => 'email_master_enabled = N'
      );
      RETURN;
    END IF;

    SELECT email, ativo, email_notificacoes_ativo
      INTO l_email, l_user_ok, l_ativo
      FROM admin.cfg_usuarios_autorizados WHERE id = p_user_id;

    IF l_user_ok <> 'S' OR l_ativo <> 'S' OR l_email IS NULL THEN
      log_email(
        p_user_id => p_user_id, p_template_static => p_template_static,
        p_to => l_email, p_from => NULL, p_subject => NULL, p_html => NULL, p_text => NULL,
        p_provider => admin.f_app_pref('email_provider'),
        p_http_status => NULL, p_response_body => NULL,
        p_status => 'INATIVO', p_erro_msg => 'usuario inativo ou sem email/notif_ativo'
      );
      RETURN;
    END IF;

    l_from_addr := NVL(admin.f_app_pref('email_from_address'), 'noreply@localhost');
    l_from_name := admin.f_app_pref('email_from_name');
    IF l_from_name IS NOT NULL THEN
      l_from := l_from_name || ' <' || l_from_addr || '>';
    ELSE
      l_from := l_from_addr;
    END IF;
    l_provider := NVL(admin.f_app_pref('email_provider'), 'RESEND');

    render_template(p_template_static, p_placeholders, l_subject, l_html, l_text);

    CASE l_provider
      WHEN 'RESEND' THEN
        enviar_resend(p_user_id, p_template_static, l_email, l_from, l_subject, l_html, l_text);
      WHEN 'SMTP' THEN
        BEGIN
          apex_mail.send(p_to => l_email, p_from => l_from_addr,
                         p_subj => l_subject, p_body => l_text, p_body_html => l_html);
          log_email(p_user_id => p_user_id, p_template_static => p_template_static,
            p_to => l_email, p_from => l_from, p_subject => l_subject,
            p_html => l_html, p_text => l_text, p_provider => 'SMTP',
            p_http_status => NULL, p_response_body => NULL, p_status => 'ENVIADO', p_erro_msg => NULL);
        EXCEPTION WHEN OTHERS THEN
          log_email(p_user_id => p_user_id, p_template_static => p_template_static,
            p_to => l_email, p_from => l_from, p_subject => l_subject,
            p_html => l_html, p_text => l_text, p_provider => 'SMTP',
            p_http_status => NULL, p_response_body => NULL,
            p_status => 'ERRO', p_erro_msg => SUBSTR(SQLERRM,1,3900));
        END;
      WHEN 'OCI_EMAIL_SMTP' THEN
        BEGIN
          apex_mail.send(p_to => l_email, p_from => l_from_addr,
                         p_subj => l_subject, p_body => l_text, p_body_html => l_html);
          BEGIN apex_mail.push_queue;
          EXCEPTION WHEN OTHERS THEN apex_debug.error('apex_mail.push_queue falhou: %s', SQLERRM); END;
          log_email(p_user_id => p_user_id, p_template_static => p_template_static,
            p_to => l_email, p_from => l_from, p_subject => l_subject,
            p_html => l_html, p_text => l_text, p_provider => 'OCI_EMAIL_SMTP',
            p_http_status => NULL, p_response_body => NULL, p_status => 'ENVIADO', p_erro_msg => NULL);
        EXCEPTION WHEN OTHERS THEN
          log_email(p_user_id => p_user_id, p_template_static => p_template_static,
            p_to => l_email, p_from => l_from, p_subject => l_subject,
            p_html => l_html, p_text => l_text, p_provider => 'OCI_EMAIL_SMTP',
            p_http_status => NULL, p_response_body => NULL,
            p_status => 'ERRO', p_erro_msg => SUBSTR(SQLERRM,1,3900));
        END;
      ELSE
        log_email(p_user_id => p_user_id, p_template_static => p_template_static,
          p_to => l_email, p_from => l_from, p_subject => l_subject,
          p_html => l_html, p_text => l_text, p_provider => l_provider,
          p_http_status => NULL, p_response_body => NULL,
          p_status => 'ERRO', p_erro_msg => 'provider desconhecido: '||l_provider);
    END CASE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      log_email(p_user_id => p_user_id, p_template_static => p_template_static,
        p_to => NULL, p_from => NULL, p_subject => NULL, p_html => NULL, p_text => NULL,
        p_provider => admin.f_app_pref('email_provider'),
        p_http_status => NULL, p_response_body => NULL,
        p_status => 'ERRO', p_erro_msg => 'usuario nao encontrado id='||p_user_id);
    WHEN OTHERS THEN
      log_email(p_user_id => p_user_id, p_template_static => p_template_static,
        p_to => NULL, p_from => NULL, p_subject => NULL, p_html => NULL, p_text => NULL,
        p_provider => admin.f_app_pref('email_provider'),
        p_http_status => NULL, p_response_body => NULL,
        p_status => 'ERRO', p_erro_msg => 'EXC: '||SUBSTR(SQLERRM,1,3900));
  END enviar_email;

  PROCEDURE gerar_notificacoes(p_user_id IN NUMBER) IS
    l_link_div   CONSTANT VARCHAR2(200) := '/ords/r/gestor_financeiro/gestor-financeiro/dividas';
    l_link_lanc  CONSTANT VARCHAR2(200) := '/ords/r/gestor_financeiro/gestor-financeiro/lancamentos';
    l_titulo     VARCHAR2(200);
    l_msg        VARCHAR2(1000);
    l_user_nome  admin.cfg_usuarios_autorizados.nome%TYPE;
    l_ph_json    JSON;
    l_dias_anteced NUMBER;
    l_hoje       DATE;
    l_renotif    VARCHAR2(20);
  BEGIN
    l_hoje := TRUNC(admin.f_now_brt);

    BEGIN SELECT NVL(nome, email) INTO l_user_nome FROM admin.cfg_usuarios_autorizados WHERE id = p_user_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN l_user_nome := 'usuario'; END;

    BEGIN l_dias_anteced := TO_NUMBER(admin.f_app_pref('email_dias_antecedencia'));
    EXCEPTION WHEN OTHERS THEN l_dias_anteced := 3; END;
    IF l_dias_anteced IS NULL OR l_dias_anteced < 0 THEN l_dias_anteced := 3; END IF;

    BEGIN l_renotif := UPPER(admin.f_app_pref('email_renotif_atrasados'));
    EXCEPTION WHEN OTHERS THEN l_renotif := 'UNICO'; END;
    IF l_renotif IS NULL THEN l_renotif := 'UNICO'; END IF;

    -- (A) Parcelas atrasadas: dedup depende de email_renotif_atrasados
    FOR pa IN (
      SELECT pa.id parcela_id, pa.numero, pa.valor, pa.data_vencimento, d.descricao d_desc, pa.divida_id
        FROM admin.fin_dividas_parcelas pa
        JOIN admin.fin_dividas d ON d.id = pa.divida_id
        LEFT JOIN admin.fin_lancamentos l ON l.id = pa.lancamento_id
       WHERE d.user_id = p_user_id AND d.ativo = 'S'
         AND (pa.lancamento_id IS NULL OR l.data_caixa IS NULL)
         AND pa.data_vencimento < l_hoje
         AND l_renotif <> 'NUNCA'
         AND (
           (l_renotif = 'DIARIO' AND NOT EXISTS (
              SELECT 1 FROM admin.fin_notificacoes n
               WHERE n.parcela_id = pa.id AND n.tipo = 'ATRASADA'
                 AND TRUNC(n.created_on) = l_hoje))
           OR
           (l_renotif = 'SEMANAL' AND NOT EXISTS (
              SELECT 1 FROM admin.fin_notificacoes n
               WHERE n.parcela_id = pa.id AND n.tipo = 'ATRASADA'
                 AND n.created_on > admin.f_now_brt - INTERVAL '7' DAY))
           OR
           (l_renotif NOT IN ('DIARIO','SEMANAL') AND NOT EXISTS (
              SELECT 1 FROM admin.fin_notificacoes n
               WHERE n.parcela_id = pa.id AND n.tipo = 'ATRASADA'
                 AND n.lido_em IS NULL))
         )
    ) LOOP
      l_titulo := pa.d_desc || ' atrasada';
      l_msg := 'Parcela ' || pa.numero || ' venceu em ' || TO_CHAR(pa.data_vencimento, 'DD/MM/YYYY') ||
               ' (' || (l_hoje - pa.data_vencimento) || 'd de atraso) - R$ ' ||
               TO_CHAR(pa.valor, 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
      INSERT INTO admin.fin_notificacoes (user_id, tipo, titulo, mensagem, link_url, parcela_id, divida_id, expira_em)
      VALUES (p_user_id, 'ATRASADA', l_titulo, l_msg, l_link_div, pa.parcela_id, pa.divida_id, admin.f_now_brt + INTERVAL '30' DAY);
      enviar_push(p_user_id, l_titulo, l_msg, l_link_div);

      l_ph_json := JSON_OBJECT(
        'TITULO' VALUE l_titulo, 'USUARIO_NOME' VALUE l_user_nome, 'MENSAGEM' VALUE l_msg,
        'DIVIDA_DESCRICAO' VALUE pa.d_desc, 'PARCELA_NUMERO' VALUE pa.numero,
        'VALOR' VALUE TO_CHAR(pa.valor,'FM999G999G990D00','NLS_NUMERIC_CHARACTERS='',.'''),
        'DATA_VENCIMENTO' VALUE TO_CHAR(pa.data_vencimento,'DD/MM/YYYY'),
        'LINK' VALUE NVL(admin.f_app_pref('app_base_url'),'http://localhost:8080') || l_link_div
        RETURNING JSON
      );
      enviar_email(p_user_id, 'EMAIL_NOTIF_VENCIMENTO', JSON_SERIALIZE(l_ph_json RETURNING CLOB));
    END LOOP;

    -- (B) Parcelas a vencer dentro da janela
    FOR pa IN (
      SELECT pa.id parcela_id, pa.numero, pa.valor, pa.data_vencimento, d.descricao d_desc, pa.divida_id
        FROM admin.fin_dividas_parcelas pa
        JOIN admin.fin_dividas d ON d.id = pa.divida_id
        LEFT JOIN admin.fin_lancamentos l ON l.id = pa.lancamento_id
       WHERE d.user_id = p_user_id AND d.ativo = 'S'
         AND (pa.lancamento_id IS NULL OR l.data_caixa IS NULL)
         AND pa.data_vencimento BETWEEN l_hoje AND l_hoje + l_dias_anteced
         AND NOT EXISTS (SELECT 1 FROM admin.fin_notificacoes n
                          WHERE n.parcela_id = pa.id AND n.tipo = 'VENC_PROXIMO' AND n.lido_em IS NULL)
    ) LOOP
      l_titulo := pa.d_desc || ' a vencer';
      l_msg := 'Parcela ' || pa.numero || ' vence em ' || TO_CHAR(pa.data_vencimento, 'DD/MM/YYYY') ||
               CASE WHEN pa.data_vencimento = l_hoje     THEN ' (hoje)'
                    WHEN pa.data_vencimento = l_hoje + 1 THEN ' (amanh' || UNISTR('\00E3') || ')'
                    ELSE ' (em ' || (pa.data_vencimento - l_hoje) || ' dias)' END ||
               ' - R$ ' || TO_CHAR(pa.valor, 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
      INSERT INTO admin.fin_notificacoes (user_id, tipo, titulo, mensagem, link_url, parcela_id, divida_id, expira_em)
      VALUES (p_user_id, 'VENC_PROXIMO', l_titulo, l_msg, l_link_div, pa.parcela_id, pa.divida_id, admin.f_now_brt + INTERVAL '30' DAY);
      enviar_push(p_user_id, l_titulo, l_msg, l_link_div);

      l_ph_json := JSON_OBJECT(
        'TITULO' VALUE l_titulo, 'USUARIO_NOME' VALUE l_user_nome, 'MENSAGEM' VALUE l_msg,
        'DIVIDA_DESCRICAO' VALUE pa.d_desc, 'PARCELA_NUMERO' VALUE pa.numero,
        'VALOR' VALUE TO_CHAR(pa.valor,'FM999G999G990D00','NLS_NUMERIC_CHARACTERS='',.'''),
        'DATA_VENCIMENTO' VALUE TO_CHAR(pa.data_vencimento,'DD/MM/YYYY'),
        'LINK' VALUE NVL(admin.f_app_pref('app_base_url'),'http://localhost:8080') || l_link_div
        RETURNING JSON
      );
      enviar_email(p_user_id, 'EMAIL_NOTIF_VENCIMENTO', JSON_SERIALIZE(l_ph_json RETURNING CLOB));
    END LOOP;

    -- (C) Avulsos atrasados: dedup depende de email_renotif_atrasados
    FOR la IN (
      SELECT l.id lanc_id, l.descricao, l.tipo, l.valor, l.data_competencia,
             SUBSTR(l.tipo, 1, 1) AS sentido
        FROM admin.fin_lancamentos l
       WHERE l.user_id = p_user_id
         AND l.ativo = 'S'
         AND l.data_caixa IS NULL
         AND l.data_competencia < l_hoje
         AND NOT EXISTS (SELECT 1 FROM admin.fin_dividas_parcelas pp WHERE pp.lancamento_id = l.id)
         AND l_renotif <> 'NUNCA'
         AND (
           (l_renotif = 'DIARIO' AND NOT EXISTS (
              SELECT 1 FROM admin.fin_notificacoes n
               WHERE n.lancamento_id = l.id AND n.tipo = 'ATRASADA'
                 AND TRUNC(n.created_on) = l_hoje))
           OR
           (l_renotif = 'SEMANAL' AND NOT EXISTS (
              SELECT 1 FROM admin.fin_notificacoes n
               WHERE n.lancamento_id = l.id AND n.tipo = 'ATRASADA'
                 AND n.created_on > admin.f_now_brt - INTERVAL '7' DAY))
           OR
           (l_renotif NOT IN ('DIARIO','SEMANAL') AND NOT EXISTS (
              SELECT 1 FROM admin.fin_notificacoes n
               WHERE n.lancamento_id = l.id AND n.tipo = 'ATRASADA'
                 AND n.lido_em IS NULL))
         )
    ) LOOP
      IF la.sentido = 'R' THEN
        l_titulo := la.descricao || ' (recebimento atrasado)';
        l_msg := 'Previsto em ' || TO_CHAR(la.data_competencia, 'DD/MM/YYYY') ||
                 ' (' || (l_hoje - la.data_competencia) || 'd de atraso) - R$ ' ||
                 TO_CHAR(la.valor, 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
      ELSE
        l_titulo := la.descricao || ' atrasado';
        l_msg := 'Venceu em ' || TO_CHAR(la.data_competencia, 'DD/MM/YYYY') ||
                 ' (' || (l_hoje - la.data_competencia) || 'd de atraso) - R$ ' ||
                 TO_CHAR(la.valor, 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
      END IF;

      INSERT INTO admin.fin_notificacoes (user_id, tipo, titulo, mensagem, link_url, lancamento_id, expira_em)
      VALUES (p_user_id, 'ATRASADA', l_titulo, l_msg, l_link_lanc, la.lanc_id, admin.f_now_brt + INTERVAL '30' DAY);
      enviar_push(p_user_id, l_titulo, l_msg, l_link_lanc);

      l_ph_json := JSON_OBJECT(
        'TITULO' VALUE l_titulo, 'USUARIO_NOME' VALUE l_user_nome, 'MENSAGEM' VALUE l_msg,
        'DIVIDA_DESCRICAO' VALUE la.descricao, 'PARCELA_NUMERO' VALUE UNISTR('\2014'),
        'VALOR' VALUE TO_CHAR(la.valor,'FM999G999G990D00','NLS_NUMERIC_CHARACTERS='',.'''),
        'DATA_VENCIMENTO' VALUE TO_CHAR(la.data_competencia,'DD/MM/YYYY'),
        'LINK' VALUE NVL(admin.f_app_pref('app_base_url'),'http://localhost:8080') || l_link_lanc
        RETURNING JSON
      );
      enviar_email(p_user_id, 'EMAIL_NOTIF_VENCIMENTO', JSON_SERIALIZE(l_ph_json RETURNING CLOB));
    END LOOP;

    -- (D) Avulsos a vencer
    FOR la IN (
      SELECT l.id lanc_id, l.descricao, l.tipo, l.valor, l.data_competencia,
             SUBSTR(l.tipo, 1, 1) AS sentido
        FROM admin.fin_lancamentos l
       WHERE l.user_id = p_user_id
         AND l.ativo = 'S'
         AND l.data_caixa IS NULL
         AND l.data_competencia BETWEEN l_hoje AND l_hoje + l_dias_anteced
         AND NOT EXISTS (SELECT 1 FROM admin.fin_dividas_parcelas pp WHERE pp.lancamento_id = l.id)
         AND NOT EXISTS (SELECT 1 FROM admin.fin_notificacoes n
                          WHERE n.lancamento_id = l.id AND n.tipo = 'VENC_PROXIMO' AND n.lido_em IS NULL)
    ) LOOP
      IF la.sentido = 'R' THEN
        l_titulo := la.descricao || ' a receber';
        l_msg := 'Previsto em ' || TO_CHAR(la.data_competencia, 'DD/MM/YYYY') ||
                 CASE WHEN la.data_competencia = l_hoje     THEN ' (hoje)'
                      WHEN la.data_competencia = l_hoje + 1 THEN ' (amanh' || UNISTR('\00E3') || ')'
                      ELSE ' (em ' || (la.data_competencia - l_hoje) || ' dias)' END ||
                 ' - R$ ' || TO_CHAR(la.valor, 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
      ELSE
        l_titulo := la.descricao || ' a vencer';
        l_msg := 'Vence em ' || TO_CHAR(la.data_competencia, 'DD/MM/YYYY') ||
                 CASE WHEN la.data_competencia = l_hoje     THEN ' (hoje)'
                      WHEN la.data_competencia = l_hoje + 1 THEN ' (amanh' || UNISTR('\00E3') || ')'
                      ELSE ' (em ' || (la.data_competencia - l_hoje) || ' dias)' END ||
                 ' - R$ ' || TO_CHAR(la.valor, 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
      END IF;

      INSERT INTO admin.fin_notificacoes (user_id, tipo, titulo, mensagem, link_url, lancamento_id, expira_em)
      VALUES (p_user_id, 'VENC_PROXIMO', l_titulo, l_msg, l_link_lanc, la.lanc_id, admin.f_now_brt + INTERVAL '30' DAY);
      enviar_push(p_user_id, l_titulo, l_msg, l_link_lanc);

      l_ph_json := JSON_OBJECT(
        'TITULO' VALUE l_titulo, 'USUARIO_NOME' VALUE l_user_nome, 'MENSAGEM' VALUE l_msg,
        'DIVIDA_DESCRICAO' VALUE la.descricao, 'PARCELA_NUMERO' VALUE UNISTR('\2014'),
        'VALOR' VALUE TO_CHAR(la.valor,'FM999G999G990D00','NLS_NUMERIC_CHARACTERS='',.'''),
        'DATA_VENCIMENTO' VALUE TO_CHAR(la.data_competencia,'DD/MM/YYYY'),
        'LINK' VALUE NVL(admin.f_app_pref('app_base_url'),'http://localhost:8080') || l_link_lanc
        RETURNING JSON
      );
      enviar_email(p_user_id, 'EMAIL_NOTIF_VENCIMENTO', JSON_SERIALIZE(l_ph_json RETURNING CLOB));
    END LOOP;

    COMMIT;
  END gerar_notificacoes;

  PROCEDURE gerar_todos IS
  BEGIN
    FOR u IN (SELECT id FROM admin.cfg_usuarios_autorizados WHERE ativo = 'S') LOOP
      gerar_notificacoes(u.id);
    END LOOP;
  END gerar_todos;

  PROCEDURE marcar_lida(p_notif_id IN NUMBER, p_user_id IN NUMBER) IS
  BEGIN
    UPDATE admin.fin_notificacoes SET lido_em = admin.f_now_brt
     WHERE id = p_notif_id AND user_id = p_user_id AND lido_em IS NULL;
    COMMIT;
  END marcar_lida;

  PROCEDURE marcar_nao_lida(p_notif_id IN NUMBER, p_user_id IN NUMBER) IS
  BEGIN
    UPDATE admin.fin_notificacoes SET lido_em = NULL
     WHERE id = p_notif_id AND user_id = p_user_id AND lido_em IS NOT NULL;
    COMMIT;
  END marcar_nao_lida;

  PROCEDURE marcar_todas_lidas(p_user_id IN NUMBER) IS
  BEGIN
    UPDATE admin.fin_notificacoes SET lido_em = admin.f_now_brt
     WHERE user_id = p_user_id AND lido_em IS NULL;
    COMMIT;
  END marcar_todas_lidas;

  FUNCTION qtd_nao_lidas(p_user_id IN NUMBER) RETURN NUMBER IS
    l_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_count FROM admin.fin_notificacoes
     WHERE user_id = p_user_id AND lido_em IS NULL
       AND (expira_em IS NULL OR expira_em > admin.f_now_brt);
    RETURN l_count;
  END qtd_nao_lidas;

  PROCEDURE criar_info(
    p_user_id IN NUMBER, p_titulo IN VARCHAR2, p_mensagem IN VARCHAR2,
    p_link_url IN VARCHAR2 DEFAULT NULL, p_expira_em IN TIMESTAMP DEFAULT NULL,
    p_id OUT NUMBER
  ) IS
    l_expira TIMESTAMP := NVL(p_expira_em, admin.f_now_brt + INTERVAL '7' DAY);
    l_last NUMBER; l_link VARCHAR2(4000);
    l_ph_json JSON; l_user_nome admin.cfg_usuarios_autorizados.nome%TYPE;

    PROCEDURE send_for(p_uid IN NUMBER) IS
    BEGIN
      SELECT NVL(nome, email) INTO l_user_nome FROM admin.cfg_usuarios_autorizados WHERE id = p_uid;
      enviar_push(p_uid, p_titulo, p_mensagem, p_link_url);
      l_link := COALESCE(p_link_url, '/ords/r/gestor_financeiro/gestor-financeiro/dashboard');
      l_ph_json := JSON_OBJECT(
        'TITULO' VALUE p_titulo, 'USUARIO_NOME' VALUE l_user_nome,
        'MENSAGEM' VALUE p_mensagem,
        'LINK' VALUE CASE WHEN l_link LIKE 'http%' THEN l_link ELSE NVL(admin.f_app_pref('app_base_url'),'http://localhost:8080') || l_link END
        RETURNING JSON
      );
      enviar_email(p_uid, 'EMAIL_NOTIF_INFO', JSON_SERIALIZE(l_ph_json RETURNING CLOB));
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
  BEGIN
    IF p_user_id IS NOT NULL THEN
      INSERT INTO admin.fin_notificacoes (user_id, tipo, titulo, mensagem, link_url, expira_em)
      VALUES (p_user_id, 'INFO', p_titulo, p_mensagem, p_link_url, l_expira)
      RETURNING id INTO p_id;
      send_for(p_user_id);
    ELSE
      FOR u IN (SELECT id FROM admin.cfg_usuarios_autorizados WHERE ativo = 'S') LOOP
        INSERT INTO admin.fin_notificacoes (user_id, tipo, titulo, mensagem, link_url, expira_em)
        VALUES (u.id, 'INFO', p_titulo, p_mensagem, p_link_url, l_expira)
        RETURNING id INTO l_last;
        send_for(u.id);
      END LOOP;
      p_id := l_last;
    END IF;
  END criar_info;

  PROCEDURE atualizar_info(p_id IN NUMBER, p_titulo IN VARCHAR2, p_mensagem IN VARCHAR2,
                           p_link_url IN VARCHAR2, p_expira_em IN TIMESTAMP) IS
  BEGIN
    UPDATE admin.fin_notificacoes
       SET titulo=p_titulo, mensagem=p_mensagem, link_url=p_link_url, expira_em=p_expira_em
     WHERE id = p_id
       AND (SYS_CONTEXT('APEX$SESSION','APP_USER') IS NULL
            OR NVL(v('G_USER_ROLE'),'NONE') = 'ADMIN'
            OR user_id = TO_NUMBER(v('G_USER_ID') DEFAULT NULL ON CONVERSION ERROR))
       ;
    IF SQL%ROWCOUNT = 0 THEN raise_application_error(-20002, 'Notificacao nao encontrada para atualizacao.'); END IF;
  END atualizar_info;

  PROCEDURE excluir(p_id IN NUMBER) IS
  BEGIN
    DELETE FROM admin.fin_notificacoes
     WHERE id = p_id
       AND (SYS_CONTEXT('APEX$SESSION','APP_USER') IS NULL
            OR NVL(v('G_USER_ROLE'),'NONE') = 'ADMIN'
            OR user_id = TO_NUMBER(v('G_USER_ID') DEFAULT NULL ON CONVERSION ERROR))
       ;
    IF SQL%ROWCOUNT = 0 THEN raise_application_error(-20003, 'Notificacao nao encontrada.'); END IF;
  END excluir;

  PROCEDURE limpar_expiradas IS
  BEGIN
    DELETE FROM admin.fin_notificacoes WHERE expira_em IS NOT NULL AND expira_em < admin.f_now_brt;
  END limpar_expiradas;

END pkg_fin_notif;
/
