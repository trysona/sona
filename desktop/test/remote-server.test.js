/* Lien Stream Deck : sur ce PC seulement, commandes relayées à Sona, état en
   direct. Sans Electron (node --test). */

const test = require("node:test");
const assert = require("node:assert/strict");
const os = require("node:os");
const { RemoteServer } = require("../src/remote-server");

const KEY = "cle-de-test-0123456789";

async function withServer(fn, { command = async () => true } = {}) {
  const seen = [];
  const names = [];
  const server = new RemoteServer({
    getState: () => ({ track: { title: "Titre", artist: "Artiste" }, paused: false }),
    command: async (body) => { seen.push(body); return command(body); },
    onClients: (list) => names.push(...list.map((c) => c.name)),
  });
  assert.equal(await server.start(0, KEY), true);
  try {
    await fn(`http://127.0.0.1:${server.port}`, { server, seen, names });
  } finally {
    await server.stop();
  }
}

test("l'état demande la clé, rien d'autre n'est servi", () => withServer(async (base) => {
  assert.equal((await fetch(`${base}/`)).status, 404);
  assert.equal((await fetch(`${base}/api/state`)).status, 401);
  assert.equal((await fetch(`${base}/api/state`, { headers: { "X-Sona-Key": "mauvaise" } })).status, 401);
  const state = await fetch(`${base}/api/state`, { headers: { "X-Sona-Key": KEY } });
  assert.equal(state.status, 200);
  assert.equal((await state.json()).track.title, "Titre");
}));

test("le serveur n'écoute que ce PC", () => withServer(async (base, { server }) => {
  assert.equal(server.server.address().address, "127.0.0.1");
  const lan = Object.values(os.networkInterfaces()).flat().find((a) => a && a.family === "IPv4" && !a.internal);
  if (lan) await assert.rejects(fetch(`http://${lan.address}:${server.port}/api/state`, { signal: AbortSignal.timeout(1500) }));
}));

test("les commandes passent à Sona et renvoient sa réponse", () => withServer(async (base, { seen }) => {
  const res = await fetch(`${base}/api/command`, {
    method: "POST", headers: { "X-Sona-Key": KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ action: "next" }),
  });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, result: true });
  assert.deepEqual(seen, [{ action: "next" }]);
  const bad = await fetch(`${base}/api/command`, { method: "POST", headers: { "X-Sona-Key": KEY }, body: "pas du json" });
  assert.equal(bad.status, 400);
}));

test("port réservé par Windows (EACCES) : le suivant est pris", async () => {
  const server = new RemoteServer({ getState: () => ({}), command: async () => true });
  const real = server.listen.bind(server);
  let calls = 0;
  server.listen = (port) => (++calls === 1 ? Promise.reject(Object.assign(new Error("listen EACCES"), { code: "EACCES" })) : real(0));
  try {
    assert.equal(await server.start(47650, KEY), true);
    assert.equal(calls, 2);
    assert.ok(server.port > 0);
  } finally {
    await server.stop();
  }
});

test("une app de ce PC (Stream Deck) passe sans clé, une page web non", () => withServer(async (base, { names }) => {
  const local = await fetch(`${base}/api/state`, { headers: { "X-Sona-Local": "streamdeck" } });
  assert.equal(local.status, 200);
  // Avec l'en-tête mais une autre adresse (DNS rebinding) : refusé.
  const http = require("node:http");
  const port = new URL(base).port;
  const status = await new Promise((resolve) => {
    http.get({ host: "127.0.0.1", port, path: "/api/state", headers: { Host: `evil.example:${port}`, "X-Sona-Local": "1" } }, (res) => { res.resume(); resolve(res.statusCode); });
  });
  assert.equal(status, 401);
  // Le client se présente sous son nom, et reçoit l'état en direct.
  const controller = new AbortController();
  const res = await fetch(`${base}/api/events?name=Stream%20Deck`, { headers: { "X-Sona-Local": "streamdeck" }, signal: controller.signal });
  assert.equal(res.status, 200);
  const reader = res.body.getReader();
  await reader.read();
  assert.ok(names.includes("Stream Deck"));
  controller.abort();
}));
