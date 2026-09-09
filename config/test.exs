import Config

config :git_hooks,
  auto_install: false

# Held HTTP/1 example requests need spare connections in the same pool.
config :req_llm, finch: [name: ReqLLM.Finch, pools: %{default: [size: 8, count: 1]}]

config :logger, :console,
  level: :warning,
  format: "$time $metadata[$level] $message\n",
  metadata: [:jido_ai]
