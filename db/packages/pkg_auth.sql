CREATE OR REPLACE PACKAGE         "PKG_AUTH" AS
  -- Hash + verify
  PROCEDURE gerar_hash(p_senha IN VARCHAR2, p_hash OUT VARCHAR2, p_salt OUT VARCHAR2);
  FUNCTION verificar_senha(p_senha_input IN VARCHAR2, p_hash IN VARCHAR2, p_salt IN VARCHAR2) RETURN BOOLEAN;

  -- Validacao de complexidade (PT-BR msg)
  FUNCTION valida_complexidade(p_senha IN VARCHAR2) RETURN VARCHAR2;

  -- Auth Scheme custom function
  FUNCTION autenticar(p_username IN VARCHAR2, p_password IN VARCHAR2) RETURN BOOLEAN;

  -- Contexto do usuario + regras de entrada. Roda no processo After Login, que dispara
  -- tanto no login com senha quanto na volta pelo cookie de "Manter conectado".
  PROCEDURE registrar_entrada(
    p_app_user     IN  VARCHAR2,
    p_user_id      OUT NUMBER,
    p_role         OUT VARCHAR2,
    p_forcar_troca OUT VARCHAR2
  );

-- Derruba o "Manter conectado". A API do APEX tambem encerra as sessoes ativas do
-- usuario, inclusive a de quem chamou.
  PROCEDURE revogar_acesso(p_id IN NUMBER, p_motivo IN VARCHAR2 DEFAULT NULL);

-- Mesma coisa com a identidade passada na chamada, para revogar depois de um UPDATE
-- que trocou username ou e-mail: o token foi emitido sob a identidade antiga.
  PROCEDURE revogar_acesso(
    p_usuario_id IN NUMBER,
    p_username   IN VARCHAR2,
    p_email      IN VARCHAR2,
    p_motivo     IN VARCHAR2 DEFAULT NULL
  );

  -- User-initiated password change
  PROCEDURE alterar_senha(p_id IN NUMBER, p_senha_atual IN VARCHAR2, p_senha_nova IN VARCHAR2);

  -- Admin actions
  PROCEDURE bloquear_conta(p_id IN NUMBER, p_solicitante_id IN NUMBER, p_motivo IN VARCHAR2 DEFAULT NULL);
  PROCEDURE desbloquear_conta(p_id IN NUMBER, p_solicitante_id IN NUMBER);

  -- Log helper (publico pra outros packages chamarem)
  PROCEDURE log_evento(
    p_evento        IN VARCHAR2,
    p_usuario_id    IN NUMBER   DEFAULT NULL,
    p_username      IN VARCHAR2 DEFAULT NULL,
    p_email         IN VARCHAR2 DEFAULT NULL,
    p_realizado_por IN NUMBER   DEFAULT NULL,
    p_detalhes      IN JSON     DEFAULT NULL
  );

  -- Constantes
  c_max_failed_attempts CONSTANT NUMBER := 3;
  c_password_lifespan_days CONSTANT NUMBER := 90;
  c_iterations CONSTANT PLS_INTEGER := 10000;

END pkg_auth;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_AUTH" AS

-- Marcador do autenticar para o registrar_entrada: so funciona porque os dois rodam na
-- mesma requisicao. A janela de 1 minuto cobre conexao reciclada do pool do ORDS.
  g_auth_user VARCHAR2(255);
  g_auth_em   TIMESTAMP;

