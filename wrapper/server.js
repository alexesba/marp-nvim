#!/usr/bin/env node
"use strict";

const http = require("http");

const marpPort = Number(process.argv[2]);
const wrapperPort = Number(process.argv[3]);

if (!marpPort || !wrapperPort) {
  console.error("usage: node server.js <marp-port> <wrapper-port>");
  process.exit(1);
}

/** @type {import("http").ServerResponse[]} */
let clients = [];

function previewHtml() {
  const marpUrl = `http://127.0.0.1:${marpPort}/`;
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
  <iframe src="${marpUrl}" title="Marp preview"></iframe>
  <script>
    const source = new EventSource("/events");
    source.addEventListener("close", function () {
      source.close();
      window.close();
    });
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

const server = http.createServer((req, res) => {
  const path = (req.url || "").split("?")[0];

  if (req.method === "GET" && path === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(previewHtml());
    return;
  }

  if (req.method === "GET" && path === "/events") {
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

  if (req.method === "POST" && path === "/close") {
    notifyClose();
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
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
