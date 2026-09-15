defmodule JidoAI.Examples.Completion.Store do
  @moduledoc "A byte store that can refuse or lose the reply to a completion write."
  use Elixir.Agent
  @behaviour Jido.Persistence.Adapter

  def start_link(_),
    do: Elixir.Agent.start_link(fn -> %{records: %{}, writes: 0, completion_writes: 0} end)

  def writes(store), do: Elixir.Agent.get(store, & &1.writes)
  def completion_writes(store), do: Elixir.Agent.get(store, & &1.completion_writes)

  def get(key, opts) do
    Elixir.Agent.get(opts[:store], fn state ->
      case Map.fetch(state.records, key) do
        {:ok, bytes} -> {:ok, bytes}
        :error -> {:error, :not_found}
      end
    end)
  end

  def put(key, bytes, opts),
    do: Elixir.Agent.update(opts[:store], &put_in(&1.records[key], bytes))

  def delete(key, opts),
    do: Elixir.Agent.update(opts[:store], &%{&1 | records: Map.delete(&1.records, key)})

  def compare_and_swap(key, expected, bytes, opts) do
    result =
      Elixir.Agent.get_and_update(opts[:store], fn state ->
        checkpoint = :erlang.binary_to_term(bytes, [:safe]).checkpoint

        completion? =
          Enum.any?(checkpoint.state.requests, fn {_, record} -> record.status != :pending end)

        state = %{
          state
          | writes: state.writes + 1,
            completion_writes: state.completion_writes + if(completion?, do: 1, else: 0)
        }

        cond do
          Map.get(state.records, key, :not_found) != expected ->
            {{:error, :conflict}, state}

          not completion? ->
            {:ok, put_in(state.records[key], bytes)}

          opts[:failure] == :conflict ->
            {{:error, :conflict}, state}

          true ->
            {opts[:failure], put_in(state.records[key], bytes)}
        end
      end)

    case result do
      :indeterminate -> {:error, :indeterminate}
      :raise -> raise "The completion was stored, but its reply was lost"
      other -> other
    end
  end
end
