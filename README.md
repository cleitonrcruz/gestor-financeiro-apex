# Gestor Financeiro

![Oracle APEX](https://img.shields.io/badge/Oracle%20APEX-26.1.4-F80000)
![Oracle AI Database](https://img.shields.io/badge/Oracle%20AI%20Database-26ai-F80000)
![OCI](https://img.shields.io/badge/OCI-Autonomous%20Database-312D2A)
![PL/SQL](https://img.shields.io/badge/PL%2FSQL-1f4e79)
![PWA](https://img.shields.io/badge/PWA-instal%C3%A1vel-5A0FC8)
![MIT](https://img.shields.io/badge/license-MIT-green)

<p align="justify">Aplicação de gestão financeira pessoal e de pessoa jurídica construída em <b>Oracle APEX</b> sobre <b>Autonomous Database</b>, em produção e em uso diário.</p>

**[Abrir a demonstração](https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/r/gestor_financeiro/gestor-financeiro/)**. Usuário `demo`, senha `demo`.

<p align="justify">A conta de demonstração tem dados fictícios e é restaurada todo dia de madrugada. Fique à vontade para criar, editar e excluir.</p>

![Dashboard](docs/img/dashboard.webp)

## O que faz

<p align="justify">Lançamentos de receita e despesa separados por pessoa física e jurídica, com regime de competência e de caixa; dívidas parceladas com recálculo de parcelas e baixa vinculada ao lançamento; anexos por lançamento; notificações de vencimento por e-mail e push; um dashboard com indicadores do período, fluxo de doze meses e categorias mais pesadas; uma tela de acessos que mostra quem entrou, de onde, com que aparelho, e as tentativas que falharam; e uma página com a documentação e o uso da API REST.</p>

## Stack

| Camada | Tecnologia |
|---|---|
| Banco | Oracle AI Database 26ai Autonomous, versão 23.26.3.3.0, região sa-saopaulo-1 |
| Aplicação | Oracle APEX 26.1.4, modo de compatibilidade 24.2 |
| REST | ORDS, com contrato OpenAPI 3.0 e Swagger UI |
| Front-end | Universal Theme 42, JavaScript, HTML e CSS |
| Offline | PWA instalável, com fila em IndexedDB |
| Notificações | Web Push nativo do APEX e e-mail por template |

## Decisões técnicas

- Segurança por linha com VPD (`DBMS_RLS`) em toda tabela com dado de usuário. O predicado fica em [`PKG_RLS`](db/packages/pkg_rls.sql) e as políticas em [`01_rls_policies.sql`](db/security/01_rls_policies.sql).
- Autenticação própria em `PKG_AUTH`: hash com salt, bloqueio por tentativas, expiração de senha e "manter conectado" com revogação.
- IP e navegador de cada acesso lidos de `X-Forwarded-For` e `User-Agent`, porque atrás do balanceador da OCI o `sys_context` devolve sempre o mesmo endereço.
- PWA com fila offline em IndexedDB. Um índice único em `external_id` impede que o reenvio duplique lançamentos ([`pwa/`](pwa/)).
- Tooltip feito como plug-in de Dynamic Action, com cores do Universal Theme ([`apex/plugin/`](apex/plugin/)). A versão portátil, que instala em qualquer aplicação a partir do APEX 24.2, virou repositório próprio: [oracle-apex-tooltip](https://github.com/cleitonrcruz/oracle-apex-tooltip).
- Regra de negócio toda em package. Nenhum processo de página faz CRUD.

## API REST

<p align="justify">A conta de demonstração também pode ser consultada por uma API REST publicada no ORDS. A leitura não exige autenticação:</p>

```bash
curl -H "Accept: application/json" https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/gestor_financeiro/v1/resumo
```

```json
{"periodo":{"de":"2026-09-01","ate":"2026-09-30"},
 "receitas":13450,"despesas":{"pf":7626.35,"pj":1033},"saldo":4790.65,
 "realizado":{"receitas":13450,"despesas":7934.35},
 "previsto":{"receitas":0,"despesas":725},"lancamentos":16}
```

<p align="justify">No <code>/resumo</code>, <b>realizado</b> são os lançamentos com data de caixa e <b>previsto</b> os que ainda não têm.</p>

| Método | Caminho | Autenticação |
|---|---|---|
| GET | `/v1/lancamentos` | aberta |
| GET | `/v1/lancamentos/{id}` | aberta |
| GET | `/v1/categorias` | aberta |
| GET | `/v1/resumo` | aberta |
| POST | `/v1/ingest/lancamentos` | OAuth2 |
| GET | `/v1/openapi.json` | aberta |

<p align="justify">O contrato OpenAPI 3.0 é servido pela própria API em <a href="https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/gestor_financeiro/v1/openapi.json"><code>/v1/openapi.json</code></a>, e o arquivo fica em <a href="ords/openapi_v1.json"><code>ords/openapi_v1.json</code></a>. Ele é escrito à mão: o documento que o ORDS gera sozinho repete a mesma descrição genérica em todas as rotas e não traz as respostas de erro. Na aplicação, a página API REST mostra o contrato no Swagger UI, junto com os indicadores de uso.</p>

### Escrita

<p align="justify">A escrita exige OAuth2 com <i>client credentials</i>. O cliente abaixo é público: só tem acesso ao endpoint de escrita, grava apenas na conta de demonstração, aceita até 100 lançamentos por dia, e os dados são restaurados toda madrugada.</p>

```bash
TOKEN=$(curl -s -X POST https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/gestor_financeiro/oauth/token \
  -H "Accept: application/json" \
  --user "ph6pTsyiEUfRUJTi8pxkyw..:JALdTI0-6OPlnnkLyiCslQ.." \
  -d grant_type=client_credentials | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

CHAVE=$(uuidgen)

curl -i -X POST https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/gestor_financeiro/v1/ingest/lancamentos \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $CHAVE" \
  -d '{"tipo":"DPF","descricao":"Assinatura de streaming","valor":39.9,
       "data_competencia":"2026-09-20","categoria_id":9}'
```

<p align="justify">Executando o último comando duas vezes no mesmo terminal, a primeira chamada responde <code>201</code> e a segunda <code>200</code> com <code>Idempotent-Replay: true</code>, devolvendo o lançamento já gravado mesmo que o corpo enviado seja outro. A unicidade é garantida por um índice único funcional sobre <code>external_id</code>, restrito às linhas gravadas pela API, no mesmo modelo do índice usado pela fila offline do PWA.</p>

### Implementação

- Os handlers não têm SQL: chamam [`PKG_API_V1`](db/packages/pkg_api_v1.sql), que tem a conta demo fixa e não recebe id de usuário. Lançamento de outra conta dá `404`.
- O filtro da conta está escrito em cada consulta, porque fora do APEX a política de linha não se aplica.
- A escrita fica em `/v1/ingest/` porque o privilégio do ORDS é por caminho.
- Paginação por keyset: `next` traz a posição do último item.
- ETag padrão do ORDS, com `304` quando o `If-None-Match` confere.
- Cada chamada fica em `LOG_API_CHAMADAS` (método, rota, status, código e duração, sem IP) e alimenta a página da API. O `401` sem token não entra, porque o ORDS responde antes do pacote.

### Erros

<p align="justify">Os erros gerados pela API saem em <code>application/problem+json</code>, com um código estável no campo <code>code</code> e sem expor <code>ORA-</code>. Os gerados pelo ORDS antes do handler, como o <code>401</code> sem token, dependem do cabeçalho <code>Accept</code>: sem pedir JSON, clientes como o Postman recebem a página de erro em HTML. Por isso os exemplos enviam <code>Accept: application/json</code>.</p>

| Código | Status | Quando |
|---|---|---|
| `CURSOR_INVALIDO` | 400 | `cursor` fora do formato AAAAMMDD-id |
| `ID_INVALIDO` | 400 | id não numérico |
| `IDEMPOTENCY_KEY_AUSENTE` | 400 | POST sem `Idempotency-Key` |
| `IDEMPOTENCY_KEY_LONGA` | 400 | `Idempotency-Key` acima de 100 caracteres |
| `CORPO_INVALIDO` | 400 | corpo que não é JSON |
| `NAO_ENCONTRADO` | 404 | lançamento inexistente ou de outra conta |
| `DATA_INVALIDA` | 422 | data fora do formato AAAA-MM-DD ou da faixa aceita |
| `PERIODO_INVALIDO` | 422 | data final anterior à inicial |
| `TIPO_INVALIDO` | 422 | `tipo` diferente de R, DPF ou DPJ |
| `DESCRICAO_AUSENTE` | 422 | `descricao` vazia |
| `DESCRICAO_LONGA` | 422 | `descricao` acima de 255 caracteres |
| `VALOR_INVALIDO` | 422 | `valor` ausente, zero, negativo ou a partir de 1 trilhão |
| `DATA_COMPETENCIA_INVALIDA` | 422 | `data_competencia` ausente ou fora do formato |
| `DATA_CAIXA_INVALIDA` | 422 | `data_caixa` fora do formato |
| `OBSERVACOES_LONGA` | 422 | `observacoes` acima de 2000 caracteres |
| `FORMA_PAGAMENTO_INVALIDA` | 422 | `forma_pagamento` fora da lista aceita |
| `CATEGORIA_INVALIDA` | 422 | categoria inexistente para a demo ou de outro tipo |
| `COTA_DIARIA` | 429 | 100 escritas no dia |
| `ERRO_INTERNO` | 500 | falha inesperada |

## Organização

| Pasta | Conteúdo |
|---|---|
| `db/tables` | DDL das tabelas de negócio e de configuração |
| `db/packages` | Pacotes PL/SQL: autenticação, RLS, lançamentos, dívidas, notificações, cadastros e expurgo |
| `db/functions` | Utilitários chamados pelos pacotes: preferência, data no fuso de Brasília, indicadores de acesso |
| `db/security` | Políticas de VPD, o índice de idempotência da fila offline e a view de acessos |
| `db/jobs` | Jobs do scheduler: expurgo por retenção e geração diária de notificações |
| `apex/plugin` | Plug-in de tooltip: instalável e render function |
| `ords` | Contrato OpenAPI, módulo, templates, handlers, privilégio e cliente OAuth2 da API |
| `pwa` | Camada offline da página, a tela offline que o APEX embute no service worker que ele mesmo gera, e os dois processos de sincronização da fila |

## Sobre este repositório

<p align="justify">É um recorte do projeto, não a aplicação inteira. Está aqui o que se lê como código: modelo de dados, regra de negócio e os componentes que valem reuso. O export completo do APEX, os scripts de migração e os dados ficam de fora por conterem informação financeira real.</p>

## Autor

Cleiton Cruz, desenvolvedor Oracle APEX e PL/SQL.
[linkedin.com/in/cleitonrcruz](https://www.linkedin.com/in/cleitonrcruz/)
