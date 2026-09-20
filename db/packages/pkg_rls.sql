CREATE OR REPLACE PACKAGE       pkg_rls AS
  FUNCTION f_rls_user_owned     (p_schema IN VARCHAR2, p_object IN VARCHAR2) RETURN VARCHAR2;
  FUNCTION f_rls_via_divida     (p_schema IN VARCHAR2, p_object IN VARCHAR2) RETURN VARCHAR2;
  FUNCTION f_rls_via_lancamento (p_schema IN VARCHAR2, p_object IN VARCHAR2) RETURN VARCHAR2;
END pkg_rls;
/

CREATE OR REPLACE PACKAGE BODY       pkg_rls AS

  FUNCTION f_rls_user_owned(p_schema IN VARCHAR2, p_object IN VARCHAR2) RETURN VARCHAR2 AS
    l_uid NUMBER;
  BEGIN
    BEGIN l_uid := TO_NUMBER(v('G_USER_ID')); EXCEPTION WHEN OTHERS THEN l_uid := NULL; END;
    IF l_uid IS NOT NULL THEN
      RETURN 'user_id = ' || l_uid;
    END IF;
    IF SYS_CONTEXT('USERENV','SESSION_USER') IN ('SYS','SYSTEM','ADMIN') THEN
      RETURN NULL;
    END IF;
    RETURN '1=0';
  END f_rls_user_owned;

  FUNCTION f_rls_via_divida(p_schema IN VARCHAR2, p_object IN VARCHAR2) RETURN VARCHAR2 AS
    l_uid NUMBER;
  BEGIN
    BEGIN l_uid := TO_NUMBER(v('G_USER_ID')); EXCEPTION WHEN OTHERS THEN l_uid := NULL; END;
    IF l_uid IS NOT NULL THEN
      RETURN 'divida_id IN (SELECT id FROM admin.fin_dividas WHERE user_id = ' || l_uid || ')';
    END IF;
    IF SYS_CONTEXT('USERENV','SESSION_USER') IN ('SYS','SYSTEM','ADMIN') THEN
      RETURN NULL;
    END IF;
    RETURN '1=0';
  END f_rls_via_divida;

  FUNCTION f_rls_via_lancamento(p_schema IN VARCHAR2, p_object IN VARCHAR2) RETURN VARCHAR2 AS
    l_uid NUMBER;
  BEGIN
    BEGIN l_uid := TO_NUMBER(v('G_USER_ID')); EXCEPTION WHEN OTHERS THEN l_uid := NULL; END;
    IF l_uid IS NOT NULL THEN
      RETURN 'lancamento_id IN (SELECT id FROM admin.fin_lancamentos WHERE user_id = ' || l_uid || ')';
    END IF;
    IF SYS_CONTEXT('USERENV','SESSION_USER') IN ('SYS','SYSTEM','ADMIN') THEN
      RETURN NULL;
    END IF;
    RETURN '1=0';
  END f_rls_via_lancamento;

END pkg_rls;
/
