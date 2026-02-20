defmodule Jido.AI.Reasoning.ReAct do
  @moduledoc """
  Public API for Task-based ReAct runtime.

  This module provides streaming and checkpoint-aware execution that can be reused
  by actions and strategies.
  """

  alias Jido.AI.Reasoning.ReAct.{Config, Runner, State, Token}

  @type config_input :: Config.t() | map() | keyword()

  @doc """
  Starts a new ReAct run and returns a lazy event stream.
  """
  @spec stream(String.t(), config_input(), keyword()) :: Enumerable.t()
  def stream(query, config, opts \\ []) when is_binary(query) and is_list(opts) do
    config = build_config(config)
    Runner.stream(query, config, opts)
  end

  @doc """
  Resumes a ReAct run from state and returns a lazy event stream.
  """
  @spec stream_from_state(State.t(), config_input(), keyword()) :: Enumerable.t()
  def stream_from_state(%State{} = state, config, opts \\ []) when is_list(opts) do
    config = build_config(config)
    Runner.stream_from_state(state, config, opts)
  end

  @doc """
  Runs ReAct to completion and returns an aggregated result map.
  """
  @spec run(String.t(), config_input(), keyword()) :: map()
  def run(query, config, opts \\ []) when is_binary(query) and is_list(opts) do
    query
    |> stream(config, opts)
    |> collect_stream()
  end

  @doc """
  Starts a run and returns run metadata plus a stream handle.
  """
  @spec start(String.t(), config_input(), keyword()) :: {:ok, map()} | {:error, term()}
  def start(query, config, opts \\ []) when is_binary(query) and is_list(opts) do
    config = build_config(config)

    state = State.new(query, config.system_prompt, Keyword.take(opts, [:request_id, :run_id]))
    events = Runner.stream(query, config, Keyword.put(opts, :state, state))

    {:ok,
     %{
       run_id: state.run_id,
       request_id: state.request_id,
       events: events,
       checkpoint_token: nil
     }}
  rescue
    e -> {:error, e}
  end

  @doc """
  Resumes a run from a checkpoint token and returns run metadata plus a stream handle.
  """
  @spec continue(String.t(), config_input(), keyword()) :: {:ok, map()} | {:error, term()}
  def continue(checkpoint_token, config, opts \\ []) when is_binary(checkpoint_token) and is_list(opts) do
    config = build_config(config)

    with {:ok, state, _payload} <- Token.decode_state(checkpoint_token, config) do
      events = Runner.stream_from_state(state, config, opts)

      {:ok,
       %{
         run_id: state.run_id,
         request_id: state.request_id,
         events: events,
         checkpoint_token: checkpoint_token
       }}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Collects run output from an event stream or checkpoint token.
  """
  @spec collect(Enumerable.t() | String.t(), config_input(), keyword()) :: {:ok, map()} | {:error, term()}
  def collect(checkpoint_token, config, opts) when is_binary(checkpoint_token) and is_list(opts) do
    run_until_terminal? = Keyword.get(opts, :run_until_terminal?, true)

    if run_until_terminal? do
      with {:ok, resumed} <- continue(checkpoint_token, config, opts) do
        {:ok, collect_stream(resumed.events)}
      end
    else
      config = build_config(config)

      with {:ok, state, payload} <- Token.decode_state(checkpoint_token, config) do
        {:ok,
         %{
           result: state.result,
           termination_reason: decode_termination_reason(state),
           usage: state.usage,
           final_token: checkpoint_token,
           trace: [],
           token_payload: payload
         }}
      end
    end
  rescue
    e -> {:error, e}
  end

  def collect(events, _config, _opts) do
    {:ok, collect_stream(events)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Marks a checkpoint token as cancelled and returns a replacement token.
  """
  @spec cancel(String.t(), config_input(), atom()) :: {:ok, String.t()} | {:error, term()}
  def cancel(checkpoint_token, config, reason \\ :cancelled)
      when is_binary(checkpoint_token) and is_atom(reason) do
    config = build_config(config)
    Token.mark_cancelled(checkpoint_token, config, reason)
  rescue
    e -> {:error, e}
  end

  @doc """
  Normalizes user-provided configuration into a `Config` struct.
  """
  @spec build_config(config_input()) :: Config.t()
  def build_config(%Config{} = config), do: config
  def build_config(config), do: Config.new(config)

  @doc """
  Reduces a ReAct event stream into terminal result, usage, token, and full trace.
  """
  @spec collect_stream(Enumerable.t()) :: map()
  def collect_stream(events) do
    acc =
      Enum.reduce(events, initial_collect_acc(), fn event, acc ->
        acc
        |> Map.update!(:trace, &[event | &1])
        |> update_collect_from_event(event)
      end)

    %{
      result: acc.result,
      termination_reason: acc.termination_reason,
      usage: acc.usage,
      final_token: acc.final_token,
      trace: Enum.reverse(acc.trace)
    }
  end

  defp initial_collect_acc do
    %{
      result: nil,
      termination_reason: nil,
      usage: %{},
      final_token: nil,
      trace: []
    }
  end

  defp update_collect_from_event(acc, %{kind: :checkpoint, data: %{token: token}}), do: %{acc | final_token: token}

  defp update_collect_from_event(acc, %{kind: :request_completed, data: data}) do
    %{
      acc
      | result: Map.get(data, :result),
        termination_reason: Map.get(data, :termination_reason, :final_answer),
        usage: Map.get(data, :usage, acc.usage)
    }
  end

  defp update_collect_from_event(acc, %{kind: :request_failed, data: data}) do
    %{acc | result: Map.get(data, :error), termination_reason: :failed}
  end

  defp update_collect_from_event(acc, %{kind: :request_cancelled, data: _data}) do
    %{acc | termination_reason: :cancelled}
  end

  defp update_collect_from_event(acc, _event), do: acc

  defp decode_termination_reason(%State{status: :completed}), do: :completed
  defp decode_termination_reason(%State{status: :failed}), do: :failed
  defp decode_termination_reason(%State{status: :cancelled}), do: :cancelled
  defp decode_termination_reason(_), do: nil
end
