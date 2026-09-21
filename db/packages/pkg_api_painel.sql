set define off

CREATE OR REPLACE PACKAGE pkg_api_painel AUTHID CURRENT_USER AS
  -- Blocos da pagina API REST. Roda com os privilegios de quem chama: as views
  -- USER_ORDS_* mostram o ORDS do schema da aplicacao, e o ADMIN nao tem grant nas DBA_ORDS_*.
  FUNCTION acesso RETURN CLOB;
  FUNCTION conferencia RETURN CLOB;
  -- Contrato para o Swagger da pagina, sem passar pela API: senao cada visita entraria no registro.
  PROCEDURE escrever_contrato;
END pkg_api_painel;
/

CREATE OR REPLACE PACKAGE BODY pkg_api_painel AS

  FUNCTION linha(p_rotulo VARCHAR2, p_valor VARCHAR2, p_copiar BOOLEAN DEFAULT FALSE) RETURN VARCHAR2 IS
  BEGIN
    RETURN '<div class="d-api-linha"><span class="d-api-rotulo">' || p_rotulo || '</span>'
        || '<code class="d-api-valor">' || apex_escape.html(p_valor) || '</code>'
        || CASE WHEN p_copiar THEN
             '<button type="button" class="t-Button t-Button--noLabel t-Button--icon t-Button--noUI t-Button--small js-copiar"'
             || ' data-copiar="' || apex_escape.html_attribute(p_valor) || '" title="Copiar" aria-label="Copiar">'
             || '<span class="t-Icon fa fa-copy" aria-hidden="true"></span></button>'
           END
        || '</div>';
  END linha;

  FUNCTION acesso RETURN CLOB IS
    l_base    VARCHAR2(400);
    l_versao  VARCHAR2(20);
    l_repo    VARCHAR2(400);
    l_id      VARCHAR2(200);
    l_segredo VARCHAR2(200);
  BEGIN
    SELECT JSON_VALUE(conteudo, '$.servers[0].url'),
           JSON_VALUE(conteudo, '$.info.version'),
           JSON_VALUE(conteudo, '$.info.contact.url')
      INTO l_base, l_versao, l_repo
      FROM admin.cfg_api_contrato
     WHERE versao = 'v1';

    BEGIN
      SELECT client_id, client_secret INTO l_id, l_segredo
        FROM user_ords_clients
       WHERE name = 'gf-demo';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN NULL;
    END;

    -- data-* alimenta o Authorize do Swagger UI
    RETURN '<div id="api-acesso" class="d-api-acesso"'
        || ' data-contrato="' || apex_escape.html_attribute(l_base || '/openapi.json') || '"'
        || ' data-client-id="' || apex_escape.html_attribute(l_id) || '"'
        || ' data-client-secret="' || apex_escape.html_attribute(l_segredo) || '">'
        || linha('URL base', l_base, TRUE)
        || linha(UNISTR('Vers\00E3o'), l_versao)
        || linha('Leitura', 'aberta')
        || linha('Escrita', 'OAuth2, client credentials')
        || CASE WHEN l_id IS NOT NULL THEN
             linha('Client id', l_id, TRUE) || linha('Client secret', l_segredo, TRUE)
           END
        || '<div class="d-api-links">'
        || '<a href="' || apex_escape.html_attribute(l_base || '/openapi.json') || '" target="_blank" rel="noopener">Contrato OpenAPI</a>'
        || '<a href="' || apex_escape.html_attribute(l_repo) || '" target="_blank" rel="noopener">'
        || UNISTR('Reposit\00F3rio') || '</a>'
        || '</div></div>';
  END acesso;

  FUNCTION conferencia RETURN CLOB IS
    TYPE t_rotas IS TABLE OF VARCHAR2(10) INDEX BY VARCHAR2(200);
    l_contrato t_rotas;
    l_ords     t_rotas;
    l_paths    json_object_t;
    l_metodos  json_object_t;
    l_chaves   json_key_list;
    l_mets     json_key_list;
    l_chave    VARCHAR2(200);
    l_doc      CLOB;
    l_html     CLOB;
    l_diverge  NUMBER := 0;
  BEGIN
    -- JSON_OBJECT_T e tipo PL/SQL: dentro de SELECT da ORA-40573 em execucao
    SELECT conteudo INTO l_doc FROM admin.cfg_api_contrato WHERE versao = 'v1';
    l_paths := json_object_t(l_doc).get_object('paths');

    l_chaves := l_paths.get_keys;
    FOR i IN 1 .. l_chaves.COUNT LOOP
      l_metodos := l_paths.get_object(l_chaves(i));
      l_mets := l_metodos.get_keys;
      FOR j IN 1 .. l_mets.COUNT LOOP
        l_contrato(UPPER(l_mets(j)) || ' ' || l_chaves(i)) := 'S';
      END LOOP;
    END LOOP;

    -- no ORDS o parametro de rota e :id; no contrato, {id}
    FOR r IN (SELECT h.method || ' /' || REGEXP_REPLACE(t.uri_template, ':(\w+)', '{\1}') AS rota
                FROM user_ords_modules m
                JOIN user_ords_templates t ON t.module_id = m.id
                JOIN user_ords_handlers h ON h.template_id = t.id
               WHERE m.name = 'gf-v1') LOOP
      l_ords(r.rota) := 'S';
    END LOOP;

    l_html := '<table class="d-api-conf"><thead><tr><th>Rota</th><th>Contrato</th><th>ORDS</th></tr></thead><tbody>';

    l_chave := l_contrato.FIRST;
    WHILE l_chave IS NOT NULL LOOP
      IF NOT l_ords.EXISTS(l_chave) THEN
        l_diverge := l_diverge + 1;
      END IF;
      l_html := l_html || '<tr><td><code>' || apex_escape.html(l_chave) || '</code></td><td>sim</td>'
             || CASE WHEN l_ords.EXISTS(l_chave) THEN '<td>sim</td>' ELSE '<td class="d-api-falta">n' || UNISTR('\00E3') || 'o</td>' END
             || '</tr>';
      l_chave := l_contrato.NEXT(l_chave);
    END LOOP;

    l_chave := l_ords.FIRST;
    WHILE l_chave IS NOT NULL LOOP
      IF NOT l_contrato.EXISTS(l_chave) THEN
        l_diverge := l_diverge + 1;
        l_html := l_html || '<tr><td><code>' || apex_escape.html(l_chave) || '</code></td>'
               || '<td class="d-api-falta">n' || UNISTR('\00E3') || 'o</td><td>sim</td></tr>';
      END IF;
      l_chave := l_ords.NEXT(l_chave);
    END LOOP;

    -- so avisa quando diverge; a tabela ja mostra o que bate
    RETURN CASE WHEN l_diverge > 0
                THEN '<p class="d-api-resumo">' || l_diverge || ' rota(s) em um lado s' || UNISTR('\00F3') || '.</p>'
           END
        || l_html || '</tbody></table>';
  END conferencia;

  PROCEDURE escrever_contrato IS
    l_doc CLOB;
    l_off NUMBER := 1;
  BEGIN
    SELECT conteudo INTO l_doc FROM admin.cfg_api_contrato WHERE versao = 'v1';
    WHILE l_off <= DBMS_LOB.GETLENGTH(l_doc) LOOP
      htp.prn(DBMS_LOB.SUBSTR(l_doc, 4000, l_off));
      l_off := l_off + 4000;
    END LOOP;
  END escrever_contrato;

END pkg_api_painel;
/

grant execute on pkg_api_painel to WKSP_GESTORFINANCEIRO;
grant execute on pkg_api_painel to CLEITON;

show errors package body pkg_api_painel

select object_name, object_type, status from all_objects
 where owner = 'ADMIN' and object_name = 'PKG_API_PAINEL' order by object_type;
