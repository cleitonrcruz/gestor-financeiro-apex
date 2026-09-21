set define off

-- Papel e privilegio da escrita. Criados antes do modulo para o POST nao ficar publicado
-- sem protecao.
-- O privilegio do ORDS vale por padrao de URI ou modulo, nao por metodo: a escrita fica
-- em /v1/ingest/ para o GET continuar aberto.

grant execute on admin.pkg_api_v1 to WKSP_GESTORFINANCEIRO;

declare
  l_roles    owa.vc_arr;
  l_patterns owa.vc_arr;
begin
  ords_admin.create_role(p_schema => 'WKSP_GESTORFINANCEIRO', p_role_name => 'gf-escritor');

  l_roles(1)    := 'gf-escritor';
  l_patterns(1) := '/v1/ingest/*';

  ords_admin.define_privilege(
    p_schema         => 'WKSP_GESTORFINANCEIRO',
    p_privilege_name => 'gf.escrita',
    p_roles          => l_roles,
    p_patterns       => l_patterns,
    p_label          => 'Escrita na conta de demonstracao',
    p_description    => 'Criacao de lancamento na conta demo pela API v1');
  commit;
end;
/

select p.name, pm.pattern, pr.role_name
  from dba_ords_privileges p
  left join dba_ords_privilege_mappings pm on pm.privilege_id = p.id
  left join dba_ords_privilege_roles pr on pr.privilege_id = p.id
 where p.name = 'gf.escrita';
