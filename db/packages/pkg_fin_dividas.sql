CREATE OR REPLACE PACKAGE         "PKG_FIN_DIVIDAS" AS
PROCEDURE inserir(
p_user_id        IN  NUMBER,
p_tipo           IN  VARCHAR2,
p_descricao      IN  VARCHAR2,
p_credor         IN  VARCHAR2  DEFAULT NULL,
p_valor_original IN  NUMBER,
p_parcelas_total IN  NUMBER,
p_taxa_juros_am  IN  NUMBER    DEFAULT NULL,
p_data_inicio    IN  DATE,
p_ativo          IN  VARCHAR2  DEFAULT 'S',
p_concluida      IN  VARCHAR2  DEFAULT NULL,
p_data_conclusao IN  DATE      DEFAULT NULL,
p_id             OUT NUMBER
);

PROCEDURE atualizar(
p_id             IN  NUMBER,
p_tipo           IN  VARCHAR2,
p_descricao      IN  VARCHAR2,
p_credor         IN  VARCHAR2,
p_valor_original IN  NUMBER,
p_parcelas_total IN  NUMBER,
p_taxa_juros_am  IN  NUMBER,
p_data_inicio    IN  DATE,
p_ativo          IN  VARCHAR2,
p_concluida      IN  VARCHAR2  DEFAULT NULL,
p_data_conclusao IN  DATE      DEFAULT NULL
);

FUNCTION  obter        (p_id IN NUMBER) RETURN FIN_DIVIDAS%ROWTYPE;
FUNCTION  pode_excluir (p_id IN NUMBER) RETURN VARCHAR2;
PROCEDURE excluir      (p_id IN NUMBER);

PROCEDURE gerar_parcelas(
p_divida_id    IN NUMBER,
p_valor_total  IN NUMBER,
p_qtd_parcelas IN NUMBER,
p_data_inicio  IN DATE
);

PROCEDURE recalcular_parcelas(
p_divida_id IN NUMBER
);

-- Cria lancamento pendente (data_caixa nulo) para cada parcela sem lancamento_id. Idempotente.
PROCEDURE gerar_lancamentos_pendentes(
p_divida_id IN NUMBER
);
END pkg_fin_dividas;
/

CREATE OR REPLACE PACKAGE BODY         "PKG_FIN_DIVIDAS" AS

-- Apaga e reinsere todas as parcelas. Sistema de juros vem da pref dividas_sistema_juros.
PROCEDURE recalcular_parcelas_internal(p_divida_id IN NUMBER) IS
r        FIN_DIVIDAS%ROWTYPE;
l_valor  NUMBER;
l_qtd    NUMBER;
l_taxa   NUMBER;
l_data   DATE;
l_pmt    NUMBER;
l_total  NUMBER;
l_last   NUMBER;
l_factor NUMBER;
l_sistema VARCHAR2(20);
BEGIN
SELECT * INTO r FROM admin.fin_dividas WHERE id = p_divida_id;
l_valor := NVL(r.valor_original, 0);
l_qtd   := NVL(r.parcelas_total, 0);
l_taxa  := NVL(r.taxa_juros_am, 0) / 100;
l_data  := NVL(r.data_inicio, TRUNC(admin.f_now_brt));
l_sistema := UPPER(NVL(admin.f_app_pref('dividas_sistema_juros'), 'PRICE'));

-- Solta o vinculo antes de deletar, senao FIN_DIVP_LAN_FK da ORA-02292.
UPDATE admin.fin_dividas_parcelas SET lancamento_id = NULL WHERE divida_id = p_divida_id;

-- So os pendentes; os pagos ficam orfaos para preservar o historico.
DELETE FROM admin.fin_lancamentos
 WHERE divida_id = p_divida_id
   AND data_caixa IS NULL;
DELETE FROM admin.fin_dividas_parcelas WHERE divida_id = p_divida_id;

IF l_qtd <= 0 OR l_valor <= 0 THEN RETURN; END IF;

IF l_taxa > 0 AND l_sistema = 'SIMPLES' THEN
  l_total := l_valor * (1 + l_taxa * l_qtd);
  l_pmt   := ROUND(l_total / l_qtd, 2);
  l_last  := ROUND(l_total - (l_pmt * (l_qtd - 1)), 2);
ELSIF l_taxa > 0 THEN
  l_factor := POWER(1 + l_taxa, l_qtd);
  l_pmt    := ROUND(l_valor * (l_taxa * l_factor) / (l_factor - 1), 2);
  l_last   := l_pmt;
