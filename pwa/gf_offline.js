/* Gestor Financeiro - camada offline.
   Carregado em toda pagina do app pela Global Page 0. Responsabilidades:
     - manter no IndexedDB um retrato das categorias/origens/lancamentos recentes,
       para a offline page ter o que mostrar sem rede;
     - drenar a fila de lancamentos criados offline quando a rede voltar.
   A offline page (embutida no sw.js pela Text Message APEX.PWA.OFFLINE.BODY) escreve na
   MESMA base e no MESMO store, entao os nomes abaixo sao contrato entre os dois lados. */
(function () {
  "use strict";

  var DB_NOME = "gf_offline";
  var DB_VERSAO = 1;
  var ST_CFG = "cfg";     // keyPath k: guarda o retrato sob a chave "snapshot"
  var ST_FILA = "fila";   // keyPath external_id: lancamentos criados offline

  function abrirDb() {
    return new Promise(function (ok, erro) {
      var req = indexedDB.open(DB_NOME, DB_VERSAO);
      req.onupgradeneeded = function (e) {
        var db = e.target.result;
        if (!db.objectStoreNames.contains(ST_CFG)) { db.createObjectStore(ST_CFG, { keyPath: "k" }); }
        if (!db.objectStoreNames.contains(ST_FILA)) { db.createObjectStore(ST_FILA, { keyPath: "external_id" }); }
      };
      req.onsuccess = function () { ok(req.result); };
      req.onerror = function () { erro(req.error); };
    });
  }

  function tx(db, store, modo, fn) {
    return new Promise(function (ok, erro) {
      var t = db.transaction(store, modo);
      var req = fn(t.objectStore(store));
      t.oncomplete = function () { ok(req && req.result); };
      t.onerror = function () { erro(t.error); };
      t.onabort = function () { erro(t.error); };
    });
  }

  function lerFila(db) {
    return tx(db, ST_FILA, "readonly", function (s) { return s.getAll(); });
  }

  /* apex.server.process com teto de tempo proprio: em sinal fraco a requisicao nao falha,
     ela pendura - e uma fila que nunca termina de drenar e pior que uma que falha rapido. */
  function chamar(processo, dados, ms) {
    return new Promise(function (ok, erro) {
      apex.server.process(processo, dados, {
        dataType: "json",
        timeout: ms || 15000,
        success: ok,
        error: function (jqXHR, textStatus) {
          // resposta que nao e JSON normalmente e a pagina de login: sessao morreu
          erro(new Error(textStatus === "parsererror" ? "sessao expirada" : textStatus));
        }
      });
    });
  }

  function baixarSnapshot(db) {
    return chamar("OFFLINE_SNAPSHOT", {}, 20000).then(function (r) {
      if (!r || !r.ok) { throw new Error((r && r.erro) || "snapshot recusado"); }
      return tx(db, ST_CFG, "readwrite", function (s) {
        return s.put({ k: "snapshot", baixado_em: new Date().toISOString(), dados: r });
      });
    });
  }

  /* Drena a fila em lotes. Item com status criado ou duplicado sai da fila; os dois
     significam "esta gravado no servidor". Item com erro fica, para tentar de novo. */
  function drenar(db) {
    return lerFila(db).then(function (itens) {
      if (!itens || !itens.length) { return { criados: 0, duplicados: 0, pendentes: 0 }; }
      var lote = itens.slice(0, 20);
      return chamar("OFFLINE_PUSH", { x01: JSON.stringify({ itens: lote }) }, 30000)
        .then(function (r) {
          if (!r || !r.ok) { throw new Error((r && r.erro) || "push recusado"); }
          var remover = (r.resultados || [])
            .filter(function (x) { return x.status === "criado" || x.status === "duplicado"; })
            .map(function (x) { return x.external_id; });
          if (!remover.length) { return r; }
          return tx(db, ST_FILA, "readwrite", function (s) {
            remover.forEach(function (id) { s.delete(id); });
            return null;
          }).then(function () { return r; });
        });
    });
  }

  function pintarBadge(qtd) {
    var el = document.getElementById("gfOfflinePendentes");
    if (!qtd) { if (el) { el.remove(); } return; }
    if (!el) {
      el = document.createElement("div");
      el.id = "gfOfflinePendentes";
      el.className = "gf-offline-badge";
      document.body.appendChild(el);
    }
    el.textContent = qtd === 1 ? "1 lancamento aguardando envio" : qtd + " lancamentos aguardando envio";
  }

  var rodando = false;

  function sincronizar(forcarSnapshot) {
    if (rodando || !navigator.onLine) { return Promise.resolve(); }
    rodando = true;
    var dbRef;
    return abrirDb()
      .then(function (db) {
        dbRef = db;
        return drenar(db).catch(function (e) {
          apex.debug.warn("gf_offline: drenar falhou: " + e.message);
        });
      })
      .then(function () {
        if (!forcarSnapshot) { return null; }
        return baixarSnapshot(dbRef).catch(function (e) {
          apex.debug.warn("gf_offline: snapshot falhou: " + e.message);
        });
      })
      .then(function () { return lerFila(dbRef); })
      .then(function (itens) { pintarBadge(itens ? itens.length : 0); })
      .catch(function (e) { apex.debug.warn("gf_offline: " + e.message); })
      .then(function () { rodando = false; });
  }

  /* Nao existe Background Sync em nenhum navegador do iOS, entao o motor de drenagem mora
     na pagina: carga, volta da rede e volta do foco. Nao em unload, que deixou de ser
     confiavel em mobile. */
  window.addEventListener("online", function () { sincronizar(false); });
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") { sincronizar(false); }
  });

  if (window.apex && apex.jQuery) {
    apex.jQuery(function () { sincronizar(true); });
  } else {
    window.addEventListener("load", function () { sincronizar(true); });
  }

  window.gfOffline = { sincronizar: sincronizar, abrirDb: abrirDb, lerFila: lerFila };
})();
