import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

const testSecrets = {
  APPLE_CLIENT_ID: "com.example.StarCompanion",
  APPLE_TEAM_ID: "TEAMID1234",
  APPLE_KEY_ID: "KEYID12345",
  APPLE_PRIVATE_KEY: [
    "-----BEGIN PRIVATE KEY-----",
    "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgIGU2D374Y+vlvS1u",
    "fiwDJiDpUo6va8YDImH2cJF+5Z+hRANCAAQvqOKp5vIujFtcjbv08c24rumdv7l1",
    "05eg1wi4B8tc3yrxYsU02ty7At1rA1VTE+opzeyU0wvINyP7NMAD9bdl",
    "-----END PRIVATE KEY-----",
  ].join("\n") + "\n",
  APPLE_REFRESH_TOKEN_ENCRYPTION_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  AUTH_RATE_LIMIT_SALT: "test-only-rate-limit-salt-at-least-thirty-two-bytes",
};

for (const [name, value] of Object.entries(testSecrets)) {
  process.env[name] ??= value;
}

export default defineConfig({
  plugins: [
    cloudflareTest(async () => {
      const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
      return {
        wrangler: { configPath: "./wrangler.jsonc" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            ...testSecrets,
          },
        },
      };
    }),
  ],
  test: {
    setupFiles: ["./test/apply-migrations.ts", "./test/setup-network.ts"],
  },
});
