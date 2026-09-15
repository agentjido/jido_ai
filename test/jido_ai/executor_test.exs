defmodule Jido.AI.TurnExecutionTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Turn
  alias ReqLLM.Message.ContentPart

  defp decode_tool_content(content) when is_binary(content), do: Jason.decode!(content)

  # Define test Action modules
  defmodule TestActions.Calculator do
    use Jido.Action,
      name: "calculator",
      description: "Performs arithmetic calculations",
      schema:
        Zoi.object(%{
          operation: Zoi.string(description: "The operation to perform"),
          a: Zoi.integer(description: "First operand"),
          b: Zoi.integer(description: "Second operand")
        })

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
      schema: Zoi.object(%{delay_ms: Zoi.integer(description: "How long to sleep")})

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
      schema: Zoi.object(%{message: Zoi.string(description: "Error message")})

    @impl true
    def run(params, _context) do
      {:error, params.message}
    end
  end

  defmodule TestActions.ExceptionAction do
    use Jido.Action,
      name: "exception_action",
      description: "An action that raises an exception",
      schema: Zoi.object(%{message: Zoi.string(description: "Exception message")})

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
      schema: Zoi.object(%{message: Zoi.string(description: "Message to echo")})

    @impl true
    def run(params, _context) do
      {:ok, %{echoed: params.message}}
    end
  end

  defmodule TestActions.LargeResult do
    use Jido.Action,
      name: "large_result",
      description: "Returns a large result for testing truncation",
      schema: Zoi.object(%{size: Zoi.integer(description: "Size of result")})

    @impl true
    def run(params, _context) do
      {:ok, %{data: String.duplicate("x", params.size)}}
    end
  end

  defmodule TestActions.BinaryResult do
    use Jido.Action,
      name: "binary_result",
      description: "Returns binary data",
      schema: Zoi.object(%{size: Zoi.integer(description: "Size of binary")})

    @impl true
    def run(params, _context) do
      {:ok, :crypto.strong_rand_bytes(params.size)}
    end
  end

  defmodule TestActions.ExceptionAction2 do
    use Jido.Action,
      name: "exception_action2",
      description: "An action that raises an exception for security tests",
      schema: Zoi.object(%{message: Zoi.string(description: "Exception message")})

    @impl true
    def run(params, _context) do
      raise ArgumentError, params.message
    end
  end

  setup do
    tools =
      Jido.AI.ToolAdapter.to_action_map([
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
      result =
        Jido.AI.Tools.Executor.execute("calculator", %{"operation" => "add", "a" => "1", "b" => "2"}, %{}, tools: tools)

      assert {:ok, %{result: 3}, []} = result
    end

    test "normalizes string keys to atom keys", %{tools: tools} do
      result =
        Jido.AI.Tools.Executor.execute("calculator", %{"operation" => "add", "a" => 1, "b" => 2}, %{}, tools: tools)

      assert {:ok, %{result: 3}, []} = result
    end

    test "parses string numbers based on schema", %{tools: tools} do
      result =
        Jido.AI.Tools.Executor.execute("calculator", %{"operation" => "multiply", "a" => "3", "b" => "4"}, %{},
          tools: tools
        )

      assert {:ok, %{result: 12}, []} = result
    end

    test "returns error from action", %{tools: tools} do
      result =
        Jido.AI.Tools.Executor.execute("calculator", %{"operation" => "divide", "a" => "10", "b" => "0"}, %{},
          tools: tools,
          timeout: 50
        )

      assert {:error, error, []} = result
      assert error.message == "Division by zero"
      assert error.details.tool_name == "calculator"
      assert error.type == :execution_error
    end
  end

  describe "execute/3 with Echo Action" do
    test "executes echo action", %{tools: tools} do
      result = Jido.AI.Tools.Executor.execute("echo", %{"message" => "hello"}, %{}, tools: tools)

      assert {:ok, %{echoed: "hello"}, []} = result
    end

    test "normalizes string keys for echo action", %{tools: tools} do
      result = Jido.AI.Tools.Executor.execute("echo", %{"message" => "world"}, %{}, tools: tools)

      assert {:ok, %{echoed: "world"}, []} = result
    end
  end

  describe "execute/3 registry lookup" do
    test "returns error for unknown tool" do
      result = Jido.AI.Tools.Executor.execute("unknown_tool", %{}, %{}, tools: %{})

      assert {:error, error, []} = result
      assert error.message == "Tool not found: unknown_tool"
      assert error.details.tool_name == "unknown_tool"
      assert error.type == :not_found
    end
  end

  describe "execute/4 with timeout" do
    test "completes within timeout", %{tools: tools} do
      result = Jido.AI.Tools.Executor.execute("slow_action", %{"delay_ms" => "20"}, %{}, tools: tools, timeout: 200)

      assert {:ok, %{completed: true, delay: 20}, []} = result
    end

    test "times out for slow operations", %{tools: tools} do
      result = Jido.AI.Tools.Executor.execute("slow_action", %{"delay_ms" => "120"}, %{}, tools: tools, timeout: 30)

      assert {:error, error, []} = result
      assert error.type == :timeout
      assert error.details.tool_name == "slow_action"
      assert String.contains?(error.message, "timed out")
    end
  end

  describe "error handling" do
    test "returns structured error from action", %{tools: tools} do
      result =
        Jido.AI.Tools.Executor.execute("error_action", %{"message" => "test error"}, %{}, tools: tools, timeout: 50)

      assert {:error, error, []} = result
      assert error.type == :execution_error
      assert error.details.tool_name == "error_action"
      assert error.message == "test error"
    end

    test "handles missing required parameters", %{tools: tools} do
      result = Jido.AI.Tools.Executor.execute("calculator", %{}, %{}, tools: tools)

      assert {:error, error, []} = result
      assert error.type == :validation_error
      assert error.details.tool_name == "calculator"
      # Error message should mention missing required option
      assert String.contains?(error.message, "required")
    end
  end

  describe "normalize_params/2" do
    test "converts string keys to atom keys" do
      schema = [a: [type: :integer], b: [type: :string]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"a" => 1, "b" => "hello"})

      assert result.a == 1
      assert result.b == "hello"
    end

    test "parses string integers" do
      schema = [count: [type: :integer]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"count" => "42"})

      assert result.count == 42
    end

    test "parses string floats" do
      schema = [value: [type: :float]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"value" => "3.14"})

      assert_in_delta result.value, 3.14, 0.001
    end

    test "handles mixed string and atom keys" do
      # jido_action v2.0.0-rc.2+ supports both string and atom keys
      schema = [a: [type: :integer], b: [type: :string]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"a" => 1, :b => "test"})

      assert result.a == 1
      assert result.b == "test"
    end

    test "returns empty map when params is empty" do
      schema = [name: [type: :string]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{})

      assert result == %{}
    end

    test "coerces integer to float when schema expects float" do
      schema = [value: [type: :float], amount: [type: :float]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"value" => 20, "amount" => 3})

      assert result.value == 20.0
      assert result.amount == 3.0
      assert is_float(result.value)
      assert is_float(result.amount)
    end

    test "preserves float values when schema expects float" do
      schema = [value: [type: :float]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"value" => 20.5})

      assert result.value == 20.5
      assert is_float(result.value)
    end

    test "parses string to float and does not double-coerce" do
      schema = [value: [type: :float]]
      result = Jido.AI.SchemaInput.normalize_tool(schema, %{"value" => "20"})

      assert result.value == 20.0
      assert is_float(result.value)
    end

    test "normalizes nested numeric tool fields and list items before Action validation" do
      schema =
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(1),
          groups: Zoi.array(Zoi.object(%{ratio: Zoi.float(), count: Zoi.integer()})),
          label: Zoi.string()
        })

      input = %{"count" => "0", "groups" => [%{"ratio" => "1.5", "count" => "-2"}], "label" => "123"}
      expected = %{count: 0, groups: [%{ratio: 1.5, count: -2}], label: "123"}
      assert Jido.AI.SchemaInput.normalize_tool(schema, input) == expected
      assert {:ok, ^expected} = Zoi.parse(schema, expected)

      assert Jido.AI.SchemaInput.normalize_tool(schema, %{"groups" => [], "label" => "ok"}) == %{
               groups: [],
               label: "ok"
             }
    end

    for value <- ["4x", "1.5", "", nil, 2.5] do
      test "invalid integer #{inspect(value)} remains invalid" do
        schema = Zoi.object(%{count: Zoi.integer()})
        normalized = Jido.AI.SchemaInput.normalize_tool(schema, %{"count" => unquote(value)})
        assert normalized == %{count: unquote(value)}
        assert {:error, _} = Zoi.parse(schema, normalized)
      end
    end

    test "unknown keys and explicit atom keys retain their values" do
      schema = Zoi.object(%{count: Zoi.integer()})
      input = %{"count" => "3", :count => 7, "unknown_numeric_key_92841" => "5"}
      assert Jido.AI.SchemaInput.normalize_tool(schema, input) == %{"unknown_numeric_key_92841" => "5", count: 7}
      assert_raise ArgumentError, fn -> String.to_existing_atom("unknown_numeric_key_92841") end
    end

    test "numeric conversion does not change strict non-tool input validation" do
      schema = Zoi.object(%{count: Zoi.integer()})
      assert Jido.AI.SchemaInput.normalize(schema, %{"count" => "3"}) == %{count: "3"}
      assert {:error, _} = Zoi.parse(schema, %{count: "3"})
    end
  end

  describe "format_tool_result_content/1" do
    test "formats common success and error payloads" do
      assert decode_tool_content(Turn.format_tool_result_content({:ok, "hello"})) == %{
               "ok" => true,
               "result" => "hello"
             }

      assert decode_tool_content(Turn.format_tool_result_content({:ok, %{value: 1}})) == %{
               "ok" => true,
               "result" => %{"value" => 1}
             }

      assert decode_tool_content(Turn.format_tool_result_content({:ok, 42})) == %{
               "ok" => true,
               "result" => 42
             }

      assert decode_tool_content(Turn.format_tool_result_content({:error, %{message: "boom"}})) == %{
               "ok" => false,
               "error" => %{
                 "message" => "boom",
                 "type" => "execution_error",
                 "retryable?" => false,
                 "details" => %{}
               }
             }

      assert decode_tool_content(Turn.format_tool_result_content({:error, :badarg})) == %{
               "ok" => false,
               "error" => %{
                 "message" => "badarg",
                 "type" => "execution_error",
                 "retryable?" => false,
                 "details" => %{"reason" => "badarg"}
               }
             }
    end

    test "transport-sanitizes non-json-safe tool payloads" do
      decoded =
        Turn.format_tool_result_content(
          {:ok,
           %{
             password: "secret",
             tuple: {:ok, self()},
             callback: fn -> :ok end
           }}
        )
        |> decode_tool_content()

      assert decoded["ok"] == true
      assert decoded["result"]["password"] == "[REDACTED]"
      assert decoded["result"]["tuple"]["type"] == "tuple"
      assert decoded["result"]["tuple"]["size"] == 2
      assert decoded["result"]["callback"]["type"] == "function"
    end

    test "normalizes map content parts into multimodal tool content" do
      assert [
               %ContentPart{type: :text, text: encoded_payload},
               %ContentPart{type: :image_url, url: "https://example.com/chart.png"}
             ] =
               Turn.format_tool_result_content(
                 {:ok,
                  %{
                    "value" => 1,
                    "__content_parts__" => [
                      %{"type" => "image_url", "url" => "https://example.com/chart.png"}
                    ]
                  }}
               )

      assert Jason.decode!(encoded_payload) == %{
               "ok" => true,
               "result" => %{
                 "output" => %{"value" => 1},
                 "content" => [%{"type" => "image_url", "url" => "https://example.com/chart.png"}]
               }
             }
    end
  end

  describe "execute_module/4" do
    test "executes action module directly" do
      result =
        Jido.AI.Tools.Executor.execute_module(
          TestActions.Calculator,
          %{"operation" => "add", "a" => "5", "b" => "3"},
          %{}
        )

      assert {:ok, %{result: 8}, []} = result
    end

    test "executes echo action module directly" do
      result =
        Jido.AI.Tools.Executor.execute_module(
          TestActions.Echo,
          %{"message" => "direct call"},
          %{}
        )

      assert {:ok, %{echoed: "direct call"}, []} = result
    end

    test "respects timeout for direct execution" do
      result =
        Jido.AI.Tools.Executor.execute_module(
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

      Jido.AI.Tools.Executor.execute("calculator", %{operation: "add", a: 1, b: 1}, %{}, tools: tools)

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

      Jido.AI.Tools.Executor.execute("slow_action", %{"delay_ms" => "120"}, %{}, tools: tools, timeout: 20)

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

      Jido.AI.Tools.Executor.execute(
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

      Jido.AI.Tools.Executor.execute("calculator", sensitive_params, %{}, tools: tools)

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

      Jido.AI.Tools.Executor.execute("calculator", nested_params, %{}, tools: tools)

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
          Jido.AI.Tools.Executor.execute("exception_action2", %{"message" => "test exception"}, %{},
            tools: tools,
            timeout: 50
          )

        assert {:error, error, []} = result
        assert error.type == :execution_error
        assert error.details.tool_name == "exception_action2"

        refute Map.has_key?(error, :stacktrace)
      end)
    end

    test "logs exceptions server-side", %{tools: tools} do
      import ExUnit.CaptureLog

      log =
        capture_log([level: :error], fn ->
          Jido.AI.Tools.Executor.execute("exception_action2", %{"message" => "logged exception"}, %{},
            tools: tools,
            timeout: 50
          )
        end)

      assert log =~ "logged exception" or log =~ "ArgumentError"
    end
  end
end
