-- Row Level Security: cada usuario so enxerga as proprias linhas.
-- O predicado sai de PKG_RLS e vem do item de aplicacao G_USER_ID.
-- update_check impede gravar linha que o proprio predicado nao deixaria ler.
-- O modulo de open banking (Pluggy) ficou fora deste recorte; as politicas dele tambem.

begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_DIVIDAS',
    policy_name     => 'P_FIN_DIVIDAS_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OWNED',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/
begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_DIVIDAS_PARCELAS',
    policy_name     => 'P_FIN_DIVP_VIA_DIV',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_VIA_DIVIDA',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/
begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_LANCAMENTOS',
    policy_name     => 'P_FIN_LANCAMENTOS_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OWNED',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/
begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_LANCAMENTOS_ANEXOS',
    policy_name     => 'P_FIN_LANC_ANEXOS_VIA_LANC',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_VIA_LANCAMENTO',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/
begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_NOTIFICACOES',
    policy_name     => 'P_FIN_NOTIF_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OWNED',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/

-- Categorias e origens misturam linha global (user_id nulo) com linha de usuario, e alimentam
-- LOV dinamica, que le a tabela pelo schema da aplicacao. Predicado de dono puro esvaziaria
-- o combo, dai o f_rls_user_or_global.
begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'CFG_CATEGORIAS',
    policy_name     => 'P_CFG_CATEGORIAS_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OR_GLOBAL',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/

begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'CFG_ORIGENS',
    policy_name     => 'P_CFG_ORIGENS_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OR_GLOBAL',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/

begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_EMAIL_LOG',
    policy_name     => 'P_FIN_EMAIL_LOG_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OWNED',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/

begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_CONCILIACAO_OFX',
    policy_name     => 'P_FIN_CONCILIACAO_USER',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_USER_OWNED',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/

-- Sem USER_ID proprio: o dono vem pela conciliacao.
begin
  dbms_rls.add_policy(
    object_schema   => 'ADMIN',
    object_name     => 'FIN_OFX_TRANSACOES',
    policy_name     => 'P_FIN_OFX_TRANS_VIA_CONC',
    function_schema => 'ADMIN',
    policy_function => 'PKG_RLS.F_RLS_VIA_CONCILIACAO',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE);
end;
/
