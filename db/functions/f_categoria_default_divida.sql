CREATE OR REPLACE FUNCTION       f_categoria_default_divida(p_tipo VARCHAR2, p_user_id NUMBER)
  RETURN NUMBER
IS
BEGIN
  -- Categoria do dono da divida. Se ele renomeou ou excluiu, volta a existir so para ele.
  RETURN admin.pkg_cfg_categorias.obter_ou_criar(
           p_user_id,
           CASE UPPER(NVL(p_tipo,'EMP'))
             WHEN 'CC' THEN UNISTR('Pagamento de Cart\00E3o de Cr\00E9dito')
             ELSE UNISTR('Pagamento de Empr\00E9stimo')
           END,
           'DPF');
END;
/
