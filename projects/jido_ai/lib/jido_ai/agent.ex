defmodule Jido.AI.Agent do
  @moduledoc """
  General purpose AI agent powered by Jido.

  This agent provides convenient methods for AI text generation, streaming, and object
  creation by leveraging the Jido framework and the AI Skill. It encapsulates the
  complexity of signal handling and provides a clean, simple API for AI operations.

  ## Usage

      # Start an AI agent
      {:ok, pid} = Jido.AI.Agent.start_link(
        id: "ai_assistant",
        default_model: "openai:gpt-4o",
        temperature: 0.7
      )

      # Generate text
      {:ok, response} = Jido.AI.Agent.generate_text(pid, "Hello, how are you?")

      # Generate structured objects
      schema = %{type: "object", properties: %{name: %{type: "string"}}}
      {:ok, object} = Jido.AI.Agent.generate_object(pid, "Generate a person", schema: schema)

      # Stream responses
      stream = Jido.AI.Agent.stream_text(pid, "Tell me a story")
      Enum.each(stream, fn chunk -> IO.write(chunk) end)

  ## Configuration

  The agent accepts all configuration options supported by `Jido.AI.Skill`:
  - `default_model` - Default AI model (e.g., "openai:gpt-4o")
  - `temperature` - Generation temperature (0.0-2.0)
  - `max_tokens` - Maximum tokens for generation
  - `system_prompt` - Default system prompt
  - `actions` - List of tool actions
  - `provider_config` - Provider-specific configuration
  """

  use Jido.Agent,
    name: "jido_ai_agent",
    description: "General purpose AI agent powered by Jido",
    category: "AI Agents",
    tags: ["ai", "agent", "text", "generation", "streaming"],
    vsn: "1.0.0"

  alias Jido.Agent.Interaction
  alias Jido.Agent.Server
  alias Jido.AI.Skill

  @default_timeout Application.compile_env(:jido_ai, :default_timeout, 30_000)

  @default_opts [
    skills: [Skill]
  ]

  @impl true
  def start_link(opts \\ []) do
    opts =
      @default_opts
      |> Keyword.merge(opts)
      |> Keyword.put(:agent, __MODULE__)

    Server.start_link(opts)
  end

  @doc """
  Generate text using the AI agent.

  ## Parameters
  - `agent_ref` - Agent PID or reference
  - `messages` - String prompt or list of messages
  - `opts` - Optional parameters (model, temperature, max_tokens, etc.)
  - `timeout` - Request timeout (default: 30s)

  ## Returns
  - `{:ok, text}` - Generated text response
  - `{:error, reason}` - Error details

  ## Examples

      # Simple text generation
      {:ok, response} = generate_text(pid, "Hello world")

      # With options
      {:ok, response} = generate_text(pid, "Explain AI", 
        model: "openai:gpt-4o", 
        temperature: 0.5,
        max_tokens: 500
      )
  """
  @spec generate_text(Jido.agent_ref(), String.t() | list(), keyword(), pos_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def generate_text(agent_ref, messages, opts \\ [], timeout \\ @default_timeout) do
    data =
      opts
      |> Keyword.put(:messages, messages)
      |> Map.new()

    with {:ok, signal} <- build_signal("jido.ai.generate_text", data),
         {:ok, result_signal} <- call_agent(agent_ref, signal, timeout) do
      extract_text_result(result_signal)
    end
  end

  @doc """
  Generate a structured object using the AI agent.

  ## Parameters
  - `agent_ref` - Agent PID or reference
  - `messages` - String prompt or list of messages
  - `opts` - Optional parameters including required `schema`
  - `timeout` - Request timeout (default: 30s)

  ## Returns
  - `{:ok, object}` - Generated structured object
  - `{:error, reason}` - Error details

  ## Examples

      schema = %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          age: %{type: "integer"}
        }
      }
      
      {:ok, person} = generate_object(pid, "Create a person", schema: schema)
  """
  @spec generate_object(Jido.agent_ref(), String.t() | list(), keyword(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def generate_object(agent_ref, messages, opts \\ [], timeout \\ @default_timeout) do
    if !Keyword.has_key?(opts, :schema) do
      raise ArgumentError, "schema option is required for generate_object"
    end

    data =
      opts
      |> Keyword.put(:messages, messages)
      |> Keyword.put(:object_schema, Keyword.get(opts, :schema))
      |> Keyword.delete(:schema)
      |> Map.new()

    with {:ok, signal} <- build_signal("jido.ai.generate_object", data),
         {:ok, result_signal} <- call_agent(agent_ref, signal, timeout) do
      extract_object_result(result_signal)
    end
  end

  @doc """
  Stream text generation from the AI agent.

  ## Parameters
  - `agent_ref` - Agent PID or reference
  - `messages` - String prompt or list of messages
  - `opts` - Optional parameters (model, temperature, max_tokens, etc.)
  - `timeout` - Request timeout (default: 30s)

  ## Returns
  - `{:ok, stream}` - Enumerable stream of text chunks
  - `{:error, reason}` - Error details

  ## Examples

      {:ok, stream} = stream_text(pid, "Tell me a story")
      Enum.each(stream, fn chunk -> IO.write(chunk) end)
  """
  @spec stream_text(Jido.agent_ref(), String.t() | list(), keyword(), pos_integer()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_text(agent_ref, messages, opts \\ [], timeout \\ @default_timeout) do
    data =
      opts
      |> Keyword.put(:messages, messages)
      |> Map.new()

    with {:ok, signal} <- build_signal("jido.ai.stream_text", data),
         {:ok, result_signal} <- call_agent(agent_ref, signal, timeout) do
      extract_stream_result(result_signal)
    end
  end

  @doc """
  Stream structured object generation from the AI agent.

  ## Parameters
  - `agent_ref` - Agent PID or reference
  - `messages` - String prompt or list of messages
  - `opts` - Optional parameters including required `schema`
  - `timeout` - Request timeout (default: 30s)

  ## Returns
  - `{:ok, stream}` - Enumerable stream of object chunks
  - `{:error, reason}` - Error details

  ## Examples

      schema = %{type: "object", properties: %{items: %{type: "array"}}}
      {:ok, stream} = stream_object(pid, "Generate a list", schema: schema)
      Enum.each(stream, fn chunk -> IO.inspect(chunk) end)
  """
  @spec stream_object(Jido.agent_ref(), String.t() | list(), keyword(), pos_integer()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_object(agent_ref, messages, opts \\ [], timeout \\ @default_timeout) do
    if !Keyword.has_key?(opts, :schema) do
      raise ArgumentError, "schema option is required for stream_object"
    end

    data =
      opts
      |> Keyword.put(:messages, messages)
      |> Keyword.put(:object_schema, Keyword.get(opts, :schema))
      |> Keyword.delete(:schema)
      |> Map.new()

    with {:ok, signal} <- build_signal("jido.ai.stream_object", data),
         {:ok, result_signal} <- call_agent(agent_ref, signal, timeout) do
      extract_stream_result(result_signal)
    end
  end

  # Private helper functions

  defp build_signal(type, data) do
    Jido.Signal.new(%{
      type: type,
      data: data
    })
  end

  defp call_agent(agent_ref, signal, timeout) do
    case Interaction.call(agent_ref, signal, timeout) do
      {:ok, %Jido.Signal{type: "jido.ai.result"} = result_signal} ->
        {:ok, result_signal}

      {:ok, %Jido.Signal{type: "jido.ai.stream_chunk"} = result_signal} ->
        {:ok, result_signal}

      {:ok, %Jido.Signal{type: "jido.ai.error", data: %{error: reason}}} ->
        {:error, reason}

      {:ok, %Jido.Signal{type: "jido.ai.error"} = error_signal} ->
        {:error, error_signal.data}

      # Handle standard agent instruction results that contain our AI data
      {:ok, %Jido.Signal{type: "jido.agent.out.instruction.result", data: data}} when is_map(data) ->
        # Create a proper AI result signal from the instruction result
        ai_result_signal = %Jido.Signal{
          id: Jido.Util.generate_id(),
          source: signal.source,
          type: "jido.ai.result",
          data: data
        }
        {:ok, ai_result_signal}

      # Handle unwrapped result data (what we actually get from Interaction.call)
      {:ok, data} when is_map(data) ->
        # Create a proper AI result signal from the raw data
        ai_result_signal = %Jido.Signal{
          id: Jido.Util.generate_id(),
          source: signal.source,
          type: "jido.ai.result",
          data: data
        }
        {:ok, ai_result_signal}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_response, other}}
    end
  end

  defp extract_text_result(%Jido.Signal{data: %{text: text}}) when is_binary(text) do
    {:ok, text}
  end

  defp extract_text_result(%Jido.Signal{data: %{content: content}}) when is_binary(content) do
    {:ok, content}
  end

  defp extract_text_result(%Jido.Signal{data: data}) do
    # Try to find text-like content in the data
    cond do
      Map.has_key?(data, :text) -> {:ok, data.text}
      Map.has_key?(data, :content) -> {:ok, data.content}
      Map.has_key?(data, :message) -> {:ok, data.message}
      Map.has_key?(data, :response) -> {:ok, data.response}
      true -> {:error, {:invalid_text_response, data}}
    end
  end

  defp extract_object_result(%Jido.Signal{data: %{object: object}}) when is_map(object) do
    {:ok, object}
  end

  defp extract_object_result(%Jido.Signal{data: %{result: result}}) when is_map(result) do
    {:ok, result}
  end

  defp extract_object_result(%Jido.Signal{data: data}) do
    # Try to find object-like content in the data
    cond do
      Map.has_key?(data, :object) -> {:ok, data.object}
      Map.has_key?(data, :result) -> {:ok, data.result}
      Map.has_key?(data, :data) -> {:ok, data.data}
      Map.has_key?(data, :response) and is_map(data.response) -> {:ok, data.response}
      true -> {:error, {:invalid_object_response, data}}
    end
  end

  defp extract_stream_result(%Jido.Signal{data: %{stream: stream}}) do
    {:ok, stream}
  end

  defp extract_stream_result(%Jido.Signal{data: data}) do
    # Try to find stream-like content in the data
    cond do
      Map.has_key?(data, :stream) -> {:ok, data.stream}
      Map.has_key?(data, :chunks) -> {:ok, data.chunks}
      Map.has_key?(data, :response) and is_struct(data.response, Stream) -> {:ok, data.response}
      Map.has_key?(data, :response) and is_function(data.response) -> {:ok, data.response}
      true -> {:error, {:invalid_stream_response, data}}
    end
  end
end
