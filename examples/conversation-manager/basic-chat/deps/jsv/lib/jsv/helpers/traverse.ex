defmodule JSV.Helpers.Traverse do
  @moduledoc """
  Helpers to work with nested generic data structures.
  """

  @type postwalk_cont :: (map, term -> {map, term})
  @type postwalk_item :: {:key, term} | {:val, term} | {:struct, struct, postwalk_cont}
  @type prewalk_item :: {:key, term} | {:val, term} | {:struct, struct}

  @doc """
  Updates a data structure in depth-first, post-order traversal.

  Operates like `postwalk/3` but without an accumulator. Handling continuations
  for structs require to handle the accumulator, whose value MUST be `nil`.
  """
  @spec postwalk(data, (postwalk_item() -> data)) :: data when data: term
  def postwalk(data, fun) when is_function(fun, 1) do
    {value, _} = postwalk(data, nil, fn value, nil -> {fun.(value), nil} end)
    value
  end

  @doc """
  Updates a JSON-compatible data structure in depth-first, post-order traversal
  while carrying an accumulator.

  The callback must return a `{new_value, new_acc}` tuple.

  Nested data structures are given to the callback before their wrappers, and
  when the wrappers are called, their children are already updated.

  JSON-compatible only means that there are restrictions on map keys and struct
  values:

  * The callback function will be called for any key but will not traverse the
    keys. For instance, with data such as `%{{x, y} => "some city"}`, the tuple
    used as key will be passed as-is but the callback will not be called for
    individual tuple elements.
  * Structs will be passed as `{:struct, value, continuation}`. The struct keys
    and values will **NOT** have been traversed yet. The callback should extract
    the struct into another term (for instance using `Map.from_struct/1`) and
    call the continuation.

    To normalize this new term you MUST call the conitnuation function manually.
    To respect the post-order of traversal, it SHOULD be called before further
    transformation of the struct:

        Traverse.postwalk(%MyStruct, [], fn
          {:struct, my_struct, cont}, acc ->
            {map, acc} = cont.(Map.from_struct(my_struct), acc)
            {struct!(MyStruct, do_something_with_map(map)), acc}
          {:val, ...} -> ...
        end)

    Note that if a map is given to the continuation function, the map itself
    will not be passed to your callback as `{:val, map}`, each key and value
    will be normalized directly.

    Since key normalization does not support structs, the keys must be already
    normalized and JSON-encodable when giving a map to the continuation
    function.

  * General data is accepted: tuples, pid, refs, etc. *
  """
  @spec postwalk(data, acc, (postwalk_item, acc -> {data, acc})) :: {data, acc} when data: term, acc: term
  def postwalk(data, acc, fun) when is_function(fun, 2) do
    {data, acc} = postwalk_subs(data, acc, fun)
    postwalk_parent(data, acc, fun)
  rescue
    e in ArgumentError ->
      stack =
        case __STACKTRACE__ do
          [h | t] -> [h | filter_stacktrace(t)]
          other -> other
        end

      reraise e, stack
  end

  # Remove the traverse numerous stacktraces except the topmost
  defp filter_stacktrace(stack) do
    not_traverse? = &(elem(&1, 0) != __MODULE__)
    {zyx, cba} = Enum.split_while(stack, not_traverse?)

    cba =
      cba
      # invert the stack to be top → bottom
      |> :lists.reverse()
      # take the top of the stack that is not traverse mod
      |> Enum.split_while(not_traverse?)
      # then reverse it to go back to bottom → top order
      # also keep one traverse call if any
      |> case do
        {ab, [c | _]} -> [c | :lists.reverse(ab)]
        {ab, []} -> :lists.reverse(ab)
      end

    zyx ++ cba
  end

  defp postwalk_parent(struct, acc, fun) when is_struct(struct) do
    cont = fn
      value, _acc when is_struct(value) ->
        raise ArgumentError, "continuation function does not accept structs, got: #{inspect(value)}"

      value, acc when is_map(value) ->
        postwalk_map_pairs(value, acc, fun)

      value, acc ->
        postwalk(value, acc, fun)
    end

    fun.({:struct, struct, cont}, acc)
  end

  defp postwalk_parent(data, acc, fun) do
    fun.({:val, data}, acc)
  end

  defp postwalk_subs(struct, acc, _fun) when is_struct(struct) do
    # Iteration on the struct is made in the continuation function
    {struct, acc}
  end

  defp postwalk_subs(map, acc, fun) when is_map(map) do
    postwalk_map_pairs(map, acc, fun)
  end

  defp postwalk_subs(list, acc, fun) when is_list(list) do
    Enum.map_reduce(list, acc, fn item, acc -> {_v, _acc} = postwalk(item, acc, fun) end)
  end

  # small optimization for 2-tuples
  defp postwalk_subs({a, b}, acc, fun) do
    {a, acc} = postwalk(a, acc, fun)
    {b, acc} = postwalk(b, acc, fun)
    {{a, b}, acc}
  end

  defp postwalk_subs(tuple, acc, fun) when is_tuple(tuple) do
    {elems, acc} =
      tuple
      |> Tuple.to_list()
      |> Enum.map_reduce(acc, fn item, acc -> {_v, _acc} = postwalk(item, acc, fun) end)

    {List.to_tuple(elems), acc}
  end

  defp postwalk_subs(data, acc, _fun) do
    {data, acc}
  end

  defp postwalk_map_pairs(map, acc, fun) do
    {pairs, acc} =
      Enum.map_reduce(map, acc, fn {k, v}, acc ->
        {v, acc} = postwalk(v, acc, fun)
        {k, acc} = fun.({:key, k}, acc)
        {{k, v}, acc}
      end)

    {Map.new(pairs), acc}
  end

  @doc """
  Updates a data structure in depth-first, pre-order traversal.

  Operates like `prewalk/3` but without an accumulator.
  """

  @spec prewalk(data, (prewalk_item() -> data)) :: data when data: term
  def prewalk(data, fun) when is_function(fun, 1) do
    {value, _} = prewalk(data, nil, fn value, nil -> {fun.(value), nil} end)
    value
  end

  @doc """
  Updates a JSON-compatible data structure in depth-first, pre-order traversal
  while carrying an accumulator.

  The callback must return a `{new_value, new_acc}` tuple.


  Nested data structures are given iterated after the parent data has been given
  to the function. So it is possible to accept a container (map, list, tuple)
  and return another one from the callback before the children are iterated.

  JSON-compatible only means that there are restrictions on map keys and struct
  values:

  * The callback function will be called for any key but will not traverse the
    keys. For instance, with data such as `%{{x, y} => "some city"}`, the tuple
    used as key will be passed as-is but the callback will not be called for
    individual tuple elements.
  * Structs are passed as a `{:struct, struct}` tuple.
  * General data is accepted: tuples, pid, refs, etc. *
  """
  @spec prewalk(data, acc, (prewalk_item, acc -> {data, acc})) :: {data, acc} when data: term, acc: term
  def prewalk(data, acc, fun) when is_function(fun, 2) do
    {new_value, acc} = prewalk_parent(data, acc, fun)
    prewalk_subs(new_value, acc, fun)
  end

  defp prewalk_parent(struct, acc, fun) when is_struct(struct) do
    fun.({:struct, struct}, acc)
  end

  defp prewalk_parent(val, acc, fun) do
    fun.({:val, val}, acc)
  end

  # TODO(doc) structs keys are not traversed
  defp prewalk_subs(%mod{} = struct, acc, fun) do
    # we need to preserve the struct, that means keep its keys.
    {pairs, acc} =
      struct
      |> Map.from_struct()
      |> Enum.map_reduce(acc, fn {k, v}, acc ->
        {v, acc} = prewalk(v, acc, fun)
        {{k, v}, acc}
      end)

    {struct(mod, pairs), acc}
  end

  defp prewalk_subs(map, acc, fun) when is_map(map) do
    prewalk_map_pairs(map, acc, fun)
  end

  defp prewalk_subs(list, acc, fun) when is_list(list) do
    Enum.map_reduce(list, acc, fn item, acc -> prewalk(item, acc, fun) end)
  end

  defp prewalk_subs({a, b}, acc, fun) do
    {a, acc} = prewalk(a, acc, fun)
    {b, acc} = prewalk(b, acc, fun)
    {{a, b}, acc}
  end

  defp prewalk_subs(tuple, acc, fun) when is_tuple(tuple) do
    {elems, acc} =
      tuple
      |> Tuple.to_list()
      |> Enum.map_reduce(acc, fn item, acc -> {_v, _acc} = prewalk(item, acc, fun) end)

    {List.to_tuple(elems), acc}
  end

  defp prewalk_subs(scalar, acc, _fun) do
    {scalar, acc}
  end

  defp prewalk_map_pairs(map, acc, fun) do
    {pairs, acc} =
      Enum.map_reduce(map, acc, fn {k, v}, acc ->
        {v, acc} = prewalk(v, acc, fun)
        {k, acc} = fun.({:key, k}, acc)
        {{k, v}, acc}
      end)

    {Map.new(pairs), acc}
  end
end
