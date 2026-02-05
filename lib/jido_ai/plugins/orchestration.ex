require Jido.AI.Actions.Orchestration.AggregateResults
require Jido.AI.Actions.Orchestration.DelegateTask
require Jido.AI.Actions.Orchestration.DiscoverCapabilities
# Ensure actions are compiled before the skill
require Jido.AI.Actions.Orchestration.SpawnChildAgent
require Jido.AI.Actions.Orchestration.StopChildAgent

defmodule Jido.AI.Plugins.Orchestration do
  @moduledoc """
  Multi-agent coordination and delegation skill.

  This skill provides orchestration primitives for spawning, managing,
  and coordinating child agents. It enables patterns like:

  * **Hierarchical delegation** - Parent delegates tasks to specialist children
  * **Scatter-gather** - Fan-out work, await results, aggregate
  * **LLM-powered routing** - Use AI to decide task routing

  ## Usage

  Attach to an orchestrator agent:

      defmodule MyOrchestrator do
        use Jido.Agent,
          skills: [
            {Jido.AI.Plugins.Orchestration, []}
          ]
      end

  ## State Structure

  The skill tracks:
  - `children` - Map of tag => child info
  - `inflight` - Map of call_id => pending delegation info
  - `capability_cache` - Cached capability descriptors

  ## Signal Routing

  The skill handles:
  - `jido.agent.child.started` - Child spawn confirmation
  - `jido.agent.child.exit` - Child termination
  - `ai.delegation.request` - Incoming delegation requests
  - `ai.delegation.result` - Delegation results from children
  - `ai.delegation.error` - Delegation errors

  ## Actions

  - `SpawnChildAgent` - Spawn a child agent
  - `StopChildAgent` - Stop a tracked child
  - `DelegateTask` - LLM-powered task routing
  - `DiscoverCapabilities` - Extract agent capabilities
  - `AggregateResults` - Combine results from multiple sources
  """

  use Jido.Plugin,
    name: "orchestration",
    state_key: :orchestration,
    actions: [
      Jido.AI.Actions.Orchestration.SpawnChildAgent,
      Jido.AI.Actions.Orchestration.StopChildAgent,
      Jido.AI.Actions.Orchestration.DelegateTask,
      Jido.AI.Actions.Orchestration.DiscoverCapabilities,
      Jido.AI.Actions.Orchestration.AggregateResults
    ],
    description: "Multi-agent coordination and delegation",
    category: "orchestration",
    tags: ["orchestration", "multi-agent", "delegation", "coordination"],
    vsn: "1.0.0"

  alias Jido.AI.Signal.{DelegationRequest, DelegationResult, DelegationError}

  @doc """
  Initialize skill state when mounted to an agent.
  """
  @impl Jido.Plugin
  def mount(_agent, _config) do
    initial_state = %{
      children: %{},
      inflight: %{},
      capability_cache: %{}
    }

    {:ok, initial_state}
  end

  @doc """
  Returns the signal router for this skill.
  """
  @impl Jido.Plugin
  def router(_config) do
    [
      {"orchestration.spawn", Jido.AI.Actions.Orchestration.SpawnChildAgent},
      {"orchestration.stop", Jido.AI.Actions.Orchestration.StopChildAgent},
      {"orchestration.delegate", Jido.AI.Actions.Orchestration.DelegateTask},
      {"orchestration.discover", Jido.AI.Actions.Orchestration.DiscoverCapabilities},
      {"orchestration.aggregate", Jido.AI.Actions.Orchestration.AggregateResults}
    ]
  end

  @doc """
  Handle incoming signals for orchestration events.
  """
  @impl Jido.Plugin
  def handle_signal(signal, context) do
    case signal.type do
      "jido.agent.child.started" ->
        handle_child_started(signal, context)

      "jido.agent.child.exit" ->
        handle_child_exit(signal, context)

      "ai.delegation.result" ->
        handle_delegation_result(signal, context)

      "ai.delegation.error" ->
        handle_delegation_error(signal, context)

      _ ->
        {:ok, :continue}
    end
  end

  @doc """
  Transform action results, potentially updating orchestration state.
  """
  @impl Jido.Plugin
  def transform_result(action, result, _context) do
    case action do
      Jido.AI.Actions.Orchestration.SpawnChildAgent ->
        result

      Jido.AI.Actions.Orchestration.DelegateTask ->
        result

      _ ->
        result
    end
  end

  @doc """
  Returns signal patterns this skill responds to.
  """
  def signal_patterns do
    [
      "orchestration.spawn",
      "orchestration.stop",
      "orchestration.delegate",
      "orchestration.discover",
      "orchestration.aggregate",
      "jido.agent.child.started",
      "jido.agent.child.exit",
      "ai.delegation.request",
      "ai.delegation.result",
      "ai.delegation.error"
    ]
  end

  # ============================================================================
  # Signal Handlers
  # ============================================================================

  defp handle_child_started(signal, _context) do
    _tag = signal.data[:tag]
    _pid = signal.data[:pid]
    {:ok, :continue}
  end

  defp handle_child_exit(signal, _context) do
    _tag = signal.data[:tag]
    _reason = signal.data[:reason]
    {:ok, :continue}
  end

  defp handle_delegation_result(_signal, _context) do
    {:ok, :continue}
  end

  defp handle_delegation_error(_signal, _context) do
    {:ok, :continue}
  end

  # ============================================================================
  # Helper Functions for Creating Delegation Signals
  # ============================================================================

  @doc """
  Create a delegation request signal.

  ## Examples

      signal = Orchestration.delegation_request("call_123", "Analyze document", :doc_agent)
  """
  def delegation_request(call_id, task, target, constraints \\ %{}) do
    DelegationRequest.new!(%{
      call_id: call_id,
      task: task,
      target: target,
      constraints: constraints
    })
  end

  @doc """
  Create a delegation result signal.

  ## Examples

      signal = Orchestration.delegation_result("call_123", {:ok, result}, :doc_agent)
  """
  def delegation_result(call_id, result, source_agent, duration_ms \\ nil) do
    data = %{
      call_id: call_id,
      result: result,
      source_agent: source_agent
    }

    data = if duration_ms, do: Map.put(data, :duration_ms, duration_ms), else: data
    DelegationResult.new!(data)
  end

  @doc """
  Create a delegation error signal.

  ## Examples

      signal = Orchestration.delegation_error("call_123", :timeout, "Task timed out")
  """
  def delegation_error(call_id, error_type, message, source_agent \\ nil) do
    data = %{
      call_id: call_id,
      error_type: error_type,
      message: message
    }

    data = if source_agent, do: Map.put(data, :source_agent, source_agent), else: data
    DelegationError.new!(data)
  end

  @doc """
  Generate a unique call ID for correlation.
  """
  def generate_call_id do
    "delegation_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
