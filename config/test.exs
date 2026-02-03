import Config

config :jido_ai, simulate_llm: true

config :logger, :console,
  level: :warning,
  format: "$time $metadata[$level] $message\n",
  metadata: [:jido_ai]