-- Helpers privados que leem cfg_app_preferencias com fallback.
  FUNCTION cfg_max_failed RETURN NUMBER IS
    l_v NUMBER;
  BEGIN
    BEGIN l_v := TO_NUMBER(admin.f_app_pref('sec_max_failed_login'));
    EXCEPTION WHEN OTHERS THEN l_v := NULL; END;
    IF l_v IS NULL OR l_v <= 0 THEN l_v := c_max_failed_attempts; END IF;
    RETURN l_v;
  END cfg_max_failed;

  FUNCTION cfg_pwd_expire_days RETURN NUMBER IS
    l_v NUMBER;
  BEGIN
    BEGIN l_v := TO_NUMBER(admin.f_app_pref('sec_force_pwd_expire_days'));
    EXCEPTION WHEN OTHERS THEN l_v := NULL; END;
    IF l_v IS NULL OR l_v < 0 THEN l_v := c_password_lifespan_days; END IF;
    RETURN l_v;
  END cfg_pwd_expire_days;

  FUNCTION cfg_pwd_min_length RETURN NUMBER IS
    l_v NUMBER;
  BEGIN
    BEGIN l_v := TO_NUMBER(admin.f_app_pref('sec_password_min_length'));
    EXCEPTION WHEN OTHERS THEN l_v := NULL; END;
    IF l_v IS NULL OR l_v < 6 THEN l_v := 8; END IF;
    RETURN l_v;
  END cfg_pwd_min_length;

  FUNCTION cfg_audit_login RETURN BOOLEAN IS
    l_v VARCHAR2(10);
  BEGIN
    BEGIN l_v := admin.f_app_pref('sec_audit_login_attempts');
    EXCEPTION WHEN OTHERS THEN l_v := NULL; END;
    -- Default true (audita) se pref ausente ou invalida
    RETURN NVL(UPPER(l_v),'S') = 'S';
  END cfg_audit_login;

  FUNCTION origem_ip_requisicao RETURN VARCHAR2 IS
    l_hdr VARCHAR2(4000);
    l_ip  VARCHAR2(4000);  -- largo de proposito: o corte e so no RETURN
  BEGIN
    -- sys_context da o IP do balanceador, igual para todos. O real vem no X-Forwarded-For.
    -- get_cgi_env levanta fora de requisicao HTTP, dai os handlers.
    BEGIN l_hdr := owa_util.get_cgi_env('X-Forwarded-For');
    EXCEPTION WHEN OTHERS THEN l_hdr := NULL; END;

    IF l_hdr IS NULL THEN
      BEGIN l_hdr := owa_util.get_cgi_env('HTTP_X_FORWARDED_FOR');
      EXCEPTION WHEN OTHERS THEN l_hdr := NULL; END;
    END IF;

    -- Ultimo item: e o que o balanceador escreveu, o cliente nao forja.
    IF l_hdr IS NOT NULL THEN
      l_ip := TRIM(REGEXP_SUBSTR(l_hdr, '[^,]+$'));
    END IF;

    -- SUBSTRB e nao SUBSTR: a coluna tem 60 BYTES e o cabecalho vem de fora.
    RETURN SUBSTRB(NVL(l_ip,
             NVL(sys_context('APEX$SESSION','IP_ADDRESS'),
                 sys_context('USERENV','IP_ADDRESS'))), 1, 60);
  EXCEPTION WHEN OTHERS THEN
    -- Nunca derrubar o registro de autenticacao por causa da origem.
    RETURN SUBSTRB(NVL(sys_context('APEX$SESSION','IP_ADDRESS'),
                       sys_context('USERENV','IP_ADDRESS')), 1, 60);
  END origem_ip_requisicao;

  FUNCTION origem_user_agent_requisicao RETURN VARCHAR2 IS
    l_ua VARCHAR2(4000);
  BEGIN
    -- MODULE da o modulo Oracle, igual para todo acesso pelo app. O real vem no User-Agent.
    -- get_cgi_env levanta fora de requisicao HTTP, dai os handlers.
    BEGIN l_ua := owa_util.get_cgi_env('User-Agent');
    EXCEPTION WHEN OTHERS THEN l_ua := NULL; END;

    IF l_ua IS NULL THEN
      BEGIN l_ua := owa_util.get_cgi_env('HTTP_USER_AGENT');
      EXCEPTION WHEN OTHERS THEN l_ua := NULL; END;
    END IF;

    -- SUBSTRB e nao SUBSTR: a coluna tem 500 BYTES e o cabecalho vem de fora.
    RETURN SUBSTRB(NVL(l_ua, sys_context('USERENV','MODULE')), 1, 500);
  EXCEPTION WHEN OTHERS THEN
    -- Nunca derrubar o registro de autenticacao por causa da origem.
    RETURN SUBSTRB(sys_context('USERENV','MODULE'), 1, 500);
  END origem_user_agent_requisicao;

