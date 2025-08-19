defmodule Sparq.Handlers.Types do
  @moduledoc """
  Handles type-related operations in the Sparq language.
  Implements core types: strings, atoms/symbols, lists, maps/structs, booleans, and nil.
  """

  use Sparq.Handlers.Behaviour

  @type validation_error ::
          :invalid_string
          | :invalid_atom
          | :invalid_list
          | :invalid_map
          | :invalid_boolean
          | :invalid_arity
          | :empty_list
          | :invalid_tuple_get
          | :invalid_tuple_put

  @type handle_result :: {term(), map()}

  @impl true
  @spec handle(atom(), map(), list(), map()) :: handle_result()
  def handle(op, _meta, args, ctx) do
    case op do
      # String operations
      :string -> handle_string(args, ctx)
      :string_concat -> handle_string_concat(args, ctx)
      # Atom operations
      :atom -> handle_atom(args, ctx)
      :atom_to_string -> handle_atom_to_string(args, ctx)
      # List operations
      :list -> handle_list(args, ctx)
      :cons -> handle_cons(args, ctx)
      :head -> handle_head(args, ctx)
      :tail -> handle_tail(args, ctx)
      :empty? -> handle_empty?(args, ctx)
      # Map operations
      :map -> handle_map(args, ctx)
      :map_put -> handle_map_put(args, ctx)
      :map_get -> handle_map_get(args, ctx)
      :map_delete -> handle_map_delete(args, ctx)
      # Boolean operations
      true -> {true, ctx}
      false -> {false, ctx}
      :and -> handle_and(args, ctx)
      :or -> handle_or(args, ctx)
      :not -> handle_not(args, ctx)
      # Tuple operations
      :tuple -> handle_tuple(args, ctx)
      :tuple_get -> handle_tuple_get(args, ctx)
      :tuple_put -> handle_tuple_put(args, ctx)
      # Type checking
      :type_of -> handle_type_of(args, ctx)
      # Nil operations
      nil -> {nil, ctx}
      :nil? -> handle_nil?(args, ctx)
    end
  end

  # String handling
  @spec handle_string([binary()], map()) :: handle_result()
  defp handle_string([value], ctx) when is_binary(value), do: {value, ctx}

  @spec handle_string_concat([binary()], map()) :: handle_result()
  defp handle_string_concat([str1, str2], ctx) when is_binary(str1) and is_binary(str2) do
    {str1 <> str2, ctx}
  end

  # Atom handling
  @spec handle_atom([atom()], map()) :: handle_result()
  defp handle_atom([name], ctx) when is_atom(name), do: {name, ctx}

  @spec handle_atom_to_string([atom()], map()) :: handle_result()
  defp handle_atom_to_string([atom], ctx) when is_atom(atom) do
    {Atom.to_string(atom), ctx}
  end

  # List handling
  @spec handle_list(list(), map()) :: handle_result()
  defp handle_list(elements, ctx), do: {List.wrap(elements), ctx}

  @spec handle_cons({term(), list()}, map()) :: handle_result()
  defp handle_cons([head, tail], ctx) when is_list(tail), do: {[head | tail], ctx}

  @spec handle_head([list()], map()) :: handle_result()
  defp handle_head([[head | _]], ctx), do: {head, ctx}

  @spec handle_tail([list()], map()) :: handle_result()
  defp handle_tail([[_ | tail]], ctx), do: {tail, ctx}

  @spec handle_empty?([list()], map()) :: handle_result()
  defp handle_empty?([list], ctx) when is_list(list), do: {Enum.empty?(list), ctx}

  # Map handling
  @spec handle_map(list(), map()) :: handle_result()
  defp handle_map([], ctx), do: {%{}, ctx}

  @spec handle_map_put({map(), term(), term()}, map()) :: handle_result()
  defp handle_map_put([map, key, value], ctx) when is_map(map) do
    {Map.put(map, key, value), ctx}
  end

  @spec handle_map_get({map(), term()}, map()) :: handle_result()
  defp handle_map_get([map, key], ctx) when is_map(map) do
    {Map.get(map, key), ctx}
  end

  @spec handle_map_delete({map(), term()}, map()) :: handle_result()
  defp handle_map_delete([map, key], ctx) when is_map(map) do
    {Map.delete(map, key), ctx}
  end

  # Boolean handling
  @spec handle_and({boolean(), boolean()}, map()) :: handle_result()
  defp handle_and([a, b], ctx) when is_boolean(a) and is_boolean(b) do
    {a and b, ctx}
  end

  @spec handle_or({boolean(), boolean()}, map()) :: handle_result()
  defp handle_or([a, b], ctx) when is_boolean(a) and is_boolean(b) do
    {a or b, ctx}
  end

  @spec handle_not({boolean()}, map()) :: handle_result()
  defp handle_not([value], ctx) when is_boolean(value) do
    {not value, ctx}
  end

  # Tuple handling
  @spec handle_tuple(list(), map()) :: handle_result()
  defp handle_tuple(elements, ctx) do
    {List.to_tuple(elements), ctx}
  end

  @spec handle_tuple_get({tuple(), non_neg_integer()}, map()) :: handle_result()
  defp handle_tuple_get([tup, index], ctx) when is_tuple(tup) and is_integer(index) do
    if index < 0 or index >= tuple_size(tup) do
      raise ArgumentError, "tuple_get index out of range"
    else
      {elem(tup, index), ctx}
    end
  end

  @spec handle_tuple_put({tuple(), non_neg_integer(), term()}, map()) :: handle_result()
  defp handle_tuple_put([tup, index, value], ctx) when is_tuple(tup) and is_integer(index) do
    if index < 0 or index >= tuple_size(tup) do
      raise ArgumentError, "tuple_put index out of range"
    else
      {put_elem(tup, index, value), ctx}
    end
  end

  # Type checking
  @spec handle_type_of({term()}, map()) :: handle_result()
  defp handle_type_of([value], ctx) do
    {infer_type(value), ctx}
  end

  # Nil handling
  @spec handle_nil?({term()}, map()) :: handle_result()
  defp handle_nil?([value], ctx) do
    {is_nil(value), ctx}
  end

  # Private helpers
  @spec infer_type(term()) :: atom()
  defp infer_type(value) when is_binary(value), do: :string
  defp infer_type(nil), do: nil
  defp infer_type(value) when is_number(value), do: :number
  defp infer_type(true), do: :boolean
  defp infer_type(false), do: :boolean
  defp infer_type(value) when is_atom(value), do: :atom
  defp infer_type(value) when is_list(value), do: :list
  defp infer_type(value) when is_map(value), do: :map
  defp infer_type(_), do: :unknown

  @impl true
  @spec validate(atom(), list()) :: :ok | {:error, validation_error()}
  def validate(op, args) do
    case op do
      # String operations
      :string -> validate_string(args)
      :string_concat -> validate_string_concat(args)
      # Atom operations
      :atom -> validate_atom(args)
      :atom_to_string -> validate_atom_to_string(args)
      # List operations
      :cons -> validate_cons(args)
      :head -> validate_head(args)
      :tail -> validate_tail(args)
      :empty? -> validate_empty?(args)
      # Map operations
      :map_put -> validate_map_put(args)
      :map_get -> validate_map_get(args)
      :map_delete -> validate_map_delete(args)
      # Boolean operations
      :and -> validate_and(args)
      :or -> validate_or(args)
      :not -> validate_not(args)
      # Tuple operations
      :tuple -> validate_tuple(args)
      :tuple_get -> validate_tuple_get(args)
      :tuple_put -> validate_tuple_put(args)
      _ -> :ok
    end
  end

  # String validation
  @spec validate_string(list()) :: :ok | {:error, validation_error()}
  defp validate_string([value]) when not is_binary(value), do: {:error, :invalid_string}
  defp validate_string([_]), do: :ok
  defp validate_string(_), do: {:error, :invalid_arity}

  @spec validate_string_concat(list()) :: :ok | {:error, validation_error()}
  defp validate_string_concat(args) when length(args) != 2, do: {:error, :invalid_arity}

  defp validate_string_concat([str1, str2]) when not is_binary(str1) or not is_binary(str2),
    do: {:error, :invalid_string}

  defp validate_string_concat([_, _]), do: :ok

  # Atom validation
  @spec validate_atom(list()) :: :ok | {:error, validation_error()}
  defp validate_atom([name]) when not is_atom(name), do: {:error, :invalid_atom}
  defp validate_atom([_]), do: :ok
  defp validate_atom(_), do: {:error, :invalid_arity}

  @spec validate_atom_to_string(list()) :: :ok | {:error, validation_error()}
  defp validate_atom_to_string([atom]) when not is_atom(atom), do: {:error, :invalid_atom}
  defp validate_atom_to_string([_]), do: :ok
  defp validate_atom_to_string(_), do: {:error, :invalid_arity}

  # List validation
  @spec validate_cons(list()) :: :ok | {:error, validation_error()}
  defp validate_cons([_head, tail]) when not is_list(tail), do: {:error, :invalid_list}
  defp validate_cons([_, _]), do: :ok
  defp validate_cons(_), do: {:error, :invalid_arity}

  @spec validate_head(list()) :: :ok | {:error, validation_error()}
  defp validate_head([[]]), do: {:error, :empty_list}
  defp validate_head([[_ | _]]), do: :ok
  defp validate_head(_), do: {:error, :invalid_arity}

  @spec validate_tail(list()) :: :ok | {:error, validation_error()}
  defp validate_tail([[]]), do: {:error, :empty_list}
  defp validate_tail([[_ | _]]), do: :ok
  defp validate_tail(_), do: {:error, :invalid_arity}

  @spec validate_empty?(list()) :: :ok | {:error, validation_error()}
  defp validate_empty?([value]) when not is_list(value), do: {:error, :invalid_list}
  defp validate_empty?([_]), do: :ok
  defp validate_empty?(_), do: {:error, :invalid_arity}

  # Map validation
  @spec validate_map_put(list()) :: :ok | {:error, validation_error()}
  defp validate_map_put([map, _key, _value]) when not is_map(map), do: {:error, :invalid_map}
  defp validate_map_put([_, _, _]), do: :ok
  defp validate_map_put(_), do: {:error, :invalid_arity}

  @spec validate_map_get(list()) :: :ok | {:error, validation_error()}
  defp validate_map_get([map, _key]) when not is_map(map), do: {:error, :invalid_map}
  defp validate_map_get([_, _]), do: :ok
  defp validate_map_get(_), do: {:error, :invalid_arity}

  @spec validate_map_delete(list()) :: :ok | {:error, validation_error()}
  defp validate_map_delete([map, _key]) when not is_map(map), do: {:error, :invalid_map}
  defp validate_map_delete([_, _]), do: :ok
  defp validate_map_delete(_), do: {:error, :invalid_arity}

  # Boolean validation
  @spec validate_and(list()) :: :ok | {:error, validation_error()}
  defp validate_and(args) when length(args) != 2, do: {:error, :invalid_arity}

  defp validate_and([a, b]) when not is_boolean(a) or not is_boolean(b),
    do: {:error, :invalid_boolean}

  defp validate_and([_, _]), do: :ok

  @spec validate_or(list()) :: :ok | {:error, validation_error()}
  defp validate_or(args) when length(args) != 2, do: {:error, :invalid_arity}

  defp validate_or([a, b]) when not is_boolean(a) or not is_boolean(b),
    do: {:error, :invalid_boolean}

  defp validate_or([_, _]), do: :ok

  @spec validate_not(list()) :: :ok | {:error, validation_error()}
  defp validate_not(args) when length(args) != 1, do: {:error, :invalid_arity}
  defp validate_not([value]) when not is_boolean(value), do: {:error, :invalid_boolean}
  defp validate_not([_]), do: :ok

  # Tuple validation
  @spec validate_tuple(list()) :: :ok | {:error, validation_error()}
  defp validate_tuple(_args), do: :ok

  @spec validate_tuple_get(list()) :: :ok | {:error, validation_error()}
  defp validate_tuple_get([tup, idx]) when is_tuple(tup) and is_integer(idx), do: :ok
  defp validate_tuple_get(_), do: {:error, :invalid_tuple_get}

  @spec validate_tuple_put(list()) :: :ok | {:error, validation_error()}
  defp validate_tuple_put([tup, idx, _]) when is_tuple(tup) and is_integer(idx), do: :ok
  defp validate_tuple_put(_), do: {:error, :invalid_tuple_put}
end
