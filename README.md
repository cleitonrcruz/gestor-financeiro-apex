# Gestor Financeiro

Aplicação de gestão financeira pessoal e de pessoa jurídica construída em **Oracle APEX** sobre **Autonomous Database**, em produção e em uso diário.

**[Abrir a demonstração](https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/r/gestor_financeiro/gestor-financeiro/)**. Usuário `demo`, senha `demo`.

A conta de demonstração tem dados fictícios e é restaurada todo dia de madrugada. Fique à vontade para criar, editar e excluir.

![Dashboard](docs/img/dashboard.webp)

## O que faz

Lançamentos de receita e despesa separados por pessoa física e jurídica, com regime de competência e de caixa; dívidas parceladas com recálculo de parcelas e baixa vinculada ao lançamento; anexos por lançamento; notificações de vencimento por e-mail e push; e um dashboard com indicadores do período, fluxo de doze meses e categorias mais pesadas.

## Stack

Oracle APEX 26.1 · Oracle Autonomous Database 23ai · ORDS · PL/SQL · JavaScript · HTML · CSS · PWA

## Decisões técnicas que valem a leitura

**Controle de acesso e conteúdo.** Lançamentos, dívidas, parcelas, anexos e notificações têm política de VPD (`DBMS_RLS`), com o predicado vindo de `PKG_RLS` e `update_check` ligado, então cada usuário só enxerga as próprias linhas. O predicado é aplicado pelo banco, não pela tela, então vale também para o que chega por parâmetro de requisição e não só para o que a página consulta. O código está em [`db/security/01_rls_policies.sql`](db/security/01_rls_policies.sql) e [`db/packages/pkg_rls.sql`](db/packages/pkg_rls.sql).

**Autenticação própria.** Esquema custom com hash e salt por usuário (`PKG_AUTH`), bloqueio por tentativas, expiração de senha, troca forçada no primeiro acesso e trilha de eventos de login. Inclui o "manter conectado" do APEX com revogação de token ao desativar, trocar papel ou resetar senha de uma conta.

**Fila offline idempotente.** O app é um PWA instalável; sem rede, os lançamentos vão para uma fila em IndexedDB e sobem quando a conexão volta. A idempotência não depende do cliente: um índice único funcional sobre `external_id` garante que reenviar a mesma fila duas vezes não duplica nada. Ver [`pwa/`](pwa/) e [`db/security/02_indice_idempotencia_offline.sql`](db/security/02_indice_idempotencia_offline.sql).

**Plug-in de verdade, não JavaScript colado na página.** O tooltip da aplicação é um plug-in de Dynamic Action com render function em PL/SQL, atributos configuráveis no Page Designer e cores saindo de variáveis do Universal Theme, então sobrevive a troca de theme style. O instalável em [`apex/plugin/`](apex/plugin/) sai do export do App Builder, nunca escrito à mão.

**Regra de negócio no banco.** Nenhum CRUD em processo de página: tudo passa por package (`PKG_FIN_LANCAMENTOS`, `PKG_FIN_DIVIDAS`, `PKG_FIN_NOTIF`, `PKG_CFG_*`), o que mantém a regra fora da tela e testável por SQL.

## Organização

| Pasta | Conteúdo |
|---|---|
| `db/tables` | DDL das tabelas de negócio e de configuração |
| `db/packages` | Pacotes PL/SQL: autenticação, RLS, lançamentos, dívidas, notificações, cadastros |
| `db/security` | Políticas de VPD e o índice de idempotência da fila offline |
| `db/jobs` | Jobs do scheduler: expurgo por retenção e geração diária de notificações |
| `apex/plugin` | Plug-in de tooltip: instalável e render function |
| `pwa` | Camada offline da página, a tela offline que o APEX embute no service worker que ele mesmo gera, e os dois processos de sincronização da fila |

## Sobre este repositório

É um recorte do projeto, não a aplicação inteira. Está aqui o que se lê como código: modelo de dados, regra de negócio e os componentes que valem reuso. O export completo do APEX, os scripts de migração e os dados ficam de fora por conterem informação financeira real. Ficam de fora também quatro utilitários chamados pelos pacotes daqui: `f_app_pref`, que lê parâmetro de configuração, `f_now_brt`, que devolve a data no fuso de Brasília, `f_categoria_default_divida` e o pacote `pkg_manutencao`, de expurgo.
