/* Lien avec le plugin Stream Deck, sur ce PC seulement (127.0.0.1).

   - Tout ce qui lit ou change la lecture demande la clé d'association (lue
     par le plugin dans les réglages de Sona), ou l'en-tête `X-Sona-Local`
     envoyé par une app de la machine.
   - Le serveur n'écoute que la machine elle-même : rien du réseau.
   - L'état part en direct (Server-Sent Events) : le plugin voit tout de
     suite un titre changé, sans redemander sans cesse. */

const http = require("node:http");
const crypto = require("node:crypto");

const MAX_BODY = 16 * 1024;

function sameKey(given, key) {
  if (!given || !key) return false;
  const a = Buffer.from(String(given));
  const b = Buffer.from(String(key));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

class RemoteServer {
  /**
   * @param {object} o
   * @param {() => object|null} o.getState  état de lecture à envoyer
   * @param {(body: object) => Promise<any>} o.command  commande du plugin
   * @param {(clients: object[]) => void} o.onClients  apps connectées
   */
  constructor({ getState, command, onClients }) {
    Object.assign(this, { getState, command, onClients });
    this.server = null;
    this.port = 0;
    this.key = "";
    this.error = null;
    this.clients = new Set();
  }

  get running() { return !!this.server; }

  async start(port, key) {
    await this.stop();
    this.key = key;
    this.error = null;
    // Port réglé, puis les suivants, puis un port libre au hasard : sous
    // Windows, Hyper-V, WSL ou Docker réservent souvent des plages entières
    // (erreur EACCES, pas EADDRINUSE). Le port obtenu est gardé dans les
    // réglages (`remoteActivePort`), où le plugin Stream Deck le lit.
    const candidates = port ? [...Array.from({ length: 20 }, (_, i) => port + i), 0] : [0];
    let last = null;
    for (const p of candidates) {
      try {
        this.server = await this.listen(p);
        this.port = this.server.address().port;
        return true;
      } catch (e) {
        this.server = null;
        last = e;
        if (!["EADDRINUSE", "EACCES", "EADDRNOTAVAIL"].includes(e.code)) break;
      }
    }
    this.error = `Impossible d'ouvrir le lien Stream Deck : ${last?.code || last?.message || "port indisponible"}`;
    return false;
  }

  listen(port) {
    return new Promise((resolve, reject) => {
      const server = http.createServer((req, res) => this.handle(req, res).catch(() => {
        if (!res.headersSent) res.writeHead(500);
        res.end();
      }));
      server.keepAliveTimeout = 30_000;
      server.once("error", reject);
      server.listen(port, "127.0.0.1", () => {
        server.off("error", reject);
        resolve(server);
      });
    });
  }

  async stop() {
    for (const c of this.clients) c.res.end();
    this.clients.clear();
    this.notifyClients();
    if (!this.server) return;
    const server = this.server;
    this.server = null;
    const closed = new Promise((r) => server.close(() => r()));
    server.closeAllConnections();
    await closed;
  }

  notifyClients() {
    this.onClients?.([...this.clients].map((c) => ({ name: c.name, since: c.since })));
  }

  /** Envoie l'état à toutes les apps connectées. */
  broadcast(state) {
    if (!this.clients.size) return;
    const data = `event: state\ndata: ${JSON.stringify(state)}\n\n`;
    for (const c of this.clients) c.res.write(data);
  }

  async handle(req, res) {
    const url = new URL(req.url, "http://local");
    const route = url.pathname;
    res.setHeader("X-Content-Type-Options", "nosniff");
    if (!route.startsWith("/api/")) { res.writeHead(404); return res.end(); }
    const given = req.headers["x-sona-key"] || url.searchParams.get("k");
    if (!sameKey(given, this.key) && !this.isLocalApp(req)) return this.json(res, 401, { error: "Réservé au plugin Stream Deck de ce PC." });
    if (route === "/api/state" && req.method === "GET") return this.json(res, 200, this.getState() || {});
    if (route === "/api/events" && req.method === "GET") return this.events(req, res);
    if (route === "/api/command" && req.method === "POST") {
      let body;
      try { body = JSON.parse(await readBody(req)); } catch { return this.json(res, 400, { error: "Requête illisible." }); }
      if (!body || typeof body.action !== "string") return this.json(res, 400, { error: "Action manquante." });
      try {
        const result = await this.command(body);
        return this.json(res, 200, { ok: true, result: result ?? null });
      } catch (e) {
        return this.json(res, 503, { error: e.message || "Sona ne répond pas." });
      }
    }
    return this.json(res, 404, { error: "Inconnu." });
  }

  /**
   * Une app de ce PC : acceptée sans clé, au cas où elle ne peut pas lire les
   * réglages de Sona. Avec l'en-tête `X-Sona-Local` (une page web ne peut pas
   * l'envoyer sans autorisation préalable, que ce serveur ne donne jamais) et
   * l'adresse 127.0.0.1 / localhost (pas de « DNS rebinding »).
   */
  isLocalApp(req) {
    const host = String(req.headers.host || "").replace(/:\d+$/, "").replace(/^\[|\]$/g, "");
    return !!req.headers["x-sona-local"] && ["127.0.0.1", "localhost", "::1"].includes(host);
  }

  events(req, res) {
    res.writeHead(200, {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    });
    // Plugin parti sans prévenir : une écriture tardive ne doit jamais faire tomber l'app.
    res.on("error", () => {});
    res.write("retry: 2000\n\n");
    const named = new URL(req.url, "http://local").searchParams.get("name") || "";
    const name = named.replace(/[^\p{L}\p{N} ._'-]/gu, "").slice(0, 30);
    const client = { res, name: name || "Appareil", since: Date.now() };
    this.clients.add(client);
    this.notifyClients();
    const state = this.getState();
    if (state) res.write(`event: state\ndata: ${JSON.stringify(state)}\n\n`);
    const ping = setInterval(() => res.write(": ping\n\n"), 15_000);
    req.on("close", () => {
      clearInterval(ping);
      this.clients.delete(client);
      this.notifyClients();
    });
  }

  json(res, status, body) {
    res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
    res.end(JSON.stringify(body));
  }
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) { reject(new Error("Trop gros")); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

module.exports = { RemoteServer };