-- Evento LOGIN_* so entra se a pref sec_audit_login_attempts estiver ligada.
  PROCEDURE log_evento(
    p_evento        IN VARCHAR2,
    p_usuario_id    IN NUMBER   DEFAULT NULL,
    p_username      IN VARCHAR2 DEFAULT NULL,
    p_email         IN VARCHAR2 DEFAULT NULL,
    p_realizado_por IN NUMBER   DEFAULT NULL,
    p_detalhes      IN JSON     DEFAULT NULL
  ) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_solic_user VARCHAR2(255);
    l_origem_ip  VARCHAR2(60);
    l_origem_ua  VARCHAR2(500);
  BEGIN
    IF p_evento LIKE 'LOGIN_%' AND NOT cfg_audit_login() THEN
      RETURN;
    END IF;

    BEGIN SELECT username INTO l_solic_user FROM cfg_usuarios_autorizados WHERE id = p_realizado_por;
    EXCEPTION WHEN NO_DATA_FOUND THEN l_solic_user := NULL; END;

    l_origem_ip := origem_ip_requisicao();
    l_origem_ua := origem_user_agent_requisicao();

    INSERT INTO log_auth_eventos (
      evento, usuario_id, username, email, origem_ip, origem_user_agent, origem_session,
      realizado_por, realizado_por_username, detalhes
    ) VALUES (
      p_evento, p_usuario_id, p_username, p_email,
      l_origem_ip,
      l_origem_ua,
      SUBSTR(NVL(sys_context('APEX$SESSION','APP_SESSION'), sys_context('USERENV','SESSIONID')),1,60),
      p_realizado_por, l_solic_user,
      p_detalhes
    );
    COMMIT;
  EXCEPTION WHEN OTHERS THEN
    BEGIN ROLLBACK; EXCEPTION WHEN OTHERS THEN NULL; END;
    apex_debug.warn('pkg_auth.log_evento falhou: '||SQLERRM);
  END log_evento;

