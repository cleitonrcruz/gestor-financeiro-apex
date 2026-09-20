DECLARE
  l_uid NUMBER := TO_NUMBER(v('G_USER_ID') DEFAULT NULL ON CONVERSION ERROR);
BEGIN
  -- Roda como Application Process On-Demand, dentro da sessao APEX: G_USER_ID esta populado
  -- e o RLS de FIN_LANCAMENTOS continua valendo. Handler ORDS nao teria nenhum dos dois.
  IF l_uid IS NULL THEN
    apex_json.open_object;
    apex_json.write('ok', FALSE);
    apex_json.write('erro', 'sessao sem contexto de usuario');
    apex_json.close_object;
    RETURN;
  END IF;

  apex_json.open_object;
  apex_json.write('ok', TRUE);
  apex_json.write('gerado_em', TO_CHAR(SYS_EXTRACT_UTC(SYSTIMESTAMP), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
  apex_json.write('user_id', l_uid);

  apex_json.open_array('categorias');
  FOR r IN (SELECT id, nome, tipo
              FROM admin.cfg_categorias
             WHERE ativo = 'S'
               AND (user_id = l_uid OR user_id IS NULL)
             ORDER BY tipo, nome) LOOP
    apex_json.open_object;
    apex_json.write('id', r.id);
    apex_json.write('nome', r.nome);
    apex_json.write('tipo', r.tipo);
    apex_json.close_object;
  END LOOP;
  apex_json.close_array;

  apex_json.open_array('origens');
  FOR r IN (SELECT id, nome, tipo, categoria_default_id
              FROM admin.cfg_origens
             WHERE ativo = 'S'
               AND user_id = l_uid
             ORDER BY nome) LOOP
    apex_json.open_object;
    apex_json.write('id', r.id);
    apex_json.write('nome', r.nome);
    apex_json.write('tipo', r.tipo);
    apex_json.write('categoria_default_id', r.categoria_default_id);
    apex_json.close_object;
  END LOOP;
  apex_json.close_array;

  -- leitura minima: o suficiente para a tela offline mostrar contexto, nao o app inteiro
  apex_json.open_array('lancamentos');
  FOR r IN (SELECT id, tipo, descricao, valor, categoria_id, origem_id,
                   TO_CHAR(data_competencia, 'YYYY-MM-DD') data_competencia,
                   TO_CHAR(data_caixa, 'YYYY-MM-DD') data_caixa
              FROM admin.fin_lancamentos
             WHERE ativo = 'S'
               AND data_competencia BETWEEN ADD_MONTHS(TRUNC(SYSDATE), -1)
                                        AND ADD_MONTHS(TRUNC(SYSDATE),  1)
             ORDER BY data_competencia DESC, id DESC
             FETCH FIRST 200 ROWS ONLY) LOOP
    apex_json.open_object;
    apex_json.write('id', r.id);
    apex_json.write('tipo', r.tipo);
    apex_json.write('descricao', r.descricao);
    apex_json.write('valor', r.valor);
    apex_json.write('categoria_id', r.categoria_id);
    apex_json.write('origem_id', r.origem_id);
    apex_json.write('data_competencia', r.data_competencia);
    apex_json.write('data_caixa', r.data_caixa);
    apex_json.close_object;
  END LOOP;
  apex_json.close_array;

  apex_json.close_object;
END;
