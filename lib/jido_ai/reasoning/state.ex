defmodule Jido.AI.Reasoning.State do
  @moduledoc """
  Portable request state passed between AI reasoning Flow components.

  The public fields contain the request input, selected Flow, controls, usage,
  and sanitized trace. ReqLLM values are encoded in the private binary field.
  Custom reasoning Flows should use Jido AI Actions to read or change that
  private value.
  """

  @type t :: %{
          required(:__jido_ai_reasoning__) => true,
          required(:request_id) => String.t(),
          required(:run_id) => String.t(),
          required(:input) => String.t(),
          required(:reasoning) => module(),
          required(:controls) => map(),
          required(:model_calls) => non_neg_integer(),
          required(:tool_calls) => non_neg_integer(),
          required(:iterations) => non_neg_integer(),
          required(:provider_usage) => map(),
          required(:trace) => [map()],
          required(:private) => binary()
        }

  @usage_keys [
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :input_cost,
    :output_cost,
    :reasoning_cost,
    :total_cost
  ]

  @doc false
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %{
      __jido_ai_reasoning__: true,
      request_id: Map.fetch!(attrs, :request_id),
      run_id: Map.fetch!(attrs, :run_id),
      input: Map.fetch!(attrs, :input),
      reasoning: Map.fetch!(attrs, :reasoning),
      controls: Map.fetch!(attrs, :controls),
      model_calls: 0,
      tool_calls: 0,
      iterations: 0,
      provider_usage: %{},
      trace: [],
      private: encode(Map.fetch!(attrs, :private))
    }
  end

  @doc false
  @spec private(t()) :: map()
  def private(%{__jido_ai_reasoning__: true, private: private}) when is_binary(private),
    do: :erlang.binary_to_term(private, [:safe])

  @doc false
  @spec put_private(t(), map()) :: t()
  def put_private(%{__jido_ai_reasoning__: true} = state, private) when is_map(private),
    do: %{state | private: encode(private)}

  @doc "Returns portable request usage counters."
  @spec usage(t()) :: map()
  def usage(%{__jido_ai_reasoning__: true} = state) do
    Map.merge(state.provider_usage, %{
      model_calls: state.model_calls,
      tool_calls: state.tool_calls,
      iterations: state.iterations
    })
  end

  @doc false
  @spec add_usage(t(), map() | nil) :: t()
  def add_usage(%{__jido_ai_reasoning__: true} = state, usage) do
    incoming = normalize_usage(usage)

    provider_usage =
      Map.merge(state.provider_usage, incoming, fn _key, current, value -> current + value end)

    %{state | provider_usage: provider_usage}
  end

  @doc false
  @spec normalize_usage(map() | nil) :: map()
  def normalize_usage(nil), do: %{}

  def normalize_usage(usage) when is_map(usage) do
    normalized = ReqLLM.Usage.normalize(usage)

    Enum.reduce(@usage_keys, %{}, fn key, result ->
      case Map.get(normalized, key) || Map.get(normalized, Atom.to_string(key)) do
        value when is_number(value) -> Map.put(result, key, value)
        _value -> result
      end
    end)
  end

  def normalize_usage(_usage), do: %{}

  @doc false
  @spec trace(t(), atom(), map()) :: t()
  def trace(%{__jido_ai_reasoning__: true} = state, type, data)
      when is_atom(type) and is_map(data) do
    event =
      Jido.AI.Event.new(state, type, data,
        sequence: length(state.trace) + 1,
        elapsed_ms: elapsed_ms(state),
        iteration: state.iterations
      )

    %{state | trace: [event | state.trace]}
  end

  @doc false
  @spec trace(t(), map()) :: t()
  def trace(%{__jido_ai_reasoning__: true} = state, %{type: type} = event) do
    trace(state, type, Map.delete(event, :type))
  end

  @doc false
  @spec since_last_event_ms(t()) :: non_neg_integer()
  def since_last_event_ms(%{__jido_ai_reasoning__: true, trace: [event | _]} = state) do
    max(elapsed_ms(state) - Map.get(event, :elapsed_ms, 0), 0)
  end

  def since_last_event_ms(%{__jido_ai_reasoning__: true} = state), do: elapsed_ms(state)

  @doc false
  @spec summarize(term()) :: map()
  def summarize(%module{}), do: %{type: :struct, module: inspect(module)}

  def summarize(value) when is_map(value) do
    %{type: :map, keys: value |> Map.keys() |> Enum.map(&key_name/1) |> Enum.sort()}
  end

  def summarize(value) when is_binary(value), do: %{type: :text, bytes: byte_size(value)}
  def summarize(value) when is_list(value), do: %{type: :list, count: length(value)}
  def summarize(value) when is_integer(value), do: %{type: :integer}
  def summarize(value) when is_float(value), do: %{type: :float}
  def summarize(value) when is_boolean(value), do: %{type: :boolean}
  def summarize(nil), do: %{type: :null}
  def summarize(value) when is_atom(value), do: %{type: :atom}
  def summarize(value) when is_tuple(value), do: %{type: :tuple, size: tuple_size(value)}
  def summarize(_value), do: %{type: :term}

  defp elapsed_ms(state) do
    case private(state) do
      %{deadline: %{at: at, timeout: timeout}} ->
        remaining = max(at - System.monotonic_time(:millisecond), 0)
        max(timeout - remaining, 0)

      _private ->
        0
    end
  end

  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(_key), do: "term"

  defp encode(value), do: :erlang.term_to_binary(value, [:deterministic])
end