-- c_iterations nao pode mudar: hash gravado com outro valor nunca mais confere.
  PROCEDURE gerar_hash(p_senha IN VARCHAR2, p_hash OUT VARCHAR2, p_salt OUT VARCHAR2) IS
    l_salt_raw RAW(16);
    l_hash_raw RAW(32);
    l_input    RAW(4000);
  BEGIN
    l_salt_raw := dbms_crypto.randombytes(16);
    l_input := UTL_RAW.CONCAT(UTL_I18N.STRING_TO_RAW(p_senha, 'AL32UTF8'), l_salt_raw);
    l_hash_raw := dbms_crypto.HASH(l_input, dbms_crypto.HASH_SH256);
    FOR i IN 2..c_iterations LOOP
      l_hash_raw := dbms_crypto.HASH(UTL_RAW.CONCAT(l_hash_raw, l_salt_raw), dbms_crypto.HASH_SH256);
    END LOOP;
    p_hash := RAWTOHEX(l_hash_raw);
    p_salt := RAWTOHEX(l_salt_raw);
  END gerar_hash;

  FUNCTION verificar_senha(p_senha_input IN VARCHAR2, p_hash IN VARCHAR2, p_salt IN VARCHAR2) RETURN BOOLEAN IS
    l_salt_raw RAW(16);
    l_hash_raw RAW(32);
    l_input    RAW(4000);
  BEGIN
    IF p_senha_input IS NULL OR p_hash IS NULL OR p_salt IS NULL THEN RETURN FALSE; END IF;
    l_salt_raw := HEXTORAW(p_salt);
    l_input := UTL_RAW.CONCAT(UTL_I18N.STRING_TO_RAW(p_senha_input, 'AL32UTF8'), l_salt_raw);
    l_hash_raw := dbms_crypto.HASH(l_input, dbms_crypto.HASH_SH256);
    FOR i IN 2..c_iterations LOOP
      l_hash_raw := dbms_crypto.HASH(UTL_RAW.CONCAT(l_hash_raw, l_salt_raw), dbms_crypto.HASH_SH256);
    END LOOP;
    RETURN RAWTOHEX(l_hash_raw) = UPPER(p_hash);
  END verificar_senha;

  FUNCTION valida_complexidade(p_senha IN VARCHAR2) RETURN VARCHAR2 IS
    l_min NUMBER := cfg_pwd_min_length();
  BEGIN
    IF p_senha IS NULL THEN RETURN unistr('Senha n\00E3o pode ser vazia.'); END IF;
    IF LENGTH(p_senha) < l_min THEN
      RETURN 'Senha deve ter ao menos '||l_min||' caracteres.';
    END IF;
    IF NOT REGEXP_LIKE(p_senha, '[A-Z]') THEN RETURN unistr('Senha deve ter ao menos 1 letra mai\00FAscula.'); END IF;
    IF NOT REGEXP_LIKE(p_senha, '[0-9]') THEN RETURN unistr('Senha deve ter ao menos 1 n\00FAmero.'); END IF;
    IF NOT REGEXP_LIKE(p_senha, '[^A-Za-z0-9]') THEN RETURN unistr('Senha deve ter ao menos 1 caractere especial.'); END IF;
    RETURN NULL;
  END valida_complexidade;

  -- autenticar: usa cfg_max_failed() e cfg_pwd_expire_days()
  FUNCTION autenticar(p_username IN VARCHAR2, p_password IN VARCHAR2) RETURN BOOLEAN IS
    l_row cfg_usuarios_autorizados%ROWTYPE;
    l_lookup_key VARCHAR2(255) := UPPER(TRIM(p_username));
    l_max_failed NUMBER := cfg_max_failed();
  BEGIN
    BEGIN
      SELECT * INTO l_row
        FROM cfg_usuarios_autorizados
       WHERE UPPER(username) = l_lookup_key
          OR LOWER(email) = LOWER(p_username);
    EXCEPTION WHEN NO_DATA_FOUND THEN
      log_evento('LOGIN_FAIL_NOT_FOUND', NULL, p_username, NULL);
      RETURN FALSE;
    END;

    IF l_row.ativo <> 'S' THEN
      log_evento('LOGIN_FAIL_INACTIVE', l_row.id, l_row.username, l_row.email);
      RETURN FALSE;
    END IF;

    IF l_row.account_locked = 'S' THEN
      log_evento('LOGIN_FAIL_LOCKED', l_row.id, l_row.username, l_row.email);
      RETURN FALSE;
    END IF;

    IF l_row.web_password IS NULL THEN
      log_evento('LOGIN_FAIL_PASSWORD', l_row.id, l_row.username, l_row.email);
      RETURN FALSE;
    END IF;

    IF NOT verificar_senha(p_password, l_row.web_password, l_row.web_password_salt) THEN
      -- Conta de demonstracao tem senha publica: quem erra nao pode acumular tentativa
      -- nem travar a conta, senao um visitante derruba a demonstracao para todos.
      IF NVL(l_row.demo,'N') = 'S' THEN
        log_evento('LOGIN_FAIL_PASSWORD', l_row.id, l_row.username, l_row.email);
        RETURN FALSE;
      END IF;

      UPDATE cfg_usuarios_autorizados
         SET failed_access_attempts = failed_access_attempts + 1,
             account_locked = CASE WHEN failed_access_attempts + 1 >= l_max_failed THEN 'S' ELSE account_locked END,
             locked_at      = CASE WHEN failed_access_attempts + 1 >= l_max_failed THEN admin.f_now_brt ELSE locked_at END
       WHERE id = l_row.id;
      COMMIT;

      log_evento('LOGIN_FAIL_PASSWORD', l_row.id, l_row.username, l_row.email,
                 NULL,
                 JSON_OBJECT('failed_attempts' VALUE l_row.failed_access_attempts + 1,
                             'max_failed'      VALUE l_max_failed RETURNING JSON));

      IF l_row.failed_access_attempts + 1 >= l_max_failed THEN
        -- ACCOUNT_LOCK e admin event - sempre loga (nao depende de cfg_audit_login)
        log_evento('ACCOUNT_LOCK', l_row.id, l_row.username, l_row.email,
                   NULL,
                   JSON_OBJECT('motivo' VALUE 'auto-lock apos N tentativas falhas',
                               'tentativas' VALUE l_max_failed RETURNING JSON));
        revogar_acesso(l_row.id, 'auto-lock apos N tentativas falhas');
      END IF;
      RETURN FALSE;
    END IF;

    -- A expiracao de senha vive no registrar_entrada, que roda no After Login e portanto
    -- vale tambem para quem volta pelo cookie persistente sem passar por aqui.

    UPDATE cfg_usuarios_autorizados
       SET failed_access_attempts = 0,
           last_login_at = admin.f_now_brt
     WHERE id = l_row.id;
    COMMIT;

    g_auth_user := UPPER(TRIM(p_username));
    g_auth_em   := SYSTIMESTAMP;

    log_evento('LOGIN_SUCCESS', l_row.id, l_row.username, l_row.email);
    RETURN TRUE;
  END autenticar;

