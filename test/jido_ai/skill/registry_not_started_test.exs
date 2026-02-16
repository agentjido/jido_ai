defmodule Jido.AI.Skill.RegistryNotStartedTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Skill
  alias Jido.AI.Skill.{Error, Registry}

  setup do
    stop_registry()

    on_exit(fn ->
      stop_registry()
    end)

    :ok
  end

  describe "when registry is not started" do
    test "lookup/1 does not raise and returns not_found" do
      assert Process.whereis(Registry) == nil

      assert {:error, %Error.NotFound{name: "missing-skill"}} = Registry.lookup("missing-skill")
      assert is_pid(Process.whereis(Registry))
    end

    test "list/0 returns an empty list" do
      assert Process.whereis(Registry) == nil

      assert Registry.list() == []
      assert is_pid(Process.whereis(Registry))
    end

    test "all/0 returns an empty list" do
      assert Process.whereis(Registry) == nil

      assert Registry.all() == []
      assert is_pid(Process.whereis(Registry))
    end

    test "Skill.resolve/1 returns a structured error" do
      assert Process.whereis(Registry) == nil

      assert {:error, %Error.NotFound{name: "missing-skill"}} = Skill.resolve("missing-skill")
      assert is_pid(Process.whereis(Registry))
    end
  end

  defp stop_registry do
    case Process.whereis(Registry) do
      nil ->
        :ok

      _pid ->
        try do
          GenServer.stop(Registry, :normal, 5_000)
        catch
          :exit, {:noproc, _} -> :ok
          :exit, {:normal, _} -> :ok
        end
    end
  end
end
