CREATE OR REPLACE FUNCTION       f_categoria_default_divida(p_tipo VARCHAR2)
  RETURN NUMBER
IS
BEGIN
  RETURN CASE UPPER(NVL(p_tipo,'EMP'))
    WHEN 'EMP' THEN 41  -- Pagamento de Empréstimo
    WHEN 'CC'  THEN 42  -- Pagamento de Cartão de Crédito
    WHEN 'SEG' THEN 82  -- Veículo (fallback p/ seguros)
    ELSE 41
  END;
END;
/
