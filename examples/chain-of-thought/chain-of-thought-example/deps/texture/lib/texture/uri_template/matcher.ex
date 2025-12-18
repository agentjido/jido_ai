defmodule Texture.UriTemplate.Matcher do
  @moduledoc false

  alias Texture.UriTemplate.TemplateMatchError

  @eos (if Mix.env() == :test do
          "终"
        else
          <<0>>
        end)

  @spec match!(Texture.UriTemplate.t(), String.t()) :: map()
  def match!(%Texture.UriTemplate{} = t, url) do
    # always finish with a null string terminator so we can match on
    # end-of-string
    parts = append_eos(t.parts)
    url = url <> @eos

    case split_on_literals(parts, url, []) do
      [] ->
        %{}

      chunks ->
        Enum.reduce(chunks, %{}, &merge_chunk_params/2)
    end
  rescue
    e in TemplateMatchError ->
      reraise %TemplateMatchError{message: e.message <> " in URI #{url}", url: url}, __STACKTRACE__
  end

  defp append_eos([{:expr, _, _} = last]) do
    [last, {:lit, @eos}]
  end

  defp append_eos([{:lit, lit}]) do
    [{:lit, lit <> @eos}]
  end

  defp append_eos([h, next | t]) do
    [h | append_eos([next | t])]
  end

  defp merge_chunk_params({exprs, url_part}, params) do
    case extract_chunk(exprs, url_part) do
      {add_params, ""} -> Map.merge(params, add_params)
      {_, rest} -> raise TemplateMatchError, "invalid match before #{inspect(rest)}"
    end
  end

  # First we will seek every literal in the url, discarding the associated
  # parts, and generate chunks associating the skipped buffer and the expression
  # parts that were in between
  defp split_on_literals(parts, url, acc)

  defp split_on_literals([], "", acc) do
    # Chunks are not reversed, so if a variable is used multiple times, the
    # matches on the beginning on the URL will take precedence.
    acc
  end

  defp split_on_literals(parts, url, acc) do
    # parts and url always finish with a literal <<0>> so we will always get a
    # remainder with expressions or an empty list
    case seek_next_lit_part(parts) do
      {[], [{:lit, search} | parts]} ->
        rest = buf_delete(url, search)

        split_on_literals(parts, rest, acc)

      {expr_parts, [{:lit, search} | parts]} ->
        # buf_take_before will return left=the string before the seeked
        # literal, and right=the rest of the url after the literal. The literal
        # part is discarded and not returned.
        {before_lit, after_lit} = buf_take_before(url, search, byte_size(search))
        chunk = {expr_parts, before_lit}
        acc = [chunk | acc]
        split_on_literals(parts, after_lit, acc)
    end
  end

  defp buf_take_before(url, search, size, acc \\ <<>>)

  # collects the string part that is found before `search`, and returns the rest
  # after `search`. The search part is discarded.
  defp buf_take_before(url, search, size, acc) do
    case url do
      <<^search::binary-size(size), rest::binary>> -> {acc, rest}
      <<c::utf8, rest::binary>> -> buf_take_before(rest, search, size, <<acc::binary, c::utf8>>)
    end
  end

  defp buf_delete(url, to_delete) do
    case do_buf_delete(url, to_delete) do
      {:ok, rest} -> rest
      :error -> raise TemplateMatchError, "could not find literal #{inspect(to_delete)}"
    end
  end

  defp do_buf_delete(<<prefix, a::binary>>, <<prefix, b::binary>>) do
    do_buf_delete(a, b)
  end

  defp do_buf_delete(_, <<_, _::binary>>) do
    :error
  end

  defp do_buf_delete(uri, <<>>) do
    {:ok, uri}
  end

  defp seek_next_lit_part(parts, acc \\ [])

  defp seek_next_lit_part([{:expr, _, _} = expr | tail], acc) do
    seek_next_lit_part(tail, [expr | acc])
  end

  defp seek_next_lit_part([{:lit, _} | _] = parts, acc) do
    {:lists.reverse(acc), parts}
  end

  defp seek_next_lit_part([], acc) do
    {:lists.reverse(acc), []}
  end

  defp extract_chunk(exprs, url_part) do
    Enum.reduce(exprs, {%{}, url_part}, fn expr, {params, url_part} ->
      {add_params, rest} = extract_expr(expr, url_part)
      {Map.merge(params, add_params), rest}
    end)
  end

  defp extract_expr({:expr, op, varlist}, url_part) do
    Enum.each(varlist, fn
      {:var, name, {:prefix, _}} ->
        raise TemplateMatchError,
              "prefix modifier is not supported for matching (variable: #{name})"

      _ ->
        :ok
    end)

    {prefix, param_sep, list_sep} =
      case op do
        :default -> {nil, ?,, nil}
        "/" -> {?/, ?/, ?,}
        "?" -> {??, ?&, ?,}
      end

    url_part =
      case url_part do
        all when is_nil(prefix) -> all
        <<^prefix, rest::binary>> -> rest
        _other -> raise TemplateMatchError, "expected prefix #{<<prefix>>} before #{inspect(url_part)}"
      end

    {values, rest} =
      take_multi(url_part, param_sep: param_sep, list_sep: list_sep)

    kvs = assign_params(op, varlist, values)
    {Map.new(kvs), rest}
  end

  @doc false
  @spec take_multi(String.t(), keyword()) :: {list(), String.t()}
  def take_multi(url, opts) do
    param_sep = Keyword.fetch!(opts, :param_sep)
    list_sep = Keyword.fetch!(opts, :list_sep)
    take_multi(url, param_sep, list_sep, _cur_param = param_empty(), _params_acc = [])
  end

  defp take_multi("", _, _, nil, _acc) do
    {[], ""}
  end

  defp take_multi(url, param_sep, list_sep, _cur_param, _params_acc) when is_binary(url) do
    {url, rest} = take_allowed(url, param_sep, list_sep, <<>>)
    raw_params = String.split(url, <<param_sep>>)

    with_dicts =
      Enum.map(raw_params, fn
        "" ->
          ""

        bin ->
          case String.split(bin, "=") do
            #
            [key, val] -> {:pair, decode(key), decode(maybe_split_list(val, list_sep))}
            [val] -> decode(maybe_split_list(val, list_sep))
            [_, _, _] -> raise TemplateMatchError, "invalid parameter syntax: #{inspect(bin)}"
          end
      end)

    {with_dicts, rest}
  end

  defp maybe_split_list(val, nil = _list_sep) do
    val
  end

  defp maybe_split_list(val, list_sep) do
    case String.split(val, <<list_sep>>) do
      [single] -> single
      list -> list
    end
  end

  defp param_empty do
    nil
  end

  # when taking the part to parse from the URL we are not yet decoding the
  # percent encoded

  defguard is_hexdig(c) when c in ?A..?f or c in ?a..?f or c in ?0..?9

  defp take_allowed(<<c::utf8, rest::binary>>, param_sep, list_sep, acc)
       when c in ?A..?Z or
              c in ?a..?z or
              c in ?0..?9 or
              c in [?-, ?., ?_, ?~, ?!, ?$, ?', ?(, ?), ?*, ?+, ?@] or c == param_sep or c == list_sep do
    take_allowed(rest, param_sep, list_sep, <<acc::binary, c>>)
  end

  # allowing this should depend on the presence of explosed variables
  defp take_allowed(<<?=, rest::binary>>, param_sep, list_sep, acc) do
    take_allowed(rest, param_sep, list_sep, <<acc::binary, ?=>>)
  end

  defp take_allowed(<<?%, a, b, rest::binary>>, param_sep, list_sep, acc) when is_hexdig(a) and is_hexdig(b) do
    take_allowed(rest, param_sep, list_sep, <<acc::binary, ?%, a, b>>)
  end

  # we will take a single percent anyway TODO check if this clause can be removed
  defp take_allowed(<<?%, rest::binary>>, param_sep, list_sep, acc) do
    take_allowed(rest, param_sep, list_sep, <<acc::binary, ?%>>)
  end

  defp take_allowed(rest_or_empty, _param_sep, _list_sep, acc) do
    {acc, rest_or_empty}
  end

  # for operators ?&; we want to assign parameters by name, to support clients
  # that do not respect URI templates fully (that is LLMs in particular), so we
  # will fetch the elements by name. Other operators use positional assignment.
  defp assign_params(op, varlist, values) do
    case op do
      :default -> assign_positional(op, varlist, values)
      "/" -> assign_positional(op, varlist, values)
      "?" -> assign_by_name(varlist, values)
    end
  end

  # param without remaining value
  defp assign_positional(op, [{:var, name, _} | vars], []) do
    [{name, nil} | assign_positional(op, vars, [])]
  end

  # last param when not exploded AND :default operator
  #
  # if remaining values are not pairs we take them all
  defp assign_positional(:default, [{:var, name, nil}], [_ | _] = vals) do
    if Enum.any?(vals, &match?({:pair, _, _}, &1)) do
      raise TemplateMatchError, "unexpected dictionary values: #{inspect(vals)}"
    else
      case vals do
        [""] -> [{name, nil}]
        [single] -> [{name, single}]
        list -> [{name, list}]
      end
    end
  end

  # new param non exploded
  defp assign_positional(op, [{:var, name, nil} | vars], [val | vals]) do
    case val do
      # non exploded cannot take a pair in positional
      {:pair, _, _} -> [{name, nil} | assign_positional(op, vars, [val | vals])]
      "" -> [{name, nil} | assign_positional(op, vars, vals)]
      v when is_binary(v) when is_list(v) -> [{name, v} | assign_positional(op, vars, vals)]
    end
  end

  # new param, exploded.
  defp assign_positional(op, [{:var, name, :explode} | vars], vals) do
    # in positional style an exploded value must be a dict or a list

    case vals do
      [{:pair, _, _} | _] ->
        # collect_head_pairs returns value is already formated as a map or nil
        {value, vals} = collect_head_pairs(vals)
        [{name, value} | assign_positional(op, vars, vals)]

      # collect exploded lists
      [v | _] when is_binary(v) ->
        {value, vals} = collect_head_raws(vals)
        [{name, value} | assign_positional(op, vars, vals)]

      _ ->
        [{name, nil} | assign_positional(op, vars, vals)]
    end
  end

  defp assign_positional(_op, [], []) do
    []
  end

  # extra parameters: no match
  defp assign_positional(op, [], [_ | _] = vals) do
    true = :default != op
    raise TemplateMatchError, "extra values were not matched: #{inspect(vals)}"
  end

  defp collect_head_pairs(values) do
    {pairs, other_values} =
      Enum.split_while(values, fn
        {:pair, _, _} -> true
        _ -> false
      end)

    value =
      case pairs do
        [] -> nil
        list -> Map.new(list, fn {:pair, k, v} -> {k, v} end)
      end

    {value, other_values}
  end

  defp collect_head_raws(values) do
    {raws, other_values} =
      Enum.split_while(values, fn
        b when is_binary(b) -> true
        _pair_or_list -> false
      end)

    value =
      case raws do
        [] -> nil
        list -> list
      end

    {value, other_values}
  end

  # when assigning by name we do not care about the order of values.
  #
  # * first we partion by exploded or not.
  # * for each non-exploded parameter, we try to find a dict with a single value
  #   and the corresponding key, and we assign that or nil.
  # * for each exploded parameter, we try to find one ore more dicts with single
  #   value and the same name, and we generate a list ({?list*} is exploded to
  #   ?list=red&list=green&list=blue).
  # * then, as we support non ordered parameters, there is no need to try to
  #   match exploded parameters in a particular order. The first remaining
  #   exploded parameter gets all the remaining dicts.
  # * there shall be no non-dict value in the values. Values that are a single
  #   string will be transformed into a key with a nil value.
  defp assign_by_name(varlist, values) do
    {values, existing_names} = normalize_values_to_pairs(values)

    %{regular: regular, list_exploded: list_exploded, map_exploded: map_exploded} =
      group_variables_by_type(varlist, existing_names)

    # Regular params first
    {regular_params, values} = assign_regular_params_by_name(regular, values)

    # Exploded params
    # First those who have corresponding values, it should be exploded lists
    {list_expl_params, values} = assign_list_exploded_params_by_name(list_exploded, values)

    # Finally the first exploded params gets everything else as a map. If there
    # are duplicated keys they will be deleted
    map_expl_params = assign_map_exploded_params_by_name(map_exploded, values)

    map_expl_params ++ list_expl_params ++ regular_params
  end

  defp normalize_values_to_pairs(values) do
    Enum.map_reduce(values, %{}, fn
      {:pair, k, _} = pair, acc ->
        {pair, Map.put(acc, k, true)}

      bin, acc when is_binary(bin) ->
        {{:pair, bin, nil}, Map.put(acc, bin, true)}

      [_ | _], _ ->
        raise TemplateMatchError, "expected only key/values or naked keys, got: #{inspect(values)}"
    end)
  end

  defp group_variables_by_type(varlist, existing_names) do
    varlist
    |> Enum.group_by(fn
      {_, name, :explode} when is_map_key(existing_names, name) -> :list_exploded
      {_, _, :explode} -> :map_exploded
      _ -> :regular
    end)
    |> Enum.into(%{regular: [], list_exploded: [], map_exploded: []})
  end

  defp assign_regular_params_by_name(regular, values) do
    Enum.map_reduce(regular, values, fn {:var, name, _}, values ->
      case list_split_first(values, &match?({:pair, ^name, _}, &1)) do
        {{:pair, ^name, ""}, values} -> {{name, nil}, values}
        {{:pair, ^name, val}, values} -> {{name, val}, values}
        {nil, values} -> {{name, nil}, values}
      end
    end)
  end

  defp assign_list_exploded_params_by_name(list_exploded, values) do
    Enum.map_reduce(list_exploded, values, fn {:var, name, _}, values ->
      {pairs, values} =
        Enum.split_with(values, fn
          {:pair, ^name, _} -> true
          _ -> false
        end)

      {{name, Enum.map(pairs, fn {:pair, _, v} -> v end)}, values}
    end)
  end

  defp assign_map_exploded_params_by_name([], _values) do
    []
  end

  defp assign_map_exploded_params_by_name([{:var, name, _} | other_maps], values) do
    remaining_values =
      case values do
        [] -> nil
        _ -> Map.new(values, fn {:pair, k, v} -> {k, v} end)
      end

    other_params = Enum.map(other_maps, fn {:var, name, _} -> {name, nil} end)

    [
      # first params takes it all
      {name, remaining_values}
      # other params must still be declared
      | other_params
    ]
  end

  defp list_split_first([h | t], predicate) do
    if predicate.(h) do
      {h, t}
    else
      {found, t} = list_split_first(t, predicate)
      {found, [h | t]}
    end
  end

  defp list_split_first([], _predicate) do
    {nil, []}
  end

  defp decode(url) when is_binary(url) do
    URI.decode(url)
  end

  defp decode(list) when is_list(list) do
    Enum.map(list, &URI.decode/1)
  end
end
