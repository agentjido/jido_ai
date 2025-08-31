defmodule Jido.AI.Agent do
  @moduledoc """
  AI-powered agent that extends the base Jido.Agent with conversation capabilities.

  This agent provides a simplified interface for AI interactions while maintaining
  full compatibility with the Jido Agent architecture. It automatically includes
  the Jido.AI.Skill and provides convenient methods for common AI operations.

  ## Usage

      # Start an AI agent with default configuration
      {:ok, pid} = Jido.AI.Agent.start_link()

      # Generate text response
      {:ok, response} = Jido.AI.Agent.generate_text(pid, "Hello, how are you?")

      # Generate structured object
      {:ok, result} = Jido.AI.Agent.generate_object(pid, "Is the sky blue?", schema: boolean_schema)

      # Stream text response
      {:ok, stream} = Jido.AI.Agent.stream_text(pid, "Tell me a story")

  ## Configuration

  The agent accepts all standard Jido.Agent options plus AI-specific configuration:

      {:ok, pid} = Jido.AI.Agent.start_link(
        # Standard Jido Agent options
        name: "my_ai_agent",

        # AI-specific configuration
        ai: [
          model: "openai:gpt-4o",
          temperature: 0.7,
          max_tokens: 2000
        ]
      )

  The agent automatically includes the Jido.AI.Skill in its skills list and provides
  convenient wrapper methods for common AI operations.
  """

  use Jido.Agent,
    name: "jido_ai_agent",
    description: "AI-powered agent with conversation capabilities",
    category: "AI Agents",
    tags: ["AI", "Agent", "Conversation"],
    vsn: "1.0.0"

  require Logger

  @default_timeout Application.compile_env(:jido_ai, :default_timeout, 30_000)

  @default_kwargs [
    timeout: @default_timeout
  ]

  @doc """
  Generates text response from the AI agent using the provided prompt.

  ## Parameters

    * `pid` - The agent process ID
    * `prompt` - The prompt to send to the agent
    * `kwargs` - Additional options including `:timeout` and `:actions`

  ## Returns

    * `{:ok, response}` - Success with the AI's response text
    * `{:error, reason}` - Error occurred during processing

  ## Examples

      {:ok, response} = Jido.AI.Agent.generate_text(pid, "What is machine learning?")
      IO.puts(response)  # Prints the AI's explanation

      # With custom timeout and actions
      {:ok, response} = Jido.AI.Agent.generate_text(pid, "Calculate 2+2", timeout: 60_000, actions: [Jido.Tools.Arithmetic.Add])
  """
  @spec generate_text(pid(), binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate_text(pid, prompt, kwargs \\ @default_kwargs) when is_binary(prompt) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    actions = Keyword.get(kwargs, :actions, [])

    data = %{prompt: prompt}
    data = if actions == [], do: data, else: Map.put(data, :actions, actions)

    with {:ok, signal} <- Jido.Signal.new(%{type: "jido.ai.generate.text", data: data}) do
      case Jido.call(pid, signal, timeout) do
        {:ok, %{data: %{text: text}}} -> {:ok, text}
        {:ok, %{data: data}} -> {:error, "Unexpected response format: #{inspect(data)}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Generates a structured object response from the AI agent.

  This method uses the AI to generate structured data conforming to a schema.
  Useful for extracting specific information or generating typed responses.

  ## Parameters

    * `pid` - The agent process ID
    * `prompt` - The prompt describing what object to generate
    * `kwargs` - Additional options including `:timeout`, `:schema`, `:output_type`, and `:enum_values`

  ## Examples

      # Generate JSON object
      schema = %{type: "object", properties: %{name: %{type: "string"}, age: %{type: "integer"}}}
      {:ok, result} = Jido.AI.Agent.generate_object(pid, "Create a person", schema: schema)

      # Generate enum value
      {:ok, result} = Jido.AI.Agent.generate_object(
        pid,
        "Is the sky blue?",
        output_type: :enum,
        enum_values: ["true", "false"]
      )
  """
  @spec generate_object(pid(), binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate_object(pid, prompt, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    schema = Keyword.get(kwargs, :schema, [])
    output_type = Keyword.get(kwargs, :output_type, :json)
    enum_values = Keyword.get(kwargs, :enum_values, [])

    data = %{
      prompt: prompt,
      schema: schema,
      output_type: output_type
    }

    data = if enum_values == [], do: data, else: Map.put(data, :enum_values, enum_values)

    case Jido.send_signal(pid, "jido.ai.generate.object", data) do
      {:ok, %{data: %{object: object}}} -> {:ok, object}
      {:ok, %{data: data}} -> {:error, "Unexpected response format: #{inspect(data)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Streams text response from the AI agent.

  Returns a stream that emits text chunks as they are generated by the AI model.
  This is useful for real-time response display or processing large responses.

  ## Parameters

    * `pid` - The agent process ID
    * `prompt` - The prompt to send to the agent
    * `kwargs` - Additional options including `:timeout` and `:actions`

  ## Examples

      {:ok, stream} = Jido.AI.Agent.stream_text(pid, "Tell me a long story")
      stream |> Enum.each(&IO.write/1)

      # With actions for tool use
      {:ok, stream} = Jido.AI.Agent.stream_text(pid, "What's the weather?", actions: [WeatherTool])
  """
  @spec stream_text(pid(), binary(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_text(pid, prompt, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    actions = Keyword.get(kwargs, :actions, [])

    data = %{prompt: prompt}
    data = if actions == [], do: data, else: Map.put(data, :actions, actions)

    with {:ok, signal} <- Jido.Signal.new(%{type: "jido.ai.stream.text", data: data}) do
      case Jido.call(pid, signal, timeout) do
        {:ok, %{data: %{stream: stream}}} -> {:ok, stream}
        {:ok, %{data: data}} -> {:error, "Unexpected response format: #{inspect(data)}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Streams object generation from the AI agent.

  Returns a stream that emits structured object chunks as they are generated.
  This is useful for real-time structured data generation or processing.

  ## Parameters

    * `pid` - The agent process ID
    * `prompt` - The prompt describing what object to generate
    * `kwargs` - Additional options including `:timeout`, `:schema`, `:output_type`

  ## Examples

      schema = %{type: "object", properties: %{items: %{type: "array"}}}
      {:ok, stream} = Jido.AI.Agent.stream_object(pid, "Generate a list of items", schema: schema)
      stream |> Enum.each(&IO.inspect/1)
  """
  @spec stream_object(pid(), binary(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_object(pid, prompt, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    schema = Keyword.get(kwargs, :schema, [])
    output_type = Keyword.get(kwargs, :output_type, :json)

    data = %{
      prompt: prompt,
      schema: schema,
      output_type: output_type
    }

    with {:ok, signal} <- Jido.Signal.new(%{type: "jido.ai.stream.object", data: data}) do
      case Jido.call(pid, signal, timeout) do
        {:ok, %{data: %{stream: stream}}} -> {:ok, stream}
        {:ok, %{data: data}} -> {:error, "Unexpected response format: #{inspect(data)}"}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
