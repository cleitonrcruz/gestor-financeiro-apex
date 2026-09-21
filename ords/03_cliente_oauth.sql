set define off

-- Rodar conectado como o schema de parsing (no APEX, SQL Workshop > SQL Commands): o
-- cliente OAuth pertence ao schema que publica o modulo.
-- Cliente publico de demonstracao, so alcanca /v1/ingest/*. Para revogar:
--   begin oauth.delete_client('gf-demo'); commit; end;

begin
  oauth.create_client(
    p_name            => 'gf-demo',
    p_grant_type      => 'client_credentials',
    p_owner           => 'Gestor Financeiro',
    p_description     => 'Cliente publico de demonstracao da API v1',
    p_support_email   => 'demo@gestorfinanceiro.app',
    p_support_uri     => 'https://github.com/cleitonrcruz/gestor-financeiro-apex',
    p_privilege_names => 'gf.escrita');

  oauth.grant_client_role('gf-demo', 'gf-escritor');
  commit;
end;
/

select name, client_id, client_secret
  from user_ords_clients
 where name = 'gf-demo';
