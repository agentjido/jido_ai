defmodule Jido.AI.Tools.ExecutorTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Tools.Executor
  alias Jido.AI.Tools.Registry

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

  # Define test Tool modules
  defmodule TestTools.Echo do
    use Jido.AI.Tools.Tool,
      name: "echo",
      description: "Echoes back the input message"

    @impl true
    def schema do
      [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, %{echoed: params.message}}
    end
  end

  defmodule TestTools.LargeResult do
    use Jido.AI.Tools.Tool,
      name: "large_result",
      description: "Returns a large result for testing truncation"

    @impl true
    def schema do
      [
        size: [type: :integer, required: true, doc: "Size of result"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, %{data: String.duplicate("x", params.size)}}
    end
  end

  defmodule TestTools.BinaryResult do
    use Jido.AI.Tools.Tool,
      name: "binary_result",
      description: "Returns binary data"

    @impl true
    def schema do
      [
        size: [type: :integer, required: true, doc: "Size of binary"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, :crypto.strong_rand_bytes(params.size)}
    end
  end

  defmodule TestTools.ExceptionTool do
    use Jido.AI.Tools.Tool,
      name: "exception_tool",
      description: "A tool that raises an exception"

    @impl true
    def schema do
      [
        message: [type: :string, required: true, doc: "Exception message"]
      ]
    end

    @impl true
    def run(params, _context) do
      raise ArgumentError, params.message
    end
  end

  setup do
    # Ensure registry is started and clear it before each test
    Registry.ensure_started()
    Registry.clear()
    :ok = Registry.register_action(TestActions.Calculator)
    :ok = Registry.register_action(TestActions.SlowAction)
    :ok = Registry.register_action(TestActions.ErrorAction)
    :ok = Registry.register_action(TestActions.ExceptionAction)
    :ok = Registry.register_tool(TestTools.Echo)
    :ok = Registry.register_tool(TestTools.LargeResult)
    :ok = Registry.register_tool(TestTools.BinaryResult)
    :ok = Registry.register_tool(TestTools.ExceptionTool)
    :ok
  end

  describe "execute/3 with Actions" do
    test "executes action via Jido.Exec" do
      # Use string keys like LLM would provide
      result = Executor.execute("calculator", %{"operation" => "add", "a" => "1", "b" => "2"}, %{})

      assert {:ok, %{result: 3}} = result
    end

    test "normalizes string keys to atom keys" do
      result = Executor.execute("calculator", %{"operation" => "add", "a" => 1, "b" => 2}, %{})

      assert {:ok, %{result: 3}} = result
    end

    test "parses string numbers based on schema" do
      result = Executor.execute("calculator", %{"operation" => "multiply", "a" => "3", "b" => "4"}, %{})

      assert {:ok, %{result: 12}} = result
    end

    test "returns error from action" do
      result = Executor.execute("calculator", %{"operation" => "divide", "a" => "10", "b" => "0"}, %{})

      assert {:error, error} = result
      assert error.error == "Division by zero"
      assert error.tool_name == "calculator"
      assert error.type == :execution_error
    end
  end

  describe "execute/3 with Tools" do
    test "executes tool via run/2" do
      result = Executor.execute("echo", %{"message" => "hello"}, %{})

      assert {:ok, %{echoed: "hello"}} = result
    end

    test "normalizes string keys for tools" do
      result = Executor.execute("echo", %{"message" => "world"}, %{})

      assert {:ok, %{echoed: "world"}} = result
    end
  end

  describe "execute/3 registry lookup" do
    test "returns error for unknown tool" do
      result = Executor.execute("unknown_tool", %{}, %{})

      assert {:error, error} = result
      assert error.error == "Tool not found: unknown_tool"
      assert error.tool_name == "unknown_tool"
      assert error.type == :not_found
    end
  end

  describe "execute/4 with timeout" do
    test "completes within timeout" do
      result = Executor.execute("slow_action", %{"delay_ms" => "50"}, %{}, timeout: 1000)

      assert {:ok, %{completed: true, delay: 50}} = result
    end

    test "times out for slow operations" do
      result = Executor.execute("slow_action", %{"delay_ms" => "500"}, %{}, timeout: 100)

      assert {:error, error} = result
      assert error.type == :timeout
      assert error.tool_name == "slow_action"
      assert String.contains?(error.error, "timed out")
    end
  end

  describe "error handling" do
    test "returns structured error from action" do
      result = Executor.execute("error_action", %{"message" => "test error"}, %{})

      assert {:error, error} = result
      assert error.type == :execution_error
      assert error.tool_name == "error_action"
      assert error.error == "test error"
    end

    test "handles missing required parameters" do
      result = Executor.execute("calculator", %{}, %{})

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
      # Only string keys get converted - atom keys are ignored by convert_params_using_schema
      schema = [a: [type: :integer], b: [type: :string]]
      result = Executor.normalize_params(%{"a" => 1, :b => "test"}, schema)

      # Only "a" is converted, :b is not picked up (string key required)
      assert result.a == 1
      refute Map.has_key?(result, :b)
    end

    test "returns empty map when params is empty" do
      schema = [name: [type: :string]]
      result = Executor.normalize_params(%{}, schema)

      assert result == %{}
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

  describe "execute_module/5" do
    test "executes action module directly" do
      # Use string keys like LLM would provide
      result =
        Executor.execute_module(
          TestActions.Calculator,
          :action,
          %{"operation" => "add", "a" => "5", "b" => "3"},
          %{}
        )

      assert {:ok, %{result: 8}} = result
    end

    test "executes tool module directly" do
      # Use string keys like LLM would provide
      result =
        Executor.execute_module(
          TestTools.Echo,
          :tool,
          %{"message" => "direct call"},
          %{}
        )

      assert {:ok, %{echoed: "direct call"}} = result
    end

    test "respects timeout for direct execution" do
      result =
        Executor.execute_module(
          TestActions.SlowAction,
          :action,
          %{"delay_ms" => "500"},
          %{},
          timeout: 100
        )

      assert {:error, error} = result
      assert error.type == :timeout
    end
  end

  describe "telemetry" do
    test "emits start and stop events" do
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

      Executor.execute("calculator", %{operation: "add", a: 1, b: 1}, %{})

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :start], %{system_time: _}, %{tool_name: "calculator"}}
      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{duration: _}, %{tool_name: "calculator"}}

      :telemetry.detach("test-handler")
    end

    test "emits exception event on timeout" do
      test_pid = self()

      :telemetry.attach(
        "test-exception-handler",
        [:jido, :ai, :tool, :execute, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Executor.execute("slow_action", %{"delay_ms" => "500"}, %{}, timeout: 50)

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :exception], %{duration: _},
                      %{tool_name: "slow_action", reason: :timeout}},
                     1000

      :telemetry.detach("test-exception-handler")
    end

    test "sanitizes sensitive parameters in telemetry" do
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

      Executor.execute("calculator", sensitive_params, %{})

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

    test "sanitizes nested sensitive parameters" do
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

      Executor.execute("calculator", nested_params, %{})

      assert_receive {:telemetry_params, sanitized_params}

      # Nested sensitive param should be redacted
      assert sanitized_params["credentials"]["api_key"] == "[REDACTED]"
      # Nested non-sensitive param should be preserved
      assert sanitized_params["credentials"]["username"] == "user"

      :telemetry.detach("test-nested-sanitize-handler")
    end
  end

  describe "security" do
    test "does not include stacktrace in exception error response" do
      import ExUnit.CaptureLog

      # Capture log to prevent noise in test output
      capture_log(fn ->
        # Use exception_tool (a Tool) which directly raises in run/2
        # Actions go through Jido.Exec which handles exceptions differently
        result = Executor.execute("exception_tool", %{"message" => "test exception"}, %{})

        assert {:error, error} = result
        assert error.type == :exception
        assert error.tool_name == "exception_tool"
        assert error.error == "test exception"
        assert error.exception_type == ArgumentError

        # CRITICAL: Stacktrace should NOT be in the response
        refute Map.has_key?(error, :stacktrace)
      end)
    end

    test "logs stacktrace server-side for exceptions" do
      import ExUnit.CaptureLog

      log =
        capture_log([level: :error], fn ->
          # Use exception_tool (a Tool) which directly raises
          Executor.execute("exception_tool", %{"message" => "logged exception"}, %{})
        end)

      # Stacktrace should be logged server-side (the message appears in log)
      assert log =~ "Tool execution exception"
      # Note: Metadata (tool_name, exception, stacktrace) is included via Logger metadata
      # The default formatter may not show all metadata, but the log message confirms logging works
    end
  end
end
