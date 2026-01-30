defmodule Jido.AI.Directive do
  @moduledoc """
  Generic LLM-related directives for Jido agents.

  These directives are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They represent side effects that the AgentServer runtime should execute.

  ## Available Directives

  - `Jido.AI.Directive.ReqLLMStream` - Stream an LLM response with optional tool support
  - `Jido.AI.Directive.ToolExec` - Execute a Jido.Action as a tool

  ## Usage

      alias Jido.AI.Directive

      # Create an LLM streaming directive
      directive = Directive.ReqLLMStream.new!(%{
        id: "call_123",
        model: "anthropic:claude-haiku-4-5",
        context: messages,
        tools: tools
      })

      # Create a tool execution directive
      directive = Directive.ToolExec.new!(%{
        id: "tool_456",
        tool_name: "calculator",
        arguments: %{a: 1, b: 2, operation: "add"}
      })
  """

  defmodule ReqLLMStream do
    @moduledoc """
    Directive asking the runtime to stream an LLM response via ReqLLM.

    Uses ReqLLM for streaming. The runtime will execute this asynchronously
    and send partial tokens as `reqllm.partial` signals and the final result
    as a `reqllm.result` signal.

    ## New Fields

    - `system_prompt` - Optional system prompt prepended to context
    - `model_alias` - Model alias (e.g., `:fast`) resolved via `Jido.AI.resolve_model/1`
    - `timeout` - Request timeout in milliseconds

    Either `model` or `model_alias` must be provided. If `model_alias` is used,
    it is resolved to a model spec at execution time.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model:
                  Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4-5'")
                  |> Zoi.optional(),
                model_alias:
                  Zoi.atom(description: "Model alias (e.g., :fast) resolved via Config")
                  |> Zoi.optional(),
                system_prompt:
                  Zoi.string(description: "Optional system prompt prepended to context")
                  |> Zoi.optional(),
                context: Zoi.any(description: "Conversation context: [ReqLLM.Message.t()] or ReqLLM.Context.t()"),
                tools:
                  Zoi.list(Zoi.any(),
                    description: "List of ReqLLM.Tool.t() structs (schema-only, callback ignored)"
                  )
                  |> Zoi.default([]),
                tool_choice:
                  Zoi.any(description: "Tool choice: :auto | :none | {:required, tool_name}")
                  |> Zoi.default(:auto),
                max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
                temperature: Zoi.number(description: "Sampling temperature (0.0–2.0)") |> Zoi.default(0.2),
                timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new ReqLLMStream directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ReqLLMStream: #{inspect(errors)}"
      end
    end
  end

  defmodule ToolExec do
    @moduledoc """
    Directive to execute a Jido.Action as a tool.

    The runtime will execute this asynchronously and send the result back
    as an `ai.tool_result` signal.

    ## Execution Modes

    1. **Direct module execution** (preferred): When `action_module` is provided,
       the module is executed directly via `Executor.execute_module/4`, bypassing
       Registry lookup. This is used by strategies that maintain their own tool lists.

    2. **Registry lookup**: When `action_module` is nil, looks up the action in
       `Jido.AI.Tools.Registry` by name and executes via `Jido.AI.Tools.Executor`.

    ## Argument Normalization

    LLM tool calls return arguments with string keys (from JSON). The execution
    normalizes arguments using the tool's schema before execution:
    - Converts string keys to atom keys
    - Parses string numbers to integers/floats based on schema type

    This ensures consistent argument semantics whether tools are called via
    DirectiveExec or any other path.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Tool call ID from LLM (ReqLLM.ToolCall.id)"),
                tool_name:
                  Zoi.string(description: "Name of the tool (used for Registry lookup if action_module not provided)"),
                action_module:
                  Zoi.atom(description: "Module to execute directly (bypasses Registry lookup)")
                  |> Zoi.optional(),
                arguments:
                  Zoi.map(description: "Arguments from LLM (string keys, normalized before exec)")
                  |> Zoi.default(%{}),
                context:
                  Zoi.map(description: "Execution context passed to Jido.Exec.run/3")
                  |> Zoi.default(%{}),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new ToolExec directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ToolExec: #{inspect(errors)}"
      end
    end
  end

  defmodule ReqLLMGenerate do
    @moduledoc """
    Directive asking the runtime to generate an LLM response (non-streaming).

    Uses `ReqLLM.Generation.generate_text/3` for non-streaming text generation.
    The runtime will execute this asynchronously and send the result as a
    `reqllm.result` signal.

    This is simpler than `ReqLLMStream` for cases where streaming is not needed.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model:
                  Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4-5'")
                  |> Zoi.optional(),
                model_alias:
                  Zoi.atom(description: "Model alias (e.g., :fast) resolved via Config")
                  |> Zoi.optional(),
                system_prompt:
                  Zoi.string(description: "Optional system prompt prepended to context")
                  |> Zoi.optional(),
                context: Zoi.any(description: "Conversation context: [ReqLLM.Message.t()] or ReqLLM.Context.t()"),
                tools:
                  Zoi.list(Zoi.any(),
                    description: "List of ReqLLM.Tool.t() structs (schema-only, callback ignored)"
                  )
                  |> Zoi.default([]),
                tool_choice:
                  Zoi.any(description: "Tool choice: :auto | :none | {:required, tool_name}")
                  |> Zoi.default(:auto),
                max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
                temperature: Zoi.number(description: "Sampling temperature (0.0–2.0)") |> Zoi.default(0.2),
                timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new ReqLLMGenerate directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ReqLLMGenerate: #{inspect(errors)}"
      end
    end
  end

  defmodule ReqLLMEmbed do
    @moduledoc """
    Directive asking the runtime to generate embeddings via ReqLLM.

    Uses `ReqLLM.Embedding.embed/3` for embedding generation. The runtime will
    execute this asynchronously and send the result as an `ai.embed_result` signal.

    Supports both single text and batch embedding (list of texts).
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model: Zoi.string(description: "Embedding model spec, e.g. 'openai:text-embedding-3-small'"),
                texts: Zoi.any(description: "Text string or list of text strings to embed"),
                dimensions:
                  Zoi.integer(description: "Number of dimensions for embedding vector")
                  |> Zoi.optional(),
                timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new ReqLLMEmbed directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ReqLLMEmbed: #{inspect(errors)}"
      end
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ReqLLMStream do
  @moduledoc """
  Spawns an async task to stream an LLM response and sends results back to the agent.

  This implementation provides **true streaming**: as tokens arrive from the LLM,
  they are immediately sent as `reqllm.partial` signals. When the stream completes,
  a final `reqllm.result` signal is sent with the full classification (tool calls
  or final answer).

  Supports:
  - `model_alias` resolution via `Jido.AI.resolve_model/1`
  - `system_prompt` prepended to context messages
  - `timeout` passed to HTTP options

  Error handling: If the LLM call raises an exception, the error is caught
  and sent back as an error result to prevent the agent from getting stuck.

  ## Task Supervisor

  This implementation uses the agent's per-instance task supervisor stored in
  `state[:task_supervisor]`. The supervisor is started automatically by Jido.AI
  when an agent is created.
  """

  alias Jido.AI.{Helpers, Signal}

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      context: context,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature
    } = directive

    # Resolve model from either model or model_alias
    model = Helpers.resolve_directive_model(directive)
    system_prompt = Map.get(directive, :system_prompt)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    stream_opts = %{
      call_id: call_id,
      model: model,
      context: context,
      system_prompt: system_prompt,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature,
      timeout: timeout,
      agent_pid: agent_pid
    }

    Task.Supervisor.start_child(task_supervisor, fn ->
      result =
        try do
          stream_with_callbacks(stream_opts)
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
        end

      signal = Signal.ReqLLMResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp stream_with_callbacks(%{
         call_id: call_id,
         model: model,
         context: context,
         system_prompt: system_prompt,
         tools: tools,
         tool_choice: tool_choice,
         max_tokens: max_tokens,
         temperature: temperature,
         timeout: timeout,
         agent_pid: agent_pid
       }) do
    opts =
      []
      |> Helpers.add_tools_opt(tools)
      |> Keyword.put(:tool_choice, tool_choice)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)
      |> Helpers.add_timeout_opt(timeout)

    messages = Helpers.build_directive_messages(context, system_prompt)

    case ReqLLM.stream_text(model, messages, opts) do
      {:ok, stream_response} ->
        on_content = fn text ->
          partial_signal =
            Signal.ReqLLMPartial.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :content
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)
        end

        on_thinking = fn text ->
          partial_signal =
            Signal.ReqLLMPartial.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :thinking
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)
        end

        case ReqLLM.StreamResponse.process_stream(stream_response,
               on_result: on_content,
               on_thinking: on_thinking
             ) do
          {:ok, response} ->
            {:ok, Helpers.classify_llm_response(response)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ReqLLMEmbed do
  @moduledoc """
  Spawns an async task to generate embeddings and sends the result back to the agent.

  Uses `ReqLLM.Embedding.embed/3` for embedding generation. The result is sent
  as an `ai.embed_result` signal.

  Supports both single text and batch embedding (list of texts).
  """

  alias Jido.AI.{Helpers, Signal}

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      model: model,
      texts: texts
    } = directive

    dimensions = Map.get(directive, :dimensions)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    Task.Supervisor.start_child(task_supervisor, fn ->
      result =
        try do
          generate_embeddings(model, texts, dimensions, timeout)
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
        end

      signal = Signal.EmbedResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp generate_embeddings(model, texts, dimensions, timeout) do
    opts =
      []
      |> add_dimensions_opt(dimensions)
      |> Helpers.add_timeout_opt(timeout)

    case ReqLLM.Embedding.embed(model, texts, opts) do
      {:ok, embeddings} ->
        {:ok, %{embeddings: embeddings, count: count_embeddings(embeddings)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_embeddings(embeddings) when is_list(embeddings), do: length(embeddings)

  defp add_dimensions_opt(opts, nil), do: opts

  defp add_dimensions_opt(opts, dimensions) when is_integer(dimensions) do
    Keyword.put(opts, :dimensions, dimensions)
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ToolExec do
  @moduledoc """
  Spawns an async task to execute a Jido.Action and sends the result back
  to the agent as an `ai.tool_result` signal.

  Supports two execution modes:
  1. Direct module execution when `action_module` is provided (bypasses Registry)
  2. Registry lookup by `tool_name` when `action_module` is nil

  Uses `Jido.AI.Tools.Executor` for execution, which provides consistent error
  handling, parameter normalization, and telemetry.
  """

  alias Jido.AI.Tools.Executor
  alias Jido.AI.{Helpers, Signal}

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      arguments: arguments,
      context: context
    } = directive

    action_module = Map.get(directive, :action_module)
    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    # Get tools from state (agent's registered actions from skill or strategy)
    tools = get_tools_from_state(state)

    Task.Supervisor.start_child(task_supervisor, fn ->
      result =
        case action_module do
          nil ->
            Executor.execute(tool_name, arguments, context, tools: tools)

          module when is_atom(module) ->
            Executor.execute_module(module, arguments, context)
        end

      signal =
        Signal.ToolResult.new!(%{
          call_id: call_id,
          tool_name: tool_name,
          result: result
        })

      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp get_tools_from_state(state) do
    state[:tools] || get_in(state, [:tool_calling, :tools]) || %{}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ReqLLMGenerate do
  @moduledoc """
  Spawns an async task to generate an LLM response (non-streaming) and sends
  the result back to the agent.

  Uses `ReqLLM.Generation.generate_text/3` for non-streaming text generation.
  The result is sent as a `reqllm.result` signal.

  Supports:
  - `model_alias` resolution via `Jido.AI.resolve_model/1`
  - `system_prompt` prepended to context messages
  - `timeout` passed to HTTP options

  ## Task Supervisor

  This implementation uses the agent's per-instance task supervisor stored in
  `state[:task_supervisor]`. The supervisor is started automatically by Jido.AI
  when an agent is created.
  """

  alias Jido.AI.{Helpers, Signal}

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      context: context,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature
    } = directive

    model = Helpers.resolve_directive_model(directive)
    system_prompt = Map.get(directive, :system_prompt)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    Task.Supervisor.start_child(task_supervisor, fn ->
      result =
        try do
          generate_text(
            model,
            context,
            system_prompt,
            tools,
            tool_choice,
            max_tokens,
            temperature,
            timeout
          )
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
        end

      signal = Signal.ReqLLMResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp generate_text(model, context, system_prompt, tools, tool_choice, max_tokens, temperature, timeout) do
    opts =
      []
      |> Helpers.add_tools_opt(tools)
      |> Keyword.put(:tool_choice, tool_choice)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)
      |> Helpers.add_timeout_opt(timeout)

    messages = Helpers.build_directive_messages(context, system_prompt)

    case ReqLLM.Generation.generate_text(model, messages, opts) do
      {:ok, response} ->
        {:ok, Helpers.classify_llm_response(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Helper functions for DirectiveExec implementations
defmodule Jido.AI.Directive.Helper do
  @moduledoc """
  Helper functions for DirectiveExec implementations.
  """

  @doc """
  Gets the task supervisor from agent state.

  First checks the TaskSupervisorSkill's internal state (`__task_supervisor_skill__`),
  then falls back to the top-level `:task_supervisor` field for standalone usage.

  ## Examples

      iex> state = %{__task_supervisor_skill__: %{supervisor: supervisor_pid}}
      iex> Jido.AI.Directive.Helper.get_task_supervisor(state)
      supervisor_pid

      iex> state = %{task_supervisor: supervisor_pid}
      iex> Jido.AI.Directive.Helper.get_task_supervisor(state)
      supervisor_pid

  """
  def get_task_supervisor(%Jido.AgentServer.State{agent: agent}) do
    # Handle AgentServer.State struct - extract the agent's state
    get_task_supervisor(agent.state)
  end

  def get_task_supervisor(state) when is_map(state) do
    # First check TaskSupervisorSkill's internal state
    case Map.get(state, :__task_supervisor_skill__) do
      %{supervisor: supervisor} when is_pid(supervisor) ->
        supervisor

      _ ->
        # Fall back to top-level state field (for standalone usage)
        case Map.get(state, :task_supervisor) do
          nil ->
            raise """
            Task supervisor not found in agent state.

            In Jido 2.0, each agent instance requires its own task supervisor.
            Ensure your agent is started with Jido.AI which will automatically
            create and store a per-instance supervisor in the agent state.

            Example:
                use Jido.AI.ReActAgent,
                  name: "my_agent",
                  tools: [MyApp.Tool1, MyApp.Tool2]
            """

          supervisor when is_pid(supervisor) ->
            supervisor
        end
    end
  end
end
