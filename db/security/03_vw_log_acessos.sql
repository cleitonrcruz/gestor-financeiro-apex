-- So os eventos de acesso. Criacao de conta e troca de senha ficam na VW_LOG_AUDIT.
-- TO_CHAR no UNISTR: NVARCHAR2 junto de VARCHAR2 num CASE da ORA-12704.
CREATE OR REPLACE VIEW vw_log_acessos AS
SELECT e.id,
       e.ts,
       e.evento,
       CASE e.evento
         WHEN 'LOGIN_SUCCESS'           THEN 'Entrada'
         WHEN 'LOGIN_PERSISTENTE'       THEN 'Entrada por cookie'
         WHEN 'LOGIN_FAIL_PASSWORD'     THEN 'Senha incorreta'
         WHEN 'LOGIN_FAIL_NOT_FOUND'    THEN TO_CHAR(UNISTR('Usu\00E1rio inexistente'))
         WHEN 'LOGIN_FAIL_LOCKED'       THEN 'Tentativa em conta bloqueada'
         WHEN 'LOGIN_FAIL_INACTIVE'     THEN 'Tentativa em conta inativa'
         WHEN 'LOGIN_FAIL_EXPIRED'      THEN 'Tentativa com senha vencida'
         WHEN 'LOGOUT'                  THEN TO_CHAR(UNISTR('Sa\00EDda'))
         WHEN 'ACCOUNT_LOCK'            THEN 'Bloqueio de conta'
         WHEN 'ACCOUNT_UNLOCK'          THEN 'Desbloqueio de conta'
         WHEN 'ACCOUNT_ACTIVATE'        THEN 'Conta ativada'
         WHEN 'ACCOUNT_DEACTIVATE'      THEN 'Conta desativada'
         WHEN 'PASSWORD_EXPIRED'        THEN 'Senha expirada'
         WHEN 'PERSISTENT_AUTH_REVOKED' THEN 'Acesso salvo revogado'
         ELSE e.evento
       END AS evento_label,
       CASE
         WHEN e.evento IN ('LOGIN_SUCCESS','LOGIN_PERSISTENTE') THEN 'ENTRADA'
         WHEN e.evento LIKE 'LOGIN_FAIL%'                       THEN 'FALHA'
         ELSE 'OUTRO'
       END AS classe,
       e.usuario_id,
       e.username,
       e.email,
       e.origem_ip,
       e.origem_user_agent,
       -- Rotulo fixo em vez do user agent cru, que vem de fora.
       CASE
         WHEN e.origem_user_agent LIKE 'WKSP%'
           OR e.origem_user_agent LIKE 'SQLcl%'           THEN '-'
         WHEN e.origem_user_agent LIKE '%iPhone%'         THEN 'iPhone'
         WHEN e.origem_user_agent LIKE '%iPad%'           THEN 'iPad'
         WHEN e.origem_user_agent LIKE '%Android%'        THEN 'Android'
         WHEN e.origem_user_agent LIKE '%Macintosh%'      THEN 'Mac'
         WHEN e.origem_user_agent LIKE '%Windows%'        THEN 'Windows'
         WHEN e.origem_user_agent LIKE '%Linux%'          THEN 'Linux'
         ELSE 'Outro'
       END ||
       CASE
         WHEN e.origem_user_agent LIKE 'WKSP%'
           OR e.origem_user_agent LIKE 'SQLcl%'           THEN ''
         WHEN e.origem_user_agent LIKE '%Edg/%'           THEN ' - Edge'
         WHEN e.origem_user_agent LIKE '%Chrome/%'        THEN ' - Chrome'
         WHEN e.origem_user_agent LIKE '%Firefox/%'       THEN ' - Firefox'
         WHEN e.origem_user_agent LIKE '%Safari/%'        THEN ' - Safari'
         ELSE ''
       END AS dispositivo,
       e.origem_session,
       e.realizado_por_username,
       e.detalhes
  FROM log_auth_eventos e
 WHERE e.evento IN ('LOGIN_SUCCESS','LOGIN_PERSISTENTE',
                    'LOGIN_FAIL_PASSWORD','LOGIN_FAIL_NOT_FOUND','LOGIN_FAIL_LOCKED',
                    'LOGIN_FAIL_INACTIVE','LOGIN_FAIL_EXPIRED','LOGOUT',
                    'ACCOUNT_LOCK','ACCOUNT_UNLOCK','ACCOUNT_ACTIVATE','ACCOUNT_DEACTIVATE',
                    'PASSWORD_EXPIRED','PERSISTENT_AUTH_REVOKED');

-- Objeto novo em ADMIN nasce sem grant: sem isto a pagina quebra no render.
grant select on vw_log_acessos to WKSP_GESTORFINANCEIRO;
grant select on vw_log_acessos to CLEITON;
