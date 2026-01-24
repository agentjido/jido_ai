require Jido.AI.Skills.Streaming.Actions.EndStream
require Jido.AI.Skills.Streaming.Actions.ProcessTokens
# Ensure actions are compiled before the skill
require Jido.AI.Skills.Streaming.Actions.StartStream

defmodule Jido.AI.Skills.Streaming do
  @moduledoc """
  A Jido.Skill providing real-time streaming response capabilities from LLMs.

  This skill provides token-by-token streaming for real-time response handling.
  It supports callbacks for each token, buffering for full response capture,
  and proper resource cleanup.

  ## Actions

  * `StartStream` - Initialize a streaming LLM request
  * `ProcessTokens` - Process tokens from an active stream with callbacks
  * `EndStream` - Finalize a stream and collect usage/metadata

  ## Usage

  Attach to an agent:

      defmodule MyAgent do
        use Jido.Agent,

        skills: [
          {Jido.AI.Skills.Streaming, []}
        ]
      end

  Or use actions directly:

      # Start a stream
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Tell me a story",
        on_token: fn token -> IO.write(token) end
      })

      # Process tokens (if using separate callback)
      {:ok, _} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.ProcessTokens, %{
        stream_id: result.stream_id
      })

  ## Streaming Patterns

  ### Pattern 1: Inline Callback
  Pass `on_token` callback to StartStream for automatic processing:

      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Hello",
        on_token: fn token -> send(pid, {:token, token}) end
      })

  ### Pattern 2: Buffered Collection
  Enable buffering to collect full response:

      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Write code",
        buffer: true
      })

  ### Pattern 3: Manual Processing
  Use ProcessTokens action for manual token handling:

      {:ok, stream} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Generate",
        auto_process: false
      })

      {:ok, _} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.ProcessTokens, %{
        stream_id: stream.stream_id,
        on_token: &MyProcessor.handle/1
      })

  ## Model Resolution

  Uses `Jido.AI.Config.resolve_model/1` for model aliases:
  * `:fast` - Quick model for streaming (default: `anthropic:claude-haiku-4-5`)
  * `:capable` - Capable model for complex tasks
  * Direct model specs also supported

  ## Architecture Notes

  **Direct ReqLLM Calls**: Calls `ReqLLM.stream_text/3` directly without
  any adapter layer, following the core design principle of Jido.AI.

  **Stream Management**: Stream state is maintained for proper lifecycle
  management and resource cleanup.

  **Callback Flexibility**: Supports function, PID, and Registry-based callbacks.
  """

  use Jido.Skill,
    name: "streaming",
    state_key: :streaming,
    actions: [
      Jido.AI.Skills.Streaming.Actions.StartStream,
      Jido.AI.Skills.Streaming.Actions.ProcessTokens,
      Jido.AI.Skills.Streaming.Actions.EndStream
    ],
    description: "Provides real-time streaming LLM response capabilities",
    category: "ai",
    tags: ["streaming", "llm", "real-time", "tokens"],
    vsn: "1.0.0"

  @doc """
  Initialize skill state when mounted to an agent.
  """
  @impl Jido.Skill
  def mount(_agent, config) do
    initial_state = %{
      default_model: Map.get(config, :default_model, :fast),
      default_max_tokens: Map.get(config, :default_max_tokens, 1024),
      default_temperature: Map.get(config, :default_temperature, 0.7),
      default_buffer_size: Map.get(config, :default_buffer_size, 8192),
      active_streams: %{}
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the schema for skill state.

  Defines the structure and defaults for Streaming skill state.
  """
  def schema do
    Zoi.object(%{
      default_model:
        Zoi.atom(description: "Default model alias (:fast, :capable)")
        |> Zoi.default(:fast),
      default_max_tokens: Zoi.integer(description: "Default max tokens for generation") |> Zoi.default(1024),
      default_temperature:
        Zoi.float(description: "Default sampling temperature (0.0-2.0)")
        |> Zoi.default(0.7),
      default_buffer_size:
        Zoi.integer(description: "Default buffer size for stream collection")
        |> Zoi.default(8192),
      active_streams:
        Zoi.map(description: "Map of active stream IDs to their metadata")
        |> Zoi.default(%{})
    })
  end

  @doc """
  Returns the signal router for this skill.

  Maps signal patterns to action modules.
  """
  @impl Jido.Skill
  def router(_config) do
    [
      {"stream.start", Jido.AI.Skills.Streaming.Actions.StartStream},
      {"stream.process", Jido.AI.Skills.Streaming.Actions.ProcessTokens},
      {"stream.end", Jido.AI.Skills.Streaming.Actions.EndStream}
    ]
  end

  @doc """
  Pre-routing hook for incoming signals.

  Currently returns :continue to allow normal routing.
  """
  @impl Jido.Skill
  def handle_signal(_signal, _context) do
    {:ok, :continue}
  end

  @doc """
  Transform the result returned from action execution.

  Currently passes through results unchanged.
  """
  @impl Jido.Skill
  def transform_result(_action, result, _context) do
    result
  end

  @doc """
  Returns signal patterns this skill responds to.
  """
  def signal_patterns do
    [
      "stream.start",
      "stream.process",
      "stream.end"
    ]
  end
end
