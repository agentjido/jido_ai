defmodule Kodo.Core.BuiltinExecutorTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Execution.BuiltinExecutor

  defmodule TestCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "test"
    def description, do: "Test command"
    def usage, do: "test [args]"
    def meta, do: [:builtin]

    def execute([], _context), do: {:ok, "success"}
    def execute(["error"], _context), do: {:error, "test error"}
    def execute(["exception"], _context), do: raise("test exception")

    def execute(["file_error"], _context),
      do: raise(File.Error, reason: :enoent, action: "open", path: "/nonexistent")

    def execute(["arg_error"], _context), do: raise(ArgumentError, "invalid argument")
  end

  defmodule NonBuiltinCommand do
    @behaviour Kodo.Ports.Command

    def name, do: "external"
    def description, do: "External command"
    def usage, do: "external"
    def meta, do: [:pure]

    def execute([], _context), do: {:ok, "external"}
  end

  setup do
    # Register test commands (handle case where registry is already started)
    case start_supervised(Kodo.Core.Commands.CommandRegistry) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Kodo.Core.Commands.CommandRegistry.register_command(TestCommand)
    Kodo.Core.Commands.CommandRegistry.register_command(NonBuiltinCommand)

    context = %{
      session_pid: self(),
      env: %{"HOME" => "/home/test"},
      current_dir: System.tmp_dir!(),
      opts: %{}
    }

    {:ok, context: context}
  end

  describe "can_execute?/1" do
    test "returns true for builtin commands" do
      assert BuiltinExecutor.can_execute?("test")
    end

    test "returns false for non-builtin commands" do
      refute BuiltinExecutor.can_execute?("external")
    end

    test "returns false for unknown commands" do
      refute BuiltinExecutor.can_execute?("unknown")
    end
  end

  describe "execute/3" do
    test "executes builtin command successfully", %{context: context} do
      result = BuiltinExecutor.execute(TestCommand, [], context)
      assert result == {:ok, "success"}
    end

    test "handles command errors", %{context: context} do
      result = BuiltinExecutor.execute(TestCommand, ["error"], context)
      assert result == {:error, "test error"}
    end

    test "handles ArgumentError exceptions", %{context: context} do
      result = BuiltinExecutor.execute(TestCommand, ["arg_error"], context)
      assert {:error, "Invalid arguments: " <> _} = result
    end

    test "handles File.Error exceptions", %{context: context} do
      result = BuiltinExecutor.execute(TestCommand, ["file_error"], context)
      assert {:error, "File operation failed: " <> _} = result
    end

    test "handles general exceptions", %{context: context} do
      result = BuiltinExecutor.execute(TestCommand, ["exception"], context)
      assert {:error, "Command failed: test exception"} = result
    end
  end
end
