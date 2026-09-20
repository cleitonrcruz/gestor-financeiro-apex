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
END pkg_cfg_categorias;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_CFG_CATEGORIAS" AS
-- Categoria global (user_id nulo) so o admin altera ou inativa.
-- Fora do APEX nao ha sessao e a regra nao vale.
  PROCEDURE checar_global(p_id IN NUMBER) IS
    v_global NUMBER;
    v_admin  NUMBER;
  BEGIN
    IF SYS_CONTEXT('APEX$SESSION','APP_USER') IS NULL THEN RETURN; END IF;
    SELECT COUNT(*) INTO v_global FROM CFG_CATEGORIAS WHERE id = p_id AND user_id IS NULL;
    IF v_global = 0 THEN RETURN; END IF;
    SELECT COUNT(*) INTO v_admin FROM CFG_USUARIOS_AUTORIZADOS
     WHERE UPPER(username) = UPPER(SYS_CONTEXT('APEX$SESSION','APP_USER'))
       AND role = 'ADMIN' AND ativo = 'S';
    IF v_admin = 0 THEN
      raise_application_error(-20004, 'Categoria global: somente administradores podem alterar.');
    END IF;
  END checar_global;

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
    checar_global(p_id);
    UPDATE CFG_CATEGORIAS
       SET user_id = p_user_id, nome = p_nome, tipo = p_tipo,
           ativo = COALESCE(p_ativo, ativo)
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      raise_application_error(-20002, 'Categoria n?o encontrada para atualizac?o.');
    END IF;
  END atualizar;

  FUNCTION obter(p_id IN NUMBER) RETURN CFG_CATEGORIAS%ROWTYPE IS
    r CFG_CATEGORIAS%ROWTYPE;
  BEGIN
    SELECT * INTO r FROM CFG_CATEGORIAS WHERE id = p_id;
    RETURN r;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN raise_application_error(-20003, 'Categoria n?o encontrada.');
  END obter;

  FUNCTION pode_excluir(p_id IN NUMBER) RETURN VARCHAR2 IS
    v_existe NUMBER; v_ja_inat VARCHAR2(4);
  BEGIN
    SELECT COUNT(*), MAX(ativo) INTO v_existe, v_ja_inat FROM CFG_CATEGORIAS WHERE id = p_id;
    IF v_existe = 0 THEN RETURN 'Categoria n?o encontrada.'; END IF;
    IF v_ja_inat = 'N' THEN RETURN 'Categoria ja esta inativa.'; END IF;
    RETURN NULL;
  END pode_excluir;

  PROCEDURE excluir(p_id IN NUMBER) IS
    v_msg VARCHAR2(4000) := pode_excluir(p_id);
  BEGIN
    IF v_msg IS NOT NULL THEN raise_application_error(-20001, v_msg); END IF;
    checar_global(p_id);
    UPDATE CFG_CATEGORIAS SET ativo = 'N' WHERE id = p_id;
  END excluir;
END pkg_cfg_categorias;
/
