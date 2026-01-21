import Config

config :logger, :console,
  format: {Jido.AI.Keyring.Filter, :format},
  metadata: [
    :module,
    # Model Registry Cache
    :table,
    :ttl,
    :cleanup_interval,
    :deleted,
    :remaining,
    # ReqLLM Bridge
    :functions,
    :tool_choice,
    # Enterprise Authentication
    :reason,
    :provider,
    # Tool Builder
    :successes,
    :failures,
    :action_module,
    :error,
    # Tool Executor
    :duration_ms,
    :exception,
    # Tool Response Handler
    :conversation_id
  ]

# ReqLLM configuration
config :req_llm,
  # Enable automatic model sync from models.dev
  auto_sync: true,
  # Default request timeout in milliseconds
  timeout: 60_000,
  # Default number of retries for failed requests
  retries: 3
