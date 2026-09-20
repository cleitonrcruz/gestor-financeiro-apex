CREATE OR REPLACE FUNCTION f_acessos_kpi(
  p_role         IN VARCHAR2,
  p_app_user     IN VARCHAR2,
  p_data_ini     IN DATE,
  p_data_fim     IN DATE,
  p_evento       IN VARCHAR2 DEFAULT NULL,
  p_filtro_user  IN VARCHAR2 DEFAULT NULL
) RETURN VARCHAR2 IS
  l_entradas  NUMBER := 0;
  l_senha     NUMBER := 0;
  l_cookie    NUMBER := 0;
  l_falhas    NUMBER := 0;
  l_usuarios  NUMBER := 0;
  l_origens   NUMBER := 0;
  l_mascarado NUMBER := 0;
  -- O IP do balanceador nao conta: inflaria a contagem de origens para sempre.
  c_ip_balanceador CONSTANT VARCHAR2(60) := '192.29.129.12';
  l_ultima    TIMESTAMP;
  l_ult_user  VARCHAR2(255);
  l_ult_ip    VARCHAR2(60);
  l_admin     BOOLEAN := NVL(p_role,'NONE') = 'ADMIN';

  FUNCTION card(p_classe VARCHAR2, p_icone VARCHAR2, p_rotulo VARCHAR2,
                p_valor VARCHAR2, p_sub VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN '<div class="d-kpi-card ' || p_classe || '">'
        || '<div class="d-kpi-icon"><span class="fa ' || p_icone || '"></span></div>'
        || '<div class="d-kpi-body">'
        || '<div class="d-kpi-label">' || p_rotulo || '</div>'
        || '<div class="d-kpi-value">' || p_valor || '</div>'
        || CASE WHEN p_sub IS NOT NULL
                THEN '<div class="d-kpi-sub">' || p_sub || '</div>' END
        || '</div></div>';
  END card;
BEGIN
  SELECT COUNT(CASE WHEN evento = 'LOGIN_SUCCESS'     THEN 1 END),
         COUNT(CASE WHEN evento = 'LOGIN_PERSISTENTE' THEN 1 END),
         COUNT(CASE WHEN classe = 'FALHA'             THEN 1 END),
         COUNT(DISTINCT UPPER(username)),
         COUNT(DISTINCT CASE WHEN origem_ip <> c_ip_balanceador THEN origem_ip END),
         COUNT(CASE WHEN origem_ip = c_ip_balanceador THEN 1 END)
    INTO l_senha, l_cookie, l_falhas, l_usuarios, l_origens, l_mascarado
    FROM admin.vw_log_acessos
   WHERE (p_data_ini IS NULL OR CAST(ts AS DATE) >= p_data_ini)
     AND (p_data_fim IS NULL OR CAST(ts AS DATE) <  p_data_fim + 1)
     AND (p_evento IS NULL OR evento = p_evento)
     AND (p_filtro_user IS NULL OR LOWER(username) LIKE LOWER('%'||p_filtro_user||'%'))
     AND (l_admin OR UPPER(username) = UPPER(p_app_user));

  l_entradas := l_senha + l_cookie;

  BEGIN
    SELECT ts, username, origem_ip
      INTO l_ultima, l_ult_user, l_ult_ip
      FROM (SELECT ts, username, origem_ip
              FROM admin.vw_log_acessos
             WHERE classe = 'ENTRADA'
               AND (p_data_ini IS NULL OR CAST(ts AS DATE) >= p_data_ini)
               AND (p_data_fim IS NULL OR CAST(ts AS DATE) <  p_data_fim + 1)
               AND (p_evento IS NULL OR evento = p_evento)
               AND (p_filtro_user IS NULL OR LOWER(username) LIKE LOWER('%'||p_filtro_user||'%'))
               AND (l_admin OR UPPER(username) = UPPER(p_app_user))
             ORDER BY ts DESC)
     WHERE ROWNUM = 1;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    l_ultima := NULL;
  END;

  RETURN '<div class="d-kpi-grid">'
  || card('d-kpi-card--success', 'fa-sign-in',
          'Entradas',
          TO_CHAR(l_entradas),
          l_senha || ' por senha e ' || l_cookie || ' por cookie')
  || card(CASE WHEN l_falhas > 0 THEN 'd-kpi-card--danger' ELSE 'd-kpi-card--info' END,
          'fa-exclamation-triangle',
          'Tentativas que falharam',
          TO_CHAR(l_falhas),
          CASE WHEN l_entradas + l_falhas > 0
               THEN TO_CHAR(ROUND(l_falhas * 100 / (l_entradas + l_falhas))) || '% das tentativas'
          END)
  || card('d-kpi-card--info', 'fa-globe',
          'Origens distintas',
          TO_CHAR(l_origens),
          CASE WHEN l_mascarado > 0
               THEN TO_CHAR(l_mascarado) || ' evento(s) antes da corre' || UNISTR('\00E7\00E3') || 'o, sem origem real'
               WHEN l_admin THEN TO_CHAR(l_usuarios) || ' usu' || UNISTR('\00E1') || 'rio(s) distinto(s)'
          END)
  || card('d-kpi-card--info', 'fa-clock-o',
          UNISTR('\00DAltima entrada'),
          CASE WHEN l_ultima IS NULL THEN '-'
               ELSE TO_CHAR(l_ultima, 'DD/MM HH24:MI') END,
          CASE WHEN l_ultima IS NOT NULL THEN l_ult_user || ' de ' || l_ult_ip END)
  || '</div>';
END f_acessos_kpi;
/
