defmodule Jido.AI.Plugins.TaskSupervisorTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Plugins.TaskSupervisor

  setup :set_mimic_from_context

  test "mount/2 starts and stores a task supervisor" do
    assert {:ok, %{supervisor: pid}} = TaskSupervisor.mount(%{}, %{})
    assert is_pid(pid)
    assert Process.alive?(pid)
    GenServer.stop(pid, :normal)
  end

  test "mount/2 returns structured error when supervisor start fails" do
    Mimic.copy(Task.Supervisor)

    Mimic.stub(Task.Supervisor, :start_link, fn ->
      {:error, :boom}
    end)

    assert {:error, {:task_supervisor_failed, :boom}} = TaskSupervisor.mount(%{}, %{})
  end
end
