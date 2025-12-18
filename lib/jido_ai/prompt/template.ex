defmodule Jido.AI.Prompt.Template do
  @moduledoc """
  Enables defining a prompt template and delaying the final
  building of it until a later time when input values are substituted in.

  This also supports the ability to create a Message from a Template.

  PromptTemplates are powerful because they support Elixir's EEx templates
  allowing for parameter substitution. This is helpful when we want to prepare a
  template message and plan to later substitute in information from the user.

  Here's an example of setting up a template using a parameter then later
  providing the input value.

      template = Jido.AI.Prompt.Template.from_string!("What's a name for a company that makes <%= @product %>?")

      # later, format the final text after after applying the values.
      Jido.AI.Prompt.Template.format(template, %{product: "colorful socks"})
      #=> "What's a name for a company that makes colorful socks?"
  """
  require Logger
  alias __MODULE__
  alias Jido.AI.Error
  alias Jido.AI.Prompt.MessageItem

  @enforce_keys [:text]
  defstruct [
    # Core fields
    :text,
    :role,
    :inputs,
    :version,
    :version_history,
    :engine,

    # Metadata fields
    :cacheable,
    :estimated_tokens,
    :created_at,
    :performance_stats,
    :sample_inputs
  ]

  @type t :: %__MODULE__{
          text: String.t(),
          role: :system | :user | :assistant | :function,
          inputs: map(),
          version: non_neg_integer() | nil,
          version_history: list(%{version: non_neg_integer(), text: String.t()}) | nil,
          engine: :eex,
          cacheable: boolean() | nil,
          estimated_tokens: non_neg_integer() | nil,
          created_at: DateTime.t() | nil,
          performance_stats: map() | nil,
          sample_inputs: map()
        }

  @schema NimbleOptions.new!(
            text: [
              type: :string,
              required: true,
              doc: "The template text to format"
            ],
            role: [
              type: {:in, [:system, :user, :assistant, :function]},
              default: :user,
              doc: "The role of the message"
            ],
            engine: [
              type: {:in, [:eex]},
              default: :eex,
              doc: "The template engine to use for formatting"
            ],
            version: [
              type: {:or, [:integer, nil]},
              default: 1,
              doc: "The version of the template"
            ],
            version_history: [
              type: {:or, [{:list, :map}, nil]},
              default: [],
              doc: "History of previous versions"
            ],
            pre_hook: [
              type: {:or, [{:fun, 1}, nil]},
              default: nil,
              doc: "A function to call before formatting the template"
            ],
            post_hook: [
              type: {:or, [{:fun, 1}, nil]},
              default: nil,
              doc: "A function to call after formatting the template"
            ],
            cacheable: [
              type: :boolean,
              default: true,
              doc: "Whether the template can be cached"
            ],
            estimated_tokens: [
              type: {:or, [:integer, nil]},
              default: nil,
              doc: "The estimated number of tokens in the template"
            ],
            sample_inputs: [
              type: :map,
              default: %{},
              doc: "Sample inputs to use for token estimation"
            ],
            created_at: [
              type: :any,
              default: DateTime.utc_now(),
              doc: "When the template was created"
            ],
            performance_stats: [
              type: :map,
              default: %{},
              doc: "Statistics about template usage and performance"
            ],
            inputs: [
              type: :map,
              default: %{},
              doc: "Default inputs to use when formatting the template"
            ]
          )

  @doc """
  Returns the NimbleOptions schema for Template.
  """
  def schema do
    @schema
  end

  @doc """
  Create a new Template struct using the attributes.

  ## Example

      {:ok, template} = Jido.AI.Prompt.Template.new(%{text: "My template", role: :user})
  """
  @spec new(attrs :: map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    # Convert map to keyword list for NimbleOptions
    opts = Map.to_list(attrs)

    case NimbleOptions.validate(opts, @schema) do
      {:ok, options} ->
        # Create struct with default values for missing fields
        template =
          struct(
            __MODULE__,
            Map.merge(
              %{
                role: :user,
                inputs: %{},
                version: 1,
                engine: :eex,
                cacheable: true,
                estimated_tokens: nil,
                created_at: DateTime.utc_now(),
                performance_stats: %{},
                sample_inputs: %{}
              },
              Map.new(options)
            )
          )

        # Validate template syntax without evaluating
        case validate_template_syntax(template) do
          :ok ->
            # Only estimate tokens if we have sample inputs
            template =
              if map_size(template.sample_inputs) > 0 do
                %{template | estimated_tokens: estimate_tokens(template, template.sample_inputs)}
              else
                template
              end

            {:ok, template}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  @doc """
  Create a new Template struct using the attributes. If invalid, an
  exception is raised with the reason.

  ## Example

  A template is created using a simple map with `text` and `role` keys.

      Jido.AI.Prompt.Template.new!(%{text: "My template", role: :user})

  Typically a template is used with parameter substitution as that's
  it's primary purpose. EEx is used to render the final text.

      Jido.AI.Prompt.Template.new!(%{
        text: "My name is <%= @user_name %>. Warmly welcome me.",
        role: :user
      })
  """
  @spec new!(attrs :: map()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, template} ->
        template

      {:error, reason} ->
        raise Error, message: "Invalid prompt template: #{reason}"
    end
  end

  @doc """
  Build a Template struct from a string.

  Shortcut function for building a user prompt.

      {:ok, template} = Jido.AI.Prompt.Template.from_string("Suggest a name for a company that makes <%= @product %>?")
  """
  @spec from_string(text :: String.t(), opts :: keyword()) :: {:ok, t()} | {:error, String.t()}
  def from_string(text, opts \\ []) do
    engine = Keyword.get(opts, :engine, :eex)
    role = Keyword.get(opts, :role, :user)

    Template.new(%{text: text, engine: engine, role: role})
  end

  @doc """
  Build a Template struct from a string and return the struct or error if invalid.

  Shortcut function for building a user prompt.

      template = Jido.AI.Prompt.Template.from_string!("Suggest a name for a company that makes <%= @product %>?")
  """
  @spec from_string!(text :: String.t(), opts :: keyword()) :: t() | no_return()
  def from_string!(text, opts \\ []) do
    case from_string(text, opts) do
      {:ok, template} -> template
      {:error, reason} -> raise Error, message: reason
    end
  end

  @doc """
  Build a Template with default values for parameters.

  This is useful when you want to set some default values that can be overridden later.

      template = Jido.AI.Prompt.Template.from_string_with_defaults(
        "Hello <%= @name %>, welcome to <%= @service %>!",
        %{service: "Jido AI"}
      )
      Jido.AI.Prompt.Template.format(template, %{name: "Alice"})
      #=> "Hello Alice, welcome to Jido AI!"
  """
  @spec from_string_with_defaults(text :: String.t(), defaults :: map(), opts :: keyword()) ::
          {:ok, t()} | {:error, String.t()}
  def from_string_with_defaults(text, defaults \\ %{}, opts \\ []) do
    with {:ok, template} <- from_string(text, opts) do
      {:ok, %{template | inputs: defaults}}
    end
  end

  @doc """
  Build a Template with default values for parameters.
  Raises an exception if the template is invalid.

      template = Jido.AI.Prompt.Template.from_string_with_defaults!(
        "Hello <%= @name %>, welcome to <%= @service %>!",
        %{service: "Jido AI"}
      )
  """
  @spec from_string_with_defaults!(text :: String.t(), defaults :: map(), opts :: keyword()) ::
          t() | no_return()
  def from_string_with_defaults!(text, defaults \\ %{}, opts \\ []) do
    case from_string_with_defaults(text, defaults, opts) do
      {:ok, template} -> template
      {:error, reason} -> raise Error, message: reason
    end
  end

  @doc """
  Format the template with inputs to replace with assigns. It returns the
  formatted text.

      template = Jido.AI.Prompt.Template.from_string!("Suggest a name for a company that makes <%= @product %>?")
      Jido.AI.Prompt.Template.format(template, %{product: "colorful socks"})
      #=> "Suggest a name for a company that makes colorful socks?"

  A Template supports storing input values on the struct. These could be
  set when the template is defined. If an input value is not provided when the
  `format` function is called, any inputs on the struct will be used.
  """
  @spec format(t(), inputs :: map(), opts :: keyword()) :: String.t()
  def format(
        %Template{text: text, inputs: template_inputs, engine: engine},
        inputs \\ %{},
        opts \\ []
      ) do
    pre_hook = Keyword.get(opts, :pre_hook, & &1)
    post_hook = Keyword.get(opts, :post_hook, & &1)

    Map.merge(template_inputs, inputs)
    |> pre_hook.()
    |> then(&format_text(text, &1, engine))
    |> post_hook.()
  end

  @doc """
  Same as format/2 but raises on error.
  """
  def format!(%Template{} = template, inputs) do
    case format(template, inputs) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to format template: #{inspect(reason)}"
    end
  end

  @doc """
  Format the template text with inputs to replace placeholders.

  Operates directly on text to apply the inputs. This does not take the
  Template struct.

      Jido.AI.Prompt.Template.format_text("Hi! My name is <%= @name %>.", %{name: "Jose"})
      #=> "Hi! My name is Jose."
  """
  @spec format_text(text :: String.t(), inputs :: map(), engine :: :eex) :: String.t()
  def format_text(text, inputs, engine \\ :eex) do
    case engine do
      :eex -> format_with_eex(text, inputs)
    end
  end

  @doc """
  Compile a template to check for syntax errors.
  """
  def compile(%__MODULE__{text: text}) do
    compile_with_eex(text)
  end

  defp compile_with_eex(text) do
    compiled = EEx.compile_string(text)
    {:ok, compiled}
  rescue
    e in [EEx.SyntaxError] ->
      raise Jido.AI.Error, "Template compilation error: #{Exception.message(e)}"

    e in CompileError ->
      {:error, Exception.message(e)}

    e ->
      {:error, "Unexpected error: #{Exception.message(e)}"}
  end

  defp format_with_eex(text, inputs) do
    EEx.eval_string(text, assigns: inputs)
  rescue
    e in [RuntimeError] ->
      raise Jido.AI.Error, "Template formatting error: #{Exception.message(e)}"

    e in CompileError ->
      raise Jido.AI.Error, "Template compilation error: #{Exception.message(e)}"

    e ->
      raise Jido.AI.Error, "Unexpected error: #{Exception.message(e)}"
  end

  @doc """
  Format a template with sub-templates.

  This is useful when you want to compose a template from other templates.
  The sub-templates can be either Template structs or strings.

  ## Example

      main = Template.new!(%{text: "Header: <%= @intro %>\nBody: <%= @body %>"})
      intro = Template.new!(%{text: "Welcome <%= @name %>!"})
      body = "This is the body text."

      Template.format_composed(main, %{intro: intro, body: body}, %{name: "Alice"})
      #=> "Header: Welcome Alice!\nBody: This is the body text."
  """
  @spec format_composed(t(), sub_templates :: map(), inputs :: map()) :: String.t()
  def format_composed(%Template{} = template, sub_templates, inputs \\ %{}) do
    # First format all sub-templates
    formatted_subs =
      Enum.reduce(sub_templates, %{}, fn {key, sub}, acc ->
        formatted =
          case sub do
            %Template{} = t -> format(t, inputs)
            str when is_binary(str) -> str
            _ -> raise Error, message: "Invalid sub-template: #{inspect(sub)}"
          end

        Map.put(acc, key, formatted)
      end)

    # Then format the main template with the formatted sub-templates
    format(template, formatted_subs)
  end

  @doc """
  Convert a template to a MessageItem struct.

  This is useful when you want to use a template as part of a conversation.
  """
  @spec to_message(t(), inputs :: map()) :: {:ok, MessageItem.t()} | {:error, String.t()}
  def to_message(%Template{} = template, inputs \\ %{}) do
    content = format(template, inputs)
    {:ok, MessageItem.new(%{role: template.role, content: content})}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Convert a template to a MessageItem struct. Raises if there's an error.
  """
  @spec to_message!(t(), inputs :: map()) :: MessageItem.t() | no_return()
  def to_message!(%Template{} = template, inputs \\ %{}) do
    content = format(template, inputs)
    MessageItem.new(%{role: template.role, content: content})
  end

  @doc """
  Convert a list of templates, message items, and strings to a list of message items.

  This is useful when you want to build a conversation from a mix of
  templates and messages.

  ## Example

      t1 = Template.new!(%{text: "System: <%= @sysinfo %>", role: :system})
      t2 = Template.new!(%{text: "Question: <%= @question %>", role: :user})

      messages = Template.to_messages!([t1, t2, "A direct user string"], %{
        sysinfo: "Guide the user",
        question: "What is 2+2?"
      })
  """
  @spec to_messages!(list(), inputs :: map()) :: [MessageItem.t()]
  def to_messages!(templates_or_messages, inputs \\ %{}) do
    Enum.map(templates_or_messages, fn
      %Template{} = t -> to_message!(t, inputs)
      %MessageItem{} = m -> m
      text when is_binary(text) -> MessageItem.new(%{role: :user, content: text})
    end)
  end

  @doc """
  Estimates the number of tokens that would be used by this template.
  This is useful for ensuring prompts don't exceed model token limits.

  Note: This is a very rough estimation - tokens vary by model.
  """
  @spec estimate_tokens(t(), inputs :: map()) :: integer()
  def estimate_tokens(%Template{} = template, inputs \\ %{}) do
    formatted = format(template, inputs)
    # Very rough estimate: ~4 characters per token for English text
    (String.length(formatted) / 4) |> round()
  rescue
    _ -> 0
  end

  @doc """
  Sanitizes user inputs to prevent template injection attacks.
  """
  def sanitize_inputs(inputs) when is_map(inputs) do
    inputs
    |> Enum.map(fn {key, value} -> {key, sanitize_value(value)} end)
    |> Map.new()
  end

  defp sanitize_value(value) when is_binary(value) do
    value
    |> String.replace("<", "\\<")
    |> String.replace(">", "\\>")
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value

  @doc """
  Records usage statistics for the template.

  ## Parameters
    - template: The template to update
    - metrics: A map containing metrics to record, such as:
      - tokens_used: Number of tokens used in the response
      - response_time_ms: Time taken to generate response
      - success: Whether the generation was successful

  ## Example
      template = record_usage(template, %{
        tokens_used: 150,
        response_time_ms: 500,
        success: true
      })
  """
  @spec record_usage(t(), map()) :: t()
  def record_usage(%__MODULE__{} = template, metrics) do
    stats = Map.get(template, :performance_stats, %{})

    # Update basic metrics
    stats =
      Map.merge(stats, %{
        usage_count: Map.get(stats, :usage_count, 0) + 1,
        last_used_at: DateTime.utc_now()
      })

    # Add additional metrics if provided
    stats =
      if metrics[:tokens_used] do
        Map.put(
          stats,
          :avg_tokens,
          calculate_average(stats[:avg_tokens], stats[:usage_count], metrics[:tokens_used])
        )
      else
        stats
      end

    stats =
      if metrics[:response_time_ms] do
        Map.put(
          stats,
          :avg_response_time,
          calculate_average(
            stats[:avg_response_time],
            stats[:usage_count],
            metrics[:response_time_ms]
          )
        )
      else
        stats
      end

    # Track success rate
    stats =
      if Map.has_key?(metrics, :success) do
        success_count = Map.get(stats, :success_count, 0) + if metrics.success, do: 1, else: 0
        Map.put(stats, :success_count, success_count)
      else
        stats
      end

    %{template | performance_stats: stats}
  end

  @doc """
  Increments the version number of the template.
  Returns a new template with the incremented version and adds the previous
  version to history.
  """
  def increment_version(%__MODULE__{} = template) do
    current_version = template.version || 1
    history = template.version_history || []

    # Add current state to history
    history_entry = %{
      version: current_version,
      text: template.text
    }

    # Update with new version
    %{template | version: current_version + 1, version_history: [history_entry | history]}
  end

  @doc """
  Updates template text and automatically increments version
  """
  def update_text(%__MODULE__{} = template, new_text) do
    # First add current version to history
    template = increment_version(template)

    # Then update the text
    %{template | text: new_text}
  end

  @doc """
  Rolls back to a specific version if it exists in history
  """
  def rollback_to_version(%__MODULE__{version_history: history} = template, version)
      when is_integer(version) and is_list(history) do
    case Enum.find(history, fn entry -> entry.version == version end) do
      nil ->
        {:error, "Version #{version} not found in history"}

      %{text: old_text} ->
        # Remove the entry from history
        new_history = Enum.reject(history, fn e -> e.version == version end)

        # Restore the text but keep the current version number
        {:ok, %{template | text: old_text, version_history: new_history}}
    end
  end

  @doc """
  Lists all available versions of the template
  """
  def list_versions(%__MODULE__{version: current_version, version_history: history}) do
    # Current version plus history
    [%{version: current_version, current: true}] ++
      Enum.map(history, fn %{version: v} -> %{version: v, current: false} end)
  end

  @doc """
  Creates a clean copy with reset version history
  """
  def create_clean_copy(%__MODULE__{} = template) do
    %{template | version: 1, version_history: []}
  end

  # Private helper to calculate running averages
  defp calculate_average(nil, _, new_value), do: new_value

  defp calculate_average(current_avg, count, new_value) do
    (current_avg * (count - 1) + new_value) / count
  end

  @doc """
  Validates the syntax of a template without evaluating it.
  """
  def validate_template_syntax(%__MODULE__{text: text, engine: :eex}) do
    case compile_with_eex(text) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      {:error, "Template compilation error: #{Exception.message(e)}"}
  end
end
