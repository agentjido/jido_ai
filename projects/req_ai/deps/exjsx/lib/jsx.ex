defmodule JSX do
  def encode!(term, opts \\ []) do
    parser_opts = :jsx_config.extract_config(opts ++ [:escaped_strings])
    parser(:jsx_to_json, opts, parser_opts).(JSX.Encoder.json(term) ++ [:end_json])
  end

  def encode(term, opts \\ []) do
    { :ok, encode!(term, opts) }
  rescue
    ArgumentError -> { :error, :badarg }
  end

  def decode!(json, opts \\ []) do
    decoder_opts = :jsx_config.extract_config(opts)
    case decoder(JSX.Decoder, opts ++ [:return_maps], decoder_opts).(json) do
      { :incomplete, _ } -> raise ArgumentError
      result -> result
    end
  end

  def decode(term, opts \\ []) do
    { :ok, decode!(term, opts) }
  rescue
    ArgumentError -> { :error, :badarg }
  end

  def format!(json, opts \\ []) do
    case :jsx.format(json, opts) do
      { :incomplete, _ } -> raise ArgumentError
      result -> result
    end
  end

  def format(json, opts \\ []) do
    { :ok, format!(json, opts) }
  rescue
    ArgumentError -> { :error, :badarg }
  end

  def minify!(json), do: format!(json, [space: 0, indent: 0])

  def minify(json) do
    { :ok, minify!(json) }
  rescue
    ArgumentError -> { :error, :badarg }
  end

  def prettify!(json), do: format!(json, [space: 1, indent: 2])

  def prettify(json) do
    { :ok, prettify!(json) }
  rescue
    ArgumentError -> { :error, :badarg }
  end

  def is_json?(json, opts \\ []) do
    case :jsx.is_json(json, opts) do
      { :incomplete, _ } -> false
      result -> result
    end
  rescue
    _ -> false
  end

  def is_term?(term, opts \\ []) do
    parser_opts = :jsx_config.extract_config(opts)
    parser(:jsx_verify, opts, parser_opts).(JSX.Encoder.json(term) ++ [:end_json])
  rescue
    _ -> false
  end

  def encoder(handler, initialstate, opts) do
    :jsx.encoder(handler, initialstate, opts)
  end

  def decoder(handler, initialstate, opts) do
    :jsx.decoder(handler, initialstate, opts)
  end

  def parser(handler, initialstate, opts) do
    :jsx.parser(handler, initialstate, opts)
  end
end

defmodule JSX.Decoder do
  def init(opts) do
    :jsx_to_term.init(opts)
  end

  def handle_event({ :literal, :null }, state), do: :jsx_to_term.insert(:nil, state)
  def handle_event(event, state), do: :jsx_to_term.handle_event(event, state)
end

defprotocol JSX.Encoder do
  @fallback_to_any true
  def json(term)
end

defimpl JSX.Encoder, for: Map do
  def json(map) do
    [:start_object] ++ unpack(map, Map.keys(map))
  end

  defp unpack(map, [k|rest]) when is_integer(k) or is_binary(k) or is_atom(k) do
    [k] ++ JSX.Encoder.json(Map.get(map, k)) ++ unpack(map, rest)
  end
  defp unpack(_, []), do: [:end_object]
end

defimpl JSX.Encoder, for: List do
  def json([]), do: [:start_array, :end_array]
  def json([{}]), do: [:start_object, :end_object]
  def json([{ _, _ }|_] = list) do
    [:start_object] ++ unzip(list)
  end
  def json(list) do
    [:start_array] ++ unhitch(list)
  end

  defp unzip([{k, v}|rest]) when is_integer(k) or is_binary(k) or is_atom(k) do
    [k] ++ JSX.Encoder.json(v) ++ unzip(rest)
  end
  defp unzip([]), do: [:end_object]

  defp unhitch([v|rest]) do
    JSX.Encoder.json(v) ++ unhitch(rest)
  end
  defp unhitch([]), do: [:end_array]
end

defimpl JSX.Encoder, for: Atom do
  def json(nil), do: [:null]
  def json(true), do: [true]
  def json(false), do: [false]
  def json(atom), do: [atom]
end

defimpl JSX.Encoder, for: [Integer, Float, BitString] do
  def json(value), do: [value]
end

defimpl JSX.Encoder, for: [Range, Stream, MapSet] do
  def json(enumerable), do: enumerable |> Enum.to_list |> JSX.Encoder.json
end

defimpl JSX.Encoder, for: [Tuple, PID, Port, Reference, Function, Any] do
  def json(map) when is_map(map), do: JSX.Encoder.Map.json(Map.delete(map, :__struct__))
  def json(_), do: raise ArgumentError
end
