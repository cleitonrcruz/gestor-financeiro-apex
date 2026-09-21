set define off

-- Com os privilegios de ADMIN: a contagem de escritas le FIN_LANCAMENTOS, que tem RLS.
CREATE OR REPLACE FUNCTION f_api_kpi RETURN VARCHAR2 IS
  l_hoje      TIMESTAMP := TRUNC(f_now_brt);
  l_total     NUMBER;
  l_erros     NUMBER;
  l_media     NUMBER;
  l_p95       NUMBER;
  l_periodo   NUMBER;
  l_escritas  NUMBER;
  l_demo      NUMBER;

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
  SELECT COUNT(*),
         COUNT(CASE WHEN status >= 400 THEN 1 END),
         ROUND(AVG(duracao_ms)),
         ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duracao_ms))
    INTO l_total, l_erros, l_media, l_p95
    FROM log_api_chamadas
   WHERE ts >= l_hoje;

  SELECT COUNT(*) INTO l_periodo
    FROM log_api_chamadas
   WHERE ts >= l_hoje - 13;

  SELECT id INTO l_demo FROM cfg_usuarios_autorizados WHERE UPPER(username) = 'DEMO';

  -- mesma conta da cota do POST em PKG_API_V1
  SELECT COUNT(*) INTO l_escritas
    FROM fin_lancamentos
   WHERE user_id = l_demo
     AND external_source = pkg_api_v1.c_fonte
     AND created_on >= l_hoje;

  RETURN '<div class="d-kpi-grid">'
  || card('d-kpi-card--info', 'fa-exchange',
          'Chamadas hoje',
          TO_CHAR(l_total),
          l_periodo || ' nos ' || UNISTR('\00FA') || 'ltimos 14 dias')
  || card(CASE WHEN l_erros > 0 THEN 'd-kpi-card--danger' ELSE 'd-kpi-card--success' END,
          'fa-exclamation-triangle',
          'Respostas com erro',
          CASE WHEN l_total > 0 THEN TO_CHAR(ROUND(l_erros * 100 / l_total)) || '%' ELSE '-' END,
          l_erros || ' com status 4xx ou 5xx')
  || card(CASE WHEN l_escritas >= pkg_api_v1.c_teto_dia THEN 'd-kpi-card--danger' ELSE 'd-kpi-card--info' END,
          'fa-pencil',
          'Escritas hoje',
          l_escritas || ' de ' || pkg_api_v1.c_teto_dia,
          'a cota zera ' || UNISTR('\00E0') || ' meia-noite')
  || card('d-kpi-card--info', 'fa-clock-o',
          'Tempo m' || UNISTR('\00E9') || 'dio hoje',
          CASE WHEN l_media IS NULL THEN '-' ELSE l_media || ' ms' END,
          CASE WHEN l_p95 IS NOT NULL THEN '95% abaixo de ' || l_p95 || ' ms' END)
  || '</div>';
END f_api_kpi;
/

grant execute on f_api_kpi to WKSP_GESTORFINANCEIRO;
grant execute on f_api_kpi to CLEITON;

show errors function f_api_kpi

select object_name, object_type, status from all_objects
 where owner = 'ADMIN' and object_name = 'F_API_KPI';
