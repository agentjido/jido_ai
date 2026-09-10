defmodule Jido.AI.Quota do
  @moduledoc false
  alias Jido.AI.Quota.Store

  def track(context, fun) do
    case if(is_map(context), do: Map.get(context, :jido_ai_quota)) do
      nil -> invoke(fun, fn _ -> :ok end)
      binding -> Jido.AI.Error.capture(fn -> tracked(binding, context, fun) end)
    end
  end

  defp tracked(binding, context, fun) do
    id = Map.get(context, :jido_ai_quota_call_id) || Jido.Signal.ID.generate!()

    case Store.begin_call(binding, id) do
      {:ok, ticket} ->
        try do
          result =
            invoke(fun, fn usage ->
              if is_map(usage) and map_size(usage) > 0,
                do:
                  Store.progress(
                    binding.store,
                    ticket,
                    Jido.AI.Usage.token_counts(usage).total_tokens
                  ),
                else: :ok
            end)

          :ok = Store.finish_call(binding.store, ticket, response_tokens(result))
          result
        catch
          kind, reason ->
            stack = __STACKTRACE__
            Store.finish_call(binding.store, ticket, nil)
            :erlang.raise(kind, reason, stack)
        end

      {:error, :quota_exceeded} ->
        {:error, error(binding)}

      {:error, _} = error ->
        error
    end
  end

  defp invoke(fun, progress) when is_function(fun, 1), do: fun.(progress)
  defp invoke(fun, _), do: fun.()

  def error(binding) do
    Jido.AI.Error.error_envelope(
      :quota_exceeded,
      binding.error_message,
      %{scope: binding.scope, request_id: binding.request_id, signal_type: binding.signal_type},
      false
    )
  end

  def total_tokens(data) do
    case field(data, :total_tokens) do
      total when is_integer(total) and total >= 0 -> total
      _ -> nonnegative(field(data, :input_tokens)) + nonnegative(field(data, :output_tokens))
    end
  end

  defp response_tokens({:ok, %{response: response}}), do: response_tokens({:ok, response})
  # ReqLLM normalizes missing provider usage to zero. Keep that ambiguity
  # explicit instead of claiming that the invocation had a known zero cost.
  defp response_tokens({:ok, %{usage: usage}}) when is_map(usage) and map_size(usage) > 0 do
    case Jido.AI.Usage.token_counts(usage).total_tokens do
      total when total > 0 -> total
      _ -> nil
    end
  end

  defp response_tokens(_), do: nil
  defp field(data, key), do: Map.get(data, key, Map.get(data, Atom.to_string(key)))
  defp nonnegative(value) when is_integer(value) and value >= 0, do: value
  defp nonnegative(_), do: 0
end
