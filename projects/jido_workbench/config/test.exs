import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :jido_workbench, JidoWorkbenchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "twi598leTbcJNAxvKitZGPMr8ZDu9ONMsUY1vk6ubAxy5Dmzx/7QrR9at+voP4X2",
  server: false

# In test we don't send emails.
config :jido_workbench, JidoWorkbench.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
