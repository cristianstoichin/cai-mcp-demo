// keycloak.js — mint persona tokens (ROPC), reproduce the RFC 8693 exchange,
// decode JWTs for display. Mirrors get-token.sh + the Phase-5 exchange (NOTES.md):
// exchange requests SCOPES only (Keycloak's audience param must name a client),
// and the subject token must carry kong-exchange in aud (mcp:use provides it).

import { config, personas, tokenUrl } from "./config.js";

export function decodeJwt(jwt) {
  const part = String(jwt).split(".")[1];
  if (!part) throw new Error("not a JWT");
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const json = Buffer.from(b64, "base64").toString("utf8");
  return JSON.parse(json);
}

async function postForm(body, errCtx) {
  const res = await fetch(tokenUrl(), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(`${errCtx}: ${data.error_description || data.error || res.status}`);
  }
  return data.access_token;
}

export async function mintToken(persona, scopeOverride) {
  const p = personas[persona];
  if (!p) throw new Error(`unknown persona: ${persona}`);
  const scope = scopeOverride || p.scope;
  const accessToken = await postForm({
    grant_type: "password",
    client_id: config.demoCliId,
    client_secret: config.demoCliSecret,
    username: p.username,
    password: config.demoPassword,
    scope,
  }, "token request failed");
  return { accessToken, claims: decodeJwt(accessToken) };
}

export async function exchangeToken(subjectToken, scopes = "dealers:read finance:read") {
  // RFC 8693 standard exchange (Keycloak V2). NOTE: request scopes only — the
  // scope mappers add aud:[dealer-api,finance-api]; passing audience= would fail
  // (that param must name a registered client). See NOTES.md Phase-5 RESOLVED.
  const accessToken = await postForm({
    grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
    client_id: config.exchangeClientId,
    client_secret: config.exchangeSecret,
    subject_token: subjectToken,
    subject_token_type: "urn:ietf:params:oauth:token-type:access_token",
    scope: scopes,
  }, "token exchange failed");
  return { accessToken, claims: decodeJwt(accessToken) };
}
