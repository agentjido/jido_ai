defmodule Jido.AI.Directive.LLMEmbed do
  @moduledoc """
  Directive asking the runtime to generate embeddings via ReqLLM.

  Uses `ReqLLM.Embedding.embed/3` for embedding generation. The runtime will
  execute this asynchronously and send the result as a `ai.embed.result` signal.

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

  @doc "Create a new LLMEmbed directive."
  def new!(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid LLMEmbed: #{inspect(errors)}"
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMEmbed do
  @moduledoc """
  Spawns an async task to generate embeddings and sends the result back to the agent.

  Uses `ReqLLM.Embedding.embed/3` for embedding generation. The result is sent
  as a `ai.embed.result` signal.

  Supports both single text and batch embedding (list of texts).
  """

  alias Jido.AI.Signal
  alias Jido.AI.Directive.Helper

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      model: model,
      texts: texts
    } = directive

    dimensions = Map.get(directive, :dimensions)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Helper.get_task_supervisor(state)

    case Task.Supervisor.start_child(task_supervisor, fn ->
           result =
             try do
               generate_embeddings(model, texts, dimensions, timeout)
             rescue
               e ->
                 {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helper.classify_error(e)}}
             catch
               kind, reason ->
                 {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
             end

           signal = Signal.EmbedResult.new!(%{call_id: call_id, result: result})
           Jido.AgentServer.cast(agent_pid, signal)
         end) do
      {:ok, _pid} ->
        {:async, nil, state}

      {:error, reason} ->
        signal =
          Signal.EmbedResult.new!(%{
            call_id: call_id,
            result: {:error, %{type: :supervisor, reason: inspect(reason), error_type: :unknown}}
          })

        Jido.AgentServer.cast(agent_pid, signal)
        {:ok, state}
    end
  end

  defp generate_embeddings(model, texts, dimensions, timeout) do
    opts =
      []
      |> add_dimensions_opt(dimensions)
      |> Helper.add_timeout_opt(timeout)

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
