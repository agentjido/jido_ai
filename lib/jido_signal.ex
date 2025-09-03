defmodule Jido.Signal do
  @moduledoc """
  Defines the core Signal structure in Jido, implementing the CloudEvents specification (v1.0.2)
  with Jido-specific extensions for agent-based systems.

  https://cloudevents.io/

  ## Overview

  Signals are the universal message format in Jido, serving as the nervous system of your
  agent-based application. Every event, command, and state change flows through the system
  as a Signal, providing:

  - Standardized event structure (CloudEvents v1.0.2 compatible)
  - Rich metadata and context tracking
  - Flexible dispatch configuration
  - Automatic serialization

  ## CloudEvents Compliance

  Each Signal implements the CloudEvents v1.0.2 specification with these required fields:

  - `specversion`: Always "1.0.2"
  - `id`: Unique identifier (UUID v4)
  - `source`: Origin of the event ("/service/component")
  - `type`: Classification of the event ("domain.entity.action")

  And optional fields:

  - `subject`: Specific subject of the event
  - `time`: Timestamp in ISO 8601 format
  - `datacontenttype`: Media type of the data (defaults to "application/json")
  - `dataschema`: Schema defining the data structure
  - `data`: The actual event payload

  ## Jido Extensions

  Beyond the CloudEvents spec, Signals include Jido-specific fields:

  - `jido_dispatch`: Routing and delivery configuration (optional)

  ## Creating Signals

  Signals can be created in several ways (prefer the positional new/3):

  ```elixir
  alias Jido.Signal

  # Preferred: positional constructor (type, data, attrs)
  {:ok, signal} = Signal.new("metrics.collected", %{cpu: 80, memory: 70},
    source: "/monitoring",
    jido_dispatch: {:pubsub, topic: "metrics"}
  )

  # Also available: map/keyword constructor (backwards compatible)
  {:ok, signal} = Signal.new(%{
    type: "user.created",
    source: "/auth/registration",
    data: %{user_id: "123", email: "user@example.com"}
  })

  # Data payloads follow CloudEvents rules:
  # - When datacontenttype is JSON (or omitted in JSON format), `data` can be any JSON value
  #   (object/map, array, string, number, boolean, null)
  # - For non-JSON payloads, encode according to datacontenttype; binary payloads use data_base64 during JSON serialization
  ```

  ## Custom Signal Types

  You can define custom Signal types using the `use Jido.Signal` pattern:

  ```elixir
  defmodule MySignal do
    use Jido.Signal,
      type: "my.custom.signal",
      default_source: "/my/service",
      datacontenttype: "application/json",
      schema: [
        user_id: [type: :string, required: true],
        message: [type: :string, required: true]
      ]
  end

  # Create instances
  {:ok, signal} = MySignal.new(%{user_id: "123", message: "Hello"})

  # Override runtime fields
  {:ok, signal} = MySignal.new(
    %{user_id: "123", message: "Hello"},
    source: "/different/source",
    subject: "user-notification",
    jido_dispatch: {:pubsub, topic: "events"}
  )
  ```

  ## Signal Types

  Signal types are strings, but typically use a hierarchical dot notation:

  ```
  <domain>.<entity>.<action>[.<qualifier>]
  ```

  Examples:
  - `user.profile.updated`
  - `order.payment.processed.success`
  - `system.metrics.collected`

  Guidelines for type naming:
  - Use lowercase with dots
  - Keep segments meaningful
  - Order from general to specific
  - Include qualifiers when needed

  ## Data Content Types

  The `datacontenttype` field indicates the format of the `data` field:

  - `application/json` (default) - JSON-structured data
  - `text/plain` - Unstructured text
  - `application/octet-stream` - Binary data
  - Custom MIME types for specific formats

  ## Dispatch Configuration

  The `jido_dispatch` field controls how the Signal is delivered:

  ```elixir
  # Single dispatch config
  jido_dispatch: {:pubsub, topic: "events"}

  # Multiple dispatch targets
  jido_dispatch: [
    {:pubsub, topic: "events"},
    {:logger, level: :info},
    {:webhook, url: "https://api.example.com/webhook"}
  ]
  ```

  ## See Also

  - `Jido.Signal.Router` - Signal routing
  - `Jido.Signal.Dispatch` - Dispatch handling
  - CloudEvents spec: https://cloudevents.io/
  """
  use TypedStruct

  import Jido.Signal.Ext.Registry, only: [get: 1]

  alias Jido.Signal.Dispatch
  alias Jido.Signal.Ext
  alias Jido.Signal.ID
  alias Jido.Signal.Serialization.Serializer
  alias Jido.Signal.Serialization.TypeProvider

  require Logger

  @core_attrs ~w[
    specversion id source type subject time
    datacontenttype dataschema data jido_dispatch extensions
  ]a

  @signal_config_schema NimbleOptions.new!(
                          type: [
                            type: :string,
                            required: true,
                            doc: "The type of the Signal"
                          ],
                          default_source: [
                            type: :string,
                            required: false,
                            doc: "The default source of the Signal"
                          ],
                          datacontenttype: [
                            type: :string,
                            required: false,
                            doc: "The content type of the data field"
                          ],
                          dataschema: [
                            type: :string,
                            required: false,
                            doc: "Schema URI for the data field (optional)"
                          ],
                          schema: [
                            type: :keyword_list,
                            default: [],
                            doc:
                              "A NimbleOptions schema for validating the Signal's data parameters"
                          ]
                        )

  @derive {Jason.Encoder,
           only: [
             :id,
             :source,
             :type,
             :subject,
             :time,
             :datacontenttype,
             :dataschema,
             :data,
             :specversion,
             :extensions
           ]}

  typedstruct do
    field(:specversion, String.t(), default: "1.0.2")
    field(:id, String.t(), enforce: true, default: ID.generate!())
    field(:source, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:subject, String.t())
    field(:time, String.t())
    field(:datacontenttype, String.t())
    field(:dataschema, String.t())
    field(:data, term())
    field(:extensions, map(), default: %{})
    # Jido-specific fields
    field(:jido_dispatch, Dispatch.dispatch_configs())
  end

  @doc """
  Defines a new Signal module.

  This macro sets up the necessary structure and callbacks for a custom Signal,
  including configuration validation and default implementations.

  ## Options

  #{NimbleOptions.docs(@signal_config_schema)}

  ## Examples

      defmodule MySignal do
        use Jido.Signal,
          type: "my.custom.signal",
          default_source: "/my/service",
          schema: [
            user_id: [type: :string, required: true],
            message: [type: :string, required: true]
          ]
      end

  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@signal_config_schema)

    quote location: :keep do
      alias Jido.Signal
      alias Jido.Signal.Error
      alias Jido.Signal.ID

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          def type, do: @validated_opts[:type]
          def default_source, do: @validated_opts[:default_source]
          def datacontenttype, do: @validated_opts[:datacontenttype]
          def dataschema, do: @validated_opts[:dataschema]
          def schema, do: @validated_opts[:schema]

          def to_json do
            %{
              datacontenttype: @validated_opts[:datacontenttype],
              dataschema: @validated_opts[:dataschema],
              default_source: @validated_opts[:default_source],
              schema: @validated_opts[:schema],
              type: @validated_opts[:type]
            }
          end

          def __signal_metadata__ do
            to_json()
          end

          @doc """
          Creates a new Signal instance with the configured type and validated data.

          ## Parameters

          - `data`: A map containing the Signal's data payload.
          - `opts`: Additional Signal options (source, subject, etc.)

          ## Returns

          `{:ok, Signal.t()}` if the data is valid, `{:error, String.t()}` otherwise.

          ## Examples

              iex> MySignal.new(%{user_id: "123", message: "Hello"})
              {:ok, %Jido.Signal{type: "my.custom.signal", data: %{user_id: "123", message: "Hello"}, ...}}

          """
          @spec new(map(), keyword()) :: {:ok, Signal.t()} | {:error, String.t()}
          def new(data \\ %{}, opts \\ []) do
            with {:ok, validated_data} <- validate_data(data),
                 {:ok, signal_attrs} <- build_signal_attrs(validated_data, opts) do
              Signal.from_map(signal_attrs)
            end
          end

          @doc """
          Creates a new Signal instance, raising an error if invalid.

          ## Parameters

          - `data`: A map containing the Signal's data payload.
          - `opts`: Additional Signal options (source, subject, etc.)

          ## Returns

          `Signal.t()` if the data is valid.

          ## Raises

          `RuntimeError` if the data is invalid.

          ## Examples

              iex> MySignal.new!(%{user_id: "123", message: "Hello"})
              %Jido.Signal{type: "my.custom.signal", data: %{user_id: "123", message: "Hello"}, ...}

          """
          @spec new!(map(), keyword()) :: Signal.t() | no_return()
          def new!(data \\ %{}, opts \\ []) do
            case new(data, opts) do
              {:ok, signal} -> signal
              {:error, reason} -> raise reason
            end
          end

          @doc """
          Validates the data for the Signal according to its schema.

          ## Examples

              iex> MySignal.validate_data(%{user_id: "123", message: "Hello"})
              {:ok, %{user_id: "123", message: "Hello"}}

              iex> MySignal.validate_data(%{})
              {:error, "Invalid data for Signal: Required key :user_id not found"}

          """
          @spec validate_data(map()) :: {:ok, map()} | {:error, String.t()}
          def validate_data(data) do
            case @validated_opts[:schema] do
              [] ->
                {:ok, data}

              schema when is_list(schema) ->
                case NimbleOptions.validate(Enum.to_list(data), schema) do
                  {:ok, validated_data} ->
                    {:ok, Map.new(validated_data)}

                  {:error, %NimbleOptions.ValidationError{} = error} ->
                    reason =
                      Error.format_nimble_validation_error(
                        error,
                        "Signal",
                        __MODULE__
                      )

                    {:error, reason}
                end
            end
          end

          defp build_signal_attrs(validated_data, opts) do
            caller =
              self()
              |> Process.info(:current_stacktrace)
              |> elem(1)
              |> Enum.find(fn {mod, _fun, _arity, _info} ->
                mod_str = to_string(mod)
                mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
              end)
              |> elem(0)
              |> to_string()

            attrs = %{
              "data" => validated_data,
              "id" => ID.generate!(),
              "source" => @validated_opts[:default_source] || caller,
              "specversion" => "1.0.2",
              "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "type" => @validated_opts[:type]
            }

            attrs =
              if @validated_opts[:datacontenttype],
                do: Map.put(attrs, "datacontenttype", @validated_opts[:datacontenttype]),
                else: attrs

            attrs =
              if @validated_opts[:dataschema],
                do: Map.put(attrs, "dataschema", @validated_opts[:dataschema]),
                else: attrs

            # Override with any user-provided options
            final_attrs =
              Enum.reduce(opts, attrs, fn {key, value}, acc ->
                Map.put(acc, to_string(key), value)
              end)

            {:ok, final_attrs}
          end

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Signal", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end

  @doc """
  Creates a new Signal struct with explicit type and data, raising an error if invalid.

  ## Parameters

  - `type`: A string representing the event type (e.g., `"user.created"`).
  - `data`: The payload (any term; see CloudEvents rules below).
  - `attrs`: (Optional) A map or keyword list of additional Signal attributes (e.g., `:source`, `:subject`, `:jido_dispatch`).

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `ArgumentError` if the attributes are invalid.

  ## Examples

      iex> Jido.Signal.new!("user.created", %{user_id: "123"}, source: "/auth")
      %Jido.Signal{type: "user.created", source: "/auth", data: %{user_id: "123"}, ...}

      iex> Jido.Signal.new!("user.created", %{user_id: "123"})
      %Jido.Signal{type: "user.created", source: "...", data: %{user_id: "123"}, ...}

  """
  @spec new!(String.t(), term(), map() | keyword()) :: t() | no_return()
  def new!(type, data, attrs \\ %{}) do
    case new(type, data, attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise ArgumentError, "invalid signal: #{reason}"
    end
  end

  @doc """
  Creates a new Signal struct, raising an error if invalid.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `Signal.t()` if the attributes are valid.

  ## Raises

  `RuntimeError` if the attributes are invalid.

  ## Examples

      iex> Jido.Signal.new!(%{type: "example.event", source: "/example"})
      %Jido.Signal{type: "example.event", source: "/example", ...}

      iex> Jido.Signal.new!(type: "example.event", source: "/example")
      %Jido.Signal{type: "example.event", source: "/example", ...}

  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Creates a new Signal struct.

  ## Parameters

  - `attrs`: A map or keyword list containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the attributes are valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.new(%{type: "example.event", source: "/example", id: "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

      iex> Jido.Signal.new(type: "example.event", source: "/example")
      {:ok, %Jido.Signal{type: "example.event", source: "/example", ...}}

  """
  @reserved_keys [:type, "type", :data, "data"]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs) do
    attrs |> Map.new() |> new()
  end

  def new(attrs) when is_map(attrs) do
    caller =
      self()
      |> Process.info(:current_stacktrace)
      |> elem(1)
      |> Enum.find(fn {mod, _fun, _arity, _info} ->
        mod_str = to_string(mod)
        mod_str != "Elixir.Jido.Signal" and mod_str != "Elixir.Process"
      end)
      |> elem(0)
      |> to_string()

    defaults = %{
      "id" => ID.generate!(),
      "source" => caller,
      "specversion" => "1.0.2",
      "time" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.merge(defaults, fn _k, user_val, _default_val -> user_val end)
    |> from_map()
  end

  @doc """
  Creates a Signal with explicit type and payload, plus optional attrs.

  - `type` must be a string
  - `data` can be any term (map, string, etc.)
  - `attrs` is a map or keyword list for other fields (e.g., `:source`, `:subject`, `:jido_dispatch`)
  - `attrs` must NOT include `:type`/`"type"` or `:data`/`"data"`

  Examples:
      iex> {:ok, s} = Jido.Signal.new("user.created", %{user_id: "123"}, source: "/auth")
      iex> s.type
      "user.created"
      iex> {:ok, s} = Jido.Signal.new("log.message", "Hello world")
      iex> s.data
      "Hello world"
  """
  @spec new(String.t(), term(), map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(type, data, attrs \\ %{})

  def new(type, data, attrs) when is_binary(type) and (is_map(attrs) or is_list(attrs)) do
    with {:ok, normalized_attrs} <- normalize_and_validate_attrs(attrs) do
      normalized_attrs
      |> Map.merge(%{data: data, type: type})
      |> new()
    end
  end

  def new(_, _, _),
    do: {:error, "expected new/3 (type :: String.t(), data :: any(), attrs :: map/keyword)"}

  defp normalize_and_validate_attrs(attrs) when is_list(attrs) do
    normalize_and_validate_attrs(Map.new(attrs))
  end

  defp normalize_and_validate_attrs(attrs) when is_map(attrs) do
    case Enum.find(@reserved_keys, &Map.has_key?(attrs, &1)) do
      nil -> {:ok, attrs}
      key -> {:error, "attribute #{inspect(key)} must not be passed in attrs when calling new/3"}
    end
  end

  @doc """
  Creates a new Signal struct from a map.

  ## Parameters

  - `map`: A map containing the Signal attributes.

  ## Returns

  `{:ok, Signal.t()}` if the map is valid, `{:error, String.t()}` otherwise.

  ## Examples

      iex> Jido.Signal.from_map(%{"type" => "example.event", "source" => "/example", "id" => "123"})
      {:ok, %Jido.Signal{type: "example.event", source: "/example", id: "123", ...}}

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    {extensions_data, remaining_attrs} = inflate_extensions(map)

    # Parse extensions that were explicitly stored in "extensions" field
    final_extensions =
      case parse_extensions(remaining_attrs["extensions"]) do
        {:ok, explicit} -> Map.merge(extensions_data, explicit)
        {:error, _} -> extensions_data
      end

    {core, maybe_ext} = Map.split(remaining_attrs, @core_attrs |> Enum.map(&to_string/1))

    unknown_extensions =
      Enum.reduce(maybe_ext, %{}, fn {k, v}, acc ->
        ns = to_string(k)

        case Jido.Signal.Ext.Registry.get(ns) do
          {:ok, _mod} ->
            acc

          {:error, :not_found} ->
            Logger.warning("Unknown extension '#{ns}' encountered - preserving as opaque data")
            Map.put(acc, ns, v)
        end
      end)

    all_extensions = Map.merge(final_extensions, unknown_extensions)
    remaining_attrs = core

    with :ok <- parse_specversion(remaining_attrs),
         {:ok, type} <- parse_type(remaining_attrs),
         {:ok, source} <- parse_source(remaining_attrs),
         {:ok, id} <- parse_id(remaining_attrs),
         {:ok, subject} <- parse_subject(remaining_attrs),
         {:ok, time} <- parse_time(remaining_attrs),
         {:ok, datacontenttype} <- parse_datacontenttype(remaining_attrs),
         {:ok, dataschema} <- parse_dataschema(remaining_attrs),
         {:ok, data} <- parse_data(remaining_attrs["data"]),
         {:ok, jido_dispatch} <- parse_jido_dispatch(remaining_attrs["jido_dispatch"]) do
      event = %__MODULE__{
        data: data,
        datacontenttype: datacontenttype || if(data, do: "application/json"),
        dataschema: dataschema,
        extensions: all_extensions,
        id: id,
        jido_dispatch: jido_dispatch,
        source: source,
        specversion: "1.0.2",
        subject: subject,
        time: time,
        type: type
      }

      {:ok, event}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  @doc """
  Converts a struct or list of structs to Signal data format.

  This function is useful for converting domain objects to Signal format
  while preserving their type information through the TypeProvider.

  ## Parameters

  - `signals`: A struct or list of structs to convert
  - `fields`: Additional fields to include (currently unused)

  ## Returns

  Signal struct or list of Signal structs with the original data as payload

  ## Examples

      # Converting a single struct
      iex> user = %User{id: 1, name: "John"}
      iex> signal = Jido.Signal.map_to_signal_data(user)
      iex> signal.data
      %User{id: 1, name: "John"}

      # Converting multiple structs
      iex> users = [%User{id: 1}, %User{id: 2}]
      iex> signals = Jido.Signal.map_to_signal_data(users)
      iex> length(signals)
      2
  """
  def map_to_signal_data(signals, fields \\ [])

  @spec map_to_signal_data(list(struct), Keyword.t()) :: list(t())
  def map_to_signal_data(signals, fields) when is_list(signals) do
    Enum.map(signals, &map_to_signal_data(&1, fields))
  end

  @spec map_to_signal_data(struct, Keyword.t()) :: t()
  def map_to_signal_data(signal, fields) do
    source = Keyword.get(fields, :source, "/#{inspect(signal.__struct__)}")

    %__MODULE__{
      data: signal,
      id: ID.generate(),
      source: source,
      type: TypeProvider.to_string(signal)
    }
  end

  # Parser functions for standard CloudEvents fields

  @spec parse_specversion(map()) :: :ok | {:error, String.t()}
  defp parse_specversion(%{"specversion" => "1.0.2"}), do: :ok
  defp parse_specversion(%{"specversion" => x}), do: {:error, "unexpected specversion #{x}"}
  defp parse_specversion(_), do: {:error, "missing specversion"}

  @spec parse_type(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_type(%{"type" => type}) when byte_size(type) > 0, do: {:ok, type}
  defp parse_type(_), do: {:error, "missing type"}

  @spec parse_source(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_source(%{"source" => source}) when byte_size(source) > 0, do: {:ok, source}
  defp parse_source(_), do: {:error, "missing source"}

  @spec parse_id(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp parse_id(%{"id" => id}) when byte_size(id) > 0, do: {:ok, id}
  defp parse_id(%{"id" => ""}), do: {:error, "id given but empty"}
  defp parse_id(_), do: {:ok, ID.generate!()}

  @spec parse_subject(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_subject(%{"subject" => sub}) when byte_size(sub) > 0, do: {:ok, sub}
  defp parse_subject(%{"subject" => ""}), do: {:error, "subject given but empty"}
  defp parse_subject(_), do: {:ok, nil}

  @spec parse_time(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_time(%{"time" => time}) when byte_size(time) > 0, do: {:ok, time}
  defp parse_time(%{"time" => ""}), do: {:error, "time given but empty"}
  defp parse_time(_), do: {:ok, nil}

  @spec parse_datacontenttype(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_datacontenttype(%{"datacontenttype" => ct}) when byte_size(ct) > 0, do: {:ok, ct}

  defp parse_datacontenttype(%{"datacontenttype" => ""}),
    do: {:error, "datacontenttype given but empty"}

  defp parse_datacontenttype(_), do: {:ok, nil}

  @spec parse_dataschema(map()) :: {:ok, String.t() | nil} | {:error, String.t()}
  defp parse_dataschema(%{"dataschema" => schema}) when byte_size(schema) > 0, do: {:ok, schema}
  defp parse_dataschema(%{"dataschema" => ""}), do: {:error, "dataschema given but empty"}
  defp parse_dataschema(_), do: {:ok, nil}

  @spec parse_data(term()) :: {:ok, term()} | {:error, String.t()}
  defp parse_data(""), do: {:error, "data field given but empty"}
  defp parse_data(data), do: {:ok, data}

  @spec parse_jido_dispatch(term()) :: {:ok, term() | nil} | {:error, String.t()}
  defp parse_jido_dispatch(nil), do: {:ok, nil}

  defp parse_jido_dispatch({adapter, opts} = config) when is_atom(adapter) and is_list(opts) do
    {:ok, config}
  end

  defp parse_jido_dispatch(config) when is_list(config) do
    {:ok, config}
  end

  defp parse_jido_dispatch(_), do: {:error, "invalid dispatch config"}

  @spec parse_extensions(term()) :: {:ok, map()} | {:error, String.t()}
  defp parse_extensions(nil), do: {:ok, %{}}
  defp parse_extensions(extensions) when is_map(extensions), do: {:ok, extensions}
  defp parse_extensions(_), do: {:error, "invalid extensions"}

  @doc """
  Serializes a Signal or a list of Signals using the specified or default serializer.

  ## Parameters

  - `signal_or_list`: A Signal struct or list of Signal structs
  - `opts`: Optional configuration including:
    - `:serializer` - The serializer module to use (defaults to configured serializer)

  ## Returns

  `{:ok, binary}` on success, `{:error, reason}` on failure

  ## Examples

      iex> signal = %Jido.Signal{type: "example.event", source: "/example"}
      iex> {:ok, binary} = Jido.Signal.serialize(signal)
      iex> is_binary(binary)
      true

      # Using a specific serializer
      iex> {:ok, binary} = Jido.Signal.serialize(signal, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
      iex> is_binary(binary)
      true

      # Serializing multiple Signals
      iex> signals = [
      ...>   %Jido.Signal{type: "event1", source: "/ex1"},
      ...>   %Jido.Signal{type: "event2", source: "/ex2"}
      ...> ]
      iex> {:ok, binary} = Jido.Signal.serialize(signals)
      iex> is_binary(binary)
      true
  """
  @spec serialize(t() | list(t()), keyword()) :: {:ok, binary()} | {:error, term()}
  def serialize(signal_or_list, opts \\ [])

  def serialize(%__MODULE__{} = signal, opts) do
    Serializer.serialize(signal, opts)
  end

  def serialize(signals, opts) when is_list(signals) do
    Serializer.serialize(signals, opts)
  end

  @doc """
  Legacy serialize function that returns binary directly (for backward compatibility).
  """
  @spec serialize!(t() | list(t()), keyword()) :: binary()
  def serialize!(signal_or_list, opts \\ []) do
    case serialize(signal_or_list, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Serialization failed: #{reason}"
    end
  end

  @doc """
  Deserializes binary data back into a Signal struct or list of Signal structs.

  ## Parameters

  - `binary`: The serialized binary data to deserialize
  - `opts`: Optional configuration including:
    - `:serializer` - The serializer module to use (defaults to configured serializer)
    - `:type` - Specific type to deserialize to
    - `:type_provider` - Custom type provider

  ## Returns

  `{:ok, Signal.t() | list(Signal.t())}` if successful, `{:error, reason}` otherwise

  ## Examples

      # JSON deserialization (default)
      iex> json = ~s({"type":"example.event","source":"/example","id":"123"})
      iex> {:ok, signal} = Jido.Signal.deserialize(json)
      iex> signal.type
      "example.event"

      # Using a specific serializer
      iex> {:ok, signal} = Jido.Signal.deserialize(binary, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
      iex> signal.type
      "example.event"

      # Deserializing multiple Signals
      iex> json = ~s([{"type":"event1","source":"/ex1"},{"type":"event2","source":"/ex2"}])
      iex> {:ok, signals} = Jido.Signal.deserialize(json)
      iex> length(signals)
      2
  """
  @spec deserialize(binary(), keyword()) :: {:ok, t() | list(t())} | {:error, term()}
  def deserialize(binary, opts \\ []) when is_binary(binary) do
    case Serializer.deserialize(binary, opts) do
      {:ok, data} ->
        result =
          if is_list(data) do
            # Handle array of Signals
            Enum.map(data, fn signal_data ->
              case convert_to_signal(signal_data) do
                {:ok, signal} -> signal
                {:error, reason} -> raise "Failed to parse signal: #{reason}"
              end
            end)
          else
            # Handle single Signal
            case convert_to_signal(data) do
              {:ok, signal} -> signal
              {:error, reason} -> raise "Failed to parse signal: #{reason}"
            end
          end

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Convert deserialized data to Signal struct
  defp convert_to_signal(%__MODULE__{} = signal), do: {:ok, signal}

  defp convert_to_signal(data) when is_map(data) do
    from_map(data)
  end

  defp convert_to_signal(data) do
    {:error, "Cannot convert #{inspect(data)} to Signal"}
  end

  @doc """
  Adds extension data to a Signal.

  Validates the extension data against the extension's schema and stores it
  in the Signal's extensions map under the extension's namespace.

  ## Parameters

  - `signal` - The Signal struct to add the extension to
  - `namespace` - The extension namespace (string)
  - `data` - The extension data to add

  ## Returns

  `{:ok, Signal.t()}` if successful, `{:error, reason}` if validation fails

  ## Examples

      # Add authentication extension data
      {:ok, signal} = Jido.Signal.put_extension(signal, "auth", %{user_id: "123"})

      # Validation will occur based on extension schema
      {:ok, signal} = Jido.Signal.put_extension(signal, "tracking", %{session_id: "abc"})
  """
  @spec put_extension(t(), String.t(), term()) :: {:ok, t()} | {:error, String.t()}
  def put_extension(%__MODULE__{} = signal, namespace, data) when is_binary(namespace) do
    case get(namespace) do
      {:ok, extension_module} ->
        case Ext.safe_validate_data(extension_module, data) do
          {:ok, {:ok, validated_data}} ->
            updated_extensions = Map.put(signal.extensions, namespace, validated_data)
            {:ok, %{signal | extensions: updated_extensions}}

          {:ok, {:error, reason}} ->
            {:error, reason}

          {:error, reason} ->
            {:error, "extension #{namespace} validation failed: #{inspect(reason)}"}
        end

      {:error, :not_found} ->
        {:error, "Unknown extension: #{namespace}"}
    end
  end

  def put_extension(_, _, _) do
    {:error, "Expected Signal struct, namespace string, and extension data"}
  end

  @doc """
  Retrieves extension data from a Signal.

  Returns the extension data stored under the given namespace, or nil
  if no data exists for that extension.

  ## Parameters

  - `signal` - The Signal struct to retrieve from
  - `namespace` - The extension namespace (string)

  ## Returns

  The extension data if present, `nil` otherwise

  ## Examples

      # Retrieve authentication data
      auth_data = Jido.Signal.get_extension(signal, "auth")
      # => %{user_id: "123", roles: ["user"]}

      # Non-existent extension returns nil
      missing = Jido.Signal.get_extension(signal, "nonexistent")
      # => nil
  """
  @spec get_extension(t(), String.t()) :: term() | nil
  def get_extension(%__MODULE__{} = signal, namespace) when is_binary(namespace) do
    case get(namespace) do
      {:ok, _extension_module} ->
        Map.get(signal.extensions, namespace)

      {:error, :not_found} ->
        nil
    end
  end

  def get_extension(_, _), do: nil

  @doc """
  Removes extension data from a Signal.

  Removes the extension data stored under the given namespace and returns
  the updated Signal.

  ## Parameters

  - `signal` - The Signal struct to remove from
  - `namespace` - The extension namespace (string)

  ## Returns

  The updated Signal struct with the extension removed

  ## Examples

      # Remove authentication extension
      updated_signal = Jido.Signal.delete_extension(signal, "auth")

      # Extension data is no longer present
      nil = Jido.Signal.get_extension(updated_signal, "auth")
  """
  @spec delete_extension(t(), String.t()) :: t()
  def delete_extension(%__MODULE__{} = signal, namespace) when is_binary(namespace) do
    updated_extensions = Map.delete(signal.extensions, namespace)
    %{signal | extensions: updated_extensions}
  end

  def delete_extension(signal, _), do: signal

  @doc """
  Lists all extensions currently present on a Signal.

  Returns a list of extension namespace strings for extensions that have
  data stored in the Signal.

  ## Parameters

  - `signal` - The Signal struct to inspect

  ## Returns

  A list of extension namespace strings

  ## Examples

      # Signal with multiple extensions
      extensions = Jido.Signal.list_extensions(signal)
      # => ["auth", "tracking", "metadata"]

      # Signal with no extensions
      extensions = Jido.Signal.list_extensions(signal)
      # => []
  """
  @spec list_extensions(t()) :: [String.t()]
  def list_extensions(%__MODULE__{} = signal) do
    Map.keys(signal.extensions)
  end

  def list_extensions(_), do: []

  @doc """
  Flattens extension data to CloudEvents-compliant top-level attributes.

  Takes a Signal struct and converts all extension data to top-level attributes
  by calling each extension's `to_attrs/1` function and merging the results
  into the base signal map.

  ## Parameters

  - `signal` - The Signal struct containing extensions to flatten

  ## Returns

  A map with extensions flattened to top-level CloudEvents attributes

  ## Examples

      signal = %Signal{type: "test", source: "/test", extensions: %{"auth" => %{user_id: "123"}}}
      flattened = Jido.Signal.flatten_extensions(signal)
      # => %{"type" => "test", "source" => "/test", "user_id" => "123", ...}
  """
  @spec flatten_extensions(t()) :: map()
  def flatten_extensions(%__MODULE__{} = signal) do
    # Start with base signal map (without extensions)
    base_map = signal |> Map.from_struct() |> Map.delete(:extensions)

    # Required CloudEvents fields that should always be included
    required_fields = ["specversion", "type", "source", "id"]

    # Convert to string keys and filter out nil values, but keep required fields
    base_map =
      base_map
      |> Enum.reject(fn {k, v} ->
        string_key = to_string(k)
        v == nil and string_key not in required_fields
      end)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    # Process each extension and merge its attributes
    Enum.reduce(signal.extensions, base_map, fn {namespace, data}, acc ->
      case get(namespace) do
        {:ok, extension_module} ->
          case Ext.safe_to_attrs(extension_module, data) do
            {:ok, extension_attrs} ->
              filtered_attrs = Enum.reject(extension_attrs, fn {_k, v} -> v == nil end)
              Map.merge(acc, Map.new(filtered_attrs))

            {:error, reason} ->
              Logger.warning(
                "Extension #{namespace} to_attrs failed: #{inspect(reason)} - skipping"
              )

              acc
          end

        {:error, :not_found} ->
          # If extension is not registered, skip it (for backward compatibility)
          acc
      end
    end)
  end

  @doc """
  Inflates top-level attributes back to extension data.

  Takes a map of attributes (typically from deserialization) and extracts
  extension data by calling each registered extension's `from_attrs/1` function.
  Returns both the extensions map and the remaining attributes with extension
  data removed.

  ## Parameters

  - `attrs` - Map of attributes to extract extensions from

  ## Returns

  A tuple `{extensions_map, remaining_attrs}` where:
  - `extensions_map` contains extension data keyed by namespace
  - `remaining_attrs` has extension-specific attributes removed

  ## Examples

      attrs = %{"type" => "test", "source" => "/test", "user_id" => "123", "roles" => ["admin"]}
      {extensions, remaining} = Jido.Signal.inflate_extensions(attrs)
      # => {%{"auth" => %{user_id: "123", roles: ["admin"]}}, %{"type" => "test", "source" => "/test"}}
  """
  @spec inflate_extensions(map()) :: {map(), map()}
  def inflate_extensions(attrs) when is_map(attrs) do
    # Get all registered extensions
    all_extensions = Jido.Signal.Ext.Registry.all()

    # Core CloudEvents fields that should never be removed
    core_fields = [
      "specversion",
      "type",
      "source",
      "id",
      "subject",
      "time",
      "datacontenttype",
      "dataschema",
      "data",
      "jido_dispatch"
    ]

    {extensions, remaining_attrs} =
      Enum.reduce(all_extensions, {%{}, attrs}, fn {namespace, extension_module},
                                                   {ext_acc, attrs_acc} ->
        # First try to get extension data
        case Ext.safe_from_attrs(extension_module, attrs_acc) do
          {:ok, extension_data} ->
            case extension_data do
              nil ->
                {ext_acc, attrs_acc}

              ^attrs_acc when map_size(extension_data) == map_size(attrs_acc) ->
                # Extension returned the full attrs map (default behavior)
                # This means it doesn't have specific logic, so we need to check
                # if any of its schema fields are present in the attrs
                case has_extension_attributes?(extension_module, attrs_acc, core_fields) do
                  {false, _} ->
                    # No relevant attributes found, skip this extension
                    {ext_acc, attrs_acc}

                  {true, matching_attrs} ->
                    # Found relevant attributes, validate them
                    # Convert to atom keys for validation
                    atom_keyed_attrs =
                      Map.new(matching_attrs, fn {k, v} -> {String.to_atom(k), v} end)

                    case Ext.safe_validate_data(extension_module, atom_keyed_attrs) do
                      {:ok, {:ok, validated_data}} ->
                        # Remove the extension's attributes from remaining attrs
                        updated_attrs =
                          Enum.reduce(matching_attrs, attrs_acc, fn {key, _value}, acc ->
                            if key in core_fields do
                              # Don't remove core fields
                              acc
                            else
                              Map.delete(acc, key)
                            end
                          end)

                        {Map.put(ext_acc, namespace, validated_data), updated_attrs}

                      {:ok, {:error, _reason}} ->
                        # Validation failed, skip this extension
                        {ext_acc, attrs_acc}

                      {:error, reason} ->
                        Logger.warning(
                          "Extension #{namespace} validate_data failed: #{inspect(reason)} - skipping"
                        )

                        {ext_acc, attrs_acc}
                    end
                end

              extension_data ->
                # Extension returned specific data (custom from_attrs)
                # Validate the extension data instead of trying to remove attributes
                case Ext.safe_validate_data(extension_module, extension_data) do
                  {:ok, {:ok, validated_data}} ->
                    # Remove the extension's attributes from remaining attrs
                    case Ext.safe_to_attrs(extension_module, validated_data) do
                      {:ok, extension_attrs} ->
                        # Only remove attributes that are not core CloudEvents fields
                        updated_attrs =
                          Enum.reduce(extension_attrs, attrs_acc, fn {key, _value}, acc ->
                            if key in core_fields do
                              # Don't remove core fields
                              acc
                            else
                              Map.delete(acc, key)
                            end
                          end)

                        {Map.put(ext_acc, namespace, validated_data), updated_attrs}

                      {:error, reason} ->
                        Logger.warning(
                          "Extension #{namespace} to_attrs failed: #{inspect(reason)} - skipping"
                        )

                        {ext_acc, attrs_acc}
                    end

                  {:ok, {:error, _reason}} ->
                    # Validation failed, skip this extension
                    {ext_acc, attrs_acc}

                  {:error, reason} ->
                    Logger.warning(
                      "Extension #{namespace} validate_data failed: #{inspect(reason)} - skipping"
                    )

                    {ext_acc, attrs_acc}
                end
            end

          {:error, reason} ->
            Logger.warning(
              "Extension #{namespace} from_attrs failed: #{inspect(reason)} - skipping"
            )

            {ext_acc, attrs_acc}
        end
      end)

    {extensions, remaining_attrs}
  end

  # Helper function to check if an extension's attributes are present in the map
  defp has_extension_attributes?(extension_module, attrs, core_fields) do
    schema = extension_module.schema()

    case schema do
      [] ->
        # No schema, can't determine what attributes belong to this extension
        {false, %{}}

      schema_fields ->
        # Check if any schema fields are present in attrs (excluding core fields)
        schema_field_names = schema_fields |> Keyword.keys() |> Enum.map(&to_string/1)

        # Only look at top-level attributes, not nested data
        top_level_attrs = Map.drop(attrs, core_fields)

        matching_attrs =
          top_level_attrs
          |> Enum.filter(fn {key, _value} ->
            key in schema_field_names
          end)
          |> Map.new()

        if Enum.empty?(matching_attrs) do
          {false, %{}}
        else
          {true, matching_attrs}
        end
    end
  end
end
