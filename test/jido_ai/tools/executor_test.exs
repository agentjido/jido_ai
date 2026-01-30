defmodule Jido.AI.Tools.ExecutorTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Tools.Executor

  # Define test Action modules
  defmodule TestActions.Calculator do
    use Jido.Action,
      name: "calculator",
      description: "Performs arithmetic calculations",
      schema: [
        operation: [type: :string, required: true, doc: "The operation to perform"],
        a: [type: :integer, required: true, doc: "First operand"],
        b: [type: :integer, required: true, doc: "Second operand"]
      ]

    @impl true
    def run(params, _context) do
      case params.operation do
        "add" -> {:ok, %{result: params.a + params.b}}
        "subtract" -> {:ok, %{result: params.a - params.b}}
        "multiply" -> {:ok, %{result: params.a * params.b}}
        "divide" when params.b != 0 -> {:ok, %{result: div(params.a, params.b)}}
        "divide" -> {:error, "Division by zero"}
        _ -> {:error, "Unknown operation: #{params.operation}"}
      end
    end
  end

  defmodule TestActions.SlowAction do
    use Jido.Action,
      name: "slow_action",
      description: "A slow action for testing timeouts",
      schema: [
        delay_ms: [type: :integer, required: true, doc: "How long to sleep"]
      ]

    @impl true
    def run(params, _context) do
      Process.sleep(params.delay_ms)
      {:ok, %{completed: true, delay: params.delay_ms}}
    end
  end

  defmodule TestActions.ErrorAction do
    use Jido.Action,
      name: "error_action",
      description: "An action that returns an error",
      schema: [
        message: [type: :string, required: true, doc: "Error message"]
      ]

    @impl true
    def run(params, _context) do
      {:error, params.message}
    end
  end

  defmodule TestActions.ExceptionAction do
    use Jido.Action,
      name: "exception_action",
      description: "An action that raises an exception",
      schema: [
        message: [type: :string, required: true, doc: "Exception message"]
      ]

    @impl true
    def run(params, _context) do
      raise ArgumentError, params.message
    end
  end

  # Additional test Action modules
  defmodule TestActions.Echo do
    use Jido.Action,
      name: "echo",
      description: "Echoes back the input message",
      schema: [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{echoed: params.message}}
    end
  end

  defmodule TestActions.LargeResult do
    use Jido.Action,
      name: "large_result",
      description: "Returns a large result for testing truncation",
      schema: [
        size: [type: :integer, required: true, doc: "Size of result"]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{data: String.duplicate("x", params.size)}}
    end
  end

  defmodule TestActions.BinaryResult do
    use Jido.Action,
      name: "binary_result",
      description: "Returns binary data",
      schema: [
        size: [type: :integer, required: true, doc: "Size of binary"]
      ]

    @impl true
    def run(params, _context) do
      {:ok, :crypto.strong_rand_bytes(params.size)}
    end
  end

  defmodule TestActions.ExceptionAction2 do
    use Jido.Action,
      name: "exception_action2",
      description: "An action that raises an exception for security tests",
      schema: [
        message: [type: :string, required: true, doc: "Exception message"]
      ]

    @impl true
    def run(params, _context) do
      raise ArgumentError, params.message
    end
  end

  setup do
    tools = Executor.build_tools_map([
      TestActions.Calculator,
      TestActions.SlowAction,
      TestActions.ErrorAction,
      TestActions.ExceptionAction,
      TestActions.Echo,
      TestActions.LargeResult,
      TestActions.BinaryResult,
      TestActions.ExceptionAction2
    ])

    {:ok, tools: tools}
  end

  describe "execute/3 with Actions" do
    test "executes action via Jido.Exec", %{tools: tools} do
      # Use string keys like LLM would provide
      result = Executor.execute("calculator", %{"operation" => "add", "a" => "1", "b" => "2"}, %{}, tools: tools)

      assert {:ok, %{result: 3}} = result
    end

    test "normalizes string keys to atom keys", %{tools: tools} do
      result = Executor.execute("calculator", %{"operation" => "add", "a" => 1, "b" => 2}, %{}, tools: tools)

      assert {:ok, %{result: 3}} = result
    end

    test "parses string numbers based on schema", %{tools: tools} do
      result = Executor.execute("calculator", %{"operation" => "multiply", "a" => "3", "b" => "4"}, %{}, tools: tools)

      assert {:ok, %{result: 12}} = result
    end

    test "returns error from action", %{tools: tools} do
      result = Executor.execute("calculator", %{"operation" => "divide", "a" => "10", "b" => "0"}, %{}, tools: tools)

      assert {:error, error} = result
      assert error.error == "Division by zero"
      assert error.tool_name == "calculator"
      assert error.type == :execution_error
    end
  end

  describe "execute/3 with Echo Action" do
    test "executes echo action", %{tools: tools} do
      result = Executor.execute("echo", %{"message" => "hello"}, %{}, tools: tools)

      assert {:ok, %{echoed: "hello"}} = result
    end

    test "normalizes string keys for echo action", %{tools: tools} do
      result = Executor.execute("echo", %{"message" => "world"}, %{}, tools: tools)

      assert {:ok, %{echoed: "world"}} = result
    end
  end

  describe "execute/3 registry lookup" do
    test "returns error for unknown tool" do
      result = Executor.execute("unknown_tool", %{}, %{}, tools: %{})

      assert {:error, error} = result
      assert error.error == "Tool not found: unknown_tool"
      assert error.tool_name == "unknown_tool"
      assert error.type == :not_found
    end
  end

  describe "execute/4 with timeout" do
    test "completes within timeout", %{tools: tools} do
      result = Executor.execute("slow_action", %{"delay_ms" => "50"}, %{}, tools: tools, timeout: 1000)

      assert {:ok, %{completed: true, delay: 50}} = result
    end

    test "times out for slow operations", %{tools: tools} do
      result = Executor.execute("slow_action", %{"delay_ms" => "500"}, %{}, tools: tools, timeout: 100)

      assert {:error, error} = result
      assert error.type == :timeout
      assert error.tool_name == "slow_action"
      assert String.contains?(error.error, "timed out")
    end
  end

  describe "error handling" do
    test "returns structured error from action", %{tools: tools} do
      result = Executor.execute("error_action", %{"message" => "test error"}, %{}, tools: tools)

      assert {:error, error} = result
      assert error.type == :execution_error
      assert error.tool_name == "error_action"
      assert error.error == "test error"
    end

    test "handles missing required parameters", %{tools: tools} do
      result = Executor.execute("calculator", %{}, %{}, tools: tools)

      assert {:error, error} = result
      assert error.type == :execution_error
      assert error.tool_name == "calculator"
      # Error message should mention missing required option
      assert String.contains?(error.error, "required")
    end
  end

  describe "normalize_params/2" do
    test "converts string keys to atom keys" do
      schema = [a: [type: :integer], b: [type: :string]]
      result = Executor.normalize_params(%{"a" => 1, "b" => "hello"}, schema)

      assert result.a == 1
      assert result.b == "hello"
    end

    test "parses string integers" do
      schema = [count: [type: :integer]]
      result = Executor.normalize_params(%{"count" => "42"}, schema)

      assert result.count == 42
    end

    test "parses string floats" do
      schema = [value: [type: :float]]
      result = Executor.normalize_params(%{"value" => "3.14"}, schema)

      assert_in_delta result.value, 3.14, 0.001
    end

    test "handles mixed string and atom keys" do
      # jido_action v2.0.0-rc.2+ supports both string and atom keys
      schema = [a: [type: :integer], b: [type: :string]]
      result = Executor.normalize_params(%{"a" => 1, :b => "test"}, schema)

      assert result.a == 1
      assert result.b == "test"
    end

    test "returns empty map when params is empty" do
      schema = [name: [type: :string]]
      result = Executor.normalize_params(%{}, schema)

      assert result == %{}
    end

    test "coerces integer to float when schema expects float" do
      schema = [value: [type: :float], amount: [type: :float]]
      result = Executor.normalize_params(%{"value" => 20, "amount" => 3}, schema)

      assert result.value == 20.0
      assert result.amount == 3.0
      assert is_float(result.value)
      assert is_float(result.amount)
    end

    test "preserves float values when schema expects float" do
      schema = [value: [type: :float]]
      result = Executor.normalize_params(%{"value" => 20.5}, schema)

      assert result.value == 20.5
      assert is_float(result.value)
    end

    test "parses string to float and does not double-coerce" do
      schema = [value: [type: :float]]
      result = Executor.normalize_params(%{"value" => "20"}, schema)

      assert result.value == 20.0
      assert is_float(result.value)
    end
  end

  describe "format_result/1" do
    test "returns simple strings as-is" do
      assert Executor.format_result("hello") == "hello"
    end

    test "returns small maps as-is" do
      result = %{a: 1, b: 2}
      assert Executor.format_result(result) == result
    end

    test "returns primitives as-is" do
      assert Executor.format_result(42) == 42
      assert Executor.format_result(true) == true
      assert Executor.format_result(nil) == nil
    end

    test "truncates large strings" do
      large_string = String.duplicate("x", 15_000)
      result = Executor.format_result(large_string)

      assert is_binary(result)
      assert String.contains?(result, "[truncated")
      assert byte_size(result) < 15_000
    end

    test "truncates large maps" do
      large_map = %{data: String.duplicate("x", 15_000)}
      result = Executor.format_result(large_map)

      assert result.truncated == true
      assert is_integer(result.size_bytes)
      assert is_list(result.keys)
    end

    test "truncates large lists" do
      large_list = Enum.to_list(1..1000)
      result = Executor.format_result(large_list)

      # This list is small enough to not be truncated (JSON is small)
      assert is_list(result)
    end

    test "handles binary data with base64 for small binaries" do
      # Use a binary with invalid UTF-8 sequence (0xFF is not valid in UTF-8)
      binary = <<0xFF, 0xFE, 0x00, 0x01>>
      result = Executor.format_result(binary)

      assert result.type == :binary
      assert result.encoding == :base64
      assert result.data == Base.encode64(binary)
      assert result.size_bytes == 4
    end

    test "describes large binary data" do
      # Use a binary with invalid UTF-8 to ensure it's treated as binary
      # Binary must be larger than max_result_size * 0.75 (7500 bytes) to get description
      binary = <<0xFF>> <> :crypto.strong_rand_bytes(7999)
      result = Executor.format_result(binary)

      assert result.type == :binary
      assert result.encoding == :description
      assert result.size_bytes == 8000
      assert String.contains?(result.message, "8000 bytes")
    end
  end

  describe "execute_module/4" do
    test "executes action module directly" do
      result =
        Executor.execute_module(
          TestActions.Calculator,
          %{"operation" => "add", "a" => "5", "b" => "3"},
          %{}
        )

      assert {:ok, %{result: 8}} = result
    end

    test "executes echo action module directly" do
      result =
        Executor.execute_module(
          TestActions.Echo,
          %{"message" => "direct call"},
          %{}
        )

      assert {:ok, %{echoed: "direct call"}} = result
    end

    test "respects timeout for direct execution" do
      result =
        Executor.execute_module(
          TestActions.SlowAction,
          %{"delay_ms" => "500"},
          %{},
          timeout: 100
        )

      assert {:error, error} = result
      assert error.type == :timeout
    end
  end

  describe "telemetry" do
    test "emits start and stop events", %{tools: tools} do
      test_pid = self()

      :telemetry.attach_many(
        "test-handler",
        [
          [:jido, :ai, :tool, :execute, :start],
          [:jido, :ai, :tool, :execute, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Executor.execute("calculator", %{operation: "add", a: 1, b: 1}, %{}, tools: tools)

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :start], %{system_time: _}, %{tool_name: "calculator"}}
      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{duration: _}, %{tool_name: "calculator"}}

      :telemetry.detach("test-handler")
    end

    test "emits exception event on timeout", %{tools: tools} do
      test_pid = self()

      :telemetry.attach(
        "test-exception-handler",
        [:jido, :ai, :tool, :execute, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Executor.execute("slow_action", %{"delay_ms" => "500"}, %{}, tools: tools, timeout: 50)

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :exception], %{duration: _},
                      %{tool_name: "slow_action", reason: :timeout}},
                     1000

      :telemetry.detach("test-exception-handler")
    end

    test "sanitizes sensitive parameters in telemetry", %{tools: tools} do
      test_pid = self()

      :telemetry.attach(
        "test-sanitize-handler",
        [:jido, :ai, :tool, :execute, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_params, metadata.params})
        end,
        nil
      )

      # Execute with sensitive parameters
      sensitive_params = %{
        "operation" => "add",
        "a" => "1",
        "b" => "2",
        "api_key" => "secret-key-12345",
        "password" => "my-password",
        "token" => "bearer-token",
        "secret_value" => "shhh"
      }

      Executor.execute("calculator", sensitive_params, %{}, tools: tools)

      assert_receive {:telemetry_params, sanitized_params}

      # Non-sensitive params should be preserved
      assert sanitized_params["operation"] == "add"
      assert sanitized_params["a"] == "1"
      assert sanitized_params["b"] == "2"

      # Sensitive params should be redacted
      assert sanitized_params["api_key"] == "[REDACTED]"
      assert sanitized_params["password"] == "[REDACTED]"
      assert sanitized_params["token"] == "[REDACTED]"
      assert sanitized_params["secret_value"] == "[REDACTED]"

      :telemetry.detach("test-sanitize-handler")
    end

    test "sanitizes nested sensitive parameters", %{tools: tools} do
      test_pid = self()

      :telemetry.attach(
        "test-nested-sanitize-handler",
        [:jido, :ai, :tool, :execute, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_params, metadata.params})
        end,
        nil
      )

      nested_params = %{
        "operation" => "add",
        "a" => "1",
        "b" => "2",
        "credentials" => %{
          "api_key" => "nested-secret",
          "username" => "user"
        }
      }

      Executor.execute("calculator", nested_params, %{}, tools: tools)

      assert_receive {:telemetry_params, sanitized_params}

      # Nested sensitive param should be redacted
      assert sanitized_params["credentials"]["api_key"] == "[REDACTED]"
      # Nested non-sensitive param should be preserved
      assert sanitized_params["credentials"]["username"] == "user"

      :telemetry.detach("test-nested-sanitize-handler")
    end
  end

  describe "security" do
    test "does not include stacktrace in exception error response", %{tools: tools} do
      import ExUnit.CaptureLog

      capture_log(fn ->
        result = Executor.execute("exception_action2", %{"message" => "test exception"}, %{}, tools: tools)

        assert {:error, error} = result
        assert error.type == :execution_error
        assert error.tool_name == "exception_action2"

        refute Map.has_key?(error, :stacktrace)
      end)
    end

    test "logs exceptions server-side", %{tools: tools} do
      import ExUnit.CaptureLog

      log =
        capture_log([level: :error], fn ->
          Executor.execute("exception_action2", %{"message" => "logged exception"}, %{}, tools: tools)
        end)

      assert log =~ "logged exception" or log =~ "ArgumentError"
    end
  end
end
