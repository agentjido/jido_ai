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

  - `Jido.AI.Reasoning.ReAct.CLIAdapter` - For `Jido.AI.Agent` modules
  - `Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter` - For `Jido.AI.AoTAgent` agents
  - `Jido.AI.Reasoning.ChainOfDraft.CLIAdapter` - For Chain-of-Draft agents
  - `Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter` - For Tree-of-Thoughts agents
  - `Jido.AI.Reasoning.ChainOfThought.CLIAdapter` - For Chain-of-Thought agents
  - `Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter` - For Graph-of-Thoughts agents
  - `Jido.AI.Reasoning.TRM.CLIAdapter` - For TRM (Tiny-Recursive-Model) agents
  - `Jido.AI.Reasoning.Adaptive.CLIAdapter` - For Adaptive strategy agents (auto-selects reasoning approach)

  ## Custom Agents

  Agent modules can optionally implement `cli_adapter/0` to specify their adapter:

      defmodule MyApp.CustomAgent do
        use Jido.AI.Agent, ...

        def cli_adapter, do: Jido.AI.Reasoning.ReAct.CLIAdapter
      end

  If not implemented, the CLI will infer the adapter from `--type` or default to ReAct.
  """

  @supported_types ~w(react aot cod cot tot got trm adaptive)
  @type_to_adapter %{
    "react" => Jido.AI.Reasoning.ReAct.CLIAdapter,
    "aot" => Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter,
    "cod" => Jido.AI.Reasoning.ChainOfDraft.CLIAdapter,
    "cot" => Jido.AI.Reasoning.ChainOfThought.CLIAdapter,
    "tot" => Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter,
    "got" => Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter,
    "trm" => Jido.AI.Reasoning.TRM.CLIAdapter,
    "adaptive" => Jido.AI.Reasoning.Adaptive.CLIAdapter
  }

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
      exports_cli_adapter?(agent_module) ->
        {:ok, agent_module.cli_adapter()}

      true ->
        resolve_type(type || "react")
    end
  end

  @doc false
  @spec supported_types() :: [String.t()]
  def supported_types, do: @supported_types

  defp resolve_type(type) do
    case Map.fetch(@type_to_adapter, type) do
      {:ok, adapter} ->
        {:ok, adapter}

      :error ->
        {:error, "Unknown agent type: #{type}. Supported: #{Enum.join(@supported_types, ", ")}"}
    end
  end

  defp exports_cli_adapter?(nil), do: false

  defp exports_cli_adapter?(agent_module) when is_atom(agent_module) do
    case Code.ensure_loaded(agent_module) do
      {:module, _} -> function_exported?(agent_module, :cli_adapter, 0)
      {:error, _} -> false
    end
  end
end
