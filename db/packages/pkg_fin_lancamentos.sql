CREATE OR REPLACE PACKAGE         "PKG_FIN_LANCAMENTOS" AS
  PROCEDURE inserir(
    p_user_id            IN  NUMBER,
    p_origem_id          IN  NUMBER   DEFAULT NULL,
    p_categoria_id       IN  NUMBER,
    p_divida_id          IN  NUMBER   DEFAULT NULL,
    p_conciliacao_ofx_id IN  NUMBER   DEFAULT NULL,
    p_tipo               IN  VARCHAR2,
    p_descricao          IN  VARCHAR2,
    p_valor              IN  NUMBER,
    p_data_competencia   IN  DATE,
    p_data_caixa         IN  DATE     DEFAULT NULL,
    p_forma_pagamento    IN  VARCHAR2 DEFAULT NULL,
    p_observacoes        IN  VARCHAR2 DEFAULT NULL,
    p_external_id        IN  VARCHAR2 DEFAULT NULL,
    p_external_source    IN  VARCHAR2 DEFAULT NULL,
    p_ativo              IN  VARCHAR2 DEFAULT 'S',
    p_id                 OUT NUMBER
  );

  PROCEDURE atualizar(
    p_id                 IN  NUMBER,
    p_origem_id          IN  NUMBER,
    p_categoria_id       IN  NUMBER,
    p_divida_id          IN  NUMBER,
    p_conciliacao_ofx_id IN  NUMBER,
    p_tipo               IN  VARCHAR2,
    p_descricao          IN  VARCHAR2,
    p_valor              IN  NUMBER,
    p_data_competencia   IN  DATE,
    p_data_caixa         IN  DATE,
    p_forma_pagamento    IN  VARCHAR2,
    p_observacoes        IN  VARCHAR2,
    p_external_id        IN  VARCHAR2,
    p_external_source    IN  VARCHAR2,
    p_ativo              IN  VARCHAR2
  );

  FUNCTION  obter        (p_id IN NUMBER) RETURN FIN_LANCAMENTOS%ROWTYPE;
  FUNCTION  pode_excluir (p_id IN NUMBER) RETURN VARCHAR2;
  PROCEDURE excluir      (p_id IN NUMBER);

  PROCEDURE vincular_parcela(
    p_lancamento_id IN NUMBER,
    p_parcela_id    IN NUMBER
  );

  PROCEDURE copiar(
    p_id_origem        IN  NUMBER,
    p_nova_competencia IN  DATE,
    p_id_novo          OUT NUMBER
  );
END pkg_fin_lancamentos;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_FIN_LANCAMENTOS" AS
PROCEDURE inserir(
  p_user_id            IN  NUMBER,
  p_origem_id          IN  NUMBER   DEFAULT NULL,
  p_categoria_id       IN  NUMBER,
  p_divida_id          IN  NUMBER   DEFAULT NULL,
  p_conciliacao_ofx_id IN  NUMBER   DEFAULT NULL,
  p_tipo               IN  VARCHAR2,
  p_descricao          IN  VARCHAR2,
  p_valor              IN  NUMBER,
  p_data_competencia   IN  DATE,
  p_data_caixa         IN  DATE     DEFAULT NULL,
  p_forma_pagamento    IN  VARCHAR2 DEFAULT NULL,
  p_observacoes        IN  VARCHAR2 DEFAULT NULL,
  p_external_id        IN  VARCHAR2 DEFAULT NULL,
  p_external_source    IN  VARCHAR2 DEFAULT NULL,
  p_ativo              IN  VARCHAR2 DEFAULT 'S',
  p_id                 OUT NUMBER
) IS
BEGIN
  INSERT INTO FIN_LANCAMENTOS (user_id, origem_id, categoria_id, divida_id, conciliacao_ofx_id,
    tipo, descricao, valor, data_competencia, data_caixa, forma_pagamento, observacoes,
    external_id, external_source, ativo)
  VALUES (p_user_id, p_origem_id, p_categoria_id, p_divida_id, p_conciliacao_ofx_id,
    p_tipo, p_descricao, p_valor, p_data_competencia, p_data_caixa, p_forma_pagamento, p_observacoes,
    p_external_id, p_external_source, NVL(p_ativo,'S'))
  RETURNING id INTO p_id;
END inserir;

