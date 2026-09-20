CREATE OR REPLACE PACKAGE         "PKG_CFG_USUARIOS" AS
  PROCEDURE inserir(
    p_email			IN VARCHAR2,
    p_nome			IN VARCHAR2,
    p_username			IN VARCHAR2,
    p_role			IN VARCHAR2 DEFAULT 'USER',
    p_email_notificacoes_ativo	IN VARCHAR2 DEFAULT 'S',
    p_ativo			IN VARCHAR2 DEFAULT 'S',
    p_id			OUT NUMBER,
    p_senha_provisoria		OUT VARCHAR2
  );

  PROCEDURE atualizar(
    p_id			IN NUMBER,
    p_email			IN VARCHAR2,
    p_nome			IN VARCHAR2,
    p_username			IN VARCHAR2,
    p_role			IN VARCHAR2,
    p_email_notificacoes_ativo	IN VARCHAR2,
    p_ativo			IN VARCHAR2 DEFAULT NULL
  );

  FUNCTION obter(p_id IN NUMBER) RETURN cfg_usuarios_autorizados%ROWTYPE;
  FUNCTION pode_inativar(p_id IN NUMBER, p_solicitante_id IN NUMBER) RETURN VARCHAR2;

  PROCEDURE excluir(p_id IN NUMBER, p_solicitante_id IN NUMBER);

-- Alem do ativo='S', zera failed_attempts e destrava a conta.
  PROCEDURE ativar(p_id IN NUMBER, p_solicitante_id IN NUMBER);

  PROCEDURE resetar_senha(
    p_id		IN NUMBER,
    p_solicitante_id	IN NUMBER,
    p_senha_provisoria	OUT VARCHAR2
  );
