defmodule Texture.UriTemplate.Renderer do
  @moduledoc false

  @spec render(Texture.UriTemplate.t(), %{optional(atom) => term, optional(binary) => term}) :: binary
  def render(%Texture.UriTemplate{parts: parts}, params) do
    params =
      Map.new(params, fn
        {key, value} when is_binary(key) -> {key, value}
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      end)

    IO.iodata_to_binary(do_render(parts, params))
  end

  defp do_render(parts, params) do
    Enum.map(parts, fn item -> render_part(item, params) end)
  end

  defp render_part({:lit, lit}, _) do
    lit
  end

  defp render_part({:expr, op, varlist}, params) do
    render_expr(op, varlist, params)
  end

  defp render_expr(op, varlist, params) do
    {escape, c_intersperse, c_listprefix} =
      case op do
        c when c in [";"] -> {:allow_unreserved, op, op}
        c when c in ["?", "&"] -> {:allow_unreserved, ?&, op}
        c when c in ["/", "."] -> {:allow_unreserved, op, op}
        "#" -> {:allow_reserved_unreserved, ?,, ?#}
        "+" -> {:allow_reserved_unreserved, ?,, nil}
        :default -> {:allow_unreserved, ?,, nil}
      end

    values = render_varlist(varlist, escape, op, params)

    values = Enum.intersperse(values, c_intersperse)

    case values do
      [_ | _] when c_listprefix != nil -> [c_listprefix | values]
      _ -> values
    end
  end

  # With those operators we will include the keys in the rendered vars
  defp render_varlist(varlist, escape, op, params) do
    Enum.flat_map(varlist, fn {:var, name, _} = var ->
      case fetch_param(params, name) do
        {:ok, value} -> render_var(var, value, escape, op)
        :error -> []
      end
    end)
  end

  # Render var always returns a list, so we can merge normal values and explode*
  # values in a list at the same level (for further intersperse)

  defp render_var({:var, name, :explode}, value, escape, op) do
    exploded_value = explode_value(value, name, explode_mode(op))
    render_pairs(exploded_value, escape, pair_mode(op))
  end

  defp render_var({:var, name, nil_or_prefix}, value, escape, op) do
    escape =
      case nil_or_prefix do
        nil -> escape
        {:prefix, max_len} -> {escape, max_len}
      end

    render_var_by_op(op, name, value, escape)
  end

  defp explode_mode(op) when op in [";", "?", "&"] do
    :all
  end

  defp explode_mode(_op) do
    :dicts
  end

  defp pair_mode(";") do
    :nonempty
  end

  defp pair_mode(_op) do
    :enforce_sep
  end

  defp render_var_by_op(op, _name, value, escape) when op in [:default, "/", "+", "#", "."] do
    [render_value(unwrap_value(value), escape)]
  end

  defp render_var_by_op(op, name, value, escape) when op in [";", "?", "&"] do
    render_pairs([{name, value}], escape, pair_mode(op))
  end

  # if the value is a map or keyword list we will flatten the keys and values into a single list
  defp unwrap_value(val) when is_binary(val) when is_number(val) when is_atom(val) do
    val
  end

  defp unwrap_value([{k, v} | t]) do
    [k, v | unwrap_value(t)]
  end

  defp unwrap_value([h | t]) do
    [h | unwrap_value(t)]
  end

  defp unwrap_value([]) do
    []
  end

  defp unwrap_value(map) when is_map(map) do
    Enum.flat_map(:maps.to_list(map_iterator(map)), fn {k, v} -> [k, v] end)
  end

  defp fetch_param(params, key) do
    # https://www.rfc-editor.org/rfc/rfc6570.html#section-2.3
    #
    # > A variable defined as a list value is considered undefined if the list
    # > contains zero members.  A variable defined as an associative array of
    # > (name, value) pairs is considered undefined if the array contains zero
    # > members or if all member names in the array are associated with
    # > undefined values.
    case Map.fetch(params, key) do
      {:ok, list} when is_list(list) ->
        check_undef_compound(list)

      {:ok, map} when is_map(map) ->
        check_undef_compound(map)

      {:ok, value} ->
        case undef?(value) do
          true -> :error
          false -> {:ok, value}
        end

      :error ->
        :error
    end
  end

  defp check_undef_compound(list) when is_list(list) do
    case Enum.reject(list, &undef?/1) do
      [] -> :error
      list -> {:ok, list}
    end
  end

  defp check_undef_compound(map) when is_map(map) do
    case Map.reject(map, fn {_, v} -> undef?(v) end) do
      empty when map_size(empty) == 0 -> :error
      %_{} = empty when map_size(empty) == 1 -> :error
      map -> {:ok, map}
    end
  end

  defp undef?(nil) do
    true
  end

  defp undef?([]) do
    true
  end

  defp undef?(empty_map) when empty_map == %{} do
    true
  end

  defp undef?(_) do
    false
  end

  # https://www.rfc-editor.org/rfc/rfc6570.html#section-2.4.2
  #
  #  > An explode ("*") modifier indicates that the variable is to be treated as
  #  > a composite value consisting of either a list of values or an associative
  #  > array of (name, value) pairs.  Hence, the expansion process is applied to
  #  > each member of the composite as if it were listed as a separate variable.
  #  > This kind of variable specification is significantly less
  #  > self-documenting than non-exploded variables, since there is less
  #  > correspondence between the variable name and how the URI reference
  #  > appears after expansion.
  #
  # We chose to explode scalar values as themselves

  defp explode_value([_ | _] = list, _default_key, :dicts) do
    Enum.map(list, fn
      {k, v} -> {k, v}
      v -> v
    end)
  end

  defp explode_value([_ | _] = list, default_key, :all) do
    Enum.map(list, fn
      {k, v} -> {k, v}
      v -> {default_key, v}
    end)
  end

  defp explode_value(map, _default_key, _) when is_map(map) do
    :maps.to_list(map_iterator(map))
  end

  defp explode_value(other, default_key, :all) do
    [{default_key, other}]
  end

  defp explode_value(other, _default_key, :dicts) do
    [other]
  end

  if Mix.env() == :test do
    defp map_iterator(map) do
      :maps.iterator(map, :ordered)
    end
  else
    defp map_iterator(map) do
      :maps.iterator(map)
    end
  end

  defp render_pairs(list, escape, sep_mode) when is_list(list) do
    Enum.map(list, fn
      {k, v} -> render_kv(k, v, escape, sep_mode)
      v -> render_value(v, escape)
    end)
  end

  defp render_kv(k, v, escape, :enforce_sep) do
    [render_key(k), ?=, render_value(v, escape)]
  end

  defp render_kv(k, v, escape, :nonempty) do
    case render_value(v, escape) do
      "" -> render_key(k)
      str -> [render_key(k), ?=, str]
    end
  end

  defp render_value(list, escape) when is_list(list) do
    Enum.map_intersperse(list, ?,, fn
      # Support for keyword list
      {k, v} ->
        v =
          v
          |> value_to_string()
          |> encode_value(escape)

        [render_key(k), ?,, v]

      v ->
        v
        |> value_to_string()
        |> encode_value(escape)
    end)
  end

  defp render_value(value, {escape, max_len}) do
    value
    |> value_to_string()
    |> String.slice(0..(max_len - 1))
    |> encode_value(escape)
  end

  defp render_value(value, escape) do
    value
    |> value_to_string()
    |> encode_value(escape)
  end

  defp value_to_string(str) when is_binary(str) do
    str
  end

  defp value_to_string(nil) do
    ""
  end

  defp value_to_string(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> rest -> rest
      all -> all
    end
  end

  defp value_to_string(list) when is_list(list) do
    Enum.map_join(list, "%2C", &value_to_string/1)
  end

  defp value_to_string(other) do
    Kernel.to_string(other)
  rescue
    e in Protocol.UndefinedError ->
      reraise ArgumentError,
              "cannot render nested value #{inspect(other)} as url parameter, undefined protocol implementation #{inspect(e.protocol)}",
              __STACKTRACE__
  end

  defp encode_value(value, :allow_unreserved) do
    URI.encode(value, &URI.char_unreserved?/1)
  end

  defp encode_value(value, :allow_reserved_unreserved) do
    URI.encode(value, &URI.char_unescaped?/1)
  end

  defp render_key(key) do
    render_value(key, :allow_unreserved)
  end
end
