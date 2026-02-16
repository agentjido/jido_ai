defmodule Jido.AI.RegistryLifecycleTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Skill.Error
  alias Jido.AI.Skill.Registry, as: SkillRegistry
  alias Jido.AI.Streaming.Registry, as: StreamingRegistry

  setup do
    stop_registry(StreamingRegistry)
    stop_registry(SkillRegistry)

    on_exit(fn ->
      stop_registry(StreamingRegistry)
      stop_registry(SkillRegistry)
    end)

    :ok
  end

  describe "registry lifecycle consistency" do
    test "both registries lazy-start on first API access" do
      assert Process.whereis(StreamingRegistry) == nil
      assert Process.whereis(SkillRegistry) == nil

      assert {:error, :stream_not_found} = StreamingRegistry.get("missing-stream")
      assert is_pid(Process.whereis(StreamingRegistry))

      assert {:error, %Error.NotFound{name: "missing-skill"}} = SkillRegistry.lookup("missing-skill")
      assert is_pid(Process.whereis(SkillRegistry))
    end

    test "ensure_started/0 is idempotent for both registries" do
      assert :ok = StreamingRegistry.ensure_started()
      streaming_pid = Process.whereis(StreamingRegistry)
      assert is_pid(streaming_pid)
      assert :ok = StreamingRegistry.ensure_started()
      assert Process.whereis(StreamingRegistry) == streaming_pid

      assert :ok = SkillRegistry.ensure_started()
      skill_pid = Process.whereis(SkillRegistry)
      assert is_pid(skill_pid)
      assert :ok = SkillRegistry.ensure_started()
      assert Process.whereis(SkillRegistry) == skill_pid
    end

    test "both registries recover after process termination" do
      assert :ok = StreamingRegistry.ensure_started()
      assert :ok = SkillRegistry.ensure_started()

      old_streaming_pid = Process.whereis(StreamingRegistry)
      old_skill_pid = Process.whereis(SkillRegistry)

      stop_registry(StreamingRegistry)
      stop_registry(SkillRegistry)

      assert Process.whereis(StreamingRegistry) == nil
      assert Process.whereis(SkillRegistry) == nil

      assert {:error, :stream_not_found} = StreamingRegistry.get("missing-stream")
      new_streaming_pid = Process.whereis(StreamingRegistry)
      assert is_pid(new_streaming_pid)
      refute new_streaming_pid == old_streaming_pid

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