END pkg_cfg_usuarios;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_CFG_USUARIOS" AS

 c_app_id    CONSTANT NUMBER := 102;
 -- O host sai do parametro app_base_url; fixar aqui manda o e-mail para o ambiente errado.
 c_link_path CONSTANT VARCHAR2(200) := '/ords/r/gestor_financeiro/gestor-financeiro/login';

 FUNCTION outros_admins_ativos(p_id_excluir IN NUMBER) RETURN NUMBER IS
   l_qtd NUMBER;
 BEGIN
   SELECT COUNT(*) INTO l_qtd FROM cfg_usuarios_autorizados WHERE role='ADMIN' AND ativo='S' AND id<>NVL(p_id_excluir,-1);
   RETURN l_qtd;
 END;

 FUNCTION gerar_senha_provisoria RETURN VARCHAR2 IS
   l_specials CONSTANT VARCHAR2(20) := '@#$!&*+';
   l_pool VARCHAR2(40);
   l_idx PLS_INTEGER;
   l_shuffled VARCHAR2(40);
 BEGIN
   l_pool := dbms_random.string('U',3) || dbms_random.string('L',3) || dbms_random.string('X',3) ||
             SUBSTR(l_specials, TRUNC(dbms_random.value(1,LENGTH(l_specials)+1)), 1);
   l_shuffled := '';
   FOR i IN 1..LENGTH(l_pool) LOOP
     l_idx := TRUNC(dbms_random.value(1, LENGTH(l_pool)+1));
     l_shuffled := l_shuffled || SUBSTR(l_pool, l_idx, 1);
     l_pool := SUBSTR(l_pool, 1, l_idx-1) || SUBSTR(l_pool, l_idx+1);
   END LOOP;
   RETURN l_shuffled;
 END gerar_senha_provisoria;

 FUNCTION valida_unicidade(
   p_email      IN VARCHAR2,
   p_username   IN VARCHAR2,
   p_id_atual   IN NUMBER DEFAULT NULL
 ) RETURN VARCHAR2 IS
   l_email_lc VARCHAR2(255) := LOWER(TRIM(p_email));
   l_uname_uc VARCHAR2(255) := UPPER(TRIM(p_username));
   l_existing_nome VARCHAR2(200);
 BEGIN
   BEGIN
     SELECT nome INTO l_existing_nome FROM cfg_usuarios_autorizados
      WHERE LOWER(email) = l_email_lc AND id <> NVL(p_id_atual,-1) AND ROWNUM=1;
     RETURN unistr('J\00E1 existe um usu\00E1rio com este email (')||
            NVL(l_existing_nome,'sem nome cadastrado')||').';
   EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;

   BEGIN
     SELECT nome INTO l_existing_nome FROM cfg_usuarios_autorizados
      WHERE UPPER(username) = l_uname_uc AND id <> NVL(p_id_atual,-1) AND ROWNUM=1;
     RETURN unistr('J\00E1 existe um usu\00E1rio com este login (')||
            NVL(l_existing_nome,'sem nome cadastrado')||').';
   EXCEPTION WHEN NO_DATA_FOUND THEN NULL; END;

   RETURN NULL;
 END valida_unicidade;

 PROCEDURE inserir(
   p_email IN VARCHAR2, p_nome IN VARCHAR2, p_username IN VARCHAR2,
   p_role IN VARCHAR2 DEFAULT 'USER',
   p_email_notificacoes_ativo IN VARCHAR2 DEFAULT 'S',
   p_ativo IN VARCHAR2 DEFAULT 'S',
   p_id OUT NUMBER, p_senha_provisoria OUT VARCHAR2
 ) IS
   l_username_uc VARCHAR2(255):=UPPER(TRIM(p_username));
   l_email_lc    VARCHAR2(255):=LOWER(TRIM(p_email));
   l_ph_clob CLOB; l_ph JSON;
   l_dup_msg VARCHAR2(500);
   l_hash VARCHAR2(255); l_salt VARCHAR2(64);
 BEGIN
   IF p_email IS NULL OR p_username IS NULL THEN raise_application_error(-20010,unistr('Email e login s\00E3o obrigat\00F3rios.')); END IF;
   IF NVL(p_role,'USER') NOT IN ('ADMIN','USER') THEN raise_application_error(-20011,unistr('Role inv\00E1lido (ADMIN ou USER).')); END IF;
   IF NOT REGEXP_LIKE(p_username, '^[A-Za-z][A-Za-z0-9_]*$') THEN
     raise_application_error(-20022, unistr('Login inv\00E1lido. Use apenas letras, n\00FAmeros e underscore. Sem espa\00E7os, pontos ou caracteres especiais.'));
   END IF;

   l_dup_msg := valida_unicidade(p_email => l_email_lc, p_username => l_username_uc);
   IF l_dup_msg IS NOT NULL THEN raise_application_error(-20020, l_dup_msg); END IF;

   p_senha_provisoria := gerar_senha_provisoria;
   pkg_auth.gerar_hash(p_senha_provisoria, l_hash, l_salt);

   INSERT INTO cfg_usuarios_autorizados (
     email, nome, username, role, ativo, email_notificacoes_ativo,
     web_password, web_password_salt, web_password_version,
     password_changed_at, forcar_troca_senha,
     failed_access_attempts, account_locked
   ) VALUES (
     l_email_lc, p_nome, l_username_uc,
     NVL(p_role,'USER'), NVL(p_ativo,'S'), NVL(p_email_notificacoes_ativo,'S'),
     l_hash, l_salt, '1',
     admin.f_now_brt, 'S',
     0, 'N'
   ) RETURNING id INTO p_id;

   pkg_auth.log_evento('ACCOUNT_CREATED', p_id, l_username_uc, l_email_lc,
     NVL(TO_NUMBER(v('G_USER_ID') DEFAULT NULL ON CONVERSION ERROR), NULL),
     JSON_OBJECT('role' VALUE NVL(p_role,'USER'),'ativo' VALUE NVL(p_ativo,'S') RETURNING JSON));

   BEGIN
     l_ph := JSON_OBJECT('USUARIO_NOME' VALUE NVL(p_nome,l_email_lc),'USERNAME' VALUE l_username_uc,'SENHA_PROVISORIA' VALUE p_senha_provisoria,'LINK' VALUE NVL(admin.f_app_pref('app_base_url'),'') || c_link_path RETURNING JSON);
     l_ph_clob := JSON_SERIALIZE(l_ph RETURNING CLOB);
     admin.pkg_fin_notif.enviar_email_async(p_id, 'EMAIL_BOAS_VINDAS', l_ph_clob);
   EXCEPTION WHEN OTHERS THEN apex_debug.warn('pkg_cfg_usuarios: pkg_fin_notif.enviar_email_async falhou: %s', SQLERRM); END;
 EXCEPTION
   WHEN DUP_VAL_ON_INDEX THEN
     raise_application_error(-20021, unistr('J\00E1 existe um usu\00E1rio com este email ou login. Tente outros valores.'));
 END inserir;

 PROCEDURE atualizar(
   p_id IN NUMBER, p_email IN VARCHAR2, p_nome IN VARCHAR2, p_username IN VARCHAR2,
   p_role IN VARCHAR2, p_email_notificacoes_ativo IN VARCHAR2,
   p_ativo IN VARCHAR2 DEFAULT NULL
 ) IS
   l_atual cfg_usuarios_autorizados%ROWTYPE;
   l_block VARCHAR2(500);
   l_uname VARCHAR2(255):=UPPER(TRIM(p_username));
   l_email_lc VARCHAR2(255):=LOWER(TRIM(p_email));
   l_ativo_novo VARCHAR2(4);
   l_dup_msg VARCHAR2(500);
   l_solicitante NUMBER := NVL(TO_NUMBER(v('G_USER_ID') DEFAULT NULL ON CONVERSION ERROR), NULL);
 BEGIN
   l_atual := obter(p_id);
   l_ativo_novo := NVL(p_ativo,l_atual.ativo);

   IF l_ativo_novo='N' AND l_atual.ativo='S' THEN
     l_block := pode_inativar(p_id, NVL(l_solicitante,0));
     IF l_block IS NOT NULL THEN raise_application_error(-20012,l_block); END IF;
   END IF;

   l_dup_msg := valida_unicidade(p_email => l_email_lc, p_username => l_uname, p_id_atual => p_id);
   IF l_dup_msg IS NOT NULL THEN raise_application_error(-20020, l_dup_msg); END IF;

   UPDATE cfg_usuarios_autorizados
      SET email=l_email_lc,nome=p_nome,username=l_uname,role=p_role,
          email_notificacoes_ativo=NVL(p_email_notificacoes_ativo,email_notificacoes_ativo),
          ativo=COALESCE(p_ativo,ativo)
    WHERE id=p_id;

   IF l_ativo_novo='N' AND l_atual.ativo='S' THEN
     pkg_auth.log_evento('ACCOUNT_DEACTIVATE', p_id, l_uname, l_email_lc, l_solicitante);
