#!/usr/bin/env node
"use strict";

const http = require("http");
const https = require("https");

const marpPort = Number(process.argv[2]);
const wrapperPort = Number(process.argv[3]);
const marpHost = process.argv[4] || "127.0.0.1";
const bindHost = process.argv[5] || "127.0.0.1";

if (!marpPort || !wrapperPort) {
  console.error("usage: node server.js <marp-port> <wrapper-port> [marp-host] [bind-host]");
  process.exit(1);
}

const MARP_PREFIX = "/marp";
const CDN_PROXY_PREFIX = "/marp-cdn/";
const WATCH_NOTIFIER_PREFIX = "/.__marp-cli-watch-notifier__";
const CLOSE_MESSAGE = "marp-close";

/** @type {import("http").ServerResponse[]} */
let clients = [];

const INJECT_SCRIPT = `<script>(function(){
  try{
    function storageShim(){
      return{getItem:function(){return null},setItem:function(){},removeItem:function(){},clear:function(){},key:function(){return null},length:0};
    }
    Object.defineProperty(window,"sessionStorage",{get:storageShim,configurable:true});
    Object.defineProperty(window,"localStorage",{get:storageShim,configurable:true});
  }catch(e){}
  var MSG=${JSON.stringify(CLOSE_MESSAGE)};
  var closing=false;
  var popups=[];
  var OrigWS=window.WebSocket;
  window.WebSocket=function(url,protocols){
    var ws=protocols!==undefined?new OrigWS(url,protocols):new OrigWS(url);
    var origAdd=ws.addEventListener.bind(ws);
    ws.addEventListener=function(type,listener,options){
      if(type==="close"){
        return origAdd(type,function(ev){
          if(!closing)listener(ev);
        },options);
      }
      return origAdd(type,listener,options);
    };
    return ws;
  };
  window.WebSocket.prototype=OrigWS.prototype;
  window.WebSocket.CONNECTING=OrigWS.CONNECTING;
  window.WebSocket.OPEN=OrigWS.OPEN;
  window.WebSocket.CLOSING=OrigWS.CLOSING;
  window.WebSocket.CLOSED=OrigWS.CLOSED;
  var origOpen=window.open;
  window.open=function(){
    var w=origOpen.apply(this,arguments);
    if(w)popups.push(w);
    return w;
  };
  function shutdown(){
    if(closing)return;
    closing=true;
    delete window.__marpCliWatchWS;
    try{
      var id=setTimeout(function(){},0);
      for(var i=0;i<=id;i++)clearTimeout(i);
    }catch(e){}
    popups.forEach(function(w){
      try{
        w.__marpPreviewShutdown?.();
        w.postMessage({type:MSG},"*");
        w.close();
      }catch(e){}
    });
    popups=[];
    try{
      document.documentElement.innerHTML="<html><head><title>Marp Preview Closed</title></head><body style=\\"margin:0;background:#1a1a1a;color:#ccc;font:16px sans-serif;display:flex;align-items:center;justify-content:center;height:100vh\\">Marp preview closed.</body></html>";
    }catch(e){}
    try{window.close();}catch(e){}
  }
  window.__marpPreviewShutdown=shutdown;
  window.addEventListener("message",function(e){
    if(e.data&&e.data.type===MSG)shutdown();
  });
})();<\/script>`;

function previewHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Marp Preview</title>
  <style>
    html, body { margin: 0; height: 100%; overflow: hidden; background: #1a1a1a; }
    iframe { width: 100%; height: 100%; border: 0; background: #fff; }
    #loading {
      position: fixed;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #1a1a1a;
      color: #aaa;
      font: 16px sans-serif;
      z-index: 1;
      pointer-events: none;
    }
    #loading.hidden { display: none; }
  </style>
</head>
<body>
  <iframe src="${MARP_PREFIX}/" title="Marp preview"></iframe>
  <p id="loading">Loading Marp preview...</p>
  <script>
    const iframe = document.querySelector("iframe");
    const loading = document.getElementById("loading");
    iframe.addEventListener("load", function () {
      loading.classList.add("hidden");
    });
    setTimeout(function () {
      if (!loading.classList.contains("hidden")) {
        loading.textContent = "Preview is taking longer than expected. Is :MarpStart still running?";
      }
    }, 10000);
    const source = new EventSource("/events");
    const closeMessage = ${JSON.stringify({ type: CLOSE_MESSAGE })};

    function closePreview() {
      source.close();
      const iframe = document.querySelector("iframe");
      try {
        iframe?.contentWindow?.__marpPreviewShutdown?.();
      } catch (_) {}
      try {
        iframe?.contentWindow?.postMessage(closeMessage, "*");
      } catch (_) {}
      document.body.innerHTML =
        '<p style="color:#ccc;text-align:center;margin-top:40vh;font:16px sans-serif">Marp preview closed. You can close this tab.</p>';
      document.body.style.background = "#1a1a1a";
      window.close();
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

function isWatchNotifierPath(urlPath) {
  return (
    urlPath === WATCH_NOTIFIER_PREFIX ||
    urlPath.startsWith(WATCH_NOTIFIER_PREFIX + "/")
  );
}

function marpUpstreamPath(urlPath) {
  if (urlPath === MARP_PREFIX) {
    return "/";
  }
  if (urlPath.startsWith(MARP_PREFIX + "/")) {
    const upstream = urlPath.slice(MARP_PREFIX.length);
    return upstream === "" ? "/" : upstream;
  }
  if (isWatchNotifierPath(urlPath)) {
    return urlPath;
  }
  return null;
}

function writeRawHeaders(socket, statusLine, headers) {
  const lines = [statusLine];
  for (const [key, value] of Object.entries(headers)) {
    if (value === undefined) {
      continue;
    }
    if (Array.isArray(value)) {
      for (const entry of value) {
        lines.push(`${key}: ${entry}`);
      }
    } else {
      lines.push(`${key}: ${value}`);
    }
  }
  socket.write(`${lines.join("\r\n")}\r\n\r\n`);
}

function proxyWebSocket(req, clientSocket, head) {
  const headers = { ...req.headers, host: `${marpHost}:${marpPort}` };
  delete headers["proxy-connection"];

  const proxyReq = http.request({
    hostname: marpHost,
    port: marpPort,
    path: req.url,
    method: req.method,
    headers,
  });

  proxyReq.on("upgrade", (proxyRes, proxySocket, proxyHead) => {
    writeRawHeaders(
      clientSocket,
      `HTTP/1.1 ${proxyRes.statusCode} ${proxyRes.statusMessage}`,
      proxyRes.headers
    );
    if (proxyHead.length) {
      clientSocket.write(proxyHead);
    }
    if (head.length) {
      proxySocket.write(head);
    }
    proxySocket.pipe(clientSocket);
    clientSocket.pipe(proxySocket);
  });

  proxyReq.on("response", (proxyRes) => {
    writeRawHeaders(
      clientSocket,
      `HTTP/1.1 ${proxyRes.statusCode} ${proxyRes.statusMessage}`,
      proxyRes.headers
    );
    proxyRes.pipe(clientSocket);
  });

  proxyReq.on("error", () => {
    clientSocket.destroy();
  });

  clientSocket.on("error", () => {
    proxyReq.destroy();
  });

  proxyReq.end();
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

function rewriteCdnUrls(body) {
  return body.replace(/https:\/\/cdn\.jsdelivr\.net\//g, `${CDN_PROXY_PREFIX}cdn.jsdelivr.net/`);
}

function injectIntoHtml(body) {
  body = rewriteCdnUrls(body);
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

function cdnUpstreamPath(urlPath) {
  if (urlPath.startsWith(CDN_PROXY_PREFIX)) {
    return urlPath.slice(CDN_PROXY_PREFIX.length);
  }
  return null;
}

function proxyToCdn(req, res, upstreamPath) {
  const queryIndex = (req.url || "").indexOf("?");
  const query = queryIndex >= 0 ? (req.url || "").slice(queryIndex) : "";
  const target = `https://${upstreamPath}${query}`;

  https
    .get(target, (proxyRes) => {
      const headers = filterResponseHeaders(proxyRes.headers);
      res.writeHead(proxyRes.statusCode || 502, headers);
      proxyRes.pipe(res);
    })
    .on("error", () => {
      if (!res.headersSent) {
        res.writeHead(502, { "Content-Type": "text/plain" });
      }
      res.end("cdn proxy error");
    });
}

function rewriteProxiedBody(body, contentType) {
  if (contentType.includes("text/html")) {
    return injectIntoHtml(body);
  }
  if (contentType.includes("text/css") || contentType.includes("javascript")) {
    return rewriteCdnUrls(body);
  }
  return body;
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

      if (!contentType.includes("text/html") && !contentType.includes("text/css") && !contentType.includes("javascript")) {
        res.writeHead(proxyRes.statusCode, headers);
        proxyRes.pipe(res);
        return;
      }

      const chunks = [];
      proxyRes.on("data", (chunk) => chunks.push(chunk));
      proxyRes.on("end", () => {
        const body = rewriteProxiedBody(Buffer.concat(chunks).toString("utf8"), contentType);
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

  const cdnPath = cdnUpstreamPath(urlPath);
  if (cdnPath !== null) {
    proxyToCdn(req, res, cdnPath);
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("not found");
});

server.on("upgrade", (req, socket, head) => {
  const urlPath = (req.url || "").split("?")[0];
  if (!isWatchNotifierPath(urlPath)) {
    socket.destroy();
    return;
  }
  proxyWebSocket(req, socket, head);
});

server.listen(wrapperPort, bindHost, () => {
  process.stdout.write(`ready:${wrapperPort}\n`);
});

function shutdown() {
  notifyClose();
  server.close(() => process.exit(0));
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
