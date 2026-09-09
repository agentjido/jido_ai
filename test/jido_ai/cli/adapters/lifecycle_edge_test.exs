defmodule Jido.AI.CLI.AdapterLifecycleEdgeTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.CLI.Adapter
  alias Jido.AI.Reasoning.Adaptive.CLIAdapter, as: AdaptiveAdapter
  alias Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter, as: AoTAdapter
  alias Jido.AI.Reasoning.ChainOfDraft.CLIAdapter, as: CoDAdapter
  alias Jido.AI.Reasoning.ChainOfThought.CLIAdapter, as: CoTAdapter
  alias Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter, as: GoTAdapter
  alias Jido.AI.Reasoning.ReAct.CLIAdapter, as: ReActAdapter
  alias Jido.AI.Reasoning.TRM.CLIAdapter, as: TRMAdapter
  alias Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter, as: ToTAdapter
  alias Jido.AI.TestSupport.CLIAdapter, as: AdapterTestSupport

  setup :set_mimic_from_context

  @adapters [
    AdaptiveAdapter,
    AoTAdapter,
    CoDAdapter,
    CoTAdapter,
    GoTAdapter,
    ReActAdapter,
    TRMAdapter,
    ToTAdapter
  ]

  defmodule LifecycleAgent do
    use Jido.Agent, name: "cli_adapter_lifecycle"
  end

  test "each adapter starts and stops an Agent and tolerates a stopped process" do
    jido = :"cli_adapter_lifecycle_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})

    for adapter <- @adapters do
      assert {:ok, pid} = adapter.start_agent(jido, LifecycleAgent, %{})
      assert Process.alive?(pid)
      assert :ok = adapter.stop(pid)
      refute Process.alive?(pid)
      assert :ok = adapter.stop(pid)
    end
  end

  test "each adapter continues polling until the Session reports completion" do
    stub(Adapter, :status, fn _pid ->
      [next | rest] = Process.get(:adapter_statuses)
      Process.put(:adapter_statuses, rest)
      {:ok, next}
    end)

    running = AdapterTestSupport.status(done?: false, snapshot_status: :running)
    completed = AdapterTestSupport.status(result: "answer")

    for adapter <- @adapters do
      Process.put(:adapter_statuses, [running, completed])
      assert {:ok, %{answer: "answer"}} = adapter.await(self(), 500, %{})
      assert Process.get(:adapter_statuses) == []
    end
  end
end
