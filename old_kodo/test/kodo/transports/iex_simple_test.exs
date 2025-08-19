defmodule Kodo.Transports.IExSimpleTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias Kodo.Transports.IEx

  describe "Transport behavior compliance" do
    test "implements Transport behavior functions" do
      assert function_exported?(IEx, :start_link, 1)
      assert function_exported?(IEx, :stop, 1)
      assert function_exported?(IEx, :write, 2)
    end

    test "is a GenServer" do
      behaviors = IEx.__info__(:attributes)[:behaviour] || []
      assert GenServer in behaviors
    end

    test "has proper module structure" do
      # Test module loads correctly
      assert is_atom(IEx)
      assert IEx.__info__(:module) == IEx
    end
  end

  describe "GenServer callbacks" do
    test "handle_cast/2 with {:write, text}" do
      output =
        capture_io(fn ->
          state = %{}
          assert {:noreply, ^state} = IEx.handle_cast({:write, "test output"}, state)
        end)

      assert output =~ "test output"
    end

    test "handle_cast/2 with formatted text" do
      output =
        capture_io(fn ->
          state = %{}
          {:noreply, _} = IEx.handle_cast({:write, "warning: test warning"}, state)
        end)

      assert output =~ "warning: test warning"
    end

    test "handle_cast/2 with non-string data" do
      output =
        capture_io(fn ->
          state = %{}
          {:noreply, _} = IEx.handle_cast({:write, %{key: :value}}, state)
        end)

      assert output =~ "%{key: :value}"
    end
  end

  describe "input handling" do
    test "handle_input/2 with exit command" do
      state = %{prompt: "test> "}

      output =
        capture_io(fn ->
          assert {:stop, :normal} = IEx.handle_input("exit", state)
        end)

      assert output =~ "Exiting shell session"
    end

    test "handle_input/2 with empty input" do
      state = %{prompt: "test> ", history: []}
      assert {:ok, ^state} = IEx.handle_input("", state)
    end

    test "handle_input/2 with whitespace only" do
      state = %{prompt: "test> ", history: []}
      assert {:ok, ^state} = IEx.handle_input("   \n\t  ", state)
    end

    test "handle_input/2 with EOF" do
      state = %{prompt: "test> "}

      output =
        capture_io(fn ->
          assert {:stop, :normal} = IEx.handle_input(:eof, state)
        end)

      assert output =~ "Received EOF, terminating"
    end
  end

  describe "output formatting" do
    test "format_output/1 with string input" do
      text = "line1\nline2\nline3"
      result = IEx.format_output(text)
      assert is_binary(result)
      assert result =~ "line1"
      assert result =~ "line2"
      assert result =~ "line3"
    end

    test "format_output/1 with non-string input" do
      result = IEx.format_output(%{key: :value})
      assert result == "%{key: :value}"
    end

    test "format_line/1 with warning" do
      line = "warning: something happened"
      result = IEx.format_line(line)
      assert result =~ line
      assert is_binary(result)
    end

    test "format_line/1 with error" do
      line = "error: something went wrong"
      result = IEx.format_line(line)
      assert result =~ line
      assert is_binary(result)
    end

    test "format_line/1 with info" do
      line = "info: some information"
      result = IEx.format_line(line)
      assert result =~ line
      assert is_binary(result)
    end

    test "format_line/1 with normal text" do
      line = "normal output"
      result = IEx.format_line(line)
      assert result == line
    end

    test "format_error/1 formats error message" do
      error = "something went wrong"
      result = IEx.format_error(error)

      assert is_binary(result)
      assert result =~ "Error:"
      assert result =~ error
      assert result =~ "Type 'help' for available commands"
      # Should contain ANSI escape sequences
      assert result =~ "\e["
    end
  end

  describe "ANSI color formatting" do
    test "format_output applies colors to different line types" do
      input = "line1\nwarning: something\nerror: problem\ninfo: details\nnormal"
      result = IEx.format_output(input)

      assert is_binary(result)
      assert result =~ "line1"
      assert result =~ "warning: something"
      assert result =~ "error: problem"
      assert result =~ "info: details"
      assert result =~ "normal"
    end

    test "format_output preserves existing ANSI codes" do
      ansi_input = "\e[32mgreen text\e[0m\nregular text"
      result = IEx.format_output(ansi_input)

      assert result =~ "\e[32m"
      assert result =~ "green text"
      assert result =~ "\e[0m"
      assert result =~ "regular text"
    end

    test "format_error includes proper ANSI formatting" do
      error_msg = "test error"
      result = IEx.format_error(error_msg)

      assert is_binary(result)
      assert result =~ "Error:"
      assert result =~ error_msg
      assert result =~ "Type 'help' for available commands"
      # Should contain ANSI escape sequences for red color
      assert result =~ "\e["
    end
  end

  describe "module exports and structure" do
    test "exports required public functions" do
      # Transport behavior functions
      assert function_exported?(IEx, :start_link, 1)
      assert function_exported?(IEx, :stop, 1)
      assert function_exported?(IEx, :write, 2)

      # GenServer callbacks
      assert function_exported?(IEx, :init, 1)
      assert function_exported?(IEx, :handle_cast, 2)
      assert function_exported?(IEx, :handle_info, 2)

      # Now public for testing
      assert function_exported?(IEx, :handle_input, 2)
      assert function_exported?(IEx, :format_output, 1)
      assert function_exported?(IEx, :format_line, 1)
      assert function_exported?(IEx, :format_error, 1)
    end

    test "follows expected module structure" do
      # Should be GenServer
      behaviors = IEx.__info__(:attributes)[:behaviour] || []
      assert GenServer in behaviors

      # Should import IO.ANSI
      # This is tested indirectly through color formatting

      # Module should compile correctly
      assert is_atom(IEx)
      assert IEx.__info__(:module) == IEx
    end

    test "has proper documentation" do
      moduledoc = IEx.__info__(:attributes)[:moduledoc]

      case moduledoc do
        nil ->
          # If no moduledoc, just verify module loads
          assert is_atom(IEx)

        [false] ->
          flunk("Module explicitly marked as having no documentation")

        [doc_content] when is_binary(doc_content) ->
          assert doc_content =~ "IEx-based transport"
          assert doc_content =~ "interactive shell"

        other ->
          flunk("Unexpected moduledoc format: #{inspect(other)}")
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles malformed input gracefully" do
      state = %{prompt: "test> ", history: []}

      # Empty string after trim should be handled
      assert {:ok, ^state} = IEx.handle_input("", state)

      # Whitespace only should be handled
      assert {:ok, ^state} = IEx.handle_input("   ", state)

      # Tab and newline combinations
      assert {:ok, ^state} = IEx.handle_input("\t\n", state)
    end

    test "format functions handle edge cases" do
      # Empty string
      assert IEx.format_output("") == ""

      # Single character
      assert IEx.format_output("x") == "x"

      # Just newlines
      result = IEx.format_output("\n\n\n")
      assert is_binary(result)

      # Non-string input
      assert IEx.format_output(nil) == "nil"
      assert IEx.format_output([1, 2, 3]) == "[1, 2, 3]"
    end

    test "format_line handles various prefixes" do
      # Case sensitivity
      # No match
      assert IEx.format_line("WARNING: test") == "WARNING: test"
      # No match
      assert IEx.format_line("Error: test") == "Error: test"

      # Exact matches
      warning_result = IEx.format_line("warning: test")
      error_result = IEx.format_line("error: test")
      info_result = IEx.format_line("info: test")

      # All should contain the original text
      assert warning_result =~ "warning: test"
      assert error_result =~ "error: test"
      assert info_result =~ "info: test"

      # Normal text unchanged
      assert IEx.format_line("normal text") == "normal text"
    end
  end

  describe "coverage helpers" do
    test "exercises all public API functions" do
      # Test format_output variants
      assert is_binary(IEx.format_output("test"))
      assert is_binary(IEx.format_output(:atom))

      # Test format_line variants
      assert is_binary(IEx.format_line("warning: test"))
      assert is_binary(IEx.format_line("error: test"))
      assert is_binary(IEx.format_line("info: test"))
      assert is_binary(IEx.format_line("normal"))

      # Test format_error
      assert is_binary(IEx.format_error("test error"))

      # Test handle_input variants
      state = %{prompt: "test> ", history: []}
      assert {:ok, _} = IEx.handle_input("", state)
      assert {:stop, :normal} = IEx.handle_input("exit", state)
      assert {:stop, :normal} = IEx.handle_input(:eof, state)
    end

    test "all exported functions are callable" do
      # Transport functions exist
      assert function_exported?(IEx, :start_link, 1)
      assert function_exported?(IEx, :stop, 1)
      assert function_exported?(IEx, :write, 2)

      # GenServer functions exist
      assert function_exported?(IEx, :init, 1)
      assert function_exported?(IEx, :handle_cast, 2)
      assert function_exported?(IEx, :handle_info, 2)

      # Formatting functions now public
      assert function_exported?(IEx, :format_output, 1)
      assert function_exported?(IEx, :format_line, 1)
      assert function_exported?(IEx, :format_error, 1)
      assert function_exported?(IEx, :handle_input, 2)
    end
  end
end
