-- Row Level Security: cada usuario so enxerga as proprias linhas.
-- O predicado sai de PKG_RLS e vem do item de aplicacao G_USER_ID.
-- update_check impede gravar linha que o proprio predicado nao deixaria ler.
-- O modulo de open banking (Pluggy) ficou fora deste recorte; as politicas dele tambem.
-- FIN_CONCILIACAO_OFX e FIN_OFX_TRANSACOES aparecem no DDL porque FIN_LANCAMENTOS tem FK
-- para elas, mas a conciliacao por OFX esta desativada e as tabelas estao vazias; por isso
-- nao ha politica aqui. Se o modulo voltar, a transacao precisa de predicado via conciliacao.

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
