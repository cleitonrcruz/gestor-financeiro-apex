DECLARE
  l_uid    NUMBER := TO_NUMBER(v('G_USER_ID') DEFAULT NULL ON CONVERSION ERROR);
  l_qtd    PLS_INTEGER;
  l_ext    VARCHAR2(100);
  l_id     NUMBER;
  l_status VARCHAR2(20);
  l_erro   VARCHAR2(500);
  l_criados    PLS_INTEGER := 0;
  l_duplicados PLS_INTEGER := 0;
  l_falhas     PLS_INTEGER := 0;
BEGIN
  IF l_uid IS NULL THEN
    apex_json.open_object;
    apex_json.write('ok', FALSE);
    apex_json.write('erro', 'sessao sem contexto de usuario');
    apex_json.close_object;
    RETURN;
  END IF;

  apex_json.parse(apex_application.g_x01);
  l_qtd := NVL(apex_json.get_count(p_path => 'itens'), 0);

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.open_array('resultados');

  FOR i IN 1 .. l_qtd LOOP
    l_ext    := apex_json.get_varchar2(p_path => 'itens[%d].external_id', p0 => i);
    l_id     := NULL;
    l_erro   := NULL;
    l_status := NULL;

    BEGIN
      -- savepoint por item: se um falhar no meio, o COMMIT do fim nao pode levar junto
      -- o DML parcial que ele deixou pendente
      SAVEPOINT sp_item;

      IF l_ext IS NULL THEN
        RAISE_APPLICATION_ERROR(-20101, 'item sem external_id');
      END IF;

      -- idempotencia: o replay de uma fila que ja subiu nao pode duplicar.
      -- O pre-check resolve o caso comum; o indice unico FIN_LAN_PWA_EXT_UK resolve a corrida.
      BEGIN
        SELECT id INTO l_id
          FROM admin.fin_lancamentos
         WHERE external_source = 'PWA_OFFLINE'
           AND external_id     = l_ext;
        l_status := 'duplicado';
      EXCEPTION WHEN NO_DATA_FOUND THEN
        admin.pkg_fin_lancamentos.inserir(
          p_user_id          => l_uid,
          p_origem_id        => apex_json.get_number(p_path => 'itens[%d].origem_id', p0 => i),
          p_categoria_id     => apex_json.get_number(p_path => 'itens[%d].categoria_id', p0 => i),
          p_tipo             => apex_json.get_varchar2(p_path => 'itens[%d].tipo', p0 => i),
          p_descricao        => apex_json.get_varchar2(p_path => 'itens[%d].descricao', p0 => i),
          p_valor            => apex_json.get_number(p_path => 'itens[%d].valor', p0 => i),
          p_data_competencia => TO_DATE(apex_json.get_varchar2(p_path => 'itens[%d].data_competencia', p0 => i), 'YYYY-MM-DD'),
          p_data_caixa       => TO_DATE(apex_json.get_varchar2(p_path => 'itens[%d].data_caixa', p0 => i), 'YYYY-MM-DD'),
          p_forma_pagamento  => apex_json.get_varchar2(p_path => 'itens[%d].forma_pagamento', p0 => i),
          p_observacoes      => apex_json.get_varchar2(p_path => 'itens[%d].observacoes', p0 => i),
          p_external_id      => l_ext,
          p_external_source  => 'PWA_OFFLINE',
          p_id               => l_id);
        l_status := 'criado';
      END;
    EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN
        -- perdeu a corrida para outra requisicao com o mesmo external_id
        ROLLBACK TO SAVEPOINT sp_item;
        l_status := 'duplicado';
        BEGIN
          SELECT id INTO l_id FROM admin.fin_lancamentos
           WHERE external_source = 'PWA_OFFLINE' AND external_id = l_ext;
        EXCEPTION WHEN OTHERS THEN l_id := NULL;
        END;
      WHEN OTHERS THEN
        ROLLBACK TO SAVEPOINT sp_item;
        l_status := 'erro';
        l_erro   := SUBSTR(SQLERRM, 1, 500);
        apex_debug.error('OFFLINE_PUSH item %s falhou: %s', l_ext, SQLERRM);
    END;

    IF    l_status = 'criado'    THEN l_criados    := l_criados + 1;
    ELSIF l_status = 'duplicado' THEN l_duplicados := l_duplicados + 1;
    ELSE                              l_falhas     := l_falhas + 1;
    END IF;

    apex_json.open_object;
    apex_json.write('external_id', l_ext);
    apex_json.write('status', l_status);
    apex_json.write('id', l_id);
    IF l_erro IS NOT NULL THEN
      apex_json.write('erro', l_erro);
    END IF;
    apex_json.close_object;
  END LOOP;

  apex_json.close_array;
  apex_json.write('criados', l_criados);
  apex_json.write('duplicados', l_duplicados);
  apex_json.write('falhas', l_falhas);
  apex_json.close_object;

  -- so commita o que deu certo; item com erro fica de fora e o cliente mantem na fila
  COMMIT;
END;
