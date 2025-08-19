defmodule CoverageTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  test "Mix.Tasks.Kodo coverage" do
    # Test help
    output =
      capture_io(fn ->
        Mix.Tasks.Kodo.run(["--help"])
      end)

    assert output =~ "Usage: mix kodo"

    # Test version  
    output =
      capture_io(fn ->
        Mix.Tasks.Kodo.run(["--version"])
      end)

    assert output =~ "Kodo version"

    # Test direct functions
    output =
      capture_io(fn ->
        Mix.Tasks.Kodo.show_help()
      end)

    assert output =~ "Usage: mix kodo"

    output =
      capture_io(fn ->
        Mix.Tasks.Kodo.show_version()
      end)

    assert output =~ "Kodo version"
  end

  test "Kodo.Transports.IEx coverage" do
    # Test handle_cast
    output =
      capture_io(fn ->
        state = %{}
        {:noreply, _} = Kodo.Transports.IEx.handle_cast({:write, "test"}, state)
      end)

    assert output =~ "test"

    # Test handle_input variants
    result = Kodo.Transports.IEx.handle_input("", %{history: []})
    assert {:ok, _} = result

    output =
      capture_io(fn ->
        result = Kodo.Transports.IEx.handle_input("exit", %{})
        assert {:stop, :normal} = result
      end)

    assert output =~ "Exiting"

    output =
      capture_io(fn ->
        result = Kodo.Transports.IEx.handle_input(:eof, %{})
        assert {:stop, :normal} = result
      end)

    assert output =~ "EOF"

    # Test formatting functions
    result = Kodo.Transports.IEx.format_output("test\nwarning: warn\nerror: err")
    assert result =~ "test"
    assert result =~ "warning: warn"
    assert result =~ "error: err"

    result = Kodo.Transports.IEx.format_output(:atom)
    assert result == ":atom"

    result = Kodo.Transports.IEx.format_line("warning: test")
    assert result =~ "warning: test"

    result = Kodo.Transports.IEx.format_line("error: test")
    assert result =~ "error: test"

    result = Kodo.Transports.IEx.format_line("info: test")
    assert result =~ "info: test"

    result = Kodo.Transports.IEx.format_line("normal")
    assert result == "normal"

    result = Kodo.Transports.IEx.format_error("test error")
    assert result =~ "Error:"
    assert result =~ "test error"
    assert result =~ "help"
  end
end
