defmodule Jido.AI.RegistryLifecycleTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Skill.Error
  alias Jido.AI.Skill.Registry, as: SkillRegistry

  setup do
    stop_registry(SkillRegistry)

    on_exit(fn ->
      stop_registry(SkillRegistry)
    end)

    :ok
  end

  describe "registry lifecycle consistency" do
    test "skill registry lazy-starts on first API access" do
      assert Process.whereis(SkillRegistry) == nil

      assert {:error, %Error.NotFound{name: "missing-skill"}} = SkillRegistry.lookup("missing-skill")
      assert is_pid(Process.whereis(SkillRegistry))
    end

    test "ensure_started/0 is idempotent" do
      assert :ok = SkillRegistry.ensure_started()
      skill_pid = Process.whereis(SkillRegistry)
      assert is_pid(skill_pid)
      assert :ok = SkillRegistry.ensure_started()
      assert Process.whereis(SkillRegistry) == skill_pid
    end

    test "registry recovers after process termination" do
      assert :ok = SkillRegistry.ensure_started()

      old_skill_pid = Process.whereis(SkillRegistry)

      stop_registry(SkillRegistry)

      assert Process.whereis(SkillRegistry) == nil

      assert {:error, %Error.NotFound{name: "missing-skill"}} = SkillRegistry.lookup("missing-skill")
      new_skill_pid = Process.whereis(SkillRegistry)
      assert is_pid(new_skill_pid)
      refute new_skill_pid == old_skill_pid
    end
  end

  defp stop_registry(name) do
    case Process.whereis(name) do
      nil ->
        :ok

      _pid ->
        try do
          GenServer.stop(name, :normal, 5_000)
        catch
          :exit, {:noproc, _} -> :ok
          :exit, {:normal, _} -> :ok
        end
    end
  end
end
