-- Sem IP e sem user agent: uso da API nao precisa de dado pessoal.
create table admin.log_api_chamadas (
  id          number generated always as identity primary key,
  ts          timestamp(6) not null,
  metodo      varchar2(10 char) not null,
  rota        varchar2(60 char) not null,
  status      number(3) not null,
  codigo      varchar2(40 char),
  duracao_ms  number
);

create index admin.log_apic_ts_ix on admin.log_api_chamadas (ts);
