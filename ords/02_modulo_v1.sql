set define off

-- Modulo, templates e handlers da API v1. Rodar depois do 01_privilegio.sql.
-- Os handlers so chamam ADMIN.PKG_API_V1, a regra fica no pacote.

begin
  ords_admin.define_module(
    p_schema         => 'WKSP_GESTORFINANCEIRO',
    p_module_name    => 'gf-v1',
    p_base_path      => 'v1/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'API publica sobre a conta de demonstracao');

  ords_admin.define_template(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'lancamentos', p_comments => 'Colecao paginada por keyset');

  ords_admin.define_handler(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'lancamentos', p_method => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source => q'~
declare
  l_json clob;
begin
  l_json := admin.pkg_api_v1.lancamentos(:cursor, :limit);
  admin.pkg_api_v1.responder(l_json, :status_code);
end;~');

  ords_admin.define_template(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'lancamentos/:id', p_comments => 'Lancamento unico');

  ords_admin.define_handler(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'lancamentos/:id', p_method => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source => q'~
declare
  l_json clob;
begin
  l_json := admin.pkg_api_v1.lancamento(:id);
  admin.pkg_api_v1.responder(l_json, :status_code);
end;~');

  ords_admin.define_template(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'categorias', p_comments => 'Categorias validas para o POST');

  ords_admin.define_handler(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'categorias', p_method => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source => q'~
declare
  l_json clob;
begin
  l_json := admin.pkg_api_v1.categorias;
  admin.pkg_api_v1.responder(l_json, :status_code);
end;~');

  ords_admin.define_template(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'resumo', p_comments => 'Indicadores do periodo');

  ords_admin.define_handler(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'resumo', p_method => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source => q'~
declare
  l_json clob;
begin
  l_json := admin.pkg_api_v1.resumo(:de, :ate);
  admin.pkg_api_v1.responder(l_json, :status_code);
end;~');

  ords_admin.define_template(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'ingest/lancamentos', p_comments => 'Escrita autenticada');

  ords_admin.define_handler(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'ingest/lancamentos', p_method => 'POST',
    p_source_type => ords.source_type_plsql,
    p_mimes_allowed => 'application/json',
    p_source => q'~
declare
  l_json clob;
  l_st   number;
  l_loc  varchar2(400);
  l_rep  varchar2(10);
begin
  admin.pkg_api_v1.criar_lancamento(:body_text, :idem_key, l_st, l_loc, l_rep, l_json);
  :status_code := l_st;
  admin.pkg_api_v1.responder_criacao(l_json, l_st, l_loc, l_rep);
end;~');

  ords_admin.define_parameter(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'ingest/lancamentos', p_method => 'POST',
    p_name => 'Idempotency-Key', p_bind_variable_name => 'idem_key',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN',
    p_comments => 'Chave de idempotencia');
  commit;
end;
/

select s.parsing_schema, s.pattern as alias, m.name, t.uri_template, h.method
  from dba_ords_schemas s
  join dba_ords_modules m on m.schema_id = s.id
  join dba_ords_templates t on t.module_id = m.id
  join dba_ords_handlers h on h.template_id = t.id
 where m.name = 'gf-v1'
 order by s.parsing_schema, t.uri_template;
