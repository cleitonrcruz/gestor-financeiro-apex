prompt --application/shared_components/plugins/dynamic_action/br_com_gestorfinanceiro_tooltip
begin
--   Manifest
--     PLUGIN: BR.COM.GESTORFINANCEIRO.TOOLTIP
--   Manifest End
wwv_flow_imp.component_begin (
 p_version_yyyy_mm_dd=>'2026.03.30'
,p_release=>'26.1.4'
,p_default_workspace_id=>9235085265755703
,p_default_application_id=>102
,p_default_id_offset=>9246019083985681
,p_default_owner=>'WKSP_GESTORFINANCEIRO'
);
wwv_flow_imp_shared.create_plugin(
 p_id=>wwv_flow_imp.id(29246019083985810)
,p_plugin_type=>'DYNAMIC ACTION'
,p_name=>'BR.COM.GESTORFINANCEIRO.TOOLTIP'
,p_display_name=>'Tooltip'
,p_apexlang_name=>'tooltip'
,p_category=>'EFFECT'
,p_image_prefix=>nvl(wwv_flow_application_install.get_static_plugin_file_prefix('DYNAMIC ACTION','BR.COM.GESTORFINANCEIRO.TOOLTIP'),'')
,p_api_version=>3
,p_render_function=>'admin.pkg_plugin_tooltip.render'
,p_standard_attributes=>'ONLOAD'
,p_help_text=>'Balao de ajuda para qualquer elemento da pagina. Marque o elemento com a classe informada em "Classe do gatilho" e ponha o texto completo no atributo data-tip-text. O texto e inserido por textContent, entao conteudo vindo do banco nao vira HTML. Um u'
||'nico balao serve a pagina toda e escuta por delegacao em document, entao elementos criados depois (refresh de regiao, paginacao) funcionam sem re-bind.'
,p_version_identifier=>'1.0'
,p_files_version=>2461304145332
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(29246019083985813)
,p_plugin_id=>wwv_flow_imp.id(29246019083985810)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>3
,p_display_sequence=>30
,p_static_id=>'accent'
,p_prompt=>'Cor do acento'
,p_apexlang_name=>'corDoAcento'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'success'
,p_is_translatable=>false
,p_lov_type=>'STATIC'
,p_help_text=>unistr('Cor da faixa lateral e do r\00F3tulo. Sai de vari\00E1vel do Universal Theme, entao acompanha o theme style.')
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(29246019083985821)
,p_plugin_attribute_id=>wwv_flow_imp.id(29246019083985813)
,p_display_sequence=>20
,p_display_value=>'Azul'
,p_return_value=>'primary'
,p_apexlang_name=>'azul'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(29246019083985822)
,p_plugin_attribute_id=>wwv_flow_imp.id(29246019083985813)
,p_display_sequence=>30
,p_display_value=>unistr('\00C2mbar')
,p_return_value=>'warning'
,p_apexlang_name=>'mbar'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(29246019083985824)
,p_plugin_attribute_id=>wwv_flow_imp.id(29246019083985813)
,p_display_sequence=>50
,p_display_value=>'Neutro'
,p_return_value=>'neutral'
,p_apexlang_name=>'neutro'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(29246019083985820)
,p_plugin_attribute_id=>wwv_flow_imp.id(29246019083985813)
,p_display_sequence=>10
,p_display_value=>'Verde'
,p_return_value=>'success'
,p_apexlang_name=>'verde'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(29246019083985823)
,p_plugin_attribute_id=>wwv_flow_imp.id(29246019083985813)
,p_display_sequence=>40
,p_display_value=>'Vermelho'
,p_return_value=>'danger'
,p_apexlang_name=>'vermelho'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(29246019083985812)
,p_plugin_id=>wwv_flow_imp.id(29246019083985810)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>2
,p_display_sequence=>20
,p_static_id=>'label'
,p_prompt=>unistr('R\00F3tulo')
,p_apexlang_name=>'rtulo'
,p_attribute_type=>'TEXT'
,p_is_required=>false
,p_max_length=>200
,p_is_translatable=>true
,p_help_text=>unistr('Texto pequeno em mai\00FAsculas no topo do balao. Deixe vazio para nao exibir r\00F3tulo.')
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(29246019083985814)
,p_plugin_id=>wwv_flow_imp.id(29246019083985810)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>4
,p_display_sequence=>40
,p_static_id=>'max-width'
,p_prompt=>unistr('Largura m\00E1xima (px)')
,p_apexlang_name=>'larguraMximaPx'
,p_attribute_type=>'NUMBER'
,p_is_required=>false
,p_default_value=>'480'
,p_min_value=>160
,p_max_value=>900
,p_is_translatable=>false
,p_help_text=>unistr('Largura m\00E1xima do balao em pixels. Entre 160 e 900.')
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(29246019083985811)
,p_plugin_id=>wwv_flow_imp.id(29246019083985810)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>1
,p_display_sequence=>10
,p_static_id=>'trigger-class'
,p_prompt=>'Classe do gatilho'
,p_apexlang_name=>'classeDoGatilho'
,p_attribute_type=>'TEXT'
,p_is_required=>false
,p_default_value=>'js-tip'
,p_max_length=>60
,p_is_translatable=>false
,p_help_text=>'Classe CSS que marca os elementos que abrem o balao. Padrao js-tip. Aceita letra, digito, hifen e sublinhado.'
);
end;
/
begin
wwv_flow_imp.component_end;
end;
/
