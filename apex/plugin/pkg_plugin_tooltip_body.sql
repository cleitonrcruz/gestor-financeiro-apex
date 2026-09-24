CREATE OR REPLACE PACKAGE BODY       pkg_plugin_tooltip AS

  c_classe_padrao CONSTANT VARCHAR2(60) := 'js-tip';
  c_largura_min   CONSTANT NUMBER := 160;
  c_largura_max   CONSTANT NUMBER := 900;

-- Cor vem de token, nunca de valor livre do usuario: evita interpolar string em CSS.
  FUNCTION cor_do_token(p_token IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE p_token
             WHEN 'success' THEN 'var(--ut-palette-success, #2e7d32)'
             WHEN 'primary' THEN 'var(--ut-palette-primary, #2563eb)'
             WHEN 'warning' THEN 'var(--ut-palette-warning, #b26a00)'
             WHEN 'danger'  THEN 'var(--ut-palette-danger, #c0392b)'
             ELSE                'var(--ut-body-text-color, #5f5e5a)'
           END;
  END cor_do_token;

  FUNCTION ler(p_da IN apex_plugin.t_dynamic_action, p_nome IN VARCHAR2) RETURN VARCHAR2 IS
    l_v VARCHAR2(32767);
  BEGIN
    l_v := p_da.attributes.get_varchar2(p_nome);
    RETURN l_v;
  EXCEPTION WHEN OTHERS THEN
    -- Plug-in cadastrado na interface antiga nao tem a colecao populada.
    RETURN NULL;
  END ler;

  PROCEDURE emitir(
    p_dynamic_action IN            apex_plugin.t_dynamic_action,
    p_result         IN OUT NOCOPY apex_plugin.t_dynamic_action_render_result)
  IS
    l_classe  VARCHAR2(60);
    l_rotulo  VARCHAR2(200);
    l_token   VARCHAR2(30);
    l_largura NUMBER;
    l_cor     VARCHAR2(120);
    l_css     VARCHAR2(32767);
  BEGIN
    l_classe := NVL(TRIM(ler(p_dynamic_action, 'trigger-class')), c_classe_padrao);
    -- Classe entra em seletor CSS e em querySelector: so aceita o que e nome de classe.
    IF NOT REGEXP_LIKE(l_classe, '^[A-Za-z][A-Za-z0-9_-]{0,59}$') THEN
      l_classe := c_classe_padrao;
    END IF;

    l_rotulo := SUBSTR(ler(p_dynamic_action, 'label'), 1, 200);

    l_token := LOWER(TRIM(ler(p_dynamic_action, 'accent')));
    -- Em PL/SQL "null not in (...)" devolve NULL, nao TRUE: o nulo tem de ser testado a parte.
    IF l_token IS NULL OR l_token NOT IN ('success','primary','warning','danger','neutral') THEN
      l_token := 'success';
    END IF;
    l_cor := cor_do_token(l_token);

    BEGIN
      l_largura := TO_NUMBER(ler(p_dynamic_action, 'max-width'));
    EXCEPTION WHEN OTHERS THEN
      l_largura := NULL;
    END;
    l_largura := LEAST(GREATEST(NVL(l_largura, 480), c_largura_min), c_largura_max);

    l_css :=
      '.gftip{position:fixed;z-index:2000;max-width:' || TO_CHAR(l_largura, 'FM999999') || 'px;min-width:200px;'
      || 'background:var(--ut-component-background-color,#fff);color:var(--ut-component-text-default-color,#2c2c2a);'
      || 'border:1px solid var(--ut-component-border-color,rgba(16,24,40,.10));'
      || 'border-radius:10px;overflow:hidden;padding:14px 18px 14px 23px;'
      || 'box-shadow:0 14px 34px -10px rgba(16,24,40,.24),0 3px 8px -3px rgba(16,24,40,.12);'
      || 'pointer-events:none;text-align:left;'
      || 'visibility:hidden;opacity:0;transform:translateY(8px) scale(.98);'
      || 'transition:opacity .18s ease-in,transform .18s ease-in,visibility 0s linear .18s}'
      || '.gftip.is-on{visibility:visible;opacity:1;transform:translateY(0) scale(1);'
      || 'transition:opacity .2s cubic-bezier(.16,1,.3,1),transform .2s cubic-bezier(.16,1,.3,1),visibility 0s}'
      || '.gftip::before{content:"";position:absolute;left:0;top:0;bottom:0;width:5px;background:' || l_cor || '}'
      || '.gftip-rot{display:block;font-size:11px;letter-spacing:.06em;text-transform:uppercase;'
      || 'color:' || l_cor || ';margin-bottom:7px}'
      || '.gftip-txt{display:block;font-size:.875rem;line-height:1.6;text-align:justify;hyphens:auto;'
      || 'white-space:normal;overflow-wrap:anywhere}'
      || '.gftip-cta{display:block;margin-top:9px;padding-top:8px;'
      || 'border-top:1px solid rgba(16,24,40,.08);font-size:.8125rem;font-weight:600;'
      || 'color:' || l_cor || '}'
      || '.' || l_classe || '{cursor:help;text-decoration:underline dotted;text-underline-offset:3px}'
      || '@media (prefers-reduced-motion:reduce){.gftip,.gftip.is-on{transition:none}}';

    apex_css.add(p_css => l_css, p_key => 'gftip-css-' || l_token || '-' || l_classe);

-- Delegacao em document: sobrevive a refresh de regiao sem re-bind.
-- Texto por textContent, nunca innerHTML.
    apex_javascript.add_inline_code(
      p_code => q'~
window.gfTooltip = window.gfTooltip || (function () {
  "use strict";
  var ID = "gfTipBalao", cfg = { classe: "js-tip", rotulo: "" }, pronto = false;
  function balao() {
    var el = document.getElementById(ID);
    if (!el) {
      el = document.createElement("div");
      el.id = ID; el.className = "gftip"; el.setAttribute("role", "tooltip");
      var rot = document.createElement("span"); rot.className = "gftip-rot";
      var txt = document.createElement("span"); txt.className = "gftip-txt";
      var cta = document.createElement("span"); cta.className = "gftip-cta";
      el.appendChild(rot); el.appendChild(txt); el.appendChild(cta);
      document.body.appendChild(el);
    }
    return el;
  }
  function gatilho(t) {
    if (!t) { return null; }
    if (t.nodeType === 1 && t.closest) { return t.closest("." + cfg.classe); }
    if (t.parentElement && t.parentElement.closest) { return t.parentElement.closest("." + cfg.classe); }
    return null;
  }
  function mostra(alvo) {
    var texto = alvo.getAttribute("data-tip-text");
    if (!texto) { return; }
    var el = balao();
    var rot = el.querySelector(".gftip-rot");
    rot.textContent = cfg.rotulo || "";
    rot.style.display = cfg.rotulo ? "" : "none";
    el.querySelector(".gftip-txt").textContent = texto;
    var chamada = alvo.getAttribute("data-tip-cta");
    var elCta = el.querySelector(".gftip-cta");
    elCta.textContent = chamada || "";
    elCta.style.display = chamada ? "" : "none";
    var r = alvo.getBoundingClientRect();
    var topo = r.bottom + 8;
    if (topo + el.offsetHeight > window.innerHeight - 8) { topo = r.top - el.offsetHeight - 8; }
    var esq = r.left;
    if (esq + el.offsetWidth > window.innerWidth - 12) { esq = window.innerWidth - el.offsetWidth - 12; }
    if (esq < 12) { esq = 12; }
    el.style.top = Math.max(8, topo) + "px";
    el.style.left = esq + "px";
    el.classList.add("is-on");
  }
  function esconde() {
    var el = document.getElementById(ID);
    if (el) { el.classList.remove("is-on"); }
  }
  return {
    init: function (opcoes) {
      if (opcoes) {
        if (opcoes.classe) { cfg.classe = opcoes.classe; }
        cfg.rotulo = opcoes.rotulo || "";
      }
      if (pronto) { return; }
      pronto = true;
      document.addEventListener("mouseover", function (e) { var a = gatilho(e.target); if (a) { mostra(a); } });
      document.addEventListener("mouseout",  function (e) { if (gatilho(e.target)) { esconde(); } });
      document.addEventListener("focusin",   function (e) { var a = gatilho(e.target); if (a) { mostra(a); } });
      document.addEventListener("focusout", esconde);
      document.addEventListener("scroll", esconde, true);
    }
  };
})();
~',
      p_key  => 'gftip-engine');

    p_result.function_name := 'window.gfTooltip.init';
    p_result.function_param.open_object;
    p_result.function_param.put('classe', l_classe);
    p_result.function_param.put('rotulo', NVL(l_rotulo, ''));
    p_result.function_param.close_object;
  END emitir;

  PROCEDURE render(
    p_dynamic_action IN            apex_plugin.t_dynamic_action,
    p_plugin         IN            apex_plugin.t_plugin,
    p_param          IN            apex_plugin.t_dynamic_action_render_param,
    p_result         IN OUT NOCOPY apex_plugin.t_dynamic_action_render_result)
  IS
  BEGIN
    emitir(p_dynamic_action, p_result);
  END render;

  PROCEDURE render(
    p_dynamic_action IN            apex_plugin.t_dynamic_action,
    p_plugin         IN            apex_plugin.t_plugin,
    p_result         IN OUT NOCOPY apex_plugin.t_dynamic_action_render_result)
  IS
  BEGIN
    emitir(p_dynamic_action, p_result);
  END render;

END pkg_plugin_tooltip;
/