-- REMOVE_PERSISTENT_AUTH apaga os tokens e encerra as sessoes ativas do usuario,
-- inclusive a de quem chamou: chamar por ultimo e depois do COMMIT.
  PROCEDURE revogar_acesso(
    p_usuario_id IN NUMBER,
    p_username   IN VARCHAR2,
    p_email      IN VARCHAR2,
    p_motivo     IN VARCHAR2 DEFAULT NULL
  ) IS
    l_ok VARCHAR2(1) := 'N';
  BEGIN
    BEGIN
      -- o login aceita username ou e-mail, e o token guarda o APP_USER, que vem em maiusculas
      IF p_username IS NOT NULL THEN
        apex_authentication.remove_persistent_auth(p_username => UPPER(p_username));
      END IF;
      IF p_email IS NOT NULL THEN
        apex_authentication.remove_persistent_auth(p_username => UPPER(p_email));
      END IF;
      l_ok := 'S';
    EXCEPTION WHEN OTHERS THEN
-- nao propaga: falhar aqui nao pode barrar a troca de senha nem o bloqueio.
      apex_debug.warn('pkg_auth.revogar_acesso: remove_persistent_auth falhou: '||SQLERRM);
    END;

    log_evento('PERSISTENT_AUTH_REVOKED', p_usuario_id, p_username, p_email, NULL,
               JSON_OBJECT('motivo'   VALUE NVL(p_motivo,'nao informado'),
                           'revogado' VALUE l_ok RETURNING JSON));
  END revogar_acesso;

  PROCEDURE revogar_acesso(p_id IN NUMBER, p_motivo IN VARCHAR2 DEFAULT NULL) IS
    l_row cfg_usuarios_autorizados%ROWTYPE;
  BEGIN
    BEGIN SELECT * INTO l_row FROM cfg_usuarios_autorizados WHERE id = p_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN RETURN; END;
    revogar_acesso(l_row.id, l_row.username, l_row.email, p_motivo);
  END revogar_acesso;

