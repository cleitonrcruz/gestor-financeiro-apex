# Gestor Financeiro

<p align="justify">Aplicação de gestão financeira pessoal e de pessoa jurídica construída em <b>Oracle APEX</b> sobre <b>Autonomous Database</b>, em produção e em uso diário.</p>

**[Abrir a demonstração](https://gd9477458323ab8-gestorfin.adb.sa-saopaulo-1.oraclecloudapps.com/ords/r/gestor_financeiro/gestor-financeiro/)**. Usuário `demo`, senha `demo`.

<p align="justify">A conta de demonstração tem dados fictícios e é restaurada todo dia de madrugada. Fique à vontade para criar, editar e excluir.</p>

![Dashboard](docs/img/dashboard.webp)

## O que faz

<p align="justify">Lançamentos de receita e despesa separados por pessoa física e jurídica, com regime de competência e de caixa; dívidas parceladas com recálculo de parcelas e baixa vinculada ao lançamento; anexos por lançamento; notificações de vencimento por e-mail e push; e um dashboard com indicadores do período, fluxo de doze meses e categorias mais pesadas.</p>

## Stack

Oracle APEX 26.1 · Oracle Autonomous Database 23ai · ORDS · PL/SQL · JavaScript · HTML · CSS · PWA

## Decisões técnicas que valem a leitura

<p align="justify"><b>Controle de acesso e conteúdo.</b> Lançamentos, dívidas, parcelas, anexos e notificações têm política de VPD (<code>DBMS_RLS</code>), com o predicado vindo de <code>PKG_RLS</code> e <code>update_check</code> ligado, então cada usuário só enxerga as próprias linhas. O predicado é aplicado pelo banco, não pela tela, então vale também para o que chega por parâmetro de requisição e não só para o que a página consulta. O código está em <a href="db/security/01_rls_policies.sql"><code>db/security/01_rls_policies.sql</code></a> e <a href="db/packages/pkg_rls.sql"><code>db/packages/pkg_rls.sql</code></a>.</p>

<p align="justify"><b>Autenticação própria.</b> Esquema custom com hash e salt por usuário (<code>PKG_AUTH</code>), bloqueio por tentativas, expiração de senha, troca forçada no primeiro acesso e trilha de eventos de login. Inclui o "manter conectado" do APEX com revogação de token ao desativar, trocar papel ou resetar senha de uma conta.</p>

<p align="justify"><b>Fila offline idempotente.</b> O app é um PWA instalável; sem rede, os lançamentos vão para uma fila em IndexedDB e sobem quando a conexão volta. A idempotência não depende do cliente: um índice único funcional sobre <code>external_id</code> garante que reenviar a mesma fila duas vezes não duplica nada. Ver <a href="pwa/"><code>pwa/</code></a> e <a href="db/security/02_indice_idempotencia_offline.sql"><code>db/security/02_indice_idempotencia_offline.sql</code></a>.</p>

<p align="justify"><b>Plug-in de verdade, não JavaScript colado na página.</b> O tooltip da aplicação é um plug-in de Dynamic Action com render function em PL/SQL, atributos configuráveis no Page Designer e cores saindo de variáveis do Universal Theme, então sobrevive a troca de theme style. O instalável em <a href="apex/plugin/"><code>apex/plugin/</code></a> sai do export do App Builder, nunca escrito à mão.</p>

<p align="justify"><b>Regra de negócio no banco.</b> Nenhum CRUD em processo de página: tudo passa por package (<code>PKG_FIN_LANCAMENTOS</code>, <code>PKG_FIN_DIVIDAS</code>, <code>PKG_FIN_NOTIF</code>, <code>PKG_CFG_*</code>), o que mantém a regra fora da tela e testável por SQL.</p>

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

<p align="justify">É um recorte do projeto, não a aplicação inteira. Está aqui o que se lê como código: modelo de dados, regra de negócio e os componentes que valem reuso. O export completo do APEX, os scripts de migração e os dados ficam de fora por conterem informação financeira real. Ficam de fora também quatro utilitários chamados pelos pacotes daqui: <code>f_app_pref</code>, que lê parâmetro de configuração, <code>f_now_brt</code>, que devolve a data no fuso de Brasília, <code>f_categoria_default_divida</code> e o pacote <code>pkg_manutencao</code>, de expurgo.</p>
