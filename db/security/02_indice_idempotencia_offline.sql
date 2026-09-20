set define off
-- Idempotencia do replay da fila offline. O FIN_LAN_EXT_IX existente e NAO-UNICO, entao sem
-- isto um replay duplicado grava duplicata em silencio. Function-based para valer so nas
-- linhas de origem PWA_OFFLINE: as demais indexam NULL e nao entram no indice.
create unique index admin.fin_lan_pwa_ext_uk
    on admin.fin_lancamentos (case when external_source = 'PWA_OFFLINE' then external_id end);
