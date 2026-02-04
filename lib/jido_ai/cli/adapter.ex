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

  - `Jido.AI.CLI.Adapters.ReAct` - For ReAct-style agents
  - `Jido.AI.CLI.Adapters.ToT` - For Tree-of-Thoughts agents
  - `Jido.AI.CLI.Adapters.CoT` - For Chain-of-Thought agents
  - `Jido.AI.CLI.Adapters.GoT` - For Graph-of-Thoughts agents
  - `Jido.AI.CLI.Adapters.TRM` - For TRM (Tiny-Recursive-Model) agents
  - `Jido.AI.CLI.Adapters.Adaptive` - For Adaptive strategy agents (auto-selects reasoning approach)

  ## Custom Agents

  Agent modules can optionally implement `cli_adapter/0` to specify their adapter:

      defmodule MyApp.CustomAgent do
        use Jido.AI.ReActAgent, ...

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

  @adapter_by_type %{
    "react" => Jido.AI.CLI.Adapters.ReAct,
    "tot" => Jido.AI.CLI.Adapters.ToT,
    "cot" => Jido.AI.CLI.Adapters.CoT,
    "got" => Jido.AI.CLI.Adapters.GoT,
    "trm" => Jido.AI.CLI.Adapters.TRM,
    "adaptive" => Jido.AI.CLI.Adapters.Adaptive,
    nil => Jido.AI.CLI.Adapters.ReAct
  }

  @doc """
  Resolve the adapter module for an agent type or agent module.
  """
  @spec resolve(type :: String.t() | nil, agent_module :: module() | nil) ::
          {:ok, module()} | {:error, term()}
  def resolve(type, agent_module) do
    if agent_module && function_exported?(agent_module, :cli_adapter, 0) do
      # If agent module provides its own adapter, use it
      {:ok, agent_module.cli_adapter()}
    else
      case Map.get(@adapter_by_type, type) do
        nil ->
          {:error, "Unknown agent type: #{type}. Supported: react, tot, cot, got, trm, adaptive"}

        adapter ->
          {:ok, adapter}
      end
    end
  end
end
