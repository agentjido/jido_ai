defmodule Kodo.Commands.KillTest do
  use ExUnit.Case, async: true

  alias Kodo.Commands.Kill

  describe "command metadata" do
    test "returns correct name" do
      assert Kill.name() == "kill"
    end

    test "returns description" do
      assert Kill.description() == "Terminate a job"
    end

    test "returns usage" do
      assert Kill.usage() == "kill [-SIGNAL] job_id"
    end

    test "returns meta" do
      assert Kill.meta() == [:builtin]
    end
  end

  describe "argument validation that fails before job manager" do
    test "handles missing job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute([], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result
    end

    test "handles invalid job ID format" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["invalid"], context)
      assert {:error, "Invalid job ID: invalid"} = result
    end

    test "handles job ID with trailing characters" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["123abc"], context)
      assert {:error, "Invalid job ID: 123abc"} = result
    end

    test "handles too many arguments" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["1", "2", "3"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result
    end

    test "handles empty string job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute([""], context)
      assert {:error, "Invalid job ID: "} = result
    end

    test "handles float job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["1.5"], context)
      assert {:error, "Invalid job ID: 1.5"} = result
    end

    test "handles hex job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["0x1"], context)
      assert {:error, "Invalid job ID: 0x1"} = result
    end

    test "handles scientific notation job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["1e10"], context)
      assert {:error, "Invalid job ID: 1e10"} = result
    end

    test "handles whitespace job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute([" "], context)
      assert {:error, "Invalid job ID:  "} = result
    end
  end

  describe "signal parsing validation" do
    test "handles signal without dash prefix" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["TERM"], context)
      assert {:error, "Invalid job ID: TERM"} = result
    end

    test "handles signal with invalid job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["-TERM", "invalid"], context)
      assert {:error, "Invalid job ID: invalid"} = result
    end

    test "handles signal with missing job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["-TERM"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result
    end

    test "handles signal with job ID with trailing characters" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["-KILL", "123abc"], context)
      assert {:error, "Invalid job ID: 123abc"} = result
    end

    test "handles signal with empty job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["-TERM", ""], context)
      assert {:error, "Invalid job ID: "} = result
    end

    test "handles signal with floating point job ID" do
      context = %{session_pid: self(), instance: :test}
      result = Kill.execute(["-INT", "12.34"], context)
      assert {:error, "Invalid job ID: 12.34"} = result
    end
  end

  describe "edge cases in Integer.parse" do
    test "validates Integer.parse edge cases that fail validation" do
      context = %{session_pid: self(), instance: :test}

      # These are cases where Integer.parse returns {int, remainder} with remainder != ""
      edge_cases = [
        # Number with letters -> {123, "abc"}
        "123abc",
        # Number with letters -> {42, "xyz"}  
        "42xyz",
        # Hex notation -> {0, "xFF"}
        "0xFF",
        # Decimal number -> {12, ".34"}
        "12.34",
        # Scientific notation -> {1, "e10"}
        "1e10",
        # Number with space -> {123, " 456"}
        "123 456",
        # Number with word -> {789, "hello"}
        "789hello",
        # Number with symbol -> {100, "%"}
        "100%",
        # Float notation -> {42, ".0"}
        "42.0",
        # Leading zeros with letters -> {7, "abc"}
        "007abc"
      ]

      for invalid_id <- edge_cases do
        result = Kill.execute([invalid_id], context)
        assert match?({:error, "Invalid job ID: " <> _}, result), "Failed for: #{invalid_id}"
      end
    end

    test "validates Integer.parse cases that return :error" do
      context = %{session_pid: self(), instance: :test}

      # These are cases where Integer.parse returns :error
      error_cases = [
        # Empty string
        "",
        # Just space
        " ",
        # Just letters
        "abc",
        # Word
        "hello",
        # Unicode infinity
        "∞",
        # Not a number
        "NaN",
        # Infinity string
        "Infinity",
        # Just sign
        "+",
        # Just decimal point
        ".",
        # Just exponent
        "e10",
        # Double signs
        "++123"
      ]

      for invalid_id <- error_cases do
        result = Kill.execute([invalid_id], context)
        assert match?({:error, "Invalid job ID: " <> _}, result), "Failed for: #{invalid_id}"
      end
    end
  end

  describe "signal parsing with edge cases" do
    test "validates signal parsing with various invalid job IDs" do
      context = %{session_pid: self(), instance: :test}

      signals = ["TERM", "KILL", "INT", "HUP", "QUIT", "USR1", "USR2", "UNKNOWN"]
      invalid_ids = ["abc", "123def", "", " ", "12.34"]

      for signal <- signals do
        for invalid_id <- invalid_ids do
          result = Kill.execute(["-#{signal}", invalid_id], context)

          assert match?({:error, "Invalid job ID: " <> _}, result),
                 "Failed for signal: #{signal}, job_id: #{invalid_id}"
        end
      end
    end

    test "validates usage errors with signals" do
      context = %{session_pid: self(), instance: :test}

      # Signal but no job ID
      result = Kill.execute(["-TERM"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result

      # Too many arguments with signal
      result = Kill.execute(["-KILL", "1", "2"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result

      # Multiple signals
      result = Kill.execute(["-TERM", "-KILL", "1"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result
    end
  end

  describe "argument count validation" do
    test "handles various invalid argument counts" do
      context = %{session_pid: self(), instance: :test}

      # No arguments
      result = Kill.execute([], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result

      # Too many arguments
      result = Kill.execute(["1", "2", "3", "4"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result

      # Even more arguments
      result = Kill.execute(["1", "2", "3", "4", "5"], context)
      assert {:error, "Usage: kill [-SIGNAL] job_id"} = result
    end
  end
end
