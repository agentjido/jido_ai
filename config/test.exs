import Config

config :git_hooks,
  auto_install: false

config :logger, :console,
  level: :warning,
  format: "$time $metadata[$level] $message\n",
  metadata: [:jido_ai]
