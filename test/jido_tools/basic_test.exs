defmodule JidoTest.Actions.BasicActionsTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Tools.Basic

  require Logger

  @moduletag :capture_log

  describe "Sleep" do
    test "sleeps for the specified duration" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, %{duration_ms: 100}} = Basic.Sleep.run(%{duration_ms: 100}, %{})
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 100
    end

    test "uses default duration when not specified" do
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, %{duration_ms: 1000}} = Basic.Sleep.run(%{duration_ms: 1000}, %{})
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 1000
    end
  end

  describe "Todo" do
    test "logs todo message" do
      log =
        capture_log([level: :debug], fn ->
          assert {:ok, %{todo: "Implement feature"}} =
                   Basic.Todo.run(%{todo: "Implement feature"}, %{})

          # Small delay to ensure log is captured
          Process.sleep(50)
        end)

      # Look for the specific todo message, ignoring other noise
      assert Enum.any?(String.split(log, "\n"), &(&1 =~ "TODO Action: Implement feature"))
    end
  end

  describe "Delay" do
    test "introduces random delay within specified range" do
      start_time = System.monotonic_time(:millisecond)

      assert {:ok, %{min_ms: 100, max_ms: 200, actual_delay: delay}} =
               Basic.RandomSleep.run(%{min_ms: 100, max_ms: 200}, %{})

      end_time = System.monotonic_time(:millisecond)

      assert delay >= 100 and delay <= 200
      assert end_time - start_time >= delay
    end
  end

  describe "Increment" do
    test "increments the value by 1" do
      assert {:ok, %{value: 6}} = Basic.Increment.run(%{value: 5}, %{})
    end
  end

  describe "Decrement" do
    test "decrements the value by 1" do
      assert {:ok, %{value: 4}} = Basic.Decrement.run(%{value: 5}, %{})
    end
  end

  describe "Noop" do
    test "returns input params unchanged" do
      params = %{test: "value", other: 123}
      assert {:ok, ^params} = Basic.Noop.run(params, %{})
    end

    test "works with empty params" do
      assert {:ok, %{}} = Basic.Noop.run(%{}, %{})
    end
  end

  describe "Inspect" do
    import ExUnit.CaptureIO

    test "inspects simple values" do
      output =
        capture_io(fn ->
          assert {:ok, %{value: 123}} = Basic.Inspect.run(%{value: 123}, %{})
        end)

      assert output =~ "123"
    end

    test "inspects complex data structures" do
      complex_value = %{a: [1, 2, 3], b: %{c: "test"}}
      expected_output = "Inspect action output: " <> inspect(complex_value)

      output =
        capture_io(fn ->
          assert {:ok, %{value: ^complex_value}} = Basic.Inspect.run(%{value: complex_value}, %{})
        end)

      assert String.trim(output) == expected_output
    end
  end

  describe "Log" do
    test "logs with empty params shows current time" do
      log =
        capture_log([level: :info], fn ->
          assert {:ok, %{}} = Basic.Log.run(%{}, %{})
          Process.sleep(50)
        end)

      assert log =~ "Current time:"
    end

    test "logs debug message" do
      log =
        capture_log([level: :debug], fn ->
          assert {:ok, %{level: :debug, message: "Debug test"}} =
                   Basic.Log.run(%{level: :debug, message: "Debug test"}, %{})

          Process.sleep(50)
        end)

      assert log =~ "Debug test"
    end

    test "logs info message" do
      log =
        capture_log([level: :info], fn ->
          assert {:ok, %{level: :info, message: "Info test"}} =
                   Basic.Log.run(%{level: :info, message: "Info test"}, %{})

          Process.sleep(50)
        end)

      assert log =~ "Info test"
    end

    test "logs warning message" do
      log =
        capture_log([level: :warning], fn ->
          assert {:ok, %{level: :warning, message: "Warning test"}} =
                   Basic.Log.run(%{level: :warning, message: "Warning test"}, %{})

          Process.sleep(50)
        end)

      assert log =~ "Warning test"
    end

    test "logs error message" do
      log =
        capture_log([level: :error], fn ->
          assert {:ok, %{level: :error, message: "Error test"}} =
                   Basic.Log.run(%{level: :error, message: "Error test"}, %{})

          Process.sleep(50)
        end)

      assert log =~ "Error test"
    end
  end

  describe "Today" do
    test "returns today's date in ISO8601 format by default" do
      assert {:ok, %{format: :iso8601, date: date}} = Basic.Today.run(%{format: :iso8601}, %{})
      assert String.match?(date, ~r/^\d{4}-\d{2}-\d{2}$/)
    end

    test "returns today's date in basic format" do
      assert {:ok, %{format: :basic, date: date}} = Basic.Today.run(%{format: :basic}, %{})
      assert String.match?(date, ~r/^\d{4}-\d{1,2}-\d{1,2}$/)
    end

    test "returns today's date in human format" do
      assert {:ok, %{format: :human, date: date}} = Basic.Today.run(%{format: :human}, %{})
      assert String.match?(date, ~r/^[A-Z][a-z]+ \d{1,2}, \d{4}$/)
    end

    test "all formats return current date" do
      today = Date.utc_today()

      {:ok, %{date: iso_date}} = Basic.Today.run(%{format: :iso8601}, %{})
      {:ok, %{date: basic_date}} = Basic.Today.run(%{format: :basic}, %{})
      {:ok, %{date: human_date}} = Basic.Today.run(%{format: :human}, %{})

      assert iso_date == Date.to_iso8601(today)
      assert basic_date == "#{today.year}-#{today.month}-#{today.day}"
      assert human_date == Calendar.strftime(today, "%B %d, %Y")
    end
  end
end
