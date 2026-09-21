set define off

CREATE OR REPLACE PACKAGE pkg_api_v1 AS
  -- API REST da conta de demonstracao: leitura aberta, escrita por OAuth2.
  -- Roda com os privilegios de ADMIN (EXEMPT ACCESS POLICY), entao a RLS nao filtra aqui.
  -- O dono e fixo em toda consulta e nenhuma rotina recebe id de usuario.

  c_fonte    CONSTANT VARCHAR2(30) := 'API_V1';
  c_teto_dia CONSTANT NUMBER       := 100;

  FUNCTION lancamentos(p_cursor IN VARCHAR2 DEFAULT NULL,
                       p_limit  IN VARCHAR2 DEFAULT NULL) RETURN CLOB;
  FUNCTION lancamento (p_id IN VARCHAR2) RETURN CLOB;
  FUNCTION categorias RETURN CLOB;
  FUNCTION resumo(p_de  IN VARCHAR2 DEFAULT NULL,
                  p_ate IN VARCHAR2 DEFAULT NULL) RETURN CLOB;
  FUNCTION contrato RETURN CLOB;

  PROCEDURE criar_lancamento(p_body     IN  CLOB,
                             p_idem_key IN  VARCHAR2,
                             p_status   OUT NUMBER,
                             p_location OUT VARCHAR2,
                             p_replay   OUT VARCHAR2,
                             p_json     OUT CLOB);

  -- Status HTTP da ultima leitura, lido pelo handler logo apos a chamada.
  FUNCTION ultimo_status RETURN NUMBER;

  -- Escreve cabecalho e corpo da resposta.
  PROCEDURE responder(p_json IN CLOB, p_status OUT NUMBER);
  PROCEDURE responder_criacao(p_json     IN CLOB,
                              p_status   IN NUMBER,
                              p_location IN VARCHAR2,
                              p_replay   IN VARCHAR2);
END pkg_api_v1;
/

