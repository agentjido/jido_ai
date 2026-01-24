defmodule Jido.AI.Accuracy.Directive do
  @moduledoc """
  Directives for accuracy pipeline execution.

  These directives allow Jido agents to execute the accuracy pipeline and receive
  results as signals.

  ## Available Directives

  - `Jido.AI.Accuracy.Directive.Run` - Execute the accuracy pipeline

  ## Usage

  Agents can emit these directives to trigger accuracy pipeline execution:

      # In agent code
      directive = Jido.AI.Accuracy.Directive.Run.new!(%{
        id: "call_123",
        query: "What is 2+2?",
        preset: :fast
      })

      # Or via agent state
      {:ok, agent} = Agent.emit_signal(agent, "accuracy.run", %{
        query: "What is 2+2?",
        preset: :fast
      })

  ## Signal Handling

  Results are emitted as `accuracy.result` signals and can be handled via `signal_routes/1`:

      def signal_routes(_agent) do
        %{
          "accuracy.result" => :handle_accuracy_result,
          "accuracy.error" => :handle_accuracy_error
        }
      end

  def handle_accuracy_result(agent, signal) do
    # signal.answer contains the final answer
    # signal.confidence contains the confidence score
    {:ok, agent}
  end
  """

  defmodule Run do
    @moduledoc """
    Directive to execute the accuracy pipeline.

    The runtime will execute this directive asynchronously and send the result
    back as an `accuracy.result` signal.

    ## Fields

    - `:id` (required) - Unique call ID for correlation
    - `:query` (required) - Query to process
    - `:preset` (optional) - Preset to use (:fast, :balanced, :accurate, :coding, :research)
    - `:config` (optional) - Custom config overrides (merged with preset)
    - `:generator` (optional) - Generator function or module (defaults to agent config)
    - `:timeout` (optional) - Execution timeout in milliseconds

    ## Execution

    The directive execution follows these steps:

    1. Resolve preset configuration (or use custom config)
    2. Create or get pipeline instance
    3. Execute pipeline with query
    4. Emit `accuracy.result` signal with answer and metadata
    5. Emit `accuracy.error` signal on failure

    ## Examples

        # Basic usage with preset
        Run.new!(%{
          id: "call_123",
          query: "What is 2+2?",
          preset: :fast
        })

        # With custom config override
        Run.new!(%{
          id: "call_456",
          query: "Explain quantum computing",
          preset: :accurate,
          config: %{
            generation_config: %{max_candidates: 15}
          }
        })

        # With generator override
        Run.new!(%{
          id: "call_789",
          query: "Write a function to sort a list",
          preset: :coding,
          generator: MyGenerator
        })

    ## Presets

    Available presets:

    - `:fast` - Minimal compute, 1-3 candidates, basic calibration
    - `:balanced` - Moderate compute, 3-5 candidates, +verification
    - `:accurate` - Maximum compute, 5-10 candidates, +search+reflection
    - `:coding` - Optimized for code, 3-5 candidates, +RAG+reflection
    - `:research` - Optimized for factuality, 3-5 candidates, +RAG with correction

    ## Result Signal

    On success, an `accuracy.result` signal is emitted with:

    - `:call_id` - The directive's ID
    - `:query` - The processed query
    - `:preset` - The preset used
    - `:answer` - The final answer
    - `:confidence` - Confidence score (0.0-1.0)
    - `:candidates` - Number of candidates generated
    - `:trace` - Execution trace
    - `:duration_ms` - Execution time
    - `:metadata` - Additional metadata (tokens, verification, etc.)

    ## Error Signal

    On failure, an `accuracy.error` signal is emitted with:

    - `:call_id` - The directive's ID
    - `:query` - The query that failed
    - `:preset` - The preset being used
    - `:error` - Error reason
    - `:stage` - Stage where error occurred (if applicable)
    - `:message` - Human-readable error message
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                query: Zoi.string(description: "Query to process"),
                preset:
                  Zoi.atom(description: "Preset to use (:fast, :balanced, :accurate, :coding, :research)")
                  |> Zoi.default(:balanced),
                config:
                  Zoi.map(description: "Custom config overrides (merged with preset)")
                  |> Zoi.default(%{}),
                generator:
                  Zoi.any(description: "Generator function or module (defaults to agent config)")
                  |> Zoi.optional(),
                timeout:
                  Zoi.integer(description: "Execution timeout in milliseconds")
                  |> Zoi.default(30_000)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new Run directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid Accuracy.Run directive: #{inspect(errors)}"
      end
    end

    @doc """
    Converts the directive to a map for execution.

    This is used by the runtime to extract execution parameters.
    """
    def to_execution_map(%__MODULE__{} = directive) do
      %{
        id: directive.id,
        query: directive.query,
        preset: directive.preset,
        config: directive.config,
        generator: directive.generator,
        timeout: directive.timeout
      }
    end
  end
end