ELSE
  l_pmt  := ROUND(l_valor / l_qtd, 2);
  l_last := ROUND(l_valor - (l_pmt * (l_qtd - 1)), 2);
END IF;

FOR i IN 1..l_qtd LOOP
  INSERT INTO admin.fin_dividas_parcelas (divida_id, numero, valor, data_vencimento)
  VALUES (p_divida_id, i, CASE WHEN i = l_qtd THEN l_last ELSE l_pmt END, ADD_MONTHS(l_data, i - 1));
END LOOP;
END recalcular_parcelas_internal;

PROCEDURE inserir(p_user_id IN NUMBER, p_tipo IN VARCHAR2, p_descricao IN VARCHAR2, p_credor IN VARCHAR2 DEFAULT NULL,
                p_valor_original IN NUMBER, p_parcelas_total IN NUMBER, p_taxa_juros_am IN NUMBER DEFAULT NULL,
                p_data_inicio IN DATE, p_ativo IN VARCHAR2 DEFAULT 'S', p_concluida IN VARCHAR2 DEFAULT NULL,
                p_data_conclusao IN DATE DEFAULT NULL, p_id OUT NUMBER) IS
BEGIN
INSERT INTO admin.fin_dividas (user_id, tipo, descricao, credor, valor_original, parcelas_total, taxa_juros_am, data_inicio, ativo, concluida, data_conclusao)
VALUES (p_user_id, p_tipo, p_descricao, p_credor, p_valor_original, p_parcelas_total, p_taxa_juros_am, p_data_inicio, NVL(p_ativo,'S'), NVL(p_concluida,'N'),
        CASE WHEN NVL(p_concluida,'N')='S' THEN COALESCE(p_data_conclusao, admin.f_now_brt) ELSE NULL END)
RETURNING id INTO p_id;
END inserir;

PROCEDURE atualizar(p_id IN NUMBER, p_tipo IN VARCHAR2, p_descricao IN VARCHAR2, p_credor IN VARCHAR2,
                  p_valor_original IN NUMBER, p_parcelas_total IN NUMBER, p_taxa_juros_am IN NUMBER,
                  p_data_inicio IN DATE, p_ativo IN VARCHAR2, p_concluida IN VARCHAR2 DEFAULT NULL,
                  p_data_conclusao IN DATE DEFAULT NULL) IS
BEGIN
UPDATE admin.fin_dividas SET tipo=p_tipo, descricao=p_descricao, credor=p_credor, valor_original=p_valor_original,
       parcelas_total=p_parcelas_total, taxa_juros_am=p_taxa_juros_am, data_inicio=p_data_inicio,
       ativo=COALESCE(p_ativo, ativo), concluida=COALESCE(p_concluida, concluida),
       data_conclusao=CASE WHEN p_concluida IS NULL THEN data_conclusao
                           WHEN p_concluida='N'   THEN NULL
                           ELSE COALESCE(p_data_conclusao, data_conclusao, admin.f_now_brt) END
 WHERE id=p_id;
IF SQL%ROWCOUNT = 0 THEN raise_application_error(-20002, 'Divida nao encontrada para atualizacao.'); END IF;

-- Divida quitada: parcela futura vira lancamento PAGO na data da conclusao, para sumir do
-- dashboard e nao oferecer "Criar lancamento". Os ja pagos ficam com a data real.
DECLARE
  l_concl   VARCHAR2(1);
  l_dtconcl DATE;
  l_uid     NUMBER;
  l_tot     NUMBER;
  l_cat     NUMBER;
  l_new     NUMBER;
BEGIN
  SELECT concluida, data_conclusao, user_id, parcelas_total
    INTO l_concl, l_dtconcl, l_uid, l_tot
    FROM admin.fin_dividas WHERE id = p_id;
  IF l_concl = 'S' AND l_dtconcl IS NOT NULL THEN
    l_cat := admin.f_categoria_default_divida(p_tipo);
    FOR rec IN (SELECT pa.id parcela_id, pa.numero, pa.valor, pa.data_vencimento
                  FROM admin.fin_dividas_parcelas pa
                 WHERE pa.divida_id = p_id AND pa.lancamento_id IS NULL
                   AND TO_CHAR(pa.data_vencimento,'YYYY-MM') > TO_CHAR(l_dtconcl,'YYYY-MM')) LOOP
      INSERT INTO admin.fin_lancamentos
        (user_id, categoria_id, divida_id, tipo, descricao, valor, data_competencia, data_caixa, ativo)
      VALUES (l_uid, l_cat, p_id, 'DPF',
              p_descricao || ' ' || LPAD(TO_CHAR(rec.numero), 2, '0') || '/' || TO_CHAR(l_tot),
              rec.valor, rec.data_vencimento, l_dtconcl, 'S')
      RETURNING id INTO l_new;
      UPDATE admin.fin_dividas_parcelas SET lancamento_id = l_new WHERE id = rec.parcela_id;
    END LOOP;
    UPDATE admin.fin_lancamentos l SET data_caixa = l_dtconcl
     WHERE l.divida_id = p_id AND l.data_caixa IS NULL AND l.ativo = 'S'
       AND TO_CHAR(l.data_competencia,'YYYY-MM') > TO_CHAR(l_dtconcl,'YYYY-MM');
  END IF;
