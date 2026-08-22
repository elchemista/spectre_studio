import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :spectre_studio, SpectreStudioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "FTx5ZhTlkl0TA94mWXMTIKDFE7Gr5fNEuFtD6DjZRqcr0S3JYzrGTT7F0uU8nso5",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Tests get their own vault file so a run never inherits another's state.
config :spectre_studio,
  vault_key: "DrCdjc1835Et5J+DVL3NyMUHzaSld7Sl97XgdiJ55bk=",
  vault_path: Path.expand("../tmp/test-vault.dets", __DIR__)
