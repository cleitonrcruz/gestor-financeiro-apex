create table admin.cfg_api_contrato (
  id          number generated always as identity primary key,
  versao      varchar2(10 char) not null,
  conteudo    clob not null,
  created_by  varchar2(255 char),
  created_on  timestamp(6),
  updated_by  varchar2(255 char),
  updated_on  timestamp(6),
  constraint cfg_apic_versao_uk unique (versao),
  constraint cfg_apic_conteudo_ck check (conteudo is json)
);

create or replace trigger admin.trg_cfg_api_contrato_biu
  before insert or update on admin.cfg_api_contrato
  for each row
begin
  if inserting then
    :new.created_on := admin.f_now_brt;
    :new.created_by := nvl(sys_context('APEX$SESSION','APP_USER'), user);
  end if;
  :new.updated_on := admin.f_now_brt;
  :new.updated_by := nvl(sys_context('APEX$SESSION','APP_USER'), user);
end;
/
