#!/usr/bin/env node
"use strict";

const http = require("http");

const marpPort = Number(process.argv[2]);
const wrapperPort = Number(process.argv[3]);
const marpHost = process.argv[4] || "127.0.0.1";

if (!marpPort || !wrapperPort) {
  console.error("usage: node server.js <marp-port> <wrapper-port> [marp-host]");
  process.exit(1);
}

const MARP_PREFIX = "/marp";
const CLOSE_KEY = "marp-close";
const CLOSE_MESSAGE = "marp-close";

/** @type {import("http").ServerResponse[]} */
let clients = [];

const INJECT_SCRIPT = `<script>(function(){
  var KEY=${JSON.stringify(CLOSE_KEY)};
  var MSG=${JSON.stringify(CLOSE_MESSAGE)};
  var popups=[];
  var origOpen=window.open;
  window.open=function(){
    var w=origOpen.apply(this,arguments);
    if(w)popups.push(w);
    return w;
  };
  function shutdown(){
    popups.forEach(function(w){try{w.close();}catch(e){}});
    popups=[];
    try{window.close();}catch(e){}
  }
  window.addEventListener("message",function(e){
    if(e.data&&e.data.type===MSG)shutdown();
  });
  window.addEventListener("storage",function(e){
    if(e.key===KEY)shutdown();
  });
})();<\/script>`;

function previewHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Marp Preview</title>
  <style>
    html, body { margin: 0; height: 100%; overflow: hidden; background: #111; }
    iframe { width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe src="${MARP_PREFIX}/" title="Marp preview"></iframe>
  <script>
    const source = new EventSource("/events");
    const closeMessage = ${JSON.stringify({ type: CLOSE_MESSAGE })};
    const closeKey = ${JSON.stringify(CLOSE_KEY)};

    function closePreview() {
      source.close();
      const iframe = document.querySelector("iframe");
      try {
        localStorage.setItem(closeKey, String(Date.now()));
        localStorage.removeItem(closeKey);
      } catch (_) {}
      try {
        iframe?.contentWindow?.postMessage(closeMessage, "*");
      } catch (_) {}
      window.close();
      setTimeout(function () {
        if (!document.hidden) {
          document.body.innerHTML =
            '<p style="color:#888;text-align:center;margin-top:40vh;font:16px sans-serif">Marp preview closed. You can close this tab.</p>';
          try { iframe?.remove(); } catch (_) {}
        }
      }, 150);
    }

    source.addEventListener("close", closePreview);
    source.onerror = function () {
      source.close();
    };
  </script>
</body>
</html>`;
}

function writeEvent(res, event, data) {
  res.write(`event: ${event}\ndata: ${data || ""}\n\n`);
}

function notifyClose() {
  for (const client of clients) {
    try {
      writeEvent(client, "close", "{}");
      client.end();
    } catch (_) {
      // client may already be gone
    }
  }
  clients = [];
}

function marpUpstreamPath(urlPath) {
  if (urlPath === MARP_PREFIX) {
    return "/";
  }
  if (urlPath.startsWith(MARP_PREFIX + "/")) {
    const upstream = urlPath.slice(MARP_PREFIX.length);
    return upstream === "" ? "/" : upstream;
  }
  return null;
}

function rewriteLocation(location) {
  try {
    const parsed = new URL(location, `http://${marpHost}:${marpPort}`);
    if (parsed.hostname === marpHost && Number(parsed.port || 80) === marpPort) {
      return `${MARP_PREFIX}${parsed.pathname}${parsed.search}${parsed.hash}`;
    }
  } catch (_) {
    if (location.startsWith("/")) {
      return `${MARP_PREFIX}${location}`;
    }
  }
  return location;
}

function injectIntoHtml(body) {
  const baseTag = `<base href="${MARP_PREFIX}/">`;
  if (/<base\s/i.test(body)) {
    return body.replace(/<\/body>/i, `${INJECT_SCRIPT}</body>`);
  }
  if (/<\/head>/i.test(body)) {
    return body.replace(/<\/head>/i, `${baseTag}${INJECT_SCRIPT}</head>`);
  }
  if (/<\/body>/i.test(body)) {
    return body.replace(/<\/body>/i, `${INJECT_SCRIPT}</body>`);
  }
  return body + INJECT_SCRIPT;
}

function filterRequestHeaders(headers) {
  const filtered = { ...headers };
  delete filtered.host;
  delete filtered.connection;
  return filtered;
}

function filterResponseHeaders(headers) {
  const filtered = { ...headers };
  delete filtered.connection;
  delete filtered["transfer-encoding"];
  return filtered;
}

function proxyToMarp(req, res, upstreamPath) {
  const queryIndex = (req.url || "").indexOf("?");
  const query = queryIndex >= 0 ? (req.url || "").slice(queryIndex) : "";

  const proxyReq = http.request(
    {
      hostname: marpHost,
      port: marpPort,
      path: upstreamPath + query,
      method: req.method,
      headers: filterRequestHeaders(req.headers),
    },
    (proxyRes) => {
      const headers = filterResponseHeaders(proxyRes.headers);
      const contentType = headers["content-type"] || "";

      if (proxyRes.statusCode >= 300 && proxyRes.statusCode < 400 && headers.location) {
        headers.location = rewriteLocation(headers.location);
        res.writeHead(proxyRes.statusCode, headers);
        res.end();
        proxyRes.resume();
        return;
      }

      if (!contentType.includes("text/html")) {
        res.writeHead(proxyRes.statusCode, headers);
        proxyRes.pipe(res);
        return;
      }

      const chunks = [];
      proxyRes.on("data", (chunk) => chunks.push(chunk));
      proxyRes.on("end", () => {
        const body = injectIntoHtml(Buffer.concat(chunks).toString("utf8"));
        delete headers["content-length"];
        res.writeHead(proxyRes.statusCode, headers);
        res.end(body);
      });
    }
  );

  proxyReq.on("error", () => {
    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "text/plain" });
    }
    res.end("marp proxy error");
  });

  req.pipe(proxyReq);
}

const server = http.createServer((req, res) => {
  const urlPath = (req.url || "").split("?")[0];

  if (req.method === "GET" && urlPath === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(previewHtml());
    return;
  }

  if (req.method === "GET" && urlPath === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(": connected\n\n");
    clients.push(res);
    req.on("close", () => {
      clients = clients.filter((client) => client !== res);
    });
    return;
  }

  if (req.method === "POST" && urlPath === "/close") {
    notifyClose();
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }

  const upstreamPath = marpUpstreamPath(urlPath);
  if (upstreamPath !== null) {
    proxyToMarp(req, res, upstreamPath);
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("not found");
});

server.listen(wrapperPort, "127.0.0.1", () => {
  process.stdout.write(`ready:${wrapperPort}\n`);
});

function shutdown() {
  notifyClose();
  server.close(() => process.exit(0));
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
