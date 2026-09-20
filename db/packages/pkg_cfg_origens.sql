CREATE OR REPLACE PACKAGE         "PKG_CFG_ORIGENS" AS
  PROCEDURE inserir(
    p_user_id              IN  NUMBER,
    p_categoria_default_id IN  NUMBER  DEFAULT NULL,
    p_nome                 IN  VARCHAR2,
    p_tipo                 IN  VARCHAR2,
    p_doc                  IN  VARCHAR2 DEFAULT NULL,
    p_ativo                IN  VARCHAR2 DEFAULT 'S',
    p_id                   OUT NUMBER
  );

  PROCEDURE atualizar(
    p_id                   IN  NUMBER,
    p_user_id              IN  NUMBER,
    p_categoria_default_id IN  NUMBER,
    p_nome                 IN  VARCHAR2,
    p_tipo                 IN  VARCHAR2,
    p_doc                  IN  VARCHAR2,
    p_ativo                IN  VARCHAR2
  );

  FUNCTION  obter        (p_id IN NUMBER) RETURN CFG_ORIGENS%ROWTYPE;
  FUNCTION  pode_excluir (p_id IN NUMBER) RETURN VARCHAR2;
  PROCEDURE excluir      (p_id IN NUMBER);
END pkg_cfg_origens;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_CFG_ORIGENS" AS
  PROCEDURE inserir(p_user_id IN NUMBER, p_categoria_default_id IN NUMBER DEFAULT NULL,
                    p_nome IN VARCHAR2, p_tipo IN VARCHAR2, p_doc IN VARCHAR2 DEFAULT NULL,
                    p_ativo IN VARCHAR2 DEFAULT 'S', p_id OUT NUMBER) IS
  BEGIN
    INSERT INTO CFG_ORIGENS (user_id, categoria_default_id, nome, tipo, doc, ativo)
    VALUES (p_user_id, p_categoria_default_id, p_nome, p_tipo, p_doc, NVL(p_ativo,'S'))
    RETURNING id INTO p_id;
  END inserir;

  PROCEDURE atualizar(p_id IN NUMBER, p_user_id IN NUMBER, p_categoria_default_id IN NUMBER,
                      p_nome IN VARCHAR2, p_tipo IN VARCHAR2, p_doc IN VARCHAR2,
                      p_ativo IN VARCHAR2) IS
  BEGIN
    UPDATE CFG_ORIGENS
       SET user_id = p_user_id, categoria_default_id = p_categoria_default_id,
           nome = p_nome, tipo = p_tipo, doc = p_doc,
           ativo = COALESCE(p_ativo, ativo)
     WHERE id = p_id;
    IF SQL%ROWCOUNT = 0 THEN
      raise_application_error(-20002, 'Origem n?o encontrada para atualizac?o.');
    END IF;
  END atualizar;

  FUNCTION obter(p_id IN NUMBER) RETURN CFG_ORIGENS%ROWTYPE IS
    r CFG_ORIGENS%ROWTYPE;
  BEGIN
    SELECT * INTO r FROM CFG_ORIGENS WHERE id = p_id;
    RETURN r;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN raise_application_error(-20003, 'Origem n?o encontrada.');
  END obter;

  FUNCTION pode_excluir(p_id IN NUMBER) RETURN VARCHAR2 IS
    v_existe NUMBER; v_ja_inat VARCHAR2(4);
  BEGIN
    SELECT COUNT(*), MAX(ativo) INTO v_existe, v_ja_inat FROM CFG_ORIGENS WHERE id = p_id;
    IF v_existe = 0 THEN RETURN 'Origem n?o encontrada.'; END IF;
    IF v_ja_inat = 'N' THEN RETURN 'Origem ja esta inativa.'; END IF;
    RETURN NULL;
  END pode_excluir;

  PROCEDURE excluir(p_id IN NUMBER) IS
    v_msg VARCHAR2(4000) := pode_excluir(p_id);
  BEGIN
    IF v_msg IS NOT NULL THEN raise_application_error(-20001, v_msg); END IF;
    UPDATE CFG_ORIGENS SET ativo = 'N' WHERE id = p_id;
  END excluir;
END pkg_cfg_origens;
/
