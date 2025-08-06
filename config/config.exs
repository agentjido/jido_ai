import Config

config :logger, :console,
  format: {Jido.AI.Keyring.Filter, :format},
  metadata: [:module]
