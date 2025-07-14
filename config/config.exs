import Config

config :logger, :console,
  format: "[$level] $message $metadata\n",
  metadata: [:module]
