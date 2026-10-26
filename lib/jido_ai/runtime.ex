defmodule Jido.AI.Runtime do
  @moduledoc false

  @doc "Returns the portable wall-clock time for one graph Action."
  @spec now_ms(map()) :: integer()
  def now_ms(context) when is_map(context) do
    case Map.get(context, :jido_ai_now_ms) do
      value when is_integer(value) -> value
      _other -> System.system_time(:millisecond)
    end
  end

  @doc "Publishes one immediate runtime Signal when a dispatch target is present."
  @spec publish(map(), String.t(), map()) :: :ok | {:error, term()}
  def publish(context, type, data) when is_map(context) and is_binary(type) and is_map(data) do
    case Map.get(context, :jido_ai_dispatch) do
      nil ->
        :ok

      dispatch ->
        source = "/jido/ai/#{Map.get(context, :agent_id, "runtime")}"

        with {:ok, signal} <- Jido.Signal.new(type, data, source: source) do
          Jido.Signal.Dispatch.dispatch(signal, dispatch)
        end
    end
  end
end
