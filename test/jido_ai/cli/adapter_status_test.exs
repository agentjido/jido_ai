defmodule Jido.AI.CLI.AdapterStatusTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.CLI.Adapter

  Mimic.copy(Jido.AI.Session)
  setup :set_mimic_from_context

  defmodule CustomAdapterAgent do
    def cli_adapter, do: __MODULE__.Adapter
  end

  test "projects each request phase into a CLI snapshot" do
    stub(Jido.AI.Session, :snapshot, fn _server -> Process.get(:session_snapshot) end)

    expected = %{
      completed: {:success, true},
      failed: {:failure, true},
      cancelled: {:failure, true},
      pending: {:running, false},
      queued: {:idle, false}
    }

    for {phase, {status, done?}} <- expected do
      request = %{
        status: phase,
        result: if(phase == :completed, do: %{answer: "done"}),
        error: if(phase == :failed, do: :boom),
        meta: %{phase: phase}
      }

      Process.put(
        :session_snapshot,
        {:ok,
         %{
           agent: %{id: "agent", state: %{count: 1}},
           request: request,
           details: %{source: :test}
         }}
      )

      assert {:ok, view} = Adapter.status(self())
      assert view.agent_id == "agent"
      assert view.raw_state == %{count: 1}
      assert view.snapshot.status == status
      assert view.snapshot.done? == done?
      assert view.snapshot.details == %{phase: phase, source: :test}
    end
  end

  test "projects an idle Session and propagates snapshot errors" do
    expect(Jido.AI.Session, :snapshot, fn _ ->
      {:ok, %{agent: %{id: "agent", state: %{}}, request: nil, details: %{}}}
    end)

    assert {:ok, %{snapshot: %{status: :idle, done?: false, result: nil}}} =
             Adapter.status(self())

    expect(Jido.AI.Session, :snapshot, fn _ -> {:error, :unavailable} end)
    assert {:error, :unavailable} = Adapter.status(self())
  end

  test "checks custom and unloaded Agent modules" do
    assert {:ok, CustomAdapterAgent.Adapter} = Adapter.resolve("react", CustomAdapterAgent)

    unloaded = Module.concat(__MODULE__, NotLoaded)
    assert {:ok, Jido.AI.Reasoning.ReAct.CLIAdapter} = Adapter.resolve("react", unloaded)
  end
end