-- Revoga por l_atual, nao pelo id: o mesmo Salvar pode ter trocado username/e-mail e o
-- token do "Manter conectado" foi emitido sob a identidade antiga.
     COMMIT;
     pkg_auth.revogar_acesso(p_id, l_atual.username, l_atual.email, 'usuario inativado');
   ELSIF l_ativo_novo='S' AND l_atual.ativo='N' THEN
     pkg_auth.log_evento('ACCOUNT_ACTIVATE', p_id, l_uname, l_email_lc, l_solicitante);
   ELSE
     pkg_auth.log_evento('ACCOUNT_UPDATED', p_id, l_uname, l_email_lc, l_solicitante);
   END IF;
 EXCEPTION
   WHEN DUP_VAL_ON_INDEX THEN
     raise_application_error(-20021, unistr('J\00E1 existe um usu\00E1rio com este email ou login. Tente outros valores.'));
 END atualizar;

 FUNCTION obter(p_id IN NUMBER) RETURN cfg_usuarios_autorizados%ROWTYPE IS
   l_row cfg_usuarios_autorizados%ROWTYPE;
 BEGIN
   SELECT * INTO l_row FROM cfg_usuarios_autorizados WHERE id=p_id; RETURN l_row;
 EXCEPTION WHEN NO_DATA_FOUND THEN raise_application_error(-20003,unistr('Usu\00E1rio n\00E3o encontrado (id=')||p_id||').');
 END obter;

 FUNCTION pode_inativar(p_id IN NUMBER, p_solicitante_id IN NUMBER) RETURN VARCHAR2 IS
   l_row cfg_usuarios_autorizados%ROWTYPE;
 BEGIN
   BEGIN SELECT * INTO l_row FROM cfg_usuarios_autorizados WHERE id=p_id;
   EXCEPTION WHEN NO_DATA_FOUND THEN RETURN unistr('Usu\00E1rio n\00E3o encontrado.'); END;
   IF l_row.ativo='N' THEN RETURN unistr('Usu\00E1rio j\00E1 est\00E1 inativo.'); END IF;
   IF p_id=NVL(p_solicitante_id,-1) THEN RETURN unistr('Voc\00EA n\00E3o pode inativar a si mesmo.'); END IF;
   IF l_row.role='ADMIN' AND outros_admins_ativos(p_id)=0 THEN RETURN unistr('N\00E3o \00E9 poss\00EDvel inativar o \00FAltimo admin ativo.'); END IF;
   RETURN NULL;
 END pode_inativar;

 PROCEDURE excluir(p_id IN NUMBER, p_solicitante_id IN NUMBER) IS
   l_block VARCHAR2(500); l_row cfg_usuarios_autorizados%ROWTYPE;
 BEGIN
   l_block := pode_inativar(p_id,p_solicitante_id);
   IF l_block IS NOT NULL THEN raise_application_error(-20013,l_block); END IF;
   l_row := obter(p_id);
   UPDATE cfg_usuarios_autorizados SET ativo='N' WHERE id=p_id;
   pkg_auth.log_evento('ACCOUNT_DEACTIVATE', p_id, l_row.username, l_row.email, p_solicitante_id,
     JSON_OBJECT('via' VALUE 'pkg_cfg_usuarios.excluir' RETURNING JSON));
   COMMIT;
   pkg_auth.revogar_acesso(p_id, 'usuario excluido');
 END excluir;

 PROCEDURE ativar(p_id IN NUMBER, p_solicitante_id IN NUMBER) IS
   l_row cfg_usuarios_autorizados%ROWTYPE;
 BEGIN
   l_row := obter(p_id);
   IF l_row.ativo='S' THEN raise_application_error(-20015, unistr('Usu\00E1rio j\00E1 est\00E1 ativo.')); END IF;

   UPDATE cfg_usuarios_autorizados
      SET ativo = 'S',
          account_locked = 'N',
          locked_at = NULL,
          failed_access_attempts = 0
    WHERE id = p_id;

   pkg_auth.log_evento('ACCOUNT_ACTIVATE', p_id, l_row.username, l_row.email, p_solicitante_id,
     JSON_OBJECT('via' VALUE 'pkg_cfg_usuarios.ativar' RETURNING JSON));
 END ativar;

 PROCEDURE resetar_senha(p_id IN NUMBER, p_solicitante_id IN NUMBER, p_senha_provisoria OUT VARCHAR2) IS
   l_row cfg_usuarios_autorizados%ROWTYPE;
   l_ph JSON; l_ph_clob CLOB;
   l_hash VARCHAR2(255); l_salt VARCHAR2(64);
 BEGIN
   l_row := obter(p_id);
   IF l_row.ativo<>'S' THEN raise_application_error(-20014,unistr('N\00E3o \00E9 poss\00EDvel resetar senha de usu\00E1rio inativo.')); END IF;
