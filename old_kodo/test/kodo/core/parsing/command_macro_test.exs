defmodule Kodo.Core.CommandMacroTest do
  use ExUnit.Case, async: true

  defmodule TestMacroCommand do
    use Kodo.Core.Parsing.CommandMacro

    defcommand "test_macro",
      description: "Test command using macro",
      usage: "test_macro [arg]",
      meta: [:builtin, :pure] do
      def execute([], _context), do: {:ok, "macro success"}
      def execute([arg], _context), do: {:ok, "macro with #{arg}"}
      def execute(_args, _context), do: {:error, "Usage: test_macro [arg]"}
    end
  end

  defmodule SimpleCommand do
    use Kodo.Core.Parsing.CommandMacro

    defcommand "simple",
      description: "Simple test command" do
      def execute([], _context), do: {:ok, "simple"}
    end
  end

  describe "defcommand macro" do
    test "generates correct name/0" do
      assert TestMacroCommand.name() == "test_macro"
    end

    test "generates correct description/0" do
      assert TestMacroCommand.description() == "Test command using macro"
    end

    test "generates correct usage/0" do
      assert TestMacroCommand.usage() == "test_macro [arg]"
    end

    test "generates correct meta/0" do
      assert TestMacroCommand.meta() == [:builtin, :pure]
    end

    test "uses default values when not provided" do
      assert SimpleCommand.name() == "simple"
      assert SimpleCommand.description() == "Simple test command"
      assert SimpleCommand.usage() == "simple"
      assert SimpleCommand.meta() == [:builtin]
    end

    test "generated execute/2 works correctly" do
      assert TestMacroCommand.execute([], %{}) == {:ok, "macro success"}
      assert TestMacroCommand.execute(["test"], %{}) == {:ok, "macro with test"}
      assert TestMacroCommand.execute(["a", "b"], %{}) == {:error, "Usage: test_macro [arg]"}
    end

    test "implements Command behavior" do
      behaviours = TestMacroCommand.module_info(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end
  end
end
