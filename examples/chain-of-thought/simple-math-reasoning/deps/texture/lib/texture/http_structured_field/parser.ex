# credo:disable-for-this-file Credo.Check.Readability.FunctionNames
# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Texture.HttpStructuredField.Parser do
  @moduledoc false

  defguard is_ALPHA(c) when c in ?a..?z or c in ?A..?Z
  defguard is_DIGIT(c) when c in ?0..?9
  defguard is_lcalpha(c) when c in ?a..?z
  defguard is_OWS(c) when c in [?\s, ?\t]

  defguard is_tchar(c)
           when is_ALPHA(c) or
                  is_DIGIT(c) or
                  c in [?_, ?-, ?!, ?., ?', ?*, ?&, ?#, ?%, ?`, ?^, ?+, ?|, ?~, ?$]

  defguard is_EOE(c) when c in [?;, ?,, ?\s, ?\t, ?)]

  defguard is_base64(c) when is_ALPHA(c) or is_DIGIT(c) or c in [?+, ?/]

  def parse_dict(buf) do
    parse_dict(buf, [])
  end

  defp parse_dict(buf, acc) do
    case parse_key(buf) do
      {:bool_true, key, buf} ->
        case collect_parameters({:boolean, true}, buf) do
          {:ok, item, buf} -> continue_dict(buf, [{key, item} | acc])
        end

      {:ok, key, <<?=, buf::binary>>} ->
        case parse_item_keep_whitespace_or_inner_list(buf) do
          {:ok, item, buf} ->
            continue_dict(buf, [{key, item} | acc])

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp continue_dict(buf, acc) do
    buf = skip_ws(buf)

    case buf do
      <<?,, buf::binary>> -> parse_dict(skip_ws(buf), acc)
      <<>> -> finalize_dict(acc, buf)
      buf -> error(:expected_delimiter, buf)
    end
  end

  defp finalize_dict(acc, buf) do
    # On duplicate keys, last occurence wins, so we dedup before reversing
    dict = acc |> Enum.uniq_by(&elem(&1, 0)) |> :lists.reverse()
    {:ok, dict, buf}
  end

  def parse_list(buf) do
    parse_list(buf, [])
  end

  defp parse_list(buf, acc) do
    case parse_item_keep_whitespace_or_inner_list(buf) do
      {:ok, item, buf} ->
        buf = skip_ws(buf)

        case buf do
          <<?,, buf::binary>> -> parse_list(skip_ws(buf), [item | acc])
          <<>> -> finalize_list([item | acc], buf)
          buf -> error(:expected_delimiter, buf)
        end

      {:error, _} = err ->
        err
    end
  end

  defp finalize_list(acc, buf) do
    {:ok, :lists.reverse(acc), buf}
  end

  defp parse_inner_list(<<?(, buf::binary>>) do
    parse_inner_list(skip_ws(buf), [])
  end

  defp parse_inner_list(buf) do
    error(:invalid_inner_list, buf)
  end

  defp parse_inner_list(<<?), buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, {:inner_list, :lists.reverse(acc)}, buf}
      <<>> -> {:ok, {:inner_list, :lists.reverse(acc)}, buf}
      buf -> error(:expected_eoe, buf)
    end
  end

  defp parse_inner_list(buf, acc) do
    with {:ok, item, buf} <- parse_item_keep_whitespace(buf),
         {:ok, buf} <- skip_expect_ws_or_lookahead_closing_paren(buf) do
      parse_inner_list(buf, [item | acc])
    else
      {:error, _} = err -> err
    end
  end

  # * If we find whitespace, then we skip it and we will arrive at the ')' or a
  #   next item to parse.
  # * If there is directly a ')' we do not consume it to arrive at it on the
  #   next loop of parse_inner_list/2, but we do not expect any whitespace
  defp skip_expect_ws_or_lookahead_closing_paren(buf)

  defp skip_expect_ws_or_lookahead_closing_paren(<<c, buf::binary>>) when is_OWS(c) do
    {:ok, skip_ws(buf)}
  end

  # Keep the closing paren in the bufer
  defp skip_expect_ws_or_lookahead_closing_paren(<<?\), _::binary>> = buf) do
    {:ok, buf}
  end

  defp skip_expect_ws_or_lookahead_closing_paren(buf) do
    error(:expected_whitespace, buf)
  end

  def parse_item(buf) do
    case parse_item_keep_whitespace(buf) do
      {:ok, item, ""} ->
        {:ok, item, ""}

      {:ok, item, buf} ->
        case skip_ws(buf) do
          "" -> {:ok, item, ""}
          rest -> error(:expected_delimiter, rest)
        end

      {:error, _} = err ->
        err
    end
  end

  def parse_item_keep_whitespace(buf) do
    case parse_bare_item(buf) do
      {:ok, item, buf} -> collect_parameters(item, buf)
      {:error, _} = err -> err
    end
  end

  defp parse_item_keep_whitespace_or_inner_list(buf) do
    case parse_inner_list(buf) do
      {:ok, inner, buf} -> collect_parameters(inner, buf)
      {:error, _} -> parse_item_keep_whitespace(buf)
    end
  end

  defp collect_parameters({tag, value}, buf) do
    case take_ws_parameters(buf, []) do
      {:ok, parameters, buf} -> {:ok, {tag, value, parameters}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_bare_item(buf) do
    with {:error, _} <- parse_decimal(buf),
         {:error, _} <- parse_integer(buf),
         {:error, _} <- parse_string(buf),
         {:error, _} <- parse_boolean(buf),
         {:error, _} <- parse_token(buf),
         {:error, _} <- parse_byte_sequence(buf) do
      error(:invalid_value, buf)
    end
  end

  defp parse_integer(<<?-, c, buf::binary>>) when is_DIGIT(c) do
    case take_integer(buf, [c, ?-]) do
      {:ok, digits, buf} -> {:ok, {:integer, finalize_integer(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_integer(<<c, buf::binary>>) when is_DIGIT(c) do
    case take_integer(buf, [c]) do
      {:ok, digits, buf} -> {:ok, {:integer, finalize_integer(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_integer(buf) do
    error(:invalid_integer, buf)
  end

  defp take_integer(<<c, buf::binary>>, acc) when is_DIGIT(c) do
    take_integer(buf, [c | acc])
  end

  defp take_integer(buf, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, :lists.reverse(acc), buf}
      <<>> -> {:ok, :lists.reverse(acc), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp finalize_integer(digits) do
    :erlang.list_to_integer(digits)
  end

  defp parse_decimal(<<?-, c, buf::binary>>) when is_DIGIT(c) do
    case take_decimal(buf, [c, ?-], _seen_dot? = false) do
      {:ok, [^c, ?-], _} -> error(:expected_dot, buf)
      {:ok, digits, buf} -> {:ok, {:decimal, finalize_decimal(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_decimal(<<c, buf::binary>>) when is_DIGIT(c) do
    case take_decimal(buf, [c], false) do
      {:ok, digits, buf} -> {:ok, {:decimal, finalize_decimal(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_decimal(buf) do
    error(:invalid_decimal, buf)
  end

  defp take_decimal(<<c, buf::binary>>, acc, seen_dot?) when is_DIGIT(c) do
    take_decimal(buf, [c | acc], seen_dot?)
  end

  defp take_decimal(<<?., c, buf::binary>>, acc, false) when is_DIGIT(c) do
    take_decimal(buf, [c, ?. | acc], true)
  end

  defp take_decimal(buf, acc, true) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, :lists.reverse(acc), buf}
      <<>> -> {:ok, :lists.reverse(acc), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_decimal(buf, _acc, false) do
    error(:invalid_decimal, buf)
  end

  defp finalize_decimal(digits) do
    :erlang.list_to_float(digits)
  end

  defp parse_boolean(<<??, ?0, buf::binary>>) do
    {:ok, {:boolean, false}, buf}
  end

  defp parse_boolean(<<??, ?1, buf::binary>>) do
    {:ok, {:boolean, true}, buf}
  end

  defp parse_boolean(buf) do
    error(:invalid_boolean, buf)
  end

  defp parse_byte_sequence(<<?:, ?:, buf::binary>> = all) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, {:byte_sequence, ""}, buf}
      <<>> -> {:ok, {:byte_sequence, ""}, buf}
      _ -> error(:expected_delimiter, all)
    end
  end

  defp parse_byte_sequence(<<?:, c, buf::binary>> = all) when is_base64(c) do
    case take_byte_sequence(buf, [c]) do
      {:ok, _bin, _buf} = ok -> ok
      {:error, :b64_decode} -> error(:invalid_byte_sequence, all)
      {:error, _} = err -> err
    end
  end

  defp parse_byte_sequence(buf) do
    error(:invalid_byte_sequence, buf)
  end

  defp take_byte_sequence(<<c, buf::binary>>, acc) when is_base64(c) do
    take_byte_sequence(buf, [c | acc])
  end

  defp take_byte_sequence(<<?=, buf::binary>>, acc) do
    # We can just add the padding to the binary. If that character is
    # present in the middle of the b64 string like this: "aGVsbG8=aGVsbG8="
    # it's going to be invalid anyway.
    take_byte_sequence(buf, [?= | acc])
  end

  defp take_byte_sequence(<<?:, buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> ok_finalize_byte_sequence(acc, buf)
      <<>> -> ok_finalize_byte_sequence(acc, buf)
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_byte_sequence(buf, _) do
    error(:invalid_byte_sequence, buf)
  end

  defp ok_finalize_byte_sequence(rev, buf) do
    b64 = IO.iodata_to_binary(:lists.reverse(rev))

    case Base.decode64(b64) do
      {:ok, value} -> {:ok, {:byte_sequence, value}, buf}
      :error -> {:error, :b64_decode}
    end
  end

  defp parse_string(<<?", buf::binary>>) do
    case take_string(buf, []) do
      {:ok, string, buf} -> {:ok, {:string, string}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_string(buf) do
    error(:invalid_string, buf)
  end

  defp take_string(<<?", buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, IO.iodata_to_binary(:lists.reverse(acc)), buf}
      <<>> -> {:ok, IO.iodata_to_binary(:lists.reverse(acc)), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_string(<<?\\, ?\\, buf::binary>>, acc) do
    take_string(buf, ["\\" | acc])
  end

  defp take_string(<<?\\, ?", buf::binary>>, acc) do
    take_string(buf, ["\"" | acc])
  end

  defp take_string(<<c::utf8, buf::binary>>, acc)
       when c == 0x20
       when c == 0x21
       when c in 0x23..0x5B
       when c in 0x5D..0x7E do
    take_string(buf, [<<c::utf8>> | acc])
  end

  defp take_string(<<_, _::binary>> = all, _acc) do
    error(:invalid_string, all)
  end

  defp take_string(<<>>, _acc) do
    error(:expected_delimiter, <<>>)
  end

  defp parse_token(<<c, buf::binary>>) when is_ALPHA(c) when c == ?* do
    case take_token(buf, [c]) do
      {:ok, token, buf} -> {:ok, {:token, token}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_token(buf) do
    error(:invalid_token, buf)
  end

  defp take_token(<<c, buf::binary>>, acc) when is_tchar(c) when c in [?:, ?/] do
    take_token(buf, [c | acc])
  end

  defp take_token(buf, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, List.to_string(:lists.reverse(acc)), buf}
      <<>> -> {:ok, List.to_string(:lists.reverse(acc)), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_ws_parameters(buf, acc) do
    case skip_ws(buf) do
      <<?;, buf::binary>> ->
        case take_parameter(skip_ws(buf)) do
          {:ok, p, buf} -> take_ws_parameters(buf, [p | acc])
          {:error, _} = err -> err
        end

      _buf_no_ws ->
        params = acc |> Enum.uniq_by(&elem(&1, 0)) |> :lists.reverse()
        {:ok, params, buf}
    end
  end

  defp take_parameter(buf) do
    with {:ok, key, <<?=, buf::binary>>} <- parse_key(buf),
         {:ok, value, buf} <- parse_bare_item(buf) do
      {:ok, {key, value}, buf}
    else
      {:bool_true, key, buf} -> {:ok, {key, {:boolean, true}}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_key(<<c, buf::binary>>) when is_lcalpha(c) when c == ?* do
    take_key(buf, [c])
  end

  defp parse_key(buf) do
    error(:invalid_key, buf)
  end

  defp take_key(<<c, buf::binary>>, acc)
       when is_lcalpha(c)
       when is_DIGIT(c)
       when c in [?_, ?-, ?., ?*] do
    take_key(buf, [c | acc])
  end

  defp take_key(<<?=, _::binary>> = buf, acc) do
    {:ok, List.to_string(:lists.reverse(acc)), buf}
  end

  defp take_key(<<c, _::binary>> = buf, acc) when is_EOE(c) do
    {:bool_true, List.to_string(:lists.reverse(acc)), buf}
  end

  defp take_key(<<>> = buf, acc) do
    {:bool_true, List.to_string(:lists.reverse(acc)), buf}
  end

  defp skip_ws(buf)

  defp skip_ws(<<c, buf::binary>>) when is_OWS(c) do
    skip_ws(buf)
  end

  defp skip_ws(buf) do
    buf
  end

  def error(errmsg, buf) do
    {:error, {errmsg, buf}}
  end
end
