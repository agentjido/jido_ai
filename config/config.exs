import Config

config :logger, :console,
  format: {Jido.AI.Keyring.Filter, :format},
  metadata: [:module]

# ReqLLM configuration
config :req_llm,
  # Enable automatic model sync from models.dev
  auto_sync: true,
  # Default request timeout in milliseconds
  timeout: 60_000,
  # Default number of retries for failed requests
  retries: 3
