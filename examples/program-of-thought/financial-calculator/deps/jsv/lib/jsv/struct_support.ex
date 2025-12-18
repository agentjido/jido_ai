defmodule JSV.StructSupport do
  alias JSV.Schema

  @moduledoc false

  @doc """
  Validates the given raw schema can be used to define a module struct or raises
  an exception.

  It will check the following:

  * Schema defines a type `object`.
  * Schema has `properties`.
  * `properties` is a map with atom keys.
  * `required`, if present, contains only atoms
  """
  @spec validate!(JSV.native_schema()) :: :ok
  def validate!(schema) do
    :ok = validate_object_type!(schema)
    :ok = validate_properties_presence!(schema)
    properties_keys = get_validate_properties_keys!(schema)
    :ok = validate_required_keys!(schema, properties_keys)
    :ok
  end

  defp validate_object_type!(schema) do
    t =
      case schema do
        %{"type" => t} -> t
        %Schema{type: nil} -> raise ArgumentError, errmsg("must define the :object type")
        %{type: t} -> t
        _ -> raise ArgumentError, errmsg("must define the :object type")
      end

    case t do
      :object -> :ok
      "object" -> :ok
      other -> raise ArgumentError, errmsg("must define the :object type, got: #{inspect(other)}")
    end
  end

  defp validate_properties_presence!(schema) do
    case schema do
      %{"properties" => properties} when is_map(properties) ->
        :ok

      %{properties: properties} when is_map(properties) ->
        :ok

      %{"properties" => other} ->
        raise ArgumentError, errmsg("must define properties as a map, got: #{inspect(other)}")

      %{properties: other} ->
        raise ArgumentError, errmsg("must define properties as a map, got: #{inspect(other)}")

      _ ->
        raise ArgumentError, errmsg("must include a properties key")
    end
  end

  defp get_validate_properties_keys!(schema) do
    properties =
      case schema do
        %{"properties" => properties} -> properties
        %{properties: properties} -> properties
      end

    keys = Enum.map(properties, fn {k, _} -> k end)

    if Enum.all?(keys, &is_atom/1) do
      keys
    else
      raise ArgumentError, errmsg("properties must be defined with atom keys")
    end
  end

  defp validate_required_keys!(schema, properties_keys) do
    required =
      case schema do
        %Schema{required: nil} -> []
        %{required: required} -> required
        %{"required" => required} -> required
        _ -> []
      end

    if not is_list(required) do
      raise ArgumentError, errmsg("required must be a list")
    end

    if not Enum.all?(required, &is_atom/1) do
      raise ArgumentError, errmsg("must list atom keys in :required, got: #{inspect(required)}")
    end

    case Enum.uniq(required) -- properties_keys do
      [] ->
        :ok

      rest ->
        raise ArgumentError, errmsg("must use known keys only in :required, unknown keys: #{inspect(rest)}")
    end

    :ok
  end

  @doc """
  Returns a list of `{binary_key, atom_key}` tuples for the given schema. The
  list is sorted by keys.

  The schema must be valid against `validate!1/`.

  This function accepts a second argument, which must be a module that
  implements a struct (with `defstruct/1`). When given, the function will
  validate that all schema keys exist in the given struct.
  """
  @spec keycast_pairs(JSV.native_schema(), target :: nil | module) :: %{binary => atom}

  def keycast_pairs(schema, target \\ nil)

  def keycast_pairs(schema, nil) do
    schema
    |> props!()
    |> Map.new(fn {k, _} when is_atom(k) -> {Atom.to_string(k), k} end)
  end

  def keycast_pairs(schema, target) do
    pairs = keycast_pairs(schema, nil)

    struct_keys = struct_keys(target)

    extra_keys =
      Enum.flat_map(pairs, fn {_, k} ->
        case k in struct_keys do
          true -> []
          false -> [k]
        end
      end)

    case extra_keys do
      [] ->
        pairs

      _ ->
        raise ArgumentError,
              "struct #{inspect(target)} does not define keys given in defschema_for/1 properties: #{inspect(extra_keys)}"
    end
  end

  defp struct_keys(module) do
    fields =
      try do
        module.__info__(:struct)
      rescue
        _ -> reraise ArgumentError, "module #{inspect(module)} does not define a struct", __STACKTRACE__
      end

    Enum.map(fields, & &1.field)
  end

  @doc """
  Returns a tuple where the first element is a list of schema `:properties` keys
  that do not have a `:default` value, and the second element is a list of
  `{key, default_value}` tuples. sorted by keys.

  Both lists are sorted by key.

  The schema must be valid against `validate!1/`.
  """
  @spec data_pairs_partition(JSV.native_schema()) :: {[atom], keyword()}
  def data_pairs_partition(schema) do
    {no_defaults, with_defaults} =
      schema
      |> props!()
      |> Enum.reduce({[], []}, fn {k, subschema}, {no_defaults, with_defaults} when is_atom(k) ->
        case fetch_default(subschema) do
          {:ok, default} -> {no_defaults, [{k, default} | with_defaults]}
          :error -> {[k | no_defaults], with_defaults}
        end
      end)

    {Enum.sort(no_defaults), Enum.sort(with_defaults)}
  end

  @doc """
  Returns the `required` property of the schema or an empty list.

  The schema must be valid against `validate!1/`.
  """
  @spec list_required(JSV.native_schema()) :: [atom()]
  def list_required(schema) do
    list =
      case schema do
        %{"required" => list} -> list
        %Schema{required: nil} -> []
        %{required: list} -> list
        _ -> []
      end

    true = is_list(list)
    list
  end

  defp props!(schema) do
    case schema do
      %{properties: properties} -> properties
      %{"properties" => properties} -> properties
    end
  end

  defp fetch_default(schema) do
    case schema do
      %{default: default} -> {:ok, default}
      %{"default" => default} -> {:ok, default}
      _ -> :error
    end
  end

  @spec take_keycast(map, %{binary => atom}, atom) :: [{atom, term}]
  def take_keycast(data, keycast, additional_properties \\ nil)

  def take_keycast(data, keycast, nil) when is_map(data) do
    Enum.reduce(keycast, [], fn {str_key, atom_key}, acc ->
      case data do
        %{^str_key => v} -> [{atom_key, v} | acc]
        _ -> acc
      end
    end)
  end

  @spec take_keycast(map, %{binary => atom}) :: [{atom, term}]
  def take_keycast(data, keycast, additional_properties_key) when is_map(data) do
    {props, add_props} =
      Enum.reduce(data, {[], []}, fn {str_key, value}, {pairs, addprops} ->
        case keycast do
          %{^str_key => atom_key} -> {[{atom_key, value} | pairs], addprops}
          _ -> {pairs, [{str_key, value} | addprops]}
        end
      end)

    [{additional_properties_key, Map.new(add_props)} | props]
  end

  @doc """
  Returns a JSON schema definition from the given keyword list. The keyword
  describes the properties of the schema. The returned value will return a map
  with `type: :object`, `properties: properties` and `:required` will be defined
  from all properties that do not have a `:default` value in the schema.
  """
  @spec props_to_schema(keyword, overrides :: map) :: %{type: :object, properties: map, required: list}
  def props_to_schema(properties, overrides) when is_list(properties) do
    # We will not validate that the keys are atoms, this is done when validating
    # the returned schema from macros.
    {props, required} =
      Enum.map_reduce(properties, _required = [], fn
        {k, {:optional, prop_schema}}, required when is_map(prop_schema) when is_atom(prop_schema) ->
          {{k, prop_schema}, required}

        {k, prop_schema}, required when is_map(prop_schema) ->
          case fetch_default(prop_schema) do
            # No default, the property is required
            :error -> {{k, prop_schema}, [k | required]}
            {:ok, _} -> {{k, prop_schema}, required}
          end

        {k, prop_schema}, required when is_atom(prop_schema) ->
          {{k, prop_schema}, [k | required]}

        _, _ ->
          raise ArgumentError, errmsg("as properties must be a keyword list, got: #{inspect(properties)}")
      end)

    Map.merge(
      %{
        type: :object,
        properties: Map.new(props),
        required: :lists.reverse(required)
      },
      overrides
    )
  end

  defp errmsg(msg) do
    "schema given to defschema/1 " <> msg
  end
end
