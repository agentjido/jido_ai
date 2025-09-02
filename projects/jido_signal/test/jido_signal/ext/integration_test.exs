defmodule Jido.Signal.Ext.IntegrationTest do
  @moduledoc """
  Comprehensive integration tests for the Signal extension system.

  This test suite validates complex scenarios, extension operations,
  error handling, backward compatibility, and real-world usage patterns.
  """

  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Serialization.JsonSerializer

  # Real-world extension examples for testing
  defmodule ThreadExtension do
    @moduledoc "Extension for LLM conversation threading"
    use Jido.Signal.Ext,
      namespace: "thread",
      schema: [
        id: [type: :string, required: true],
        parent_id: [type: :string],
        depth: [type: :non_neg_integer, default: 0],
        model: [type: :string],
        tokens_used: [type: :non_neg_integer]
      ]
  end

  defmodule TraceExtension do
    @moduledoc "Extension for distributed tracing"
    use Jido.Signal.Ext,
      namespace: "trace",
      schema: [
        trace_id: [type: :string, required: true],
        span_id: [type: :string, required: true],
        parent_span_id: [type: :string],
        baggage: [type: :map, default: %{}]
      ]
  end

  defmodule SecurityExtension do
    @moduledoc "Extension for security/auth context"
    use Jido.Signal.Ext,
      namespace: "security",
      schema: [
        user_id: [type: :string, required: true],
        permissions: [type: {:list, :string}, default: []],
        roles: [type: {:list, :string}, default: []],
        session_id: [type: :string],
        expires_at: [type: :pos_integer]
      ]
  end

  defmodule MetricsExtension do
    @moduledoc "Extension for metrics and monitoring"
    use Jido.Signal.Ext,
      namespace: "metrics",
      schema: [
        labels: [type: :map, default: %{}],
        tags: [type: {:list, :string}, default: []],
        counters: [type: :map, default: %{}],
        gauges: [type: :map, default: %{}],
        histograms: [type: :map, default: %{}]
      ]
  end

  defmodule CustomSerializationExtension do
    @moduledoc "Extension with custom serialization logic"
    use Jido.Signal.Ext,
      namespace: "custom.serialization",
      schema: [
        data: [type: :map, required: true],
        format: [type: :string, default: "json"]
      ]

    @impl Jido.Signal.Ext
    def to_attrs(data) do
      # Custom serialization: encode data based on format
      case data.format do
        "base64" ->
          encoded_data =
            data.data
            |> Jason.encode!()
            |> Base.encode64()

          %{"encoded_data" => encoded_data, "format" => "base64"}

        _ ->
          %{"data" => data.data, "format" => data.format}
      end
    end

    @impl Jido.Signal.Ext
    def from_attrs(attrs) do
      case attrs do
        %{"encoded_data" => encoded, "format" => "base64"} ->
          decoded_data =
            encoded
            |> Base.decode64!()
            |> Jason.decode!()

          %{data: decoded_data, format: "base64"}

        %{"data" => data, "format" => format} ->
          %{data: data, format: format}

        _ ->
          attrs
      end
    end
  end

  describe "multiple extensions integration" do
    test "adding multiple extensions to signal works correctly" do
      # Create basic signal
      {:ok, signal} =
        Signal.new(
          "llm.conversation.message",
          %{message: "Hello, world!", role: "user"}
        )

      # Add thread extension
      {:ok, signal} =
        Signal.put_extension(signal, "thread", %{
          id: "thread-123",
          parent_id: "thread-parent-456",
          depth: 2,
          model: "gpt-4",
          tokens_used: 15
        })

      # Add trace extension
      {:ok, signal} =
        Signal.put_extension(signal, "trace", %{
          trace_id: "trace-abc123",
          span_id: "span-def456",
          parent_span_id: "span-parent-789",
          baggage: %{user_id: "user-123", session: "sess-456"}
        })

      # Add security extension
      {:ok, signal} =
        Signal.put_extension(signal, "security", %{
          user_id: "user-123",
          permissions: ["chat.send", "chat.read"],
          roles: ["user", "premium"],
          session_id: "sess-456",
          expires_at: 1_703_980_800
        })

      # Add metrics extension
      {:ok, signal} =
        Signal.put_extension(signal, "metrics", %{
          labels: %{environment: "production", region: "us-east-1"},
          tags: ["llm", "conversation", "user-message"],
          counters: %{messages_sent: 1},
          gauges: %{active_users: 42}
        })

      # Verify all extensions are present and correct
      thread_ext = Signal.get_extension(signal, "thread")
      assert thread_ext.id == "thread-123"
      assert thread_ext.depth == 2
      assert thread_ext.model == "gpt-4"

      trace_ext = Signal.get_extension(signal, "trace")
      assert trace_ext.trace_id == "trace-abc123"
      assert trace_ext.baggage.user_id == "user-123"

      security_ext = Signal.get_extension(signal, "security")
      assert security_ext.user_id == "user-123"
      assert "chat.send" in security_ext.permissions
      assert "premium" in security_ext.roles

      metrics_ext = Signal.get_extension(signal, "metrics")
      assert metrics_ext.labels.environment == "production"
      assert "llm" in metrics_ext.tags
      assert metrics_ext.counters.messages_sent == 1
    end

    test "extensions don't interfere with each other" do
      # Create signal
      {:ok, signal} =
        Signal.new(
          "test.multi.extension",
          %{test: true}
        )

      # Add extensions with similar data structures
      {:ok, signal} = Signal.put_extension(signal, "thread", %{id: "thread-123"})

      {:ok, signal} =
        Signal.put_extension(signal, "trace", %{trace_id: "trace-123", span_id: "span-123"})

      {:ok, signal} = Signal.put_extension(signal, "security", %{user_id: "user-123"})

      # Verify each extension maintains its own data
      thread_ext = Signal.get_extension(signal, "thread")
      trace_ext = Signal.get_extension(signal, "trace")
      security_ext = Signal.get_extension(signal, "security")

      assert thread_ext.id == "thread-123"
      assert trace_ext.trace_id == "trace-123"
      assert security_ext.user_id == "user-123"

      # Verify no cross-contamination
      refute Map.has_key?(thread_ext, :trace_id)
      refute Map.has_key?(trace_ext, :user_id)
      refute Map.has_key?(security_ext, :id)
    end

    test "extension API operations with multiple extensions" do
      {:ok, signal} =
        Signal.new(
          "test.extension.api",
          %{message: "test"}
        )

      # Add extensions
      {:ok, signal} = Signal.put_extension(signal, "thread", %{id: "thread-123"})

      {:ok, signal} =
        Signal.put_extension(signal, "trace", %{trace_id: "trace-123", span_id: "span-123"})

      # Test get_extension
      thread_data = Signal.get_extension(signal, "thread")
      assert thread_data.id == "thread-123"

      trace_data = Signal.get_extension(signal, "trace")
      assert trace_data.trace_id == "trace-123"

      # Test put_extension (updating existing)
      {:ok, updated_signal} =
        Signal.put_extension(signal, "thread", %{
          id: "thread-456",
          parent_id: "thread-123",
          depth: 1
        })

      # Verify thread updated but trace unchanged
      updated_thread = Signal.get_extension(updated_signal, "thread")
      assert updated_thread.id == "thread-456"
      assert updated_thread.depth == 1

      updated_trace = Signal.get_extension(updated_signal, "trace")
      assert updated_trace.trace_id == "trace-123"

      # Test adding new extension
      {:ok, final_signal} =
        Signal.put_extension(updated_signal, "security", %{
          user_id: "user-456"
        })

      # Verify all extensions present
      final_thread = Signal.get_extension(final_signal, "thread")
      final_trace = Signal.get_extension(final_signal, "trace")
      final_security = Signal.get_extension(final_signal, "security")

      assert final_thread.id == "thread-456"
      assert final_trace.trace_id == "trace-123"
      assert final_security.user_id == "user-456"

      # Test delete_extension
      no_trace_signal = Signal.delete_extension(final_signal, "trace")

      assert Signal.get_extension(no_trace_signal, "trace") == nil
      assert Signal.get_extension(no_trace_signal, "thread").id == "thread-456"
      assert Signal.get_extension(no_trace_signal, "security").user_id == "user-456"
    end
  end

  describe "extension data persistence" do
    test "signal with extensions maintains data correctly" do
      {:ok, signal} =
        Signal.new(
          "complex.persistence.test",
          %{
            message: "Complex data",
            nested: %{level: 1, items: [1, 2, 3]},
            timestamp: ~U[2023-12-20 15:30:00Z]
          }
        )

      # Add extensions
      {:ok, signal} =
        Signal.put_extension(signal, "thread", %{
          id: "thread-complex-123",
          depth: 3,
          model: "gpt-4-turbo"
        })

      {:ok, signal} =
        Signal.put_extension(signal, "trace", %{
          trace_id: "complex-trace-456",
          span_id: "complex-span-789",
          baggage: %{
            complex_key: "complex_value",
            nested: %{deep: "value"}
          }
        })

      {:ok, signal} =
        Signal.put_extension(signal, "metrics", %{
          labels: %{
            service: "signal-processor",
            version: "1.0.0"
          },
          counters: %{
            processed: 100,
            errors: 2
          },
          histograms: %{
            response_time: [10, 20, 15, 25, 30]
          }
        })

      # Verify core data
      assert signal.type == "complex.persistence.test"
      assert signal.data.message == "Complex data"
      assert signal.data.nested.level == 1
      assert signal.data.nested.items == [1, 2, 3]

      # Verify all extensions are correctly stored and accessible
      thread_ext = Signal.get_extension(signal, "thread")
      assert thread_ext.id == "thread-complex-123"
      assert thread_ext.depth == 3
      assert thread_ext.model == "gpt-4-turbo"

      trace_ext = Signal.get_extension(signal, "trace")
      assert trace_ext.trace_id == "complex-trace-456"
      assert trace_ext.baggage.complex_key == "complex_value"
      assert trace_ext.baggage.nested.deep == "value"

      metrics_ext = Signal.get_extension(signal, "metrics")
      assert metrics_ext.labels.service == "signal-processor"
      assert metrics_ext.counters.processed == 100
      assert metrics_ext.histograms.response_time == [10, 20, 15, 25, 30]

      # Verify extension list operations
      extension_list = Signal.list_extensions(signal)
      # list_extensions returns a list of {namespace, data} tuples
      extension_namespaces =
        case extension_list do
          # Handle list of tuples format
          list when is_list(list) and (is_list(list) and list != []) ->
            case List.first(list) do
              {_namespace, _data} ->
                Enum.map(list, fn {namespace, _data} -> namespace end)

              namespace when is_binary(namespace) ->
                list

              _ ->
                []
            end

          _ ->
            []
        end

      assert "thread" in extension_namespaces
      assert "trace" in extension_namespaces
      assert "metrics" in extension_namespaces
      assert length(extension_namespaces) == 3
    end

    test "extension data modifications persist correctly" do
      {:ok, signal} =
        Signal.new(
          "modification.test",
          %{message: "modification test", count: 42}
        )

      # Add extensions
      {:ok, signal} = Signal.put_extension(signal, "thread", %{id: "thread-mod-123"})

      {:ok, signal} =
        Signal.put_extension(signal, "security", %{
          user_id: "user-mod-456",
          permissions: ["read", "write"]
        })

      # Modify extension data
      {:ok, modified_signal} =
        Signal.put_extension(signal, "thread", %{
          id: "thread-mod-updated",
          depth: 1,
          model: "updated-model"
        })

      # Verify original signal unchanged
      original_thread = Signal.get_extension(signal, "thread")
      assert original_thread.id == "thread-mod-123"
      # depth has a default value of 0 from the schema
      assert original_thread.depth == 0

      # Verify modified signal has new data
      modified_thread = Signal.get_extension(modified_signal, "thread")
      assert modified_thread.id == "thread-mod-updated"
      assert modified_thread.depth == 1
      assert modified_thread.model == "updated-model"

      # Verify other extensions unchanged
      original_security = Signal.get_extension(signal, "security")
      modified_security = Signal.get_extension(modified_signal, "security")
      assert original_security.user_id == modified_security.user_id
      assert original_security.permissions == modified_security.permissions
    end
  end

  describe "error handling integration" do
    test "invalid extension data is handled properly" do
      # Create signal
      {:ok, signal} =
        Signal.new(
          "error.handling.test",
          %{message: "test"}
        )

      # Try to add invalid data for thread extension (missing required id)
      assert {:error, error} = Signal.put_extension(signal, "thread", %{depth: 2})
      assert error =~ "required :id option not found"

      # Try to add invalid data for trace extension (wrong type for trace_id)
      assert {:error, error} =
               Signal.put_extension(signal, "trace", %{trace_id: 123, span_id: "span-123"})

      assert error =~ "expected string"

      # Try to add invalid data for security extension (permissions should be list)
      assert {:error, error} =
               Signal.put_extension(signal, "security", %{
                 user_id: "user-123",
                 permissions: "not-a-list"
               })

      assert error =~ "expected list"
    end

    test "unknown extension namespaces return proper errors" do
      {:ok, signal} = Signal.new("test.unknown.extension", %{message: "test"})

      # Try to add extension with unknown namespace
      assert {:error, error} = Signal.put_extension(signal, "unknown.extension", %{some: "data"})
      assert error =~ "Unknown extension: unknown.extension"
    end
  end

  describe "backward compatibility validation" do
    test "signals work without extensions" do
      # Create basic signal without extensions
      {:ok, basic_signal} = Signal.new("test.basic", %{message: "basic test"})
      assert basic_signal.type == "test.basic"
      assert basic_signal.data.message == "basic test"
      assert basic_signal.extensions == %{}

      # Signal with jido_dispatch still works
      {:ok, dispatch_signal} =
        Signal.new(
          "test.dispatch",
          %{message: "dispatch test"},
          jido_dispatch: {:logger, [level: :info]}
        )

      assert dispatch_signal.jido_dispatch == {:logger, [level: :info]}

      # Serialization of basic signals still works
      {:ok, serialized} = JsonSerializer.serialize(basic_signal)
      {:ok, deserialized} = JsonSerializer.deserialize(serialized, type: "Elixir.Jido.Signal")
      assert deserialized.type == "test.basic"
      assert deserialized.data.message == "basic test"
    end

    test "jido_dispatch backward compatibility works" do
      # Create signal with old-style dispatch
      {:ok, signal_with_old_dispatch} =
        Signal.new(
          "dispatch.compatibility.test",
          %{message: "test dispatch compatibility"},
          jido_dispatch: {:logger, [level: :info]}
        )

      # Should have jido_dispatch
      assert signal_with_old_dispatch.jido_dispatch == {:logger, [level: :info]}

      # Note: JSON serialization of tuples may not be supported
      # This test validates that the jido_dispatch field works correctly
      # even without serialization testing
    end
  end

  describe "performance scenarios" do
    test "extension registry lookup performance" do
      # Test multiple lookups
      lookups = ["thread", "trace", "security", "metrics"]

      {lookup_time, _} =
        :timer.tc(fn ->
          Enum.each(1..100, fn _ ->
            Enum.each(lookups, fn namespace ->
              case Jido.Signal.Ext.Registry.get(namespace) do
                {:ok, _module} -> :ok
                {:error, :not_found} -> :ok
              end
            end)
          end)
        end)

      # 500 lookups should complete quickly (less than 100ms)
      assert lookup_time < 100_000
    end

    test "many extensions on single signal" do
      {:ok, signal} = Signal.new("performance.many.extensions", %{message: "perf test"})

      # Add multiple extensions
      extensions_to_add = [
        {"thread", %{id: "thread-perf-123"}},
        {"trace", %{trace_id: "trace-perf-456", span_id: "span-perf-789"}},
        {"security", %{user_id: "user-perf-123"}},
        {"metrics", %{labels: %{test: "performance"}}}
      ]

      # Measure creation time
      {creation_time, final_signal} =
        :timer.tc(fn ->
          Enum.reduce(extensions_to_add, signal, fn {namespace, data}, acc ->
            {:ok, new_signal} = Signal.put_extension(acc, namespace, data)
            new_signal
          end)
        end)

      # Should complete in reasonable time (less than 50ms)
      # microseconds
      assert creation_time < 50_000

      # Verify extensions are all present
      assert Signal.get_extension(final_signal, "thread").id == "thread-perf-123"
      assert Signal.get_extension(final_signal, "trace").trace_id == "trace-perf-456"
      assert Signal.get_extension(final_signal, "security").user_id == "user-perf-123"
      assert Signal.get_extension(final_signal, "metrics").labels.test == "performance"
    end
  end

  describe "real-world usage patterns" do
    test "LLM conversation signal with context" do
      # Simulate an LLM conversation signal with comprehensive context
      {:ok, signal} =
        Signal.new(
          "llm.conversation.turn",
          %{
            role: "assistant",
            content: "Here's how to implement authentication...",
            model: "gpt-4",
            finish_reason: "stop",
            usage: %{
              prompt_tokens: 150,
              completion_tokens: 75,
              total_tokens: 225
            }
          }
        )

      # Add comprehensive context
      {:ok, signal} =
        Signal.put_extension(signal, "thread", %{
          id: "conv-abc123",
          parent_id: "turn-def456",
          depth: 5,
          model: "gpt-4",
          tokens_used: 225
        })

      {:ok, signal} =
        Signal.put_extension(signal, "trace", %{
          trace_id: "trace-llm-456",
          span_id: "span-generation-789",
          parent_span_id: "span-request-123",
          baggage: %{
            user_id: "user-123",
            session_id: "sess-456",
            api_version: "v1"
          }
        })

      {:ok, signal} =
        Signal.put_extension(signal, "security", %{
          user_id: "user-123",
          permissions: ["llm.chat", "llm.premium"],
          roles: ["premium_user"],
          session_id: "sess-456",
          expires_at: 1_703_980_800
        })

      {:ok, signal} =
        Signal.put_extension(signal, "metrics", %{
          labels: %{
            model: "gpt-4",
            user_tier: "premium",
            conversation_type: "api_help"
          },
          tags: ["llm", "conversation", "premium", "api_help"],
          counters: %{
            tokens_used: 225,
            api_calls: 1
          },
          gauges: %{
            conversation_depth: 5,
            response_time_ms: 1250
          }
        })

      # Verify complex interaction works
      assert signal.data.role == "assistant"
      assert signal.data.usage.total_tokens == 225

      thread_ext = Signal.get_extension(signal, "thread")
      assert thread_ext.tokens_used == 225

      trace_ext = Signal.get_extension(signal, "trace")
      assert trace_ext.baggage.user_id == "user-123"

      security_ext = Signal.get_extension(signal, "security")
      assert security_ext.user_id == "user-123"

      metrics_ext = Signal.get_extension(signal, "metrics")
      assert metrics_ext.counters.tokens_used == 225
    end
  end

  describe "final validation" do
    test "extension registry has expected extensions" do
      # Get registry state
      extensions = Jido.Signal.Ext.Registry.all()
      registered_namespaces = Enum.map(extensions, &elem(&1, 0))

      # Our test extensions should be registered
      expected_extensions = [
        "thread",
        "trace",
        "security",
        "metrics",
        "custom.serialization"
      ]

      for expected <- expected_extensions do
        assert expected in registered_namespaces,
               "Extension #{expected} should be registered"
      end

      # Registry count should be stable
      assert Jido.Signal.Ext.Registry.count() >= length(expected_extensions)
    end

    test "extension system doesn't break existing signal functionality" do
      # Test basic signal operations still work
      {:ok, basic_signal} = Signal.new("test.basic", %{message: "basic test"})
      assert basic_signal.type == "test.basic"
      assert basic_signal.data.message == "basic test"
      assert basic_signal.extensions == %{}

      # Test signal with jido_dispatch still works
      {:ok, dispatch_signal} =
        Signal.new(
          "test.dispatch",
          %{message: "dispatch test"},
          jido_dispatch: {:logger, [level: :info]}
        )

      assert dispatch_signal.jido_dispatch == {:logger, [level: :info]}
    end
  end
end
