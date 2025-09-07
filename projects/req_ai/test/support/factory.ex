defmodule ReqLLM.Test.Factory do
  @moduledoc """
  Factory functions for creating test objects in ReqLLM.

  Provides builders for common test objects including content parts, messages,
  models, and schemas to simplify test setup and improve consistency.
  """

  alias ReqLLM.{ContentPart, Message, ObjectSchema}

  # Content Part Builders

  @doc """
  Creates a text content part for testing.

  ## Examples

      iex> text_part("Hello world")
      %ReqLLM.ContentPart{type: :text, text: "Hello world"}

      iex> text_part("Hello", metadata: %{cache_control: %{type: "ephemeral"}})
      %ReqLLM.ContentPart{type: :text, text: "Hello", metadata: %{cache_control: %{type: "ephemeral"}}}

  """
  @spec text_part(String.t(), keyword()) :: ContentPart.t()
  def text_part(text, opts \\ []) do
    %ContentPart{
      type: :text,
      text: text,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates an image URL content part for testing.

  ## Examples

      iex> image_part("https://example.com/image.png")
      %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/image.png"}

      iex> image_part("https://example.com/image.png", metadata: %{detail: "high"})
      %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/image.png", metadata: %{detail: "high"}}

  """
  @spec image_part(String.t(), keyword()) :: ContentPart.t()
  def image_part(url, opts \\ []) do
    %ContentPart{
      type: :image_url,
      url: url,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a tool call content part for testing.

  ## Examples

      iex> tool_use_part("call_123", "get_weather", %{location: "NYC"})
      %ReqLLM.ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}

  """
  @spec tool_use_part(String.t(), String.t(), map(), keyword()) :: ContentPart.t()
  def tool_use_part(tool_call_id, tool_name, input, opts \\ []) do
    %ContentPart{
      type: :tool_call,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      input: input,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a tool result content part for testing.

  ## Examples

      iex> tool_result_part("call_123", "get_weather", %{temperature: 72})
      %ReqLLM.ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}}

  """
  @spec tool_result_part(String.t(), String.t(), any(), keyword()) :: ContentPart.t()
  def tool_result_part(tool_call_id, tool_name, output, opts \\ []) do
    %ContentPart{
      type: :tool_result,
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      output: output,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  # Message Builders

  @doc """
  Creates a user message for testing.

  ## Examples

      iex> user_msg("Hello")
      %ReqLLM.Message{role: :user, content: "Hello"}

      iex> user_msg([text_part("Hello"), image_part("https://example.com/image.png")])
      %ReqLLM.Message{role: :user, content: [%ReqLLM.ContentPart{...}, ...]}

  """
  @spec user_msg(String.t() | [ContentPart.t()], keyword()) :: Message.t()
  def user_msg(content, opts \\ []) do
    %Message{
      role: :user,
      content: content,
      name: Keyword.get(opts, :name),
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates an assistant message for testing.

  ## Examples

      iex> assistant_msg("Hello back")
      %ReqLLM.Message{role: :assistant, content: "Hello back"}

      iex> assistant_msg("I'll help you", name: "assistant")
      %ReqLLM.Message{role: :assistant, content: "I'll help you", name: "assistant"}

  """
  @spec assistant_msg(String.t() | [ContentPart.t()], keyword()) :: Message.t()
  def assistant_msg(content, opts \\ []) do
    %Message{
      role: :assistant,
      content: content,
      name: Keyword.get(opts, :name),
      tool_calls: Keyword.get(opts, :tool_calls),
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a system message for testing.

  ## Examples

      iex> system_msg("You are a helpful assistant")
      %ReqLLM.Message{role: :system, content: "You are a helpful assistant"}

  """
  @spec system_msg(String.t() | [ContentPart.t()], keyword()) :: Message.t()
  def system_msg(content, opts \\ []) do
    %Message{
      role: :system,
      content: content,
      name: Keyword.get(opts, :name),
      metadata: Keyword.get(opts, :metadata)
    }
  end

  @doc """
  Creates a tool message for testing.

  ## Examples

      iex> tool_msg("call_123", [tool_result_part("call_123", "get_weather", %{temperature: 72})])
      %ReqLLM.Message{role: :tool, tool_call_id: "call_123", content: [%ReqLLM.ContentPart{...}]}

  """
  @spec tool_msg(String.t(), [ContentPart.t()], keyword()) :: Message.t()
  def tool_msg(tool_call_id, content, opts \\ []) do
    %Message{
      role: :tool,
      tool_call_id: tool_call_id,
      content: content,
      metadata: Keyword.get(opts, :metadata)
    }
  end

  # Model Builders

  @doc """
  Creates a basic model configuration for testing.

  ## Examples

      iex> basic_model()
      %{name: "gpt-4", temperature: 0.7, max_tokens: 1000}

  """
  @spec basic_model(keyword()) :: map()
  def basic_model(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "gpt-4"),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 1000)
    }
  end

  @doc """
  Creates an Anthropic model configuration for testing.

  ## Examples

      iex> anthropic_model()
      %{name: "claude-3-5-sonnet-20241022", temperature: 0.7, max_tokens: 4000}

  """
  @spec anthropic_model(keyword()) :: map()
  def anthropic_model(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "claude-3-5-sonnet-20241022"),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 4000)
    }
  end

  @doc """
  Creates an OpenAI model configuration for testing.

  ## Examples

      iex> openai_model()
      %{name: "gpt-4", temperature: 0.7, max_tokens: 1000}

  """
  @spec openai_model(keyword()) :: map()
  def openai_model(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "gpt-4"),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 1000)
    }
  end

  # Schema Builders

  @doc """
  Creates a simple object schema for testing.

  ## Examples

      iex> simple_schema()
      %ReqLLM.ObjectSchema{output_type: :object, properties: [name: [type: :string, required: true]]}

  """
  @spec simple_schema(keyword()) :: ObjectSchema.t()
  def simple_schema(opts \\ []) do
    properties =
      Keyword.get(opts, :properties, name: [type: :string, required: true, doc: "Full name"])

    {:ok, schema} =
      ObjectSchema.new(
        output_type: :object,
        properties: properties
      )

    schema
  end

  @doc """
  Creates a complex object schema for testing.

  ## Examples

      iex> complex_schema()
      %ReqLLM.ObjectSchema{output_type: :object, properties: [...]}

  """
  @spec complex_schema(keyword()) :: ObjectSchema.t()
  def complex_schema(opts \\ []) do
    properties =
      Keyword.get(opts, :properties,
        name: [type: :string, required: true, doc: "Full name"],
        age: [type: :pos_integer, doc: "Age in years"],
        email: [type: :string, doc: "Email address"],
        tags: [type: {:list, :string}, default: [], doc: "List of tags"],
        address: [
          type: :keyword_list,
          doc: "Address information",
          keys: [
            street: [type: :string, required: true],
            city: [type: :string, required: true],
            zip: [type: :string]
          ]
        ]
      )

    {:ok, schema} =
      ObjectSchema.new(
        output_type: :object,
        properties: properties
      )

    schema
  end

  @doc """
  Creates an enum schema for testing.

  ## Examples

      iex> enum_schema(["red", "green", "blue"])
      %ReqLLM.ObjectSchema{output_type: :enum, enum_values: ["red", "green", "blue"]}

  """
  @spec enum_schema([String.t()], keyword()) :: ObjectSchema.t()
  def enum_schema(values, _opts \\ []) do
    {:ok, schema} =
      ObjectSchema.new(
        output_type: :enum,
        enum_values: values
      )

    schema
  end

  @doc """
  Creates an array schema for testing.

  ## Examples

      iex> array_schema()
      %ReqLLM.ObjectSchema{output_type: :array, properties: [...]}

  """
  @spec array_schema(keyword()) :: ObjectSchema.t()
  def array_schema(opts \\ []) do
    properties =
      Keyword.get(opts, :properties,
        name: [type: :string, required: true, doc: "Item name"],
        value: [type: :pos_integer, doc: "Item value"]
      )

    {:ok, schema} =
      ObjectSchema.new(
        output_type: :array,
        properties: properties
      )

    schema
  end

  # Data Builders

  @doc """
  Creates valid test data for simple schema validation.

  ## Examples

      iex> simple_data()
      %{"name" => "John Doe"}

  """
  @spec simple_data(keyword()) :: map()
  def simple_data(opts \\ []) do
    %{
      "name" => Keyword.get(opts, :name, "John Doe")
    }
  end

  @doc """
  Creates valid test data for complex schema validation.

  ## Examples

      iex> complex_data()
      %{"name" => "John Doe", "age" => 30, ...}

  """
  @spec complex_data(keyword()) :: map()
  def complex_data(opts \\ []) do
    %{
      "name" => Keyword.get(opts, :name, "John Doe"),
      "age" => Keyword.get(opts, :age, 30),
      "email" => Keyword.get(opts, :email, "john@example.com"),
      "tags" => Keyword.get(opts, :tags, ["developer", "elixir"]),
      "address" =>
        Keyword.get(opts, :address, %{
          "street" => "123 Main St",
          "city" => "Anytown",
          "zip" => "12345"
        })
    }
  end

  # Multi-message Builders

  @doc """
  Creates a basic conversation for testing.

  ## Examples

      iex> basic_conversation()
      [%ReqLLM.Message{role: :system, ...}, %ReqLLM.Message{role: :user, ...}]

  """
  @spec basic_conversation(keyword()) :: [Message.t()]
  def basic_conversation(opts \\ []) do
    system_content = Keyword.get(opts, :system, "You are a helpful assistant.")
    user_content = Keyword.get(opts, :user, "Hello!")

    [
      system_msg(system_content),
      user_msg(user_content)
    ]
  end

  @doc """
  Creates a multi-modal conversation for testing.

  ## Examples

      iex> multimodal_conversation()
      [%ReqLLM.Message{role: :user, content: [...]}, ...]

  """
  @spec multimodal_conversation(keyword()) :: [Message.t()]
  def multimodal_conversation(opts \\ []) do
    text = Keyword.get(opts, :text, "Describe this image:")
    image_url = Keyword.get(opts, :image_url, "https://example.com/image.png")

    [
      user_msg([
        text_part(text),
        image_part(image_url)
      ])
    ]
  end

  @doc """
  Creates a tool-based conversation for testing.

  ## Examples

      iex> tool_conversation()
      [%ReqLLM.Message{role: :user, ...}, %ReqLLM.Message{role: :assistant, ...}, ...]

  """
  @spec tool_conversation(keyword()) :: [Message.t()]
  def tool_conversation(opts \\ []) do
    tool_call_id = Keyword.get(opts, :tool_call_id, "call_123")
    tool_name = Keyword.get(opts, :tool_name, "get_weather")
    location = Keyword.get(opts, :location, "NYC")
    temperature = Keyword.get(opts, :temperature, 72)

    [
      user_msg("What's the weather in #{location}?"),
      assistant_msg([
        text_part("I'll check the weather for you."),
        tool_use_part(tool_call_id, tool_name, %{location: location})
      ]),
      tool_msg(tool_call_id, [
        tool_result_part(tool_call_id, tool_name, %{temperature: temperature})
      ]),
      assistant_msg("The temperature in #{location} is #{temperature}°F.")
    ]
  end
end
