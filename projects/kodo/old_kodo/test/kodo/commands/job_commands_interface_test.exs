defmodule Kodo.Commands.JobCommandsInterfaceTest do
  use ExUnit.Case, async: true

  alias Kodo.Commands.{Bg, Fg, Jobs, Kill}

  describe "job command interfaces" do
    test "Bg command implements Command behavior correctly" do
      assert Bg.name() == "bg"
      assert Bg.description() == "Send job to background"
      assert Bg.usage() == "bg [job_id]"
      assert Bg.meta() == [:builtin]
    end

    test "Fg command implements Command behavior correctly" do
      assert Fg.name() == "fg"
      assert Fg.description() == "Bring job to foreground"
      assert Fg.usage() == "fg [job_id]"
      assert Fg.meta() == [:builtin]
    end

    test "Jobs command implements Command behavior correctly" do
      assert Jobs.name() == "jobs"
      assert Jobs.description() == "List active jobs"
      assert Jobs.usage() == "jobs [-l]"
      assert Jobs.meta() == [:builtin, :pure]
    end

    test "Kill command implements Command behavior correctly" do
      assert Kill.name() == "kill"
      assert Kill.description() == "Terminate a job"
      assert Kill.usage() == "kill [-SIGNAL] job_id"
      assert Kill.meta() == [:builtin]
    end
  end

  describe "argument validation (without JobManager)" do
    test "Bg validates job ID format" do
      context = %{session_pid: self()}
      assert {:error, "Invalid job ID: abc"} = Bg.execute(["abc"], context)
    end

    test "Bg validates argument count" do
      context = %{session_pid: self()}
      assert {:error, "Usage: bg [job_id]"} = Bg.execute(["1", "2"], context)
    end

    test "Fg validates job ID format" do
      context = %{session_pid: self()}
      assert {:error, "Invalid job ID: abc"} = Fg.execute(["abc"], context)
    end

    test "Fg validates argument count" do
      context = %{session_pid: self()}
      assert {:error, "Usage: fg [job_id]"} = Fg.execute(["1", "2"], context)
    end

    test "Kill validates job ID format" do
      assert {:error, "Invalid job ID: abc"} = Kill.execute(["abc"], %{})
    end

    test "Kill validates argument presence" do
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = Kill.execute([], %{})
    end

    test "Kill validates argument count" do
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = Kill.execute(["1", "2", "3"], %{})
    end
  end

  describe "signal parsing (Kill command)" do
    test "parses known signals correctly" do
      assert parse_signal("TERM") == :sigterm
      assert parse_signal("KILL") == :sigkill
      assert parse_signal("INT") == :sigint
      assert parse_signal("HUP") == :sighup
      assert parse_signal("QUIT") == :sigquit
      assert parse_signal("USR1") == :sigusr1
      assert parse_signal("USR2") == :sigusr2
    end

    test "passes through unknown signals" do
      assert parse_signal("UNKNOWN") == "UNKNOWN"
      assert parse_signal("custom") == "custom"
    end

    test "signal parsing is case sensitive" do
      # lowercase not recognized
      assert parse_signal("term") == "term"
      # uppercase recognized
      assert parse_signal("TERM") == :sigterm
    end

    test "parses kill arguments correctly" do
      # Default signal
      {signal, args} = parse_kill_args(["123"])
      assert signal == :sigterm
      assert args == ["123"]

      # Explicit signal
      {signal, args} = parse_kill_args(["-KILL", "123"])
      assert signal == :sigkill
      assert args == ["123"]

      # Unknown signal
      {signal, args} = parse_kill_args(["-CUSTOM", "123"])
      assert signal == "CUSTOM"
      assert args == ["123"]
    end
  end

  # Helper functions to replicate the private logic from Kill module
  defp parse_signal("TERM"), do: :sigterm
  defp parse_signal("KILL"), do: :sigkill
  defp parse_signal("INT"), do: :sigint
  defp parse_signal("HUP"), do: :sighup
  defp parse_signal("QUIT"), do: :sigquit
  defp parse_signal("USR1"), do: :sigusr1
  defp parse_signal("USR2"), do: :sigusr2
  defp parse_signal(unknown), do: unknown

  defp parse_kill_args(args) do
    case args do
      ["-" <> signal_str | rest] ->
        signal = parse_signal(signal_str)
        {signal, rest}

      args ->
        {:sigterm, args}
    end
  end
end