CREATE OR REPLACE PACKAGE BODY pkg_api_v1 AS

  g_status NUMBER := 200;
  -- Chamada em curso, para o registro em LOG_API_CHAMADAS.
  g_metodo VARCHAR2(10);
  g_rota   VARCHAR2(60);
  g_codigo VARCHAR2(40);
  g_inicio TIMESTAMP WITH TIME ZONE;

  -- Usar so via variavel: funcao privada do corpo nao pode ir dentro de SQL (PLS-00231).
  FUNCTION demo_user_id RETURN NUMBER IS
    l_id NUMBER;
  BEGIN
    SELECT id INTO l_id
      FROM cfg_usuarios_autorizados
     WHERE UPPER(username) = 'DEMO';
    RETURN l_id;
  END demo_user_id;

  FUNCTION erro(p_status IN NUMBER, p_code IN VARCHAR2,
                p_title  IN VARCHAR2, p_detail IN VARCHAR2) RETURN CLOB IS
    l_json CLOB;
  BEGIN
    g_status := p_status;
    g_codigo := p_code;
    SELECT JSON_OBJECT('type'   VALUE 'https://github.com/cleitonrcruz/gestor-financeiro-apex#erros',
                       'title'  VALUE p_title,
                       'status' VALUE p_status,
                       'detail' VALUE p_detail,
                       'code'   VALUE p_code
                       RETURNING CLOB)
      INTO l_json FROM dual;
    RETURN l_json;
  END erro;

  -- A resposta nao expoe o ORA; o registro guarda, para diagnostico.
  FUNCTION falha(p_sqlcode IN NUMBER) RETURN CLOB IS
    l_json CLOB;
  BEGIN
    l_json   := erro(500, 'ERRO_INTERNO', 'Erro interno', 'Nao foi possivel montar a resposta.');
    g_codigo := 'ERRO_INTERNO ORA-' || LPAD(ABS(p_sqlcode), 5, '0');
    RETURN l_json;
  END falha;

  FUNCTION ultimo_status RETURN NUMBER IS
  BEGIN
    RETURN g_status;
  END ultimo_status;

  PROCEDURE marcar(p_metodo IN VARCHAR2, p_rota IN VARCHAR2) IS
  BEGIN
    g_status := 200;
    g_codigo := NULL;
    g_metodo := p_metodo;
    g_rota   := p_rota;
    g_inicio := SYSTIMESTAMP;
  END marcar;

  PROCEDURE registrar(p_status IN NUMBER) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    l_int INTERVAL DAY(2) TO SECOND(6) := SYSTIMESTAMP - g_inicio;
    l_ms  NUMBER;
  BEGIN
    l_ms := ROUND((EXTRACT(DAY FROM l_int) * 86400 + EXTRACT(HOUR FROM l_int) * 3600
                 + EXTRACT(MINUTE FROM l_int) * 60 + EXTRACT(SECOND FROM l_int)) * 1000);
    INSERT INTO log_api_chamadas (ts, metodo, rota, status, codigo, duracao_ms)
    VALUES (f_now_brt, g_metodo, g_rota, p_status, g_codigo, l_ms);
    COMMIT;
  EXCEPTION
    -- o registro nao pode derrubar a resposta, que ja foi escrita
    WHEN OTHERS THEN
      ROLLBACK;
  END registrar;

  -- Cursor no formato AAAAMMDD-id: data de competencia e id do ultimo item da pagina.
  PROCEDURE decodificar_cursor(p_cursor IN VARCHAR2, p_data OUT DATE, p_id OUT NUMBER) IS
  BEGIN
    p_data := NULL;
    p_id   := NULL;
    IF p_cursor IS NULL THEN
      RETURN;
    END IF;
    IF NOT REGEXP_LIKE(p_cursor, '^[0-9]{8}-[0-9]+$') THEN
      RAISE_APPLICATION_ERROR(-20400, 'cursor invalido');
    END IF;
    p_data := TO_DATE(SUBSTR(p_cursor, 1, 8) DEFAULT NULL ON CONVERSION ERROR, 'YYYYMMDD');
    p_id   := TO_NUMBER(SUBSTR(p_cursor, 10) DEFAULT NULL ON CONVERSION ERROR);
    IF p_data IS NULL OR p_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20400, 'cursor invalido');
    END IF;
  END decodificar_cursor;

  FUNCTION lancamentos(p_cursor IN VARCHAR2 DEFAULT NULL,
                       p_limit  IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    l_demo NUMBER;
    l_lim  NUMBER := LEAST(GREATEST(NVL(TRUNC(TO_NUMBER(p_limit DEFAULT NULL ON CONVERSION ERROR)), 25), 1), 100);
    l_lim1 NUMBER;
    l_data DATE;
    l_id   NUMBER;
    l_json CLOB;
  BEGIN
    marcar('GET', '/v1/lancamentos');
    l_demo := demo_user_id;
    decodificar_cursor(p_cursor, l_data, l_id);
    -- uma linha a mais so para saber se existe proxima pagina
    l_lim1 := l_lim + 1;

    WITH pag AS (
      SELECT l.id, l.tipo, l.descricao, l.valor, l.data_competencia, l.data_caixa,
             l.forma_pagamento, c.nome AS categoria, o.nome AS origem
        FROM fin_lancamentos l
        JOIN cfg_categorias c ON c.id = l.categoria_id
        LEFT JOIN cfg_origens o ON o.id = l.origem_id
       WHERE l.user_id = l_demo
         AND l.ativo = 'S'
         AND (l_data IS NULL
              OR l.data_competencia < l_data
              OR (l.data_competencia = l_data AND l.id < l_id))
       ORDER BY l.data_competencia DESC, l.id DESC
       FETCH FIRST l_lim1 ROWS ONLY
    ), num AS (
      SELECT p.*, ROW_NUMBER() OVER (ORDER BY data_competencia DESC, id DESC) AS rn
        FROM pag p
    )
    SELECT JSON_OBJECT(
             'items' VALUE NVL((SELECT JSON_ARRAYAGG(
                                         JSON_OBJECT('id'               VALUE id,
                                                     'tipo'             VALUE tipo,
                                                     'descricao'        VALUE descricao,
                                                     'valor'            VALUE valor,
                                                     'categoria'        VALUE categoria,
                                                     'origem'           VALUE origem,
                                                     'forma_pagamento'  VALUE forma_pagamento,
                                                     'data_competencia' VALUE TO_CHAR(data_competencia, 'YYYY-MM-DD'),
                                                     'data_caixa'       VALUE TO_CHAR(data_caixa, 'YYYY-MM-DD'),
                                                     'realizado'        VALUE CASE WHEN data_caixa IS NULL THEN 'false' ELSE 'true' END FORMAT JSON
                                                     NULL ON NULL RETURNING CLOB)
                                         ORDER BY data_competencia DESC, id DESC
                                         RETURNING CLOB)
                                  FROM num WHERE rn <= l_lim),
                               JSON_ARRAY(RETURNING CLOB)) FORMAT JSON,
             'count' VALUE (SELECT COUNT(*) FROM num WHERE rn <= l_lim),
             'next'  VALUE (SELECT CASE WHEN (SELECT MAX(rn) FROM num) > l_lim
                                        THEN TO_CHAR(n.data_competencia, 'YYYYMMDD') || '-' || n.id
                                   END
                              FROM num n WHERE n.rn = l_lim)
             NULL ON NULL RETURNING CLOB)
      INTO l_json
      FROM dual;

    RETURN l_json;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20400 THEN
        RETURN erro(400, 'CURSOR_INVALIDO', 'Cursor invalido',
                    'O parametro cursor deve vir no formato AAAAMMDD-id, como devolvido no campo next.');
      END IF;
      RETURN falha(SQLCODE);
  END lancamentos;

  -- Separado de lancamento para a criacao montar a resposta sem trocar a rota registrada.
  FUNCTION lancamento_json(p_id IN NUMBER) RETURN CLOB IS
    l_demo NUMBER := demo_user_id;
    l_json CLOB;
  BEGIN
    SELECT JSON_OBJECT('id'               VALUE l.id,
                       'tipo'             VALUE l.tipo,
                       'descricao'        VALUE l.descricao,
                       'valor'            VALUE l.valor,
                       'categoria'        VALUE c.nome,
                       'origem'           VALUE o.nome,
                       'forma_pagamento'  VALUE l.forma_pagamento,
                       'observacoes'      VALUE l.observacoes,
                       'data_competencia' VALUE TO_CHAR(l.data_competencia, 'YYYY-MM-DD'),
                       'data_caixa'       VALUE TO_CHAR(l.data_caixa, 'YYYY-MM-DD'),
                       'realizado'        VALUE CASE WHEN l.data_caixa IS NULL THEN 'false' ELSE 'true' END FORMAT JSON
                       NULL ON NULL RETURNING CLOB)
      INTO l_json
      FROM fin_lancamentos l
      JOIN cfg_categorias c ON c.id = l.categoria_id
      LEFT JOIN cfg_origens o ON o.id = l.origem_id
     WHERE l.id = p_id
       AND l.user_id = l_demo
       AND l.ativo = 'S';

    RETURN l_json;
  END lancamento_json;

  FUNCTION lancamento(p_id IN VARCHAR2) RETURN CLOB IS
    l_id NUMBER;
  BEGIN
    marcar('GET', '/v1/lancamentos/{id}');
    l_id := TO_NUMBER(p_id DEFAULT NULL ON CONVERSION ERROR);
    IF l_id IS NULL THEN
      RETURN erro(400, 'ID_INVALIDO', 'Identificador invalido', 'O id do lancamento deve ser numerico.');
    END IF;
    RETURN lancamento_json(l_id);
  EXCEPTION
    -- Lancamento de outra conta tambem cai aqui: 404 nao revela se ele existe.
    WHEN NO_DATA_FOUND THEN
      RETURN erro(404, 'NAO_ENCONTRADO', 'Lancamento nao encontrado',
                  'Nao existe lancamento ' || l_id || ' na conta de demonstracao.');
    WHEN OTHERS THEN
      RETURN falha(SQLCODE);
  END lancamento;

  FUNCTION categorias RETURN CLOB IS
    l_demo NUMBER;
    l_json CLOB;
  BEGIN
    marcar('GET', '/v1/categorias');
    l_demo := demo_user_id;
    -- user_id nulo e categoria global, vale para qualquer conta
    SELECT JSON_OBJECT(
             'items' VALUE NVL(JSON_ARRAYAGG(
                                 JSON_OBJECT('id'   VALUE id,
                                             'nome' VALUE nome,
                                             'tipo' VALUE tipo
                                             RETURNING CLOB)
                                 ORDER BY tipo, nome
                                 RETURNING CLOB),
                               JSON_ARRAY(RETURNING CLOB)) FORMAT JSON,
             'count' VALUE COUNT(*)
             NULL ON NULL RETURNING CLOB)
      INTO l_json
      FROM cfg_categorias
     WHERE ativo = 'S'
       AND (user_id = l_demo OR user_id IS NULL);

    RETURN l_json;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN falha(SQLCODE);
  END categorias;

  FUNCTION resumo(p_de  IN VARCHAR2 DEFAULT NULL,
                  p_ate IN VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    l_demo NUMBER;
    l_hoje DATE   := f_now_brt;
    l_de   DATE;
    l_ate  DATE;
    l_json CLOB;
  BEGIN
    marcar('GET', '/v1/resumo');
    l_demo := demo_user_id;
    l_de  := TRUNC(l_hoje, 'MM');
    l_ate := LAST_DAY(TRUNC(l_hoje, 'MM'));

    IF p_de IS NOT NULL THEN
      l_de := TO_DATE(p_de DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD');
      IF l_de IS NULL THEN
        RETURN erro(422, 'DATA_INVALIDA', 'Data invalida', 'O parametro de deve vir como AAAA-MM-DD.');
      END IF;
    END IF;
    IF p_ate IS NOT NULL THEN
      l_ate := TO_DATE(p_ate DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD');
      IF l_ate IS NULL THEN
        RETURN erro(422, 'DATA_INVALIDA', 'Data invalida', 'O parametro ate deve vir como AAAA-MM-DD.');
      END IF;
    END IF;
    -- o filtro soma um dia ao fim do periodo
    IF l_ate > DATE '9998-12-31' THEN
      RETURN erro(422, 'DATA_INVALIDA', 'Data invalida', 'O parametro ate esta fora da faixa aceita.');
    END IF;
    IF l_ate < l_de THEN
      RETURN erro(422, 'PERIODO_INVALIDO', 'Periodo invalido', 'A data final e anterior a inicial.');
    END IF;

    -- < ate + 1 e nao BETWEEN: a coluna e DATE e o ultimo dia ficaria de fora.
    SELECT JSON_OBJECT(
             'periodo'  VALUE JSON_OBJECT('de'  VALUE TO_CHAR(l_de,  'YYYY-MM-DD'),
                                          'ate' VALUE TO_CHAR(l_ate, 'YYYY-MM-DD')),
             'receitas' VALUE NVL(SUM(CASE WHEN tipo = 'R' THEN valor END), 0),
             'despesas' VALUE JSON_OBJECT(
                                'pf' VALUE NVL(SUM(CASE WHEN tipo = 'DPF' THEN valor END), 0),
                                'pj' VALUE NVL(SUM(CASE WHEN tipo = 'DPJ' THEN valor END), 0)),
             'saldo'    VALUE NVL(SUM(CASE WHEN tipo = 'R' THEN valor ELSE -valor END), 0),
             'realizado' VALUE JSON_OBJECT(
                                'receitas' VALUE NVL(SUM(CASE WHEN tipo = 'R'  AND data_caixa IS NOT NULL THEN valor END), 0),
                                'despesas' VALUE NVL(SUM(CASE WHEN tipo <> 'R' AND data_caixa IS NOT NULL THEN valor END), 0)),
             'previsto'  VALUE JSON_OBJECT(
                                'receitas' VALUE NVL(SUM(CASE WHEN tipo = 'R'  AND data_caixa IS NULL THEN valor END), 0),
                                'despesas' VALUE NVL(SUM(CASE WHEN tipo <> 'R' AND data_caixa IS NULL THEN valor END), 0)),
             'lancamentos' VALUE COUNT(*)
             NULL ON NULL RETURNING CLOB)
      INTO l_json
      FROM fin_lancamentos
     WHERE user_id = l_demo
       AND ativo = 'S'
       AND data_competencia >= l_de
       AND data_competencia <  l_ate + 1;

    RETURN l_json;
  EXCEPTION
    WHEN OTHERS THEN
      RETURN falha(SQLCODE);
  END resumo;

  FUNCTION contrato RETURN CLOB IS
    l_json CLOB;
  BEGIN
    marcar('GET', '/v1/openapi.json');
    SELECT conteudo INTO l_json FROM cfg_api_contrato WHERE versao = 'v1';
    RETURN l_json;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN erro(404, 'CONTRATO_AUSENTE', 'Contrato nao carregado', 'O contrato da v1 nao esta na base.');
    WHEN OTHERS THEN
      RETURN falha(SQLCODE);
  END contrato;

  PROCEDURE criar_lancamento(p_body     IN  CLOB,
                             p_idem_key IN  VARCHAR2,
                             p_status   OUT NUMBER,
                             p_location OUT VARCHAR2,
                             p_replay   OUT VARCHAR2,
                             p_json     OUT CLOB) IS
    l_demo    NUMBER;
    l_valido  NUMBER;
    -- lidos sem limite de tamanho: RETURNING menor devolve nulo em vez de erro e o dado some
    l_tipo    VARCHAR2(32767);
    l_desc    VARCHAR2(32767);
    l_forma   VARCHAR2(32767);
    l_caixa   VARCHAR2(32767);
    l_obs     CLOB;
    l_valor   NUMBER;
    l_dtcomp  DATE;
    l_dtcaixa DATE;
    l_cat     NUMBER;
    l_id      NUMBER;
    l_usadas  NUMBER;
    l_cat_ok  NUMBER;
  BEGIN
    marcar('POST', '/v1/ingest/lancamentos');
    l_demo     := demo_user_id;
    p_replay   := 'false';
    p_location := NULL;

    IF p_idem_key IS NULL OR LENGTH(TRIM(p_idem_key)) = 0 THEN
      p_json := erro(400, 'IDEMPOTENCY_KEY_AUSENTE', 'Cabecalho obrigatorio',
                     'Envie o cabecalho Idempotency-Key para que o reenvio do mesmo lancamento nao duplique.');
      p_status := 400;
      RETURN;
    END IF;
    -- a coluna external_id tem 100: sem este corte o reenvio estoura ORA-12899
    IF LENGTH(p_idem_key) > 100 THEN
      p_json := erro(400, 'IDEMPOTENCY_KEY_LONGA', 'Cabecalho invalido',
                     'O Idempotency-Key aceita no maximo 100 caracteres.');
      p_status := 400;
      RETURN;
    END IF;

    -- chave ja usada: devolve a linha que ficou, sem gravar de novo
    BEGIN
      SELECT id INTO l_id
        FROM fin_lancamentos
       WHERE external_source = c_fonte
         AND external_id = p_idem_key
         AND user_id = l_demo;
      p_replay   := 'true';
      p_status   := 200;
      p_location := '../lancamentos/' || l_id;
      p_json     := lancamento_json(l_id);
      RETURN;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN NULL;
    END;

    SELECT COUNT(*) INTO l_usadas
      FROM fin_lancamentos
     WHERE user_id = l_demo
       AND external_source = c_fonte
       AND created_on >= TRUNC(f_now_brt);
    IF l_usadas >= c_teto_dia THEN
      p_json := erro(429, 'COTA_DIARIA', 'Cota diaria atingida',
                     'A conta de demonstracao aceita ' || c_teto_dia ||
                     ' escritas por dia. A contagem zera na virada do dia em Brasilia.');
      p_status := 429;
      RETURN;
    END IF;

    SELECT CASE WHEN p_body IS JSON THEN 1 ELSE 0 END INTO l_valido FROM dual;
    IF p_body IS NULL OR l_valido = 0 THEN
      p_json := erro(400, 'CORPO_INVALIDO', 'Corpo invalido', 'O corpo da requisicao precisa ser um JSON valido.');
      p_status := 400;
      RETURN;
    END IF;

    l_tipo    := JSON_VALUE(p_body, '$.tipo'             RETURNING VARCHAR2(32767));
    l_desc    := JSON_VALUE(p_body, '$.descricao'        RETURNING VARCHAR2(32767));
    l_valor   := JSON_VALUE(p_body, '$.valor'            RETURNING NUMBER);
    l_cat     := JSON_VALUE(p_body, '$.categoria_id'     RETURNING NUMBER);
    l_forma   := JSON_VALUE(p_body, '$.forma_pagamento'  RETURNING VARCHAR2(32767));
    l_obs     := JSON_VALUE(p_body, '$.observacoes'      RETURNING CLOB);
    l_caixa   := JSON_VALUE(p_body, '$.data_caixa'       RETURNING VARCHAR2(32767));
    l_dtcomp  := TO_DATE(JSON_VALUE(p_body, '$.data_competencia' RETURNING VARCHAR2(10))
                         DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD');
    l_dtcaixa := TO_DATE(l_caixa DEFAULT NULL ON CONVERSION ERROR, 'YYYY-MM-DD');

    IF l_tipo IS NULL OR l_tipo NOT IN ('R', 'DPF', 'DPJ') THEN
      p_json := erro(422, 'TIPO_INVALIDO', 'Tipo invalido',
                     'O campo tipo aceita R para receita, DPF para despesa pessoa fisica e DPJ para pessoa juridica.');
      p_status := 422;
      RETURN;
    END IF;
    IF l_desc IS NULL OR LENGTH(TRIM(l_desc)) = 0 THEN
      p_json := erro(422, 'DESCRICAO_AUSENTE', 'Descricao obrigatoria', 'O campo descricao e obrigatorio.');
      p_status := 422;
      RETURN;
    END IF;
    IF LENGTH(l_desc) > 255 THEN
      p_json := erro(422, 'DESCRICAO_LONGA', 'Descricao longa', 'O campo descricao aceita no maximo 255 caracteres.');
      p_status := 422;
      RETURN;
    END IF;
    -- a coluna e NUMBER(14,2)
    IF l_valor IS NULL OR l_valor <= 0 OR l_valor >= 1e12 THEN
      p_json := erro(422, 'VALOR_INVALIDO', 'Valor invalido',
                     'O campo valor deve ser um numero maior que zero e menor que 1000000000000.');
      p_status := 422;
      RETURN;
    END IF;
    IF l_dtcomp IS NULL THEN
      p_json := erro(422, 'DATA_COMPETENCIA_INVALIDA', 'Data de competencia invalida',
                     'O campo data_competencia e obrigatorio e deve vir como AAAA-MM-DD.');
      p_status := 422;
      RETURN;
    END IF;
    IF l_caixa IS NOT NULL AND l_dtcaixa IS NULL THEN
      p_json := erro(422, 'DATA_CAIXA_INVALIDA', 'Data de caixa invalida', 'O campo data_caixa deve vir como AAAA-MM-DD.');
      p_status := 422;
      RETURN;
    END IF;
    IF DBMS_LOB.GETLENGTH(l_obs) > 2000 THEN
      p_json := erro(422, 'OBSERVACOES_LONGA', 'Observacoes longas', 'O campo observacoes aceita no maximo 2000 caracteres.');
      p_status := 422;
      RETURN;
    END IF;
    IF l_forma IS NOT NULL
       AND l_forma NOT IN ('DINHEIRO','PIX','DEBITO','CREDITO_VISTA','CREDITO_PARC','BOLETO','TED') THEN
      p_json := erro(422, 'FORMA_PAGAMENTO_INVALIDA', 'Forma de pagamento invalida',
                     'Valores aceitos: DINHEIRO, PIX, DEBITO, CREDITO_VISTA, CREDITO_PARC, BOLETO, TED.');
      p_status := 422;
      RETURN;
    END IF;

    -- a categoria precisa existir para a demo e ser do mesmo tipo do lancamento
    SELECT COUNT(*) INTO l_cat_ok
      FROM cfg_categorias
     WHERE id = l_cat
       AND ativo = 'S'
       AND tipo = l_tipo
       AND (user_id = l_demo OR user_id IS NULL);
    IF l_cat IS NULL OR l_cat_ok = 0 THEN
      p_json := erro(422, 'CATEGORIA_INVALIDA', 'Categoria invalida',
                     'A categoria informada nao existe para a conta de demonstracao ou nao e do tipo ' ||
                     l_tipo || '. Consulte /v1/categorias.');
      p_status := 422;
      RETURN;
    END IF;

    BEGIN
      pkg_fin_lancamentos.inserir(
        p_user_id          => l_demo,
        p_categoria_id     => l_cat,
        p_tipo             => l_tipo,
        p_descricao        => l_desc,
        p_valor            => l_valor,
        p_data_competencia => l_dtcomp,
        p_data_caixa       => l_dtcaixa,
        p_forma_pagamento  => l_forma,
        p_observacoes      => DBMS_LOB.SUBSTR(l_obs, 2000, 1),
        p_external_id      => p_idem_key,
        p_external_source  => c_fonte,
        p_id               => l_id);
      COMMIT;
    EXCEPTION
      -- envio simultaneo com a mesma chave: o indice barra o segundo, que devolve a linha gravada
      WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        SELECT id INTO l_id
          FROM fin_lancamentos
         WHERE external_source = c_fonte
           AND external_id = p_idem_key
           AND user_id = l_demo;
        p_replay   := 'true';
        p_status   := 200;
        p_location := '../lancamentos/' || l_id;
        p_json     := lancamento_json(l_id);
        RETURN;
    END;

    p_status   := 201;
    p_location := '../lancamentos/' || l_id;
    p_json     := lancamento_json(l_id);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      p_replay   := 'false';
      p_location := NULL;
      p_status   := 500;
      p_json     := falha(SQLCODE);
  END criar_lancamento;

  PROCEDURE escrever(p_json IN CLOB) IS
    l_off NUMBER := 1;
    l_len NUMBER := DBMS_LOB.GETLENGTH(p_json);
  BEGIN
    WHILE l_off <= l_len LOOP
      htp.prn(DBMS_LOB.SUBSTR(p_json, 4000, l_off));
      l_off := l_off + 4000;
    END LOOP;
  END escrever;

  PROCEDURE responder(p_json IN CLOB, p_status OUT NUMBER) IS
  BEGIN
    p_status := g_status;
    owa_util.mime_header(CASE WHEN g_status >= 400 THEN 'application/problem+json'
                              ELSE 'application/json' END, FALSE);
    owa_util.http_header_close;
    escrever(p_json);
    registrar(g_status);
  END responder;

  PROCEDURE responder_criacao(p_json     IN CLOB,
                              p_status   IN NUMBER,
                              p_location IN VARCHAR2,
                              p_replay   IN VARCHAR2) IS
  BEGIN
    owa_util.mime_header(CASE WHEN p_status >= 400 THEN 'application/problem+json'
                              ELSE 'application/json' END, FALSE);
    -- O ORDS resolve o Location relativo a /v1/ingest/, dai o ../lancamentos/.
    IF p_location IS NOT NULL THEN
      htp.p('Location: ' || p_location);
    END IF;
    htp.p('Idempotent-Replay: ' || p_replay);
    IF p_status = 429 THEN
      htp.p('Retry-After: 3600');
    END IF;
    owa_util.http_header_close;
    escrever(p_json);
    registrar(p_status);
  END responder_criacao;

END pkg_api_v1;
/

show errors package pkg_api_v1
show errors package body pkg_api_v1

select object_name, object_type, status
  from all_objects
 where owner = 'ADMIN'
   and object_name = 'PKG_API_V1'
 order by object_type;
