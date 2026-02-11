defmodule Jido.AI.RLM.BudgetStore do
  @moduledoc """
  Tree-wide budget tracking for RLM agent trees.

  Tracks two resource limits across all agents in a query tree:

    * `max_children_total` — hard cap on total spawned agents
    * `token_budget` — total token cap across all agents

  Both limits are optional; when unset, usage is unlimited.

  ## Usage

      {:ok, ref} = BudgetStore.new("req-123", max_children_total: 10, token_budget: 50_000)
      {:ok, granted, remaining} = BudgetStore.reserve_children(ref, 3)
      :ok = BudgetStore.add_tokens(ref, 1200)
      status = BudgetStore.status(ref)
      :ok = BudgetStore.destroy(ref)
  """

  use GenServer

  @type budget_ref :: %{pid: pid()}

  @spec new(String.t(), keyword()) :: {:ok, budget_ref()}
  def new(_request_id, opts \\ []) do
    children_max = Keyword.get(opts, :max_children_total)
    tokens_max = Keyword.get(opts, :token_budget)

    state = %{
      children_used: 0,
      children_max: children_max,
      tokens_used: 0,
      tokens_max: tokens_max
    }

    {:ok, pid} = GenServer.start_link(__MODULE__, state)
    {:ok, %{pid: pid}}
  end

  @spec reserve_children(budget_ref(), non_neg_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer() | :unlimited}
  def reserve_children(%{pid: pid}, n) do
    GenServer.call(pid, {:reserve_children, n})
  end

  @spec add_tokens(budget_ref(), non_neg_integer()) :: :ok | {:error, :token_budget_exceeded}
  def add_tokens(%{pid: pid}, tokens) do
    GenServer.call(pid, {:add_tokens, tokens})
  end

  @spec status(budget_ref()) :: map()
  def status(%{pid: pid}) do
    GenServer.call(pid, :status)
  end

  @spec destroy(budget_ref()) :: :ok
  def destroy(%{pid: pid}) do
    GenServer.stop(pid, :normal)
    :ok
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:reserve_children, n}, _from, %{children_max: nil} = state) do
    new_state = Map.update!(state, :children_used, &(&1 + n))
    {:reply, {:ok, n, :unlimited}, new_state}
  end

  def handle_call({:reserve_children, n}, _from, state) do
    available = max(state.children_max - state.children_used, 0)
    granted = min(n, available)
    new_state = Map.update!(state, :children_used, &(&1 + granted))
    remaining = state.children_max - new_state.children_used
    {:reply, {:ok, granted, remaining}, new_state}
  end

  @impl true
  def handle_call({:add_tokens, tokens}, _from, %{tokens_max: nil} = state) do
    new_state = Map.update!(state, :tokens_used, &(&1 + tokens))
    {:reply, :ok, new_state}
  end

  def handle_call({:add_tokens, tokens}, _from, state) do
    new_used = state.tokens_used + tokens

    if new_used > state.tokens_max do
      {:reply, {:error, :token_budget_exceeded}, state}
    else
      {:reply, :ok, %{state | tokens_used: new_used}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end
end
