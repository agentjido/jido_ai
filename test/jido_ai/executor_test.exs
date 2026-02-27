defmodule Jido.AI.TurnExecutionTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Turn

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
    tools =
      Turn.build_tools_map([
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
      result = Turn.execute("calculator", %{"operation" => "add", "a" => "1", "b" => "2"}, %{}, tools: tools)

      assert {:ok, %{result: 3}, []} = result
    end

    test "normalizes string keys to atom keys", %{tools: tools} do
      result = Turn.execute("calculator", %{"operation" => "add", "a" => 1, "b" => 2}, %{}, tools: tools)

      assert {:ok, %{result: 3}, []} = result
    end

    test "parses string numbers based on schema", %{tools: tools} do
      result = Turn.execute("calculator", %{"operation" => "multiply", "a" => "3", "b" => "4"}, %{}, tools: tools)

      assert {:ok, %{result: 12}, []} = result
    end

    test "returns error from action", %{tools: tools} do
      result =
        Turn.execute("calculator", %{"operation" => "divide", "a" => "10", "b" => "0"}, %{},
          tools: tools,
          timeout: 50
        )

      assert {:error, error, []} = result
      assert error.error == "Division by zero"
      assert error.tool_name == "calculator"
      assert error.type == :execution_error
    end
  end

  describe "execute/3 with Echo Action" do
    test "executes echo action", %{tools: tools} do
      result = Turn.execute("echo", %{"message" => "hello"}, %{}, tools: tools)

      assert {:ok, %{echoed: "hello"}, []} = result
    end

    test "normalizes string keys for echo action", %{tools: tools} do
      result = Turn.execute("echo", %{"message" => "world"}, %{}, tools: tools)

      assert {:ok, %{echoed: "world"}, []} = result
    end
  end

  describe "execute/3 registry lookup" do
    test "returns error for unknown tool" do
      result = Turn.execute("unknown_tool", %{}, %{}, tools: %{})

      assert {:error, error, []} = result
      assert error.error == "Tool not found: unknown_tool"
      assert error.tool_name == "unknown_tool"
      assert error.type == :not_found
    end
  end

  describe "execute/4 with timeout" do
    test "completes within timeout", %{tools: tools} do
      result = Turn.execute("slow_action", %{"delay_ms" => "20"}, %{}, tools: tools, timeout: 200)

      assert {:ok, %{completed: true, delay: 20}, []} = result
    end

    test "times out for slow operations", %{tools: tools} do
      result = Turn.execute("slow_action", %{"delay_ms" => "120"}, %{}, tools: tools, timeout: 30)

      assert {:error, error, []} = result
      assert error.type == :timeout
      assert error.tool_name == "slow_action"
      assert String.contains?(error.error, "timed out")
    end
  end

  describe "error handling" do
    test "returns structured error from action", %{tools: tools} do
      result = Turn.execute("error_action", %{"message" => "test error"}, %{}, tools: tools, timeout: 50)

      assert {:error, error, []} = result
      assert error.type == :execution_error
      assert error.tool_name == "error_action"
      assert error.error == "test error"
    end

    test "handles missing required parameters", %{tools: tools} do
      result = Turn.execute("calculator", %{}, %{}, tools: tools)

      assert {:error, error, []} = result
      assert error.type == :execution_error
      assert error.tool_name == "calculator"
      # Error message should mention missing required option
      assert String.contains?(error.error, "required")
    end
  end

  describe "normalize_params/2" do
    test "converts string keys to atom keys" do
      schema = [a: [type: :integer], b: [type: :string]]
      result = Turn.normalize_params(%{"a" => 1, "b" => "hello"}, schema)

      assert result.a == 1
      assert result.b == "hello"
    end

    test "parses string integers" do
      schema = [count: [type: :integer]]
      result = Turn.normalize_params(%{"count" => "42"}, schema)

      assert result.count == 42
    end

    test "parses string floats" do
      schema = [value: [type: :float]]
      result = Turn.normalize_params(%{"value" => "3.14"}, schema)

      assert_in_delta result.value, 3.14, 0.001
    end

    test "handles mixed string and atom keys" do
      # jido_action v2.0.0-rc.2+ supports both string and atom keys
      schema = [a: [type: :integer], b: [type: :string]]
      result = Turn.normalize_params(%{"a" => 1, :b => "test"}, schema)

      assert result.a == 1
      assert result.b == "test"
    end

    test "returns empty map when params is empty" do
      schema = [name: [type: :string]]
      result = Turn.normalize_params(%{}, schema)

      assert result == %{}
    end

    test "coerces integer to float when schema expects float" do
      schema = [value: [type: :float], amount: [type: :float]]
      result = Turn.normalize_params(%{"value" => 20, "amount" => 3}, schema)

      assert result.value == 20.0
      assert result.amount == 3.0
      assert is_float(result.value)
      assert is_float(result.amount)
    end

    test "preserves float values when schema expects float" do
      schema = [value: [type: :float]]
      result = Turn.normalize_params(%{"value" => 20.5}, schema)

      assert result.value == 20.5
      assert is_float(result.value)
    end

    test "parses string to float and does not double-coerce" do
      schema = [value: [type: :float]]
      result = Turn.normalize_params(%{"value" => "20"}, schema)

      assert result.value == 20.0
      assert is_float(result.value)
    end
  end

  describe "format_tool_result_content/1" do
    test "formats common success and error payloads" do
      assert Turn.format_tool_result_content({:ok, "hello"}) == "hello"
      assert Turn.format_tool_result_content({:ok, %{value: 1}}) == "{\"value\":1}"
      assert Turn.format_tool_result_content({:ok, 42}) == "42"
      assert Turn.format_tool_result_content({:error, %{message: "boom"}}) == "boom"
      assert Turn.format_tool_result_content({:error, :badarg}) == ":badarg"
    end
  end

  describe "execute_module/4" do
    test "executes action module directly" do
      result =
        Turn.execute_module(
          TestActions.Calculator,
          %{"operation" => "add", "a" => "5", "b" => "3"},
          %{}
        )

      assert {:ok, %{result: 8}, []} = result
    end

    test "executes echo action module directly" do
      result =
        Turn.execute_module(
          TestActions.Echo,
          %{"message" => "direct call"},
          %{}
        )

      assert {:ok, %{echoed: "direct call"}, []} = result
    end

    test "respects timeout for direct execution" do
      result =
        Turn.execute_module(
          TestActions.SlowAction,
          %{"delay_ms" => "120"},
          %{},
          timeout: 30
        )

      assert {:error, error, []} = result
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

      Turn.execute("calculator", %{operation: "add", a: 1, b: 1}, %{}, tools: tools)

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

      Turn.execute("slow_action", %{"delay_ms" => "120"}, %{}, tools: tools, timeout: 20)

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :exception], %{duration: _},
                      %{tool_name: "slow_action", reason: :timeout}},
                     1000

      :telemetry.detach("test-exception-handler")
    end

    test "includes request_id in telemetry metadata when provided", %{tools: tools} do
      test_pid = self()
      request_id = "req_telemetry_123"

      :telemetry.attach_many(
        "test-request-id-handler",
        [
          [:jido, :ai, :tool, :execute, :start],
          [:jido, :ai, :tool, :execute, :stop]
        ],
        fn event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, metadata})
        end,
        nil
      )

      Turn.execute(
        "calculator",
        %{"operation" => "add", "a" => "2", "b" => "3"},
        %{request_id: request_id},
        tools: tools
      )

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :start], %{request_id: ^request_id}}

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{request_id: ^request_id}}

      :telemetry.detach("test-request-id-handler")
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

      Turn.execute("calculator", sensitive_params, %{}, tools: tools)

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

      Turn.execute("calculator", nested_params, %{}, tools: tools)

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
        result =
          Turn.execute("exception_action2", %{"message" => "test exception"}, %{}, tools: tools, timeout: 50)

        assert {:error, error, []} = result
        assert error.type == :execution_error
        assert error.tool_name == "exception_action2"

        refute Map.has_key?(error, :stacktrace)
      end)
    end

    test "logs exceptions server-side", %{tools: tools} do
      import ExUnit.CaptureLog

      log =
        capture_log([level: :error], fn ->
          Turn.execute("exception_action2", %{"message" => "logged exception"}, %{}, tools: tools, timeout: 50)
        end)

      assert log =~ "logged exception" or log =~ "ArgumentError"
    end
  end
end
