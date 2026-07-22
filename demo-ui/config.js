// config.js — single source for env-derived config. Defaults MIRROR the existing
// scripts (get-token.sh, demo.sh) so the UI and the CLI behave identically.
// Sensitive values are used server-side only; never serialized to the browser.

const env = process.env;

export const config = {
  kongUrl:         env.KONG_URL              || "http://localhost:8000",
  keycloakBase:    env.KEYCLOAK_BASE         || "http://localhost:8080",
  realm:           env.KEYCLOAK_REALM        || "cox-auto",
  demoCliId:       env.DEMO_CLI_CLIENT_ID    || "demo-cli",
  demoCliSecret:   env.DEMO_CLI_SECRET       || "demo-cli-secret-change-me",
  demoPassword:    env.DEMO_PASSWORD         || "Demo1234!",
  exchangeClientId: env.KONG_EXCHANGE_CLIENT_ID || "kong-exchange",
  exchangeSecret:  env.KONG_EXCHANGE_SECRET  || "kong-exchange-secret-change-me",
  konnectToken:    env.KONNECT_TOKEN         || "",
  konnectRegion:   env.KONNECT_REGION        || "us",
  registryId:      env.KONNECT_MCP_REGISTRY_ID || "",
  dashboardId:     env.KONNECT_DASHBOARD_ID  || "",
  uiPort:          Number(env.UI_PORT) || 4000,
};

// Persona Contract — mirrors get-token.sh:46-50.
export const personas = {
  dana:   { username: "dana.dealer",   group: "dealers", scope: "openid dealers:read mcp:use" },
  frank:  { username: "frank.finance", group: "finance", scope: "openid finance:read mcp:use" },
  olivia: { username: "olivia.ops",    group: "ops",     scope: "openid dealers:read finance:read mcp:use" },
};

// tokenUrl helper (used by keycloak.js).
export const tokenUrl = () =>
  `${config.keycloakBase}/realms/${config.realm}/protocol/openid-connect/token`;
