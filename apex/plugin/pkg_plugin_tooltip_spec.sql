CREATE OR REPLACE PACKAGE       pkg_plugin_tooltip AS
-- Plug-in de Dynamic Action: o gatilho e a classe marcada no elemento, o texto vem de data-tip-text.
-- Duas assinaturas: a doc da 26.1 pede quatro parametros e o exemplo do WWV_FLOW_PLUGIN_API usa tres.
  PROCEDURE render(
    p_dynamic_action IN            apex_plugin.t_dynamic_action,
    p_plugin         IN            apex_plugin.t_plugin,
    p_param          IN            apex_plugin.t_dynamic_action_render_param,
    p_result         IN OUT NOCOPY apex_plugin.t_dynamic_action_render_result);

  PROCEDURE render(
    p_dynamic_action IN            apex_plugin.t_dynamic_action,
    p_plugin         IN            apex_plugin.t_plugin,
    p_result         IN OUT NOCOPY apex_plugin.t_dynamic_action_render_result);
END pkg_plugin_tooltip;
/
