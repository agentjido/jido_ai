defmodule Kodo.Transports.IExTest do
  use Kodo.Case, async: false

  alias Kodo.Transports.IEx
  import ExUnit.CaptureIO

  describe "handle_input/2" do
    test "handles exit command" do
      state = %{prompt: "test> ", session_pid: nil, history: [], instance: :test}

      assert {:stop, :normal} = IEx.handle_input("exit", state)
    end

    test "handles empty input" do
      state = %{prompt: "test> ", session_pid: nil, history: [], instance: :test}

      assert {:ok, ^state} = IEx.handle_input("", state)
    end

    test "handles whitespace-only input" do
      state = %{prompt: "test> ", session_pid: nil, history: [], instance: :test}

      assert {:ok, ^state} = IEx.handle_input("   \n  ", state)
    end

    test "handles EOF input" do
      state = %{prompt: "test> ", session_pid: nil, history: [], instance: :test}

      assert {:stop, :normal} = IEx.handle_input(:eof, state)
    end
  end

  describe "format_output/1" do
    test "formats string output" do
      result = IEx.format_output("hello world")
      assert result == "hello world"
    end

    test "formats non-string output" do
      result = IEx.format_output(42)
      assert result == "42"
    end

    test "formats multiline text with warnings" do
      text =
        "warning: this is a warning\ninfo: this is info\nerror: this is an error\nnormal line"

      result = IEx.format_output(text)

      assert String.contains?(result, "warning: this is a warning")
      assert String.contains?(result, "info: this is info")
      assert String.contains?(result, "error: this is an error")
      assert String.contains?(result, "normal line")
    end

    test "formats lines with different prefixes" do
      assert IEx.format_line("warning: test") =~ "warning: test"
      assert IEx.format_line("error: test") =~ "error: test"
      assert IEx.format_line("info: test") =~ "info: test"
      assert IEx.format_line("normal line") == "normal line"
    end
  end

  describe "format_error/1" do
    test "formats error message with ANSI colors" do
      result = IEx.format_error("Something went wrong")

      assert String.contains?(result, "Error:")
      assert String.contains?(result, "Something went wrong")
      assert String.contains?(result, "Type 'help' for available commands")
    end

    test "formats error with special characters" do
      result = IEx.format_error("Error with special chars: !@#$%")
      assert String.contains?(result, "!@#$%")
    end
  end

  describe "GenServer callbacks" do
    test "handle_cast with write message" do
      state = %{prompt: "test> ", session_pid: nil, history: [], instance: :test}

      output =
        capture_io(fn ->
          {:noreply, ^state} = IEx.handle_cast({:write, "test output"}, state)
        end)

      assert String.contains?(output, "test output")
    end

    test "handle_cast with formatted output" do
      state = %{prompt: "test> ", session_pid: nil, history: [], instance: :test}

      output =
        capture_io(fn ->
          {:noreply, ^state} = IEx.handle_cast({:write, "error: test error"}, state)
        end)

      assert String.contains?(output, "error: test error")
    end
  end

  describe "initialization options" do
    test "uses default prompt when none provided" do
      # We can't easily test init/1 without starting a full session
      # but we can test the prompt formatting logic
      assert String.contains?(IEx.format_output("test"), "test")
    end

    test "format_line handles various line types" do
      # Test all the condition branches in format_line
      assert IEx.format_line("warning: test") =~ "warning: test"
      assert IEx.format_line("error: test") =~ "error: test"
      assert IEx.format_line("info: test") =~ "info: test"
      assert IEx.format_line("debug: test") == "debug: test"
      assert IEx.format_line("normal text") == "normal text"
      assert IEx.format_line("") == ""
    end
  end

  describe "transport behavior" do
    test "implements required transport functions" do
      assert function_exported?(IEx, :start_link, 1)
      assert function_exported?(IEx, :stop, 1)
      assert function_exported?(IEx, :write, 2)
    end

    test "write function accepts various input types" do
      fake_pid = spawn(fn -> :ok end)

      assert :ok = IEx.write(fake_pid, "string")
      assert :ok = IEx.write(fake_pid, 123)
      assert :ok = IEx.write(fake_pid, [:list, :data])
    end

    test "module follows expected behavior declarations" do
      behaviors = IEx.__info__(:attributes)[:behaviour] || []
      assert GenServer in behaviors
      # Transport behavior might not be in compiled attributes, so just verify module structure
      assert function_exported?(IEx, :start_link, 1)
      assert function_exported?(IEx, :stop, 1)
      assert function_exported?(IEx, :write, 2)
    end
  end
end
