import Config

alias Jido.AI.Keyring.Filter

# Default model configuration
config :jido_ai, :default_model, "openrouter:openai/gpt-oss-20b:free"

config :logger, :console,
  format: {Filter, :format},
  metadata: [:module]

# Test environment - suppress debug logs during tests
if Mix.env() == :test do
  config :logger, level: :warning
end
