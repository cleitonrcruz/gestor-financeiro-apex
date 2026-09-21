set define off

-- Unicidade da Idempotency-Key do POST. O FIN_LAN_PWA_EXT_UK so cobre as linhas de
-- origem PWA_OFFLINE, entao as da API precisam de indice proprio.
create unique index admin.fin_lan_api_ext_uk
    on admin.fin_lancamentos (case when external_source = 'API_V1' then external_id end);

select index_name, uniqueness, index_type, status
  from all_indexes
 where table_owner = 'ADMIN'
   and table_name = 'FIN_LANCAMENTOS'
   and index_name in ('FIN_LAN_PWA_EXT_UK','FIN_LAN_API_EXT_UK')
 order by index_name;