-- Unico ponto que roda nas duas entradas: login com senha e volta pelo cookie, que nao
-- passa pelo autenticar. Por isso expiracao de senha e auditoria de entrada ficam aqui.
  PROCEDURE registrar_entrada(
    p_app_user     IN  VARCHAR2,
    p_user_id      OUT NUMBER,
    p_role         OUT VARCHAR2,
    p_forcar_troca OUT VARCHAR2
  ) IS
    l_row cfg_usuarios_autorizados%ROWTYPE;
    l_expire_days   NUMBER := cfg_pwd_expire_days();
    l_pwd_age_days  NUMBER;
    l_veio_de_senha BOOLEAN;
  BEGIN
    p_user_id := NULL; p_role := NULL; p_forcar_troca := 'N';

    l_veio_de_senha := g_auth_em IS NOT NULL
                   AND g_auth_user = UPPER(TRIM(p_app_user))
                   AND g_auth_em > SYSTIMESTAMP - INTERVAL '1' MINUTE;
    g_auth_user := NULL;
    g_auth_em   := NULL;

    BEGIN
      SELECT * INTO l_row
        FROM cfg_usuarios_autorizados
       WHERE (UPPER(username) = UPPER(p_app_user) OR LOWER(email) = LOWER(p_app_user))
         AND ativo = 'S' AND account_locked = 'N';
    EXCEPTION WHEN NO_DATA_FOUND THEN
-- Sem linha aqui so no retorno por cookie com conta inativa ou bloqueada. Sem derrubar
-- o token o aparelho continua entrando ate o cookie expirar.
      BEGIN
        log_evento('LOGIN_FAIL_INACTIVE', NULL, p_app_user, NULL, NULL,
                   JSON_OBJECT('via' VALUE 'cookie persistente' RETURNING JSON));
        apex_authentication.remove_persistent_auth(p_username => UPPER(TRIM(p_app_user)));
      EXCEPTION WHEN OTHERS THEN
        apex_debug.warn('pkg_auth.registrar_entrada: revogacao de conta invalida falhou: '||SQLERRM);
      END;
      RETURN;
    END;

    -- Efeito colateral em bloco proprio: falha de auditoria nao pode derrubar o login.
    BEGIN
      -- A demonstracao nao expira: forcar troca de senha nela trancaria a conta publica.
      IF l_expire_days > 0 AND l_row.password_changed_at IS NOT NULL
         AND NVL(l_row.demo,'N') = 'N' THEN
        l_pwd_age_days := EXTRACT(DAY FROM (admin.f_now_brt - l_row.password_changed_at));
        IF l_pwd_age_days >= l_expire_days THEN
          UPDATE cfg_usuarios_autorizados SET forcar_troca_senha = 'S'
           WHERE id = l_row.id AND forcar_troca_senha = 'N';
          IF SQL%ROWCOUNT > 0 THEN
            l_row.forcar_troca_senha := 'S';
            COMMIT;
            log_evento('PASSWORD_EXPIRED', l_row.id, l_row.username, l_row.email,
                       NULL,
                       JSON_OBJECT('idade_dias'  VALUE l_pwd_age_days,
                                   'expire_days' VALUE l_expire_days RETURNING JSON));
          END IF;
        END IF;
      END IF;

      IF NOT l_veio_de_senha THEN
        -- entrada sem senha digitada: o autenticar nao rodou, logo nao existe LOGIN_SUCCESS
        -- e este e o unico registro de que a pessoa entrou
        log_evento('LOGIN_PERSISTENTE', l_row.id, l_row.username, l_row.email,
                   NULL,
                   JSON_OBJECT('app_session' VALUE sys_context('APEX$SESSION','APP_SESSION') RETURNING JSON));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      apex_debug.warn('pkg_auth.registrar_entrada: efeito colateral falhou: '||SQLERRM);
    END;

    p_user_id      := l_row.id;
    p_role         := l_row.role;
    p_forcar_troca := NVL(l_row.forcar_troca_senha,'N');
  END registrar_entrada;

  PROCEDURE alterar_senha(p_id IN NUMBER, p_senha_atual IN VARCHAR2, p_senha_nova IN VARCHAR2) IS
    l_row cfg_usuarios_autorizados%ROWTYPE;
    l_validation VARCHAR2(500);
    l_new_hash VARCHAR2(255);
    l_new_salt VARCHAR2(64);
  BEGIN
    BEGIN SELECT * INTO l_row FROM cfg_usuarios_autorizados WHERE id = p_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN raise_application_error(-20030, unistr('Usu\00E1rio n\00E3o encontrado.'));
    END;

    IF NVL(l_row.demo,'N') = 'S' THEN
      raise_application_error(-20034, unistr('A conta de demonstra\00E7\00E3o n\00E3o pode ter a senha alterada.'));
    END IF;

    IF NOT verificar_senha(p_senha_atual, l_row.web_password, l_row.web_password_salt) THEN
      raise_application_error(-20031, 'Senha atual incorreta.');
    END IF;

    l_validation := valida_complexidade(p_senha_nova);
    IF l_validation IS NOT NULL THEN raise_application_error(-20032, l_validation); END IF;

    IF verificar_senha(p_senha_nova, l_row.web_password, l_row.web_password_salt) THEN
      raise_application_error(-20033, unistr('Nova senha n\00E3o pode ser igual \00E0 atual.'));
    END IF;

    gerar_hash(p_senha_nova, l_new_hash, l_new_salt);

    UPDATE cfg_usuarios_autorizados
       SET web_password = l_new_hash,
           web_password_salt = l_new_salt,
           web_password_version = '1',
           password_changed_at = admin.f_now_brt,
           forcar_troca_senha = 'N',
           failed_access_attempts = 0
     WHERE id = p_id;

    log_evento('PASSWORD_CHANGE', l_row.id, l_row.username, l_row.email, p_id);

