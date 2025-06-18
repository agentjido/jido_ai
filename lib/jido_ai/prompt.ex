defmodule Jido.AI.Prompt do
  @moduledoc ~S"""
  A module that provides struct-based prompt generation.

  The struct-based approach provides full visibility into the prompt's content
  when inspecting the agent state, making it easier to debug and understand
  the conversation flow.

  ## Examples

      # Create a simple prompt with a single message
      prompt = Jido.AI.Prompt.new(%{
        messages: [
          %{role: :user, content: "Hello"}
        ]
      })

      # Create a prompt with EEx templates
      prompt = Jido.AI.Prompt.new(%{
        messages: [
          %{role: :system, content: "You are a <%= @assistant_type %>", engine: :eex},
          %{role: :user, content: "Hello <%= @name %>", engine: :eex}
        ],
        params: %{
          assistant_type: "helpful assistant",
          name: "Alice"
        }
      })

      # Create a prompt with Liquid templates
      prompt = Jido.AI.Prompt.new(%{
        messages: [
          %{role: :system, content: "You are a {{ assistant_type }}", engine: :liquid},
          %{role: :user, content: "Hello {{ name }}", engine: :liquid}
        ],
        params: %{
          assistant_type: "helpful assistant",
          name: "Alice"
        }
      })

      # Render the prompt to get the final messages
      messages = Jido.AI.Prompt.render(prompt)
      # => [
      #      %{role: :system, content: "You are a helpful assistant"},
      #      %{role: :user, content: "Hello Alice"}
      #    ]
  """

  alias __MODULE__
  alias Jido.AI.Prompt.MessageItem

  use TypedStruct

  typedstruct do
    @typedoc "A complete prompt with messages and parameters"

    # Unique identifier for the prompt
    field(:id, String.t(), default: Jido.Util.generate_id())

    # Current version number of the prompt
    field(:version, non_neg_integer(), default: 1)

    # History of previous versions of this prompt
    field(:history, list(map()), default: [])

    # Holds a list of messages, each might be raw string or templated content
    # with a role to indicate system|assistant|user or others
    field(:messages, list(MessageItem.t()), default: [])

    # A map of parameters that can be interpolated into the messages (if they use EEx)
    field(:params, map(), default: %{})

    # Optional metadata or advanced features
    field(:metadata, map(), default: %{})

    # LLM specific options (temperature, max_tokens, top_p, stop, timeout)
    field(:options, keyword(), default: [])

    # Schema to validate the expected output structure
    field(:output_schema, NimbleOptions.t(), default: nil)
  end

  @doc """
  Creates a new prompt struct from the given attributes.

  ## Rules
  - Only one system message is allowed
  - If present, the system message must be the first message
  - Messages are rendered without the engine field

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(%{
      ...>   messages: [
      ...>     %{role: :user, content: "Hello"}
      ...>   ]
      ...> })
      iex> prompt.messages |> length()
      1
      iex> hd(prompt.messages).role
      :user
      iex> hd(prompt.messages).content
      "Hello"
  """
  def new(attrs) when is_map(attrs) do
    # Convert message maps to MessageItem structs
    messages =
      attrs
      |> Map.get(:messages, [])
      |> Enum.map(fn
        %MessageItem{} = item -> item
        map when is_map(map) -> MessageItem.new(map)
      end)

    # Validate system message rules
    validate_system_message_rules!(messages)

    # Create the prompt struct
    struct(
      __MODULE__,
      attrs
      |> Map.put(:messages, messages)
      |> Map.put_new(:params, %{})
      |> Map.put_new(:metadata, %{})
    )
  end

  @doc """
  Creates a new prompt with a single message.

  This is a convenience function for creating a prompt with a single message.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Hello")
      iex> prompt.messages |> length()
      1
      iex> hd(prompt.messages).role
      :user
      iex> hd(prompt.messages).content
      "Hello"
  """
  def new(role, content, opts \\ []) when is_atom(role) and is_binary(content) do
    engine = Keyword.get(opts, :engine, :none)
    params = Keyword.get(opts, :params, %{})
    metadata = Keyword.get(opts, :metadata, %{})
    id = Keyword.get(opts, :id)

    new(%{
      messages: [%{role: role, content: content, engine: engine}],
      params: params,
      metadata: metadata,
      id: id
    })
  end

  @doc """
  Validates and converts the prompt option.

  Accepts either:
  - A string, which is converted to a system message in a Prompt struct
  - An existing Prompt struct, which is returned as-is

  ## Examples

      iex> Jido.AI.Prompt.validate_prompt_opts("You are a helpful assistant")
      {:ok, %Jido.AI.Prompt{messages: [%Jido.AI.Prompt.MessageItem{role: :system, content: "You are a helpful assistant", engine: :none}], id: nil, version: 1, history: [], params: %{}, metadata: %{}}}

      iex> prompt = Jido.AI.Prompt.new(:system, "Custom prompt")
      iex> Jido.AI.Prompt.validate_prompt_opts(prompt)
      {:ok, prompt}
  """
  @spec validate_prompt_opts(String.t() | t()) :: {:ok, t()} | {:error, String.t()}
  def validate_prompt_opts(prompt) when is_binary(prompt) do
    # Convert the string to a Prompt struct with a system message
    {:ok, new(:system, prompt)}
  end

  def validate_prompt_opts(%__MODULE__{} = prompt) do
    # If it's already a Prompt struct, return it as-is
    {:ok, prompt}
  end

  def validate_prompt_opts(other) do
    {:error, "Expected a string or a Jido.AI.Prompt struct, got: #{inspect(other)}"}
  end

  @doc """
  Renders the prompt into a list of messages with interpolated content.

  The rendered messages will only include the role and content fields,
  excluding the engine field to ensure compatibility with API requests.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(%{
      ...>   messages: [
      ...>     %{role: :user, content: "Hello <%= @name %>", engine: :eex}
      ...>   ],
      ...>   params: %{name: "Alice"}
      ...> })
      iex> Prompt.render(prompt)
      [%{role: :user, content: "Hello Alice"}]
  """
  @spec render(t(), map()) :: list(%{role: atom(), content: String.t()})
  def render(%Prompt{} = prompt, override_params \\ %{}) do
    # 1. Merge params
    final_params = Map.merge(prompt.params, override_params)

    # 2. Build final messages
    Enum.map(prompt.messages, fn msg ->
      # Ensure message has an engine field
      msg =
        if is_map(msg) && !Map.has_key?(msg, :engine), do: Map.put(msg, :engine, :none), else: msg

      content =
        case msg.engine do
          :eex ->
            EEx.eval_string(msg.content, assigns: final_params)

          :liquid ->
            {:ok, template} = Solid.parse(msg.content)
            # Convert atom keys to strings for Liquid templates
            liquid_params = Map.new(final_params, fn {k, v} -> {Atom.to_string(k), v} end)
            {:ok, parts, _} = Solid.render(template, liquid_params, [])
            Enum.join(parts, "")

          :none ->
            msg.content

          _ ->
            # Handle any other engine type as :none
            msg.content
        end

      # Only include role and content in the rendered message
      %{role: msg.role, content: content}
    end)
  end

  @doc """
  Renders the prompt with options for an LLM API call.

  Returns a map containing both the rendered messages and any LLM-specific options.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Generate a story")
      ...> |> Prompt.with_temperature(0.7)
      ...> |> Prompt.with_max_tokens(500)
      iex> result = Prompt.render_with_options(prompt)
      iex> result[:messages]
      [%{role: :user, content: "Generate a story"}]
      iex> result[:temperature]
      0.7
      iex> result[:max_tokens]
      500
  """
  @spec render_with_options(t(), map()) :: map()
  def render_with_options(%Prompt{} = prompt, override_params \\ %{}) do
    # Render the messages
    messages = render(prompt, override_params)

    # Create the base map with messages
    base = %{messages: messages}

    # Add each option to the map if present
    Enum.reduce(prompt.options, base, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  @doc """
  Converts the prompt to a single text string.

  This is useful for debugging or when the LLM API expects a single text prompt.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(%{
      ...>   messages: [
      ...>     %{role: :system, content: "You are an assistant"},
      ...>     %{role: :user, content: "Hello"}
      ...>   ]
      ...> })
      iex> Prompt.to_text(prompt)
      "[system] You are an assistant\\n[user] Hello"
  """
  @spec to_text(t(), map()) :: String.t()
  def to_text(%Prompt{} = prompt, override_params \\ %{}) do
    prompt
    |> render(override_params)
    |> Enum.map(fn %{role: r, content: c} -> "[#{r}] #{c}" end)
    |> Enum.join("\n")
  end

  @doc """
  Adds a new message to the prompt.

  Enforces the rule that system messages can only appear first in the message list.
  Raises ArgumentError if attempting to add a system message in any other position.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(%{
      ...>   messages: [
      ...>     %{role: :user, content: "Hello"}
      ...>   ]
      ...> })
      iex> updated = Prompt.add_message(prompt, :assistant, "Hi there!")
      iex> length(updated.messages)
      2
      iex> List.last(updated.messages).content
      "Hi there!"
  """
  @spec add_message(t(), atom(), String.t(), keyword()) :: t()
  def add_message(%Prompt{} = prompt, role, content, opts \\ []) do
    engine = Keyword.get(opts, :engine, :none)

    # Validate system message rules before adding
    messages = prompt.messages
    new_message = MessageItem.new(%{role: role, content: content, engine: engine})
    validate_system_message_rules!(messages ++ [new_message])

    %{prompt | messages: messages ++ [new_message]}
  end

  # Private helper to validate system message rules
  @spec validate_system_message_rules!([MessageItem.t()]) :: :ok | no_return()
  defp validate_system_message_rules!(messages) do
    system_messages = Enum.filter(messages, &(&1.role == :system))

    cond do
      length(system_messages) > 1 ->
        raise ArgumentError, "Only one system message is allowed and it must be first"

      length(system_messages) == 1 && hd(messages).role != :system ->
        raise ArgumentError, "Only one system message is allowed and it must be first"

      true ->
        :ok
    end
  end

  @doc """
  Creates a new version of the prompt.

  This function creates a new version of the prompt by:
  1. Storing the current state in the history
  2. Incrementing the version number
  3. Applying the changes to the prompt

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Hello")
      iex> updated = Prompt.new_version(prompt, fn p -> Prompt.add_message(p, :assistant, "Hi there!") end)
      iex> updated.version
      2
      iex> length(updated.history)
      1
      iex> length(updated.messages)
      2
  """
  @spec new_version(t(), (t() -> t())) :: t()
  def new_version(%Prompt{} = prompt, change_fn) when is_function(change_fn, 1) do
    # Store current state in history
    current_state = %{
      version: prompt.version,
      messages: prompt.messages,
      params: prompt.params,
      metadata: prompt.metadata,
      options: prompt.options,
      output_schema: prompt.output_schema
    }

    # Apply changes to create a new version
    prompt
    |> change_fn.()
    |> Map.put(:version, prompt.version + 1)
    |> Map.put(:history, [current_state | prompt.history])
  end

  @doc """
  Gets a specific version of the prompt.

  Returns the current prompt if version matches the current version,
  or reconstructs a historical version from the history.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Hello")
      iex> updated = Prompt.new_version(prompt, fn p -> Prompt.add_message(p, :assistant, "Hi there!") end)
      iex> {:ok, original} = Prompt.get_version(updated, 1)
      iex> length(original.messages)
      1
      iex> hd(original.messages).content
      "Hello"
  """
  @spec get_version(t(), non_neg_integer()) :: {:ok, t()} | {:error, String.t()}
  def get_version(%Prompt{} = prompt, version) when is_integer(version) and version > 0 do
    cond do
      # Current version
      version == prompt.version ->
        {:ok, prompt}

      # Historical version
      version < prompt.version ->
        case Enum.find(prompt.history, &(&1.version == version)) do
          nil ->
            {:error, "Version #{version} not found in history"}

          historical ->
            reconstructed =
              %{
                prompt
                | messages: historical.messages,
                  params: historical.params,
                  metadata: historical.metadata,
                  options: historical.options || [],
                  output_schema: historical.output_schema,
                  version: historical.version
              }

            {:ok, reconstructed}
        end

      # Future version
      true ->
        {:error, "Cannot get future version #{version} (current: #{prompt.version})"}
    end
  end

  @doc """
  Lists all available versions of the prompt.

  Returns a list of version numbers, with the most recent first.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Hello")
      iex> v2 = Prompt.new_version(prompt, fn p -> Prompt.add_message(p, :assistant, "Hi there!") end)
      iex> v3 = Prompt.new_version(v2, fn p -> Prompt.add_message(p, :user, "How are you?") end)
      iex> Prompt.list_versions(v3)
      [3, 2, 1]
  """
  @spec list_versions(t()) :: list(non_neg_integer())
  def list_versions(%Prompt{} = prompt) do
    [prompt.version | Enum.map(prompt.history, & &1.version)]
  end

  @doc """
  Adds LLM options to the prompt.

  ## Options
  - `:temperature` - Controls randomness. Higher values mean more random completions.
  - `:max_tokens` - Maximum number of tokens to generate in the completion.
  - `:top_p` - Controls diversity via nucleus sampling.
  - `:stop` - Sequences where the API will stop generating tokens.
  - `:timeout` - Request timeout in milliseconds.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Generate a creative story")
      iex> prompt = Prompt.with_options(prompt, temperature: 0.8, max_tokens: 1000)
      iex> prompt.options[:temperature]
      0.8
  """
  @spec with_options(t(), keyword()) :: t()
  def with_options(%Prompt{} = prompt, options) when is_list(options) do
    %{prompt | options: Keyword.merge(prompt.options, options)}
  end

  @doc """
  Sets the temperature option.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Generate a creative story")
      iex> prompt = Prompt.with_temperature(prompt, 0.8)
      iex> prompt.options[:temperature]
      0.8
  """
  @spec with_temperature(t(), number()) :: t()
  def with_temperature(%Prompt{} = prompt, temperature) when is_number(temperature) do
    with_options(prompt, temperature: temperature)
  end

  @doc """
  Sets the max_tokens option.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Summarize this text")
      iex> prompt = Prompt.with_max_tokens(prompt, 500)
      iex> prompt.options[:max_tokens]
      500
  """
  @spec with_max_tokens(t(), non_neg_integer()) :: t()
  def with_max_tokens(%Prompt{} = prompt, max_tokens)
      when is_integer(max_tokens) and max_tokens > 0 do
    with_options(prompt, max_tokens: max_tokens)
  end

  @doc """
  Sets the top_p option.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Generate diverse responses")
      iex> prompt = Prompt.with_top_p(prompt, 0.9)
      iex> prompt.options[:top_p]
      0.9
  """
  @spec with_top_p(t(), number()) :: t()
  def with_top_p(%Prompt{} = prompt, top_p) when is_number(top_p) and top_p > 0 and top_p <= 1 do
    with_options(prompt, top_p: top_p)
  end

  @doc """
  Sets the stop sequences option.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Write until you reach the end")
      iex> prompt = Prompt.with_stop(prompt, ["END", "STOP"])
      iex> prompt.options[:stop]
      ["END", "STOP"]
  """
  @spec with_stop(t(), String.t() | [String.t()]) :: t()
  def with_stop(%Prompt{} = prompt, stop) when is_binary(stop) do
    with_options(prompt, stop: [stop])
  end

  def with_stop(%Prompt{} = prompt, stop) when is_list(stop) do
    with_options(prompt, stop: stop)
  end

  @doc """
  Sets the timeout option in milliseconds.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Process this request")
      iex> prompt = Prompt.with_timeout(prompt, 30000)
      iex> prompt.options[:timeout]
      30000
  """
  @spec with_timeout(t(), non_neg_integer()) :: t()
  def with_timeout(%Prompt{} = prompt, timeout) when is_integer(timeout) and timeout > 0 do
    with_options(prompt, timeout: timeout)
  end

  @doc """
  Sets the output schema for validating LLM responses.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> schema = NimbleOptions.new!([
      ...>   name: [type: :string, required: true],
      ...>   age: [type: :integer, required: true]
      ...> ])
      iex> prompt = Prompt.new(:user, "Generate a person")
      iex> prompt = Prompt.with_output_schema(prompt, schema)
      iex> prompt.output_schema == schema
      true
  """
  @spec with_output_schema(t(), NimbleOptions.t()) :: t()
  def with_output_schema(%Prompt{} = prompt, schema) do
    %{prompt | output_schema: schema}
  end

  @doc """
  Creates a new output schema from the given schema specification.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> schema_spec = [
      ...>   name: [type: :string, required: true],
      ...>   age: [type: :integer, required: true]
      ...> ]
      iex> prompt = Prompt.new(:user, "Generate a person")
      iex> prompt = Prompt.with_new_output_schema(prompt, schema_spec)
      iex> prompt.output_schema != nil
      true
  """
  @spec with_new_output_schema(t(), keyword()) :: t()
  def with_new_output_schema(%Prompt{} = prompt, schema_spec) when is_list(schema_spec) do
    schema = NimbleOptions.new!(schema_spec)
    with_output_schema(prompt, schema)
  end

  @doc """
  Compares two versions of a prompt and returns the differences.

  ## Examples

      iex> alias Jido.AI.Prompt
      iex> prompt = Prompt.new(:user, "Hello")
      iex> v2 = Prompt.new_version(prompt, fn p -> Prompt.add_message(p, :assistant, "Hi there!") end)
      iex> {:ok, diff} = Prompt.compare_versions(v2, 2, 1)
      iex> diff.added_messages
      [%{role: :assistant, content: "Hi there!"}]
  """
  @spec compare_versions(t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, %{added_messages: list(map()), removed_messages: list(map())}}
          | {:error, String.t()}
  def compare_versions(%Prompt{} = prompt, version1, version2)
      when is_integer(version1) and is_integer(version2) and version1 > 0 and version2 > 0 do
    with {:ok, v1} <- get_version(prompt, version1),
         {:ok, v2} <- get_version(prompt, version2) do
      # Convert messages to simple maps for comparison
      v1_msgs = render(v1)
      v2_msgs = render(v2)

      # Find added and removed messages
      added = v1_msgs -- v2_msgs
      removed = v2_msgs -- v1_msgs

      {:ok, %{added_messages: added, removed_messages: removed}}
    end
  end
end
