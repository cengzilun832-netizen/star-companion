// Apple auth remains fail-closed until every secret is installed with
// `wrangler secret put`. Keeping these bindings optional allows the snapshot
// API to be deployed first without putting placeholders in configuration.
interface OptionalAppleAuthBindings {
  APPLE_CLIENT_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_PRIVATE_KEY?: string;
  APPLE_REFRESH_TOKEN_ENCRYPTION_KEY?: string;
  AUTH_RATE_LIMIT_SALT?: string;
}

interface Env extends OptionalAppleAuthBindings {}

declare namespace Cloudflare {
  interface Env extends OptionalAppleAuthBindings {}
}
