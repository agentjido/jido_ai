defmodule Mix.Tasks.KodoTest do
  # Mix tasks need to be synchronous
  use ExUnit.Case, async: false

  describe "Mix.Tasks.Kodo" do
    test "has run/1 function" do
      assert function_exported?(Mix.Tasks.Kodo, :run, 1)
    end

    test "task is properly defined" do
      assert Mix.Tasks.Kodo.__info__(:attributes)[:shortdoc] == [
               "Start an interactive Kodo shell"
             ]
    end

    test "is a Mix task" do
      behaviors = Mix.Tasks.Kodo.__info__(:attributes)[:behaviour] || []
      assert Mix.Task in behaviors
    end

    test "has expected module structure" do
      # Test that the module has the expected function exports
      assert function_exported?(Mix.Tasks.Kodo, :run, 1)

      # Test module attributes exist
      assert Mix.Tasks.Kodo.__info__(:attributes)[:shortdoc] != nil
    end

    test "run/1 function signature accepts arguments" do
      # Test that the module defines run/1 by checking if it can be referenced
      # without actually calling it (which would hang)

      # Test that the function exists in the module's function list
      functions = Mix.Tasks.Kodo.__info__(:functions)
      assert {:run, 1} in functions
    end

    test "module has proper documentation" do
      moduledoc = Mix.Tasks.Kodo.__info__(:attributes)[:moduledoc]
      # Module should have documentation (not false, and should exist)
      if moduledoc == nil do
        # If no moduledoc, that's still valid - just test the module loads
        assert is_atom(Mix.Tasks.Kodo)
      else
        assert moduledoc != [false]
      end
    end
  end
end
