set define off

begin
  ords_admin.define_template(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'openapi.json', p_comments => 'Contrato OpenAPI da v1');

  ords_admin.define_handler(
    p_schema => 'WKSP_GESTORFINANCEIRO', p_module_name => 'gf-v1',
    p_pattern => 'openapi.json', p_method => 'GET',
    p_source_type => ords.source_type_plsql,
    p_source => q'~
declare
  l_json clob;
begin
  l_json := admin.pkg_api_v1.contrato;
  admin.pkg_api_v1.responder(l_json, :status_code);
end;~');
  commit;
end;
/
