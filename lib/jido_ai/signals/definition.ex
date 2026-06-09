defmodule Jido.AI.Signal.Definition do
  @moduledoc false

  @typedoc false
  @type schema :: keyword(keyword())

  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)
    default_source = Keyword.get(opts, :default_source)
    datacontenttype = Keyword.get(opts, :datacontenttype)
    dataschema = Keyword.get(opts, :dataschema)
    schema = Keyword.get(opts, :schema, [])

    unless is_binary(type) and type != "" do
      raise ArgumentError, "signal type must be a non-empty string"
    end

    unless Keyword.keyword?(schema) do
      raise ArgumentError, "signal schema must be a keyword list"
    end

    quote bind_quoted: [
            type: type,
            default_source: default_source,
            datacontenttype: datacontenttype,
            dataschema: dataschema,
            schema: schema
          ] do
      @signal_type type
      @signal_default_source default_source
      @signal_datacontenttype datacontenttype
      @signal_dataschema dataschema
      @signal_schema schema

      @doc "Returns the CloudEvents type emitted by this signal module."
      @spec type() :: String.t()
      def type, do: @signal_type

      @doc "Returns the default CloudEvents source for this signal module."
      @spec default_source() :: String.t() | nil
      def default_source, do: @signal_default_source

      @doc "Returns the configured data content type, if present."
      @spec datacontenttype() :: String.t() | nil
      def datacontenttype, do: @signal_datacontenttype

      @doc "Returns the configured data schema URI, if present."
      @spec dataschema() :: String.t() | nil
      def dataschema, do: @signal_dataschema

      @doc "Returns the field schema used to validate signal data."
      @spec schema() :: keyword(keyword())
      def schema, do: @signal_schema

      @doc "Returns the extension policy for this signal module."
      @spec extension_policy() :: map()
      def extension_policy, do: %{}

      @doc "Returns this signal definition as metadata."
      @spec to_json() :: map()
      def to_json do
        %{
          type: @signal_type,
          default_source: @signal_default_source,
          datacontenttype: @signal_datacontenttype,
          dataschema: @signal_dataschema,
          schema: @signal_schema,
          extension_policy: %{}
        }
      end

      @doc "Returns this signal definition as metadata."
      @spec __signal_metadata__() :: map()
      def __signal_metadata__, do: to_json()

      @doc "Builds a validated `Jido.Signal` from signal data."
      @spec new(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
      def new(data \\ %{}, opts \\ []) do
        with {:ok, validated_data} <-
               Jido.AI.Signal.Definition.validate_data(__MODULE__, @signal_schema, data) do
          __MODULE__
          |> Jido.AI.Signal.Definition.build_attrs(
            @signal_type,
            @signal_default_source,
            @signal_datacontenttype,
            @signal_dataschema,
            validated_data,
            opts
          )
          |> Jido.Signal.from_map()
        end
      end

      @doc "Builds a validated `Jido.Signal` or raises when validation fails."
      @spec new!(map(), keyword()) :: Jido.Signal.t() | no_return()
      def new!(data \\ %{}, opts \\ []) do
        case new(data, opts) do
          {:ok, signal} -> signal
          {:error, reason} -> raise RuntimeError, message: to_string(reason)
        end
      end

      @doc "Validates data against this signal module's schema."
      @spec validate_data(map()) :: {:ok, map()} | {:error, String.t()}
      def validate_data(data) do
        Jido.AI.Signal.Definition.validate_data(__MODULE__, @signal_schema, data)
      end
    end
  end

  @doc "Validates signal data against the given schema."
  @spec validate_data(module(), schema(), map()) :: {:ok, map()} | {:error, String.t()}
  def validate_data(module, schema, data) when is_map(data) do
    schema_keys = Keyword.keys(schema)

    with {:ok, normalized_data} <- normalize_input(module, data, schema_keys) do
      Enum.reduce_while(schema, {:ok, %{}}, fn {field, opts}, {:ok, acc} ->
        case Map.fetch(normalized_data, field) do
          {:ok, value} ->
            case validate_field(module, field, value, opts) do
              :ok -> {:cont, {:ok, Map.put(acc, field, value)}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          :error ->
            cond do
              Keyword.has_key?(opts, :default) ->
                {:cont, {:ok, Map.put(acc, field, Keyword.fetch!(opts, :default))}}

              Keyword.get(opts, :required, false) ->
                {:halt, {:error, "Signal #{inspect(module)} missing required field #{inspect(field)}"}}

              true ->
                {:cont, {:ok, acc}}
            end
        end
      end)
    end
  end

  def validate_data(module, _schema, data) do
    {:error, "Signal #{inspect(module)} expected data to be a map, got: #{inspect(data)}"}
  end

  @doc "Builds CloudEvents attributes for a typed signal module."
  @spec build_attrs(
          module(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil,
          map(),
          Enumerable.t()
        ) :: map()
  def build_attrs(module, type, default_source, datacontenttype, dataschema, data, opts) do
    %{
      "data" => data,
      "id" => Jido.Signal.ID.generate!(),
      "source" => default_source || module_source(module),
      "specversion" => "1.0.2",
      "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "type" => type
    }
    |> put_optional("datacontenttype", datacontenttype)
    |> put_optional("dataschema", dataschema)
    |> Map.merge(stringify_keys(opts))
  end

  defp normalize_input(module, data, schema_keys) do
    Enum.reduce_while(data, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case normalize_key(key, schema_keys) do
        {:ok, normalized_key} ->
          {:cont, {:ok, Map.put(acc, normalized_key, value)}}

        :error ->
          {:halt, {:error, "Signal #{inspect(module)} received unknown field #{inspect(key)}"}}
      end
    end)
  end

  defp normalize_key(key, schema_keys) when is_atom(key) do
    if key in schema_keys, do: {:ok, key}, else: :error
  end

  defp normalize_key(key, schema_keys) when is_binary(key) do
    case Enum.find(schema_keys, &(Atom.to_string(&1) == key)) do
      nil -> :error
      normalized_key -> {:ok, normalized_key}
    end
  end

  defp normalize_key(_key, _schema_keys), do: :error

  defp validate_field(module, field, value, opts) do
    type = Keyword.get(opts, :type, :any)

    if valid_type?(type, value) do
      :ok
    else
      {:error,
       "Signal #{inspect(module)} expected #{inspect(field)} to be #{type_description(type)}, got: #{inspect(value)}"}
    end
  end

  defp valid_type?(:any, _value), do: true
  defp valid_type?(:atom, value), do: is_atom(value)
  defp valid_type?(:integer, value), do: is_integer(value)
  defp valid_type?(:map, value), do: is_map(value)
  defp valid_type?(:string, value), do: is_binary(value)
  defp valid_type?(_type, _value), do: false

  defp type_description(:atom), do: "an atom"
  defp type_description(:integer), do: "an integer"
  defp type_description(:map), do: "a map"
  defp type_description(:string), do: "a string"
  defp type_description(type), do: inspect(type)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp stringify_keys(values) do
    Enum.into(values, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp module_source(module) do
    "/" <> (module |> Module.split() |> Enum.map(&Macro.underscore/1) |> Enum.join("/"))
  end
end
