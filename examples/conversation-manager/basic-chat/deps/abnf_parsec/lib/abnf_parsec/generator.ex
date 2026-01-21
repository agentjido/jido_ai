defmodule AbnfParsec.Generator do
  @moduledoc false

  @external_resource Path.join(:code.priv_dir(:abnf_parsec), "core.abnf")

  @core_rules AbnfParsec.Parser.parse!(File.read!(@external_resource))

  core_rulenames =
    Enum.map(
      @core_rules,
      fn {:rule, [{:rulename, rulename} | _definition]} ->
        rulename
      end
    )

  @core_rulenames core_rulenames

  def generate(rulelist, opts) do
    required_rulenames =
      @core_rulenames --
        for(
          {:rule, [{:rulename, rulename} | _definition]} <- rulelist,
          do: String.upcase(rulename)
        )

    required_core_rules =
      Enum.filter(@core_rules, fn {:rule, [{:rulename, rulename} | _definition]} ->
        rulename in required_rulenames
      end)

    for {:rule, [{:rulename, rulename} | definition]} <- required_core_rules ++ rulelist do
      define(rulename, definition, opts)
    end
  end

  defp define(rulename, definition, opts) do
    parsec_name = normalize_rulename(rulename)
    definition = expand(definition, opts[:mode] || :text)

    definition = transform(rulename, definition, get_in(opts, [:transform, rulename]))

    definition =
      cond do
        rulename in Map.get(opts, :ignore, []) ->
          Macro.pipe(definition, quote(do: ignore()), 0)

        rulename in Map.get(opts, :unwrap, []) ->
          Macro.pipe(definition, quote(do: unwrap_and_tag(unquote(parsec_name))), 0)

        rulename in Map.get(opts, :untag, []) ->
          Macro.pipe(definition, quote(do: wrap()), 0)

        rulename in Map.get(opts, :unbox, []) ->
          definition

        rulename in @core_rulenames ->
          # unbox core rules by default to achieve backwards compatibility
          # TODO: maybe leave this to users or make it configurable
          definition

        true ->
          Macro.pipe(definition, quote(do: tag(unquote(parsec_name))), 0)
      end

    cond do
      rulename in Map.get(opts, :skip, []) ->
        []

      opts[:private] ->
        quote do
          defparsecp unquote(parsec_name), unquote(definition)
        end

      true ->
        quote do
          defparsec unquote(parsec_name), unquote(definition)
        end
    end
  end

  defp transform(rulename, definition, transformations) do
    transformations =
      if is_nil(transformations) and rulename in @core_rulenames do
        # transform core rules by default for convenience
        # TODO: maybe leave this to users or make it configurable
        [{:reduce, {List, :to_string, []}}]
      else
        List.wrap(transformations)
      end

    Enum.reduce(transformations, definition, &do_transform/2)
  end

  defp do_transform(transformation, definition) do
    case transformation do
      {:reduce, mfa} ->
        Macro.pipe(definition, quote(do: reduce(unquote(Macro.escape(mfa)))), 0)

      {:map, mfa} ->
        Macro.pipe(definition, quote(do: map(unquote(Macro.escape(mfa)))), 0)

      {:replace, val} ->
        Macro.pipe(definition, quote(do: replace(unquote(Macro.escape(val)))), 0)

      {:pre_traverse, mfa} ->
        Macro.pipe(definition, quote(do: pre_traverse(unquote(Macro.escape(mfa)))), 0)

      {:post_traverse, mfa} ->
        Macro.pipe(definition, quote(do: post_traverse(unquote(Macro.escape(mfa)))), 0)

      nil ->
        definition
    end
  end

  defp normalize_rulename(rulename) do
    rulename
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp base_num(num, base) do
    String.to_integer(
      num,
      case base do
        "x" -> 16
        "d" -> 10
        "b" -> 2
      end
    )
  end

  defp pipe(a, b) do
    quote do
      unquote(a) |> unquote(b)
    end
  end

  defp expand(list, mode) when is_list(list) do
    [element] = Enum.reject(list, &match?({:comment, _}, &1))
    expand(element, mode)
  end

  defp expand({:rulename, rulename}, _mode) do
    parsec_name = normalize_rulename(rulename)

    quote do
      parsec(unquote(parsec_name))
    end
  end

  defp expand(<<char::utf8>> = string, mode) when char not in ?a..?z and char not in ?A..?Z do
    expand({:case_sensitive, string}, mode)
  end

  defp expand(string, mode) when is_binary(string) do
    expand({:case_insensitive, string}, mode)
  end

  defp expand({:case_insensitive, string}, mode) when is_binary(string) do
    lower = String.downcase(string)
    upper = String.upcase(string)

    insensitive =
      Enum.zip(String.to_charlist(lower), String.to_charlist(upper))
      |> Enum.map(fn
        {c, c} -> {:case_sensitive, <<c>>}
        {l, u} -> {:alternation, [{:case_sensitive, <<l>>}, {:case_sensitive, <<u>>}]}
      end)

    concat = expand({:concatenation, insensitive}, mode)

    quote do
      reduce(unquote(concat), {Enum, :join, []})
    end
  end

  defp expand({:case_sensitive, string}, _mode) when is_binary(string) do
    quote do
      string(unquote(string))
    end
  end

  defp expand({:num_literal, [{:base, base}, num]}, mode) do
    num = base_num(num, base)

    case mode do
      :text ->
        quote do
          utf8_char([unquote(num)])
        end

      :byte ->
        quote do
          ascii_char([unquote(num)])
        end
    end
  end

  defp expand({:num_range, [{:base, base}, a, b]}, mode) do
    a = base_num(a, base)
    b = base_num(b, base)

    case mode do
      :text ->
        quote do
          utf8_char([unquote(a)..unquote(b)])
        end

      :byte ->
        quote do
          ascii_char([unquote(a)..unquote(b)])
        end
    end
  end

  defp expand({:num_sequence, [{:base, base} | nums]}, mode) do
    nums = Enum.map(nums, &base_num(&1, base))

    case mode do
      :text ->
        str = to_string(nums)

        quote do
          string(unquote(str))
        end

      :byte ->
        quote do
          string(<<unquote_splicing(nums)>>)
        end
    end
  end

  defp expand({:concatenation, elements}, mode) do
    elements
    |> Enum.map(&expand(&1, mode))
    |> Enum.reduce(fn
      {:|>, _, _} = b, a ->
        Enum.reduce(
          [a | b |> Macro.unpipe() |> Enum.map(&elem(&1, 0))],
          &pipe(&2, &1)
        )

      b, a ->
        pipe(a, b)
    end)
  end

  defp expand({:alternation, elements}, mode) do
    alternations = Enum.map(elements, &expand(&1, mode))

    quote do
      choice(unquote(alternations))
    end
  end

  defp expand({:repetition, [{:repeat, repeat}, repeated]}, mode) do
    repeated = expand(repeated, mode)

    case repeat do
      [] ->
        quote do
          repeat(unquote(repeated))
        end

      [times: times] ->
        quote do
          duplicate(unquote(repeated), unquote(times))
        end

      repeat ->
        quote do
          times(unquote(repeated), unquote(repeat))
        end
    end
  end

  defp expand({:option, element}, mode) do
    option = expand(element, mode)

    quote do
      optional(unquote(option))
    end
  end

  defp expand({:prose_val, _}, _mode) do
    quote do
      ascii_string([{:not, ?\r}, {:not, ?\n}], min: 0)
    end
  end

  # Extension: Used in RFC3501

  defp expand({:exception, [range | exceptions]}, mode) do
    except = Enum.map(exceptions, &expand(&1, mode))
    proceed = expand(range, mode)

    lookahead =
      case except do
        [except] ->
          except

        [_ | _] ->
          quote do
            choice(unquote(except))
          end
      end

    quote do
      lookahead_not(unquote(lookahead)) |> unquote(proceed)
    end
  end
end
