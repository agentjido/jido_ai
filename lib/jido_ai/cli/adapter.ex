defmodule Jido.AI.CLI.Adapter do
  @moduledoc """
  Behavior for CLI adapters that drive different agent types.

  Adapters encapsulate the specifics of how to:
  - Start an agent
  - Submit a query
  - Wait for completion
  - Extract the result

  This keeps the Mix task clean and allows new agent types (CoT, ToT, etc.)
  to be added by implementing this behavior.

  ## Built-in Adapters

  - `Jido.AI.CLI.Adapters.ReAct` - For `Jido.AI.Agent` modules
  - `Jido.AI.CLI.Adapters.ToT` - For Tree-of-Thoughts agents
  - `Jido.AI.CLI.Adapters.CoT` - For Chain-of-Thought agents
  - `Jido.AI.CLI.Adapters.GoT` - For Graph-of-Thoughts agents
  - `Jido.AI.CLI.Adapters.TRM` - For TRM (Tiny-Recursive-Model) agents
  - `Jido.AI.CLI.Adapters.Adaptive` - For Adaptive strategy agents (auto-selects reasoning approach)

  ## Custom Agents

  Agent modules can optionally implement `cli_adapter/0` to specify their adapter:

      defmodule MyApp.CustomAgent do
        use Jido.AI.Agent, ...

        def cli_adapter, do: Jido.AI.CLI.Adapters.ReAct
      end

  If not implemented, the CLI will infer the adapter from `--type` or default to ReAct.
  """

  @type config :: map()
  @type result :: %{answer: String.t(), meta: map()}

  @doc """
  Start an agent and return its pid.
  """
  @callback start_agent(jido_instance :: atom(), agent_module :: module(), config()) ::
              {:ok, pid()} | {:error, term()}

  @doc """
  Submit a query to the running agent.
  """
  @callback submit(pid(), query :: String.t(), config()) :: :ok | {:error, term()}

  @doc """
  Wait for the agent to complete and return the result.
  """
  @callback await(pid(), timeout_ms :: non_neg_integer(), config()) ::
              {:ok, result()} | {:error, term()}

  @doc """
  Stop the agent process.
  """
  @callback stop(pid()) :: :ok

  @doc """
  Create an ephemeral agent module with the given configuration.
  Returns the module name. Only called when --agent is not provided.
  """
  @callback create_ephemeral_agent(config()) :: module()

  @doc """
  Resolve the adapter module for an agent type or agent module.
  """
  @spec resolve(type :: String.t() | nil, agent_module :: module() | nil) ::
          {:ok, module()} | {:error, term()}
  def resolve(type, agent_module) do
    cond do
      # If agent module provides its own adapter, use it
      agent_module && function_exported?(agent_module, :cli_adapter, 0) ->
        {:ok, agent_module.cli_adapter()}

      # Type explicitly specified
      type == "react" || type == nil ->
        {:ok, Jido.AI.CLI.Adapters.ReAct}

      type == "tot" ->
        {:ok, Jido.AI.CLI.Adapters.ToT}

      type == "cot" ->
        {:ok, Jido.AI.CLI.Adapters.CoT}

      type == "got" ->
        {:ok, Jido.AI.CLI.Adapters.GoT}

      type == "trm" ->
        {:ok, Jido.AI.CLI.Adapters.TRM}

      type == "adaptive" ->
        {:ok, Jido.AI.CLI.Adapters.Adaptive}

      true ->
        {:error, "Unknown agent type: #{type}. Supported: react, tot, cot, got, trm, adaptive"}
    end
  end
end
