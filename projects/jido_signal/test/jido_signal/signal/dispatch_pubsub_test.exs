defmodule JidoTest.Signal.Dispatch.PubSubTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch.PubSub

  @moduletag :capture_log

  # Test PubSub server name
  @test_pubsub __MODULE__.PubSub

  setup_all do
    # Start a test PubSub server for the tests
    start_supervised!({Phoenix.PubSub, name: @test_pubsub})
    :ok
  end

  describe "behaviour implementation" do
    test "implements Adapter behaviour" do
      # Ensure module is loaded before checking exports to prevent flaky test
      Code.ensure_loaded!(PubSub)

      assert function_exported?(PubSub, :validate_opts, 1)
      assert function_exported?(PubSub, :deliver, 2)

      behaviours = PubSub.__info__(:attributes)[:behaviour] || []
      assert Jido.Signal.Dispatch.Adapter in behaviours
    end
  end

  describe "validate_opts/1" do
    test "succeeds with valid target and topic" do
      opts = [target: @test_pubsub, topic: "test.events"]
      assert {:ok, validated_opts} = PubSub.validate_opts(opts)

      assert Keyword.get(validated_opts, :target) == @test_pubsub
      assert Keyword.get(validated_opts, :topic) == "test.events"
    end

    test "preserves additional options" do
      opts = [
        target: @test_pubsub,
        topic: "test.events",
        extra: "option",
        timeout: 5000
      ]

      assert {:ok, validated_opts} = PubSub.validate_opts(opts)
      assert Keyword.get(validated_opts, :extra) == "option"
      assert Keyword.get(validated_opts, :timeout) == 5000
    end

    test "fails when target is missing" do
      opts = [topic: "test.events"]
      assert {:error, "target must be an atom"} = PubSub.validate_opts(opts)
    end

    test "fails when target is not an atom" do
      invalid_targets = ["string", 123, %{}, [], {:tuple}]

      for target <- invalid_targets do
        opts = [target: target, topic: "test.events"]
        assert {:error, "target must be an atom"} = PubSub.validate_opts(opts)
      end
    end

    test "fails when topic is missing" do
      opts = [target: @test_pubsub]
      assert {:error, "topic must be a string"} = PubSub.validate_opts(opts)
    end

    test "fails when topic is not a string" do
      invalid_topics = [:atom, 123, %{}, [], {:tuple}]

      for topic <- invalid_topics do
        opts = [target: @test_pubsub, topic: topic]
        assert {:error, "topic must be a string"} = PubSub.validate_opts(opts)
      end
    end

    test "accepts various string topic formats" do
      valid_topics = [
        "simple",
        "dotted.topic",
        "colon:separated",
        "user:123:events",
        "namespace.service.events",
        "events-with-dashes",
        "events_with_underscores",
        "MixedCase",
        "with spaces",
        "unicode-世界",
        "symbols!@#$%"
      ]

      for topic <- valid_topics do
        opts = [target: @test_pubsub, topic: topic]
        assert {:ok, validated_opts} = PubSub.validate_opts(opts)
        assert Keyword.get(validated_opts, :topic) == topic
      end
    end

    test "accepts empty string topic" do
      opts = [target: @test_pubsub, topic: ""]
      assert {:ok, validated_opts} = PubSub.validate_opts(opts)
      assert Keyword.get(validated_opts, :topic) == ""
    end
  end

  describe "deliver/2" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test/source",
          data: %{message: "test message", value: 42}
        })

      topic = "test.events.#{:erlang.unique_integer([:positive])}"
      opts = [target: @test_pubsub, topic: topic]

      {:ok, signal: signal, opts: opts, topic: topic}
    end

    test "successfully broadcasts signal to PubSub", %{signal: signal, opts: opts, topic: topic} do
      # Subscribe to the topic to receive the broadcast
      Phoenix.PubSub.subscribe(@test_pubsub, topic)

      # Deliver the signal
      assert :ok = PubSub.deliver(signal, opts)

      # Should receive the signal via PubSub
      assert_receive ^signal, 1000
    end

    test "multiple subscribers receive the same signal", %{
      signal: signal,
      opts: opts,
      topic: topic
    } do
      test_process = self()

      # Subscribe from multiple processes
      test_pids =
        for i <- 1..3 do
          spawn_link(fn ->
            Phoenix.PubSub.subscribe(@test_pubsub, topic)

            receive do
              ^signal -> send(test_process, {:received, i})
            after
              1000 -> send(test_process, {:timeout, i})
            end
          end)
        end

      # Small delay to ensure subscriptions are established
      Process.sleep(10)

      # Deliver the signal
      assert :ok = PubSub.deliver(signal, opts)

      # All processes should receive the signal
      for _pid <- test_pids do
        assert_receive {:received, _i}, 1000
      end
    end

    test "delivers signal with all data intact", %{opts: opts, topic: topic} do
      complex_data = %{
        user: %{id: 123, name: "John Doe"},
        metadata: %{tags: ["important"], version: "1.0"},
        nested: %{deep: %{value: "test"}}
      }

      {:ok, signal} =
        Signal.new(%{
          type: "complex.signal",
          source: "/complex/source",
          data: complex_data
        })

      Phoenix.PubSub.subscribe(@test_pubsub, topic)

      assert :ok = PubSub.deliver(signal, opts)

      assert_receive received_signal, 1000
      assert received_signal.type == "complex.signal"
      assert received_signal.source == "/complex/source"
      assert received_signal.data == complex_data
      assert received_signal.id == signal.id
      assert received_signal.time == signal.time
    end

    test "handles signal with nil data", %{opts: opts, topic: topic} do
      {:ok, signal} =
        Signal.new(%{
          type: "nil.data",
          source: "/test"
          # No data field
        })

      Phoenix.PubSub.subscribe(@test_pubsub, topic)

      assert :ok = PubSub.deliver(signal, opts)

      assert_receive received_signal, 1000
      assert received_signal.data == nil
    end

    test "returns error when PubSub server is not found", %{signal: signal} do
      # Use a completely non-existent PubSub server name
      nonexistent_name = :"nonexistent_pubsub_#{:erlang.unique_integer([:positive])}"
      opts = [target: nonexistent_name, topic: "test.topic"]

      assert {:error, :pubsub_not_found} = PubSub.deliver(signal, opts)
    end

    test "broadcasts to different topics independently", %{signal: signal} do
      topic1 = "topic1.#{:erlang.unique_integer([:positive])}"
      topic2 = "topic2.#{:erlang.unique_integer([:positive])}"

      # Subscribe to both topics
      Phoenix.PubSub.subscribe(@test_pubsub, topic1)
      Phoenix.PubSub.subscribe(@test_pubsub, topic2)

      # Deliver to topic1 only
      opts1 = [target: @test_pubsub, topic: topic1]
      assert :ok = PubSub.deliver(signal, opts1)

      # Should receive on topic1
      assert_receive ^signal, 1000

      # Should not receive duplicate
      refute_receive ^signal, 100
    end

    test "concurrent deliveries work correctly", %{signal: signal, topic: topic} do
      Phoenix.PubSub.subscribe(@test_pubsub, topic)

      # Send multiple signals concurrently
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            opts = [target: @test_pubsub, topic: topic]
            PubSub.deliver(signal, opts)
          end)
        end

      results = Task.await_many(tasks)

      # All deliveries should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # Should receive all 5 signals
      for _i <- 1..5 do
        assert_receive ^signal, 1000
      end
    end

    test "validates opts are validated by validate_opts first", %{signal: signal} do
      # This would typically be caught by calling validate_opts first,
      # but test that deliver expects validated opts
      _invalid_opts = [target: "invalid", topic: :invalid]

      # Should raise because target is not an atom when fetched
      assert_raise KeyError, fn ->
        PubSub.deliver(signal, topic: "test")
      end
    end
  end

  describe "topic-based routing" do
    test "signals are isolated by topic", %{} do
      {:ok, signal1} = Signal.new(%{type: "signal1", source: "/test", data: %{id: 1}})
      {:ok, signal2} = Signal.new(%{type: "signal2", source: "/test", data: %{id: 2}})

      topic_a = "events.a.#{:erlang.unique_integer([:positive])}"
      topic_b = "events.b.#{:erlang.unique_integer([:positive])}"

      # Subscribe to topic A only
      Phoenix.PubSub.subscribe(@test_pubsub, topic_a)

      # Send signal1 to topic A
      opts_a = [target: @test_pubsub, topic: topic_a]
      assert :ok = PubSub.deliver(signal1, opts_a)

      # Send signal2 to topic B
      opts_b = [target: @test_pubsub, topic: topic_b]
      assert :ok = PubSub.deliver(signal2, opts_b)

      # Should only receive signal1
      assert_receive ^signal1, 1000
      refute_receive ^signal2, 100
    end

    test "hierarchical topic patterns" do
      {:ok, signal} = Signal.new(%{type: "test.signal", source: "/test"})

      topics = [
        "events.user.created",
        "events.user.updated",
        "events.order.created",
        "events.system.startup"
      ]

      # Subscribe to all topics
      for topic <- topics do
        Phoenix.PubSub.subscribe(@test_pubsub, topic)
      end

      # Send to one specific topic
      target_topic = "events.user.created"
      opts = [target: @test_pubsub, topic: target_topic]
      assert :ok = PubSub.deliver(signal, opts)

      # Should receive only once (on the target topic)
      assert_receive ^signal, 1000
      refute_receive ^signal, 100
    end
  end

  describe "error handling" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test/source",
          data: %{message: "test message", value: 42}
        })

      {:ok, signal: signal}
    end

    test "handles non-existent PubSub server", %{signal: signal} do
      # Use a PubSub name that was never started
      nonexistent_pubsub = :"nonexistent_pubsub_#{:erlang.unique_integer([:positive])}"
      opts = [target: nonexistent_pubsub, topic: "test.topic"]

      # Should return error for non-existent server
      assert {:error, :pubsub_not_found} = PubSub.deliver(signal, opts)
    end

    test "handles malformed opts gracefully" do
      {:ok, signal} = Signal.new(%{type: "test", source: "/test"})

      # Missing required keys should raise
      assert_raise KeyError, fn ->
        PubSub.deliver(signal, [])
      end

      assert_raise KeyError, fn ->
        PubSub.deliver(signal, target: @test_pubsub)
      end
    end
  end

  describe "integration scenarios" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test/source",
          data: %{message: "test message", value: 42}
        })

      {:ok, signal: signal}
    end

    test "works with complete validation and delivery workflow", %{signal: signal} do
      raw_opts = [target: @test_pubsub, topic: "integration.test"]

      # Step 1: Validate options
      assert {:ok, validated_opts} = PubSub.validate_opts(raw_opts)

      # Step 2: Subscribe to receive the signal
      topic = Keyword.get(validated_opts, :topic)
      Phoenix.PubSub.subscribe(@test_pubsub, topic)

      # Step 3: Deliver with validated options
      assert :ok = PubSub.deliver(signal, validated_opts)

      # Step 4: Verify signal was received
      assert_receive ^signal, 1000
    end

    test "can be used with dynamic topic generation", %{signal: signal} do
      # Generate topic based on signal properties
      dynamic_topic = "#{signal.type}.#{signal.source |> String.replace("/", ".")}"
      opts = [target: @test_pubsub, topic: dynamic_topic]

      assert {:ok, validated_opts} = PubSub.validate_opts(opts)

      Phoenix.PubSub.subscribe(@test_pubsub, dynamic_topic)

      assert :ok = PubSub.deliver(signal, validated_opts)
      assert_receive ^signal, 1000
    end
  end
end