PROCEDURE atualizar(
  p_id                 IN  NUMBER,
  p_origem_id          IN  NUMBER,
  p_categoria_id       IN  NUMBER,
  p_divida_id          IN  NUMBER,
  p_conciliacao_ofx_id IN  NUMBER,
  p_tipo               IN  VARCHAR2,
  p_descricao          IN  VARCHAR2,
  p_valor              IN  NUMBER,
  p_data_competencia   IN  DATE,
  p_data_caixa         IN  DATE,
  p_forma_pagamento    IN  VARCHAR2,
  p_observacoes        IN  VARCHAR2,
  p_external_id        IN  VARCHAR2,
  p_external_source    IN  VARCHAR2,
  p_ativo              IN  VARCHAR2
) IS
BEGIN
  UPDATE FIN_LANCAMENTOS
     SET origem_id          = p_origem_id,
         categoria_id       = p_categoria_id,
         divida_id          = p_divida_id,
         conciliacao_ofx_id = p_conciliacao_ofx_id,
         tipo               = p_tipo,
         descricao          = p_descricao,
         valor              = p_valor,
         data_competencia   = p_data_competencia,
         data_caixa         = p_data_caixa,
         forma_pagamento    = p_forma_pagamento,
         observacoes        = p_observacoes,
         external_id        = p_external_id,
         external_source    = p_external_source,
         ativo              = COALESCE(p_ativo, ativo)
   WHERE id = p_id;
  IF SQL%ROWCOUNT = 0 THEN
    raise_application_error(-20002, 'Lancamento n?o encontrado para atualizac?o.');
  END IF;
END atualizar;

FUNCTION obter(p_id IN NUMBER) RETURN FIN_LANCAMENTOS%ROWTYPE IS
  r FIN_LANCAMENTOS%ROWTYPE;
BEGIN
  SELECT * INTO r FROM FIN_LANCAMENTOS WHERE id = p_id;
  RETURN r;
EXCEPTION
  WHEN NO_DATA_FOUND THEN raise_application_error(-20003, 'Lancamento n?o encontrado.');
END obter;

FUNCTION pode_excluir(p_id IN NUMBER) RETURN VARCHAR2 IS
  v_existe NUMBER; v_ja_inat VARCHAR2(4);
BEGIN
  SELECT COUNT(*), MAX(ativo) INTO v_existe, v_ja_inat FROM FIN_LANCAMENTOS WHERE id = p_id;
  IF v_existe = 0 THEN RETURN 'Lancamento n?o encontrado.'; END IF;
  IF v_ja_inat = 'N' THEN RETURN 'Lancamento ja esta inativo.'; END IF;
  RETURN NULL;
END pode_excluir;

PROCEDURE excluir(p_id IN NUMBER) IS
  v_msg VARCHAR2(4000) := pode_excluir(p_id);
BEGIN
  IF v_msg IS NOT NULL THEN raise_application_error(-20001, v_msg); END IF;
  UPDATE FIN_DIVIDAS_PARCELAS SET lancamento_id = NULL WHERE lancamento_id = p_id;
  UPDATE FIN_OFX_TRANSACOES   SET lancamento_id = NULL WHERE lancamento_id = p_id;
  UPDATE FIN_LANCAMENTOS      SET ativo = 'N'          WHERE id            = p_id;
END excluir;

PROCEDURE vincular_parcela(p_lancamento_id IN NUMBER, p_parcela_id IN NUMBER) IS
  l_owner FIN_LANCAMENTOS.user_id%TYPE;
BEGIN
  IF p_lancamento_id IS NULL THEN RETURN; END IF;
-- Dono sai do proprio lancamento, cujo id vem assinado por checksum; o da parcela nao.
-- Sem isto a procedure roda como ADMIN, isenta de RLS, e prende parcela de outro usuario.
  BEGIN
    SELECT user_id INTO l_owner FROM FIN_LANCAMENTOS WHERE id = p_lancamento_id;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20004, 'Lancamento nao encontrado.');
  END;
-- cobre troca de parcela e desvinculo quando p_parcela_id vem nulo
  UPDATE FIN_DIVIDAS_PARCELAS
     SET lancamento_id = NULL
   WHERE lancamento_id = p_lancamento_id
     AND (p_parcela_id IS NULL OR id <> p_parcela_id);
  IF p_parcela_id IS NOT NULL THEN
    UPDATE FIN_DIVIDAS_PARCELAS
       SET lancamento_id = p_lancamento_id
     WHERE id = p_parcela_id
       AND (lancamento_id IS NULL OR lancamento_id = p_lancamento_id)
       AND divida_id IN (SELECT id FROM FIN_DIVIDAS WHERE user_id = l_owner);
  END IF;
END vincular_parcela;

PROCEDURE copiar(
  p_id_origem        IN  NUMBER,
  p_nova_competencia IN  DATE,
  p_id_novo          OUT NUMBER
) IS
  r FIN_LANCAMENTOS%ROWTYPE;
BEGIN
  r := obter(p_id_origem);
  inserir(
    p_user_id            => r.user_id,
    p_origem_id          => r.origem_id,
    p_categoria_id       => r.categoria_id,
    p_divida_id          => NULL,
    p_conciliacao_ofx_id => NULL,
    p_tipo               => r.tipo,
    p_descricao          => r.descricao,
    p_valor              => r.valor,
    p_data_competencia   => p_nova_competencia,
    p_data_caixa         => NULL,
    p_forma_pagamento    => r.forma_pagamento,
    p_observacoes        => r.observacoes,
    p_external_id        => NULL,
    p_external_source    => NULL,
    p_ativo              => 'S',
    p_id                 => p_id_novo
  );
END copiar;
END pkg_fin_lancamentos;
/
