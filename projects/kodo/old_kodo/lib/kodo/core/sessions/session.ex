defmodule Kodo.Core.Sessions.Session do
  @moduledoc """
  Manages individual shell sessions, maintaining state for command history,
  environment variables, and variable bindings.
  """
  use GenServer
  require Logger

  defstruct id: nil,
            history: [],
            env: %{},
            bindings: [],
            created_at: nil

  # Client API

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id)
  end

  def start_link(session_id, opts) do
    GenServer.start_link(__MODULE__, session_id, opts)
  end

  @doc """
  Evaluates an expression in the session.
  """
  @spec eval(pid(), String.t()) :: {:ok, term()} | {:error, term()}
  def eval(pid, expression) do
    GenServer.call(pid, {:evaluate, expression})
  end

  @doc """
  Gets the command history.
  """
  @spec history(pid()) :: [String.t()]
  def history(pid) do
    GenServer.call(pid, :get_history)
  end

  @doc """
  Gets all environment variables.
  """
  @spec env(pid()) :: %{String.t() => String.t()}
  def env(pid) do
    GenServer.call(pid, :get_env)
  end

  @doc """
  Sets an environment variable.
  """
  @spec set_env(pid(), String.t(), String.t()) :: :ok
  def set_env(pid, key, value) do
    GenServer.call(pid, {:set_env, key, value})
  end

  @doc """
  Gets a specific environment variable.
  """
  @spec get_env(pid(), String.t()) :: {:ok, String.t()} | :error
  def get_env(pid, key) do
    GenServer.call(pid, {:get_env, key})
  end

  # Server callbacks

  @impl true
  def init(session_id) do
    Logger.debug("Starting shell session", session_id: session_id)

    {:ok,
     %__MODULE__{
       id: session_id,
       env: default_env(),
       created_at: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_call({:evaluate, expression}, _from, state) do
    {result, new_bindings} = eval_expression(expression, state.bindings)
    new_state = %{state | history: [expression | state.history], bindings: new_bindings}
    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Enum.reverse(state.history), state}
  end

  @impl true
  def handle_call(:get_env, _from, state) do
    {:reply, state.env, state}
  end

  @impl true
  def handle_call({:set_env, key, value}, _from, state) do
    new_env = Map.put(state.env, key, value)
    {:reply, :ok, %{state | env: new_env}}
  end

  @impl true
  def handle_call({:get_env, key}, _from, state) do
    case Map.get(state.env, key) do
      nil -> {:reply, :error, state}
      value -> {:reply, {:ok, value}, state}
    end
  end

  # Private functions

  defp default_env do
    %{
      "HOME" => System.user_home(),
      "PWD" => File.cwd!(),
      "SHELL" => "kodo"
    }
  end

  defp eval_expression(expression, bindings) do
    try do
      {result, new_bindings} = Code.eval_string(expression, bindings)
      {{:ok, result}, new_bindings}
    rescue
      e ->
        Logger.warning("Expression evaluation failed",
          expression: expression,
          error: inspect(e)
        )

        {{:error, Exception.message(e)}, bindings}
    end
  end
end
