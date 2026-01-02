import Config

config :logger, :console,
  level: :warning,
  format: "$time $metadata[$level] $message\n",
  metadata: [:jido_ai]