END;
END atualizar;

FUNCTION obter(p_id IN NUMBER) RETURN FIN_DIVIDAS%ROWTYPE IS r FIN_DIVIDAS%ROWTYPE;
BEGIN SELECT * INTO r FROM admin.fin_dividas WHERE id = p_id; RETURN r;
EXCEPTION WHEN NO_DATA_FOUND THEN raise_application_error(-20003, 'Divida nao encontrada.'); END;

FUNCTION pode_excluir(p_id IN NUMBER) RETURN VARCHAR2 IS v_existe NUMBER; v_ja_inat VARCHAR2(4);
BEGIN SELECT COUNT(*), MAX(ativo) INTO v_existe, v_ja_inat FROM admin.fin_dividas WHERE id = p_id;
IF v_existe = 0 THEN RETURN 'Divida nao encontrada.'; END IF;
IF v_ja_inat = 'N' THEN RETURN 'Divida ja esta inativa.'; END IF;
RETURN NULL;
END pode_excluir;

PROCEDURE excluir(p_id IN NUMBER) IS v_msg VARCHAR2(4000) := pode_excluir(p_id);
BEGIN IF v_msg IS NOT NULL THEN raise_application_error(-20001, v_msg); END IF;
UPDATE admin.fin_dividas SET ativo='N' WHERE id = p_id;
END excluir;

PROCEDURE gerar_lancamentos_pendentes(p_divida_id IN NUMBER) IS
l_divida   FIN_DIVIDAS%ROWTYPE;
l_cat_id   NUMBER;
l_lanc_id  NUMBER;
l_descr    VARCHAR2(800);
BEGIN
SELECT * INTO l_divida FROM admin.fin_dividas WHERE id = p_divida_id;
l_cat_id := admin.f_categoria_default_divida(l_divida.tipo);

FOR rec IN (
  SELECT id AS parcela_id, numero, valor, data_vencimento
    FROM admin.fin_dividas_parcelas
   WHERE divida_id = p_divida_id
     AND lancamento_id IS NULL
   ORDER BY numero
) LOOP
  l_descr := l_divida.descricao || ' ' ||
             LPAD(TO_CHAR(rec.numero), 2, '0') || '/' ||
             TO_CHAR(l_divida.parcelas_total);
  INSERT INTO admin.fin_lancamentos (
    user_id, categoria_id, divida_id, tipo, descricao, valor,
    data_competencia, data_caixa, ativo
  ) VALUES (
    l_divida.user_id, l_cat_id, p_divida_id, 'DPF',
    l_descr, rec.valor, rec.data_vencimento, NULL, 'S'
  ) RETURNING id INTO l_lanc_id;
  UPDATE admin.fin_dividas_parcelas
     SET lancamento_id = l_lanc_id
   WHERE id = rec.parcela_id;
END LOOP;
EXCEPTION
WHEN NO_DATA_FOUND THEN
  raise_application_error(-20004, 'Divida nao encontrada (gerar_lancamentos_pendentes): '||p_divida_id);
END gerar_lancamentos_pendentes;

PROCEDURE gerar_parcelas(p_divida_id IN NUMBER, p_valor_total IN NUMBER, p_qtd_parcelas IN NUMBER, p_data_inicio IN DATE) IS
l_existing NUMBER;
BEGIN
SELECT COUNT(*) INTO l_existing FROM admin.fin_dividas_parcelas WHERE divida_id = p_divida_id;
IF l_existing > 0 THEN RETURN; END IF;
recalcular_parcelas_internal(p_divida_id);
gerar_lancamentos_pendentes(p_divida_id);
END gerar_parcelas;

PROCEDURE recalcular_parcelas(p_divida_id IN NUMBER) IS
BEGIN
recalcular_parcelas_internal(p_divida_id);
-- recalcular_parcelas_internal deletou os pendentes; recria.
gerar_lancamentos_pendentes(p_divida_id);
END recalcular_parcelas;

END pkg_fin_dividas;
/