-- Resetar a propria senha derrubaria a sessao do admin antes de ele ler a provisoria,
-- que so aparece uma vez na tela.
   IF p_id = NVL(p_solicitante_id,-1) THEN
     raise_application_error(-20016, unistr('Para trocar a pr\00F3pria senha, use a tela Trocar senha.'));
   END IF;

   p_senha_provisoria := gerar_senha_provisoria;
   pkg_auth.gerar_hash(p_senha_provisoria, l_hash, l_salt);

   UPDATE cfg_usuarios_autorizados
      SET web_password = l_hash,
          web_password_salt = l_salt,
          web_password_version = '1',
          password_changed_at = admin.f_now_brt,
          forcar_troca_senha = 'S',
          failed_access_attempts = 0,
          account_locked = 'N',
          locked_at = NULL
    WHERE id = p_id;

   pkg_auth.log_evento('PASSWORD_RESET', p_id, l_row.username, l_row.email, p_solicitante_id);

   BEGIN
     l_ph := JSON_OBJECT('USUARIO_NOME' VALUE NVL(l_row.nome,l_row.email),'SENHA_PROVISORIA' VALUE p_senha_provisoria,'LINK' VALUE NVL(admin.f_app_pref('app_base_url'),'') || c_link_path RETURNING JSON);
     l_ph_clob := JSON_SERIALIZE(l_ph RETURNING CLOB);
     admin.pkg_fin_notif.enviar_email_async(p_id, 'EMAIL_RESET_SENHA', l_ph_clob);
   EXCEPTION WHEN OTHERS THEN apex_debug.warn('pkg_cfg_usuarios: pkg_fin_notif.enviar_email_async falhou: %s', SQLERRM); END;

   -- reset de senha invalida a credencial: o cookie tem que cair junto. Por ultimo e depois
   -- de COMMIT, porque a revogacao encerra as sessoes do usuario.
   COMMIT;
   pkg_auth.revogar_acesso(p_id, 'senha resetada pelo administrador');
 END resetar_senha;

END pkg_cfg_usuarios;
/