-- Commit antes de revogar: a revogacao encerra as sessoes e a senha nova precisa ja
-- estar gravada. Derruba o "Manter conectado" de todos os aparelhos, de proposito.
    COMMIT;
    revogar_acesso(p_id, 'troca de senha pelo usuario');
  END alterar_senha;

  -- bloquear_conta / desbloquear_conta (admin events - sempre logam)
  PROCEDURE bloquear_conta(p_id IN NUMBER, p_solicitante_id IN NUMBER, p_motivo IN VARCHAR2 DEFAULT NULL) IS
    l_row cfg_usuarios_autorizados%ROWTYPE;
  BEGIN
    BEGIN SELECT * INTO l_row FROM cfg_usuarios_autorizados WHERE id = p_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN raise_application_error(-20030, unistr('Usu\00E1rio n\00E3o encontrado.'));
    END;
    UPDATE cfg_usuarios_autorizados
       SET account_locked = 'S', locked_at = admin.f_now_brt
     WHERE id = p_id;
    log_evento('ACCOUNT_LOCK', l_row.id, l_row.username, l_row.email, p_solicitante_id,
               JSON_OBJECT('motivo' VALUE NVL(p_motivo, 'manual pelo administrador') RETURNING JSON));
    COMMIT;
    revogar_acesso(p_id, NVL(p_motivo, 'conta bloqueada pelo administrador'));
  END bloquear_conta;

  PROCEDURE desbloquear_conta(p_id IN NUMBER, p_solicitante_id IN NUMBER) IS
    l_row cfg_usuarios_autorizados%ROWTYPE;
  BEGIN
    BEGIN SELECT * INTO l_row FROM cfg_usuarios_autorizados WHERE id = p_id;
    EXCEPTION WHEN NO_DATA_FOUND THEN raise_application_error(-20030, unistr('Usu\00E1rio n\00E3o encontrado.'));
    END;
    UPDATE cfg_usuarios_autorizados
       SET account_locked = 'N', locked_at = NULL, failed_access_attempts = 0
     WHERE id = p_id;
    log_evento('ACCOUNT_UNLOCK', l_row.id, l_row.username, l_row.email, p_solicitante_id);
  END desbloquear_conta;

END pkg_auth;
/
