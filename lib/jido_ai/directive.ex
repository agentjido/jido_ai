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
        action_module: MyApp.Actions.Calculator,
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
    - `model_alias` - Model alias (e.g., `:fast`) resolved via `Jido.AI.Config`
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

    ## Argument Normalization

    LLM tool calls return arguments with string keys (from JSON). The execution
    normalizes arguments using the action's schema before execution:
    - Converts string keys to atom keys
    - Parses string numbers to integers/floats based on schema type

    This ensures consistent argument semantics whether tools are called via
    DirectiveExec or any other path.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Tool call ID from LLM (ReqLLM.ToolCall.id)"),
                tool_name: Zoi.string(description: "Name of the tool (matches Jido.Action.name/0)"),
                action_module: Zoi.any(description: "Module implementing Jido.Action behaviour"),
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
  - `model_alias` resolution via `Jido.AI.Config.resolve_model/1`
  - `system_prompt` prepended to context messages
  - `timeout` passed to HTTP options

  Error handling: If the LLM call raises an exception, the error is caught
  and sent back as an error result to prevent the agent from getting stuck.
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

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      result =
        try do
          stream_with_callbacks(
            call_id,
            model,
            context,
            system_prompt,
            tools,
            tool_choice,
            max_tokens,
            temperature,
            timeout,
            agent_pid
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

  defp stream_with_callbacks(
         call_id,
         model,
         context,
         system_prompt,
         tools,
         tool_choice,
         max_tokens,
         temperature,
         timeout,
         agent_pid
       ) do
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

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
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
  defp count_embeddings(_), do: 1

  defp add_dimensions_opt(opts, nil), do: opts

  defp add_dimensions_opt(opts, dimensions) when is_integer(dimensions) do
    Keyword.put(opts, :dimensions, dimensions)
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ToolExec do
  @moduledoc """
  Spawns an async task to execute a Jido.Action and sends the result back
  to the agent as an `ai.tool_result` signal.

  If the action raises an exception, the error is caught and sent back as an
  error result to prevent the agent from getting stuck in an awaiting state.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      action_module: action_module,
      arguments: arguments,
      context: context
    } = directive

    agent_pid = self()

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      result =
        try do
          normalized_args = normalize_arguments(action_module, arguments)

          case Jido.Exec.run(action_module, normalized_args, context) do
            {:ok, output} -> {:ok, output}
            {:error, reason} -> {:error, reason}
          end
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason)}}
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

  defp normalize_arguments(action_module, arguments) do
    schema = action_module.schema()
    Jido.Action.Tool.convert_params_using_schema(arguments, schema)
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ReqLLMGenerate do
  @moduledoc """
  Spawns an async task to generate an LLM response (non-streaming) and sends
  the result back to the agent.

  Uses `ReqLLM.Generation.generate_text/3` for non-streaming text generation.
  The result is sent as a `reqllm.result` signal.

  Supports:
  - `model_alias` resolution via `Jido.AI.Config.resolve_model/1`
  - `system_prompt` prepended to context messages
  - `timeout` passed to HTTP options
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

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
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
