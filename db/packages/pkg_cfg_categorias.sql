CREATE OR REPLACE PACKAGE         "PKG_CFG_CATEGORIAS" AS
  PROCEDURE inserir(
    p_user_id IN  NUMBER,
    p_nome    IN  VARCHAR2,
    p_tipo    IN  VARCHAR2,
    p_ativo   IN  VARCHAR2 DEFAULT 'S',
    p_id      OUT NUMBER
  );

  PROCEDURE atualizar(
    p_id      IN  NUMBER,
    p_user_id IN  NUMBER,
    p_nome    IN  VARCHAR2,
    p_tipo    IN  VARCHAR2,
    p_ativo   IN  VARCHAR2
  );

  FUNCTION  obter        (p_id IN NUMBER) RETURN CFG_CATEGORIAS%ROWTYPE;
  FUNCTION  pode_excluir (p_id IN NUMBER) RETURN VARCHAR2;
  PROCEDURE excluir      (p_id IN NUMBER);

  -- Copia a lista padrao para o usuario, sem repetir nome e tipo que ele ja tem.
  PROCEDURE copiar_padrao       (p_user_id IN NUMBER);
  PROCEDURE copiar_padrao_async (p_user_id IN NUMBER);

  -- Categoria do usuario com esse nome e tipo; reativa ou cria quando nao houver.
  FUNCTION  obter_ou_criar(p_user_id IN NUMBER, p_nome IN VARCHAR2, p_tipo IN VARCHAR2) RETURN NUMBER;
END pkg_cfg_categorias;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_CFG_CATEGORIAS" AS
-- Cada categoria e de um usuario so. Nas telas do APEX a politica de RLS filtra e barra gravacao
-- de categoria de outro usuario; no SQLcl e nos jobs a conta ADMIN e isenta dela.

  PROCEDURE inserir(p_user_id IN NUMBER, p_nome IN VARCHAR2, p_tipo IN VARCHAR2,
                    p_ativo IN VARCHAR2 DEFAULT 'S', p_id OUT NUMBER) IS
  BEGIN
    INSERT INTO CFG_CATEGORIAS (user_id, nome, tipo, ativo)
    VALUES (p_user_id, p_nome, p_tipo, NVL(p_ativo,'S'))
    RETURNING id INTO p_id;
  END inserir;

  PROCEDURE atualizar(p_id IN NUMBER, p_user_id IN NUMBER, p_nome IN VARCHAR2,
                      p_tipo IN VARCHAR2, p_ativo IN VARCHAR2) IS
  BEGIN
    UPDATE CFG_CATEGORIAS
       SET user_id = p_user_id, nome = p_nome, tipo = p_tipo,
           ativo = COALESCE(p_ativo, ativo)
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      raise_application_error(-20002, UNISTR('Categoria n\00E3o encontrada para atualiza\00E7\00E3o.'));
    END IF;
  END atualizar;

  FUNCTION obter(p_id IN NUMBER) RETURN CFG_CATEGORIAS%ROWTYPE IS
    r CFG_CATEGORIAS%ROWTYPE;
  BEGIN
    SELECT * INTO r FROM CFG_CATEGORIAS WHERE id = p_id;
    RETURN r;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN raise_application_error(-20003, UNISTR('Categoria n\00E3o encontrada.'));
  END obter;

  FUNCTION pode_excluir(p_id IN NUMBER) RETURN VARCHAR2 IS
    v_existe NUMBER; v_ja_inat VARCHAR2(4);
  BEGIN
    SELECT COUNT(*), MAX(ativo) INTO v_existe, v_ja_inat FROM CFG_CATEGORIAS WHERE id = p_id;
    IF v_existe = 0 THEN RETURN UNISTR('Categoria n\00E3o encontrada.'); END IF;
    IF v_ja_inat = 'N' THEN RETURN UNISTR('Categoria j\00E1 est\00E1 inativa.'); END IF;
    RETURN NULL;
  END pode_excluir;

  PROCEDURE excluir(p_id IN NUMBER) IS
    v_msg VARCHAR2(4000) := pode_excluir(p_id);
  BEGIN
    IF v_msg IS NOT NULL THEN raise_application_error(-20001, v_msg); END IF;
    UPDATE CFG_CATEGORIAS SET ativo = 'N' WHERE id = p_id;
  END excluir;

  PROCEDURE copiar_padrao(p_user_id IN NUMBER) IS
  BEGIN
    INSERT INTO CFG_CATEGORIAS (user_id, nome, tipo, ativo)
    SELECT p_user_id, p.nome, p.tipo, 'S'
      FROM CFG_CATEGORIAS_PADRAO p
     WHERE NOT EXISTS (SELECT 1
                         FROM CFG_CATEGORIAS c
                        WHERE c.user_id = p_user_id
                          AND c.nome    = p.nome
                          AND c.tipo    = p.tipo)
     ORDER BY p.id;
  END copiar_padrao;

  -- O cadastro de usuario roda na sessao APEX do admin, onde o RLS barraria gravar categoria de
  -- outro usuario. O job roda sem sessao APEX, como ADMIN, e a politica nao filtra.
  PROCEDURE copiar_padrao_async(p_user_id IN NUMBER) IS
  BEGIN
    dbms_scheduler.create_job(
      job_name   => 'CAT_PADRAO_' || TO_CHAR(p_user_id) || '_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF3'),
      job_type   => 'PLSQL_BLOCK',
      job_action => 'BEGIN admin.pkg_cfg_categorias.copiar_padrao(' || TO_CHAR(p_user_id) || '); COMMIT; END;',
      start_date => SYSTIMESTAMP,
      enabled    => TRUE,
      auto_drop  => TRUE
    );
  END copiar_padrao_async;

  FUNCTION obter_ou_criar(p_user_id IN NUMBER, p_nome IN VARCHAR2, p_tipo IN VARCHAR2) RETURN NUMBER IS
    l_id    NUMBER;
    l_ativo VARCHAR2(4);
  BEGIN
    BEGIN
      SELECT id, ativo INTO l_id, l_ativo
        FROM (SELECT id, ativo
                FROM CFG_CATEGORIAS
               WHERE user_id = p_user_id
                 AND nome    = p_nome
                 AND tipo    = p_tipo
               ORDER BY DECODE(ativo, 'S', 0, 1), id)
       WHERE ROWNUM = 1;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN l_id := NULL;
    END;

    IF l_id IS NULL THEN
      inserir(p_user_id, p_nome, p_tipo, 'S', l_id);
    ELSIF l_ativo = 'N' THEN
      UPDATE CFG_CATEGORIAS SET ativo = 'S' WHERE id = l_id;
    END IF;
    RETURN l_id;
  END obter_ou_criar;
END pkg_cfg_categorias;
/
