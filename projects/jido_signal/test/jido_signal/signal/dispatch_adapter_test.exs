defmodule JidoTest.Signal.Dispatch.AdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch.Adapter

  @moduletag :capture_log

  # Test adapter implementation that validates required options
  defmodule TestAdapter do
    @behaviour Adapter

    @impl true
    def validate_opts(opts) do
      cond do
        not Keyword.keyword?(opts) ->
          {:error, :invalid_opts_format}

        Keyword.get(opts, :fail_validation) ->
          {:error, :validation_failed}

        not Keyword.has_key?(opts, :required_option) ->
          {:error, :missing_required_option}

        true ->
          validated_opts = Keyword.put(opts, :validated, true)
          {:ok, validated_opts}
      end
    end

    @impl true
    def deliver(%Signal{id: signal_id} = _signal, opts) do
      cond do
        Keyword.get(opts, :fail_delivery) ->
          {:error, :delivery_failed}

        Keyword.get(opts, :simulate_timeout) ->
          Process.sleep(100)
          {:error, :timeout}

        not Keyword.get(opts, :validated, false) ->
          {:error, :opts_not_validated}

        true ->
          # Simulate successful delivery
          target_pid = Keyword.get(opts, :test_pid, self())
          send(target_pid, {:delivered, signal_id, opts})
          :ok
      end
    end
  end

  # Minimal test adapter
  defmodule MinimalAdapter do
    @behaviour Adapter

    @impl true
    def validate_opts(_opts), do: {:ok, []}

    @impl true
    def deliver(_signal, _opts), do: :ok
  end

  # Adapter that modifies options during validation
  defmodule NormalizingAdapter do
    @behaviour Adapter

    @impl true
    def validate_opts(opts) do
      normalized_opts =
        opts
        |> Keyword.put_new(:timeout, 5000)
        |> Keyword.update(:url, nil, &String.downcase/1)
        |> Keyword.put(:normalized, true)

      {:ok, normalized_opts}
    end

    @impl true
    def deliver(_signal, opts) do
      if Keyword.get(opts, :normalized) do
        :ok
      else
        {:error, :not_normalized}
      end
    end
  end

  describe "behaviour implementation requirements" do
    test "TestAdapter implements required callbacks" do
      # Verify the behaviour is correctly implemented
      assert function_exported?(TestAdapter, :validate_opts, 1)
      assert function_exported?(TestAdapter, :deliver, 2)

      # Verify behaviour attribute
      behaviours = TestAdapter.__info__(:attributes)[:behaviour] || []
      assert Adapter in behaviours
    end

    test "MinimalAdapter implements required callbacks" do
      assert function_exported?(MinimalAdapter, :validate_opts, 1)
      assert function_exported?(MinimalAdapter, :deliver, 2)

      behaviours = MinimalAdapter.__info__(:attributes)[:behaviour] || []
      assert Adapter in behaviours
    end
  end

  describe "validate_opts/1 callback" do
    test "successful validation returns {:ok, validated_opts}" do
      opts = [required_option: "test", extra: "data"]
      assert {:ok, validated_opts} = TestAdapter.validate_opts(opts)

      assert Keyword.get(validated_opts, :validated) == true
      assert Keyword.get(validated_opts, :required_option) == "test"
      assert Keyword.get(validated_opts, :extra) == "data"
    end

    test "validation failure returns {:error, reason}" do
      # Missing required option
      assert {:error, :missing_required_option} = TestAdapter.validate_opts([])

      # Explicit validation failure
      opts = [required_option: "test", fail_validation: true]
      assert {:error, :validation_failed} = TestAdapter.validate_opts(opts)

      # Invalid format
      assert {:error, :invalid_opts_format} = TestAdapter.validate_opts("not a keyword list")
    end

    test "minimal adapter accepts any options" do
      assert {:ok, []} = MinimalAdapter.validate_opts([])
      assert {:ok, []} = MinimalAdapter.validate_opts(any: "option")
      assert {:ok, []} = MinimalAdapter.validate_opts(invalid: :format)
    end

    test "normalizing adapter modifies options" do
      opts = [url: "HTTP://EXAMPLE.COM", custom: "value"]
      assert {:ok, normalized_opts} = NormalizingAdapter.validate_opts(opts)

      assert Keyword.get(normalized_opts, :url) == "http://example.com"
      assert Keyword.get(normalized_opts, :timeout) == 5000
      assert Keyword.get(normalized_opts, :normalized) == true
      assert Keyword.get(normalized_opts, :custom) == "value"
    end
  end

  describe "deliver/2 callback" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{message: "test delivery"}
        })

      {:ok, signal: signal}
    end

    test "successful delivery returns :ok", %{signal: signal} do
      opts = [required_option: "test", validated: true]
      assert :ok = TestAdapter.deliver(signal, opts)

      # Should receive delivery confirmation
      assert_receive {:delivered, signal_id, delivered_opts}
      assert signal_id == signal.id
      assert Keyword.get(delivered_opts, :validated) == true
    end

    test "delivery failure returns {:error, reason}", %{signal: signal} do
      # Simulate delivery failure
      opts = [required_option: "test", validated: true, fail_delivery: true]
      assert {:error, :delivery_failed} = TestAdapter.deliver(signal, opts)

      # Simulate timeout
      opts = [required_option: "test", validated: true, simulate_timeout: true]
      assert {:error, :timeout} = TestAdapter.deliver(signal, opts)
    end

    test "delivery with unvalidated options fails", %{signal: signal} do
      # missing :validated flag
      opts = [required_option: "test"]
      assert {:error, :opts_not_validated} = TestAdapter.deliver(signal, opts)
    end

    test "minimal adapter always succeeds", %{signal: signal} do
      assert :ok = MinimalAdapter.deliver(signal, [])
      assert :ok = MinimalAdapter.deliver(signal, any: "options")
    end

    test "normalizing adapter requires normalized options", %{signal: signal} do
      # Without normalization
      assert {:error, :not_normalized} = NormalizingAdapter.deliver(signal, [])

      # With normalization
      {:ok, normalized_opts} = NormalizingAdapter.validate_opts([])
      assert :ok = NormalizingAdapter.deliver(signal, normalized_opts)
    end
  end

  describe "full validation and delivery workflow" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{message: "test delivery"}
        })

      {:ok, signal: signal}
    end

    test "complete workflow with TestAdapter", %{signal: signal} do
      # Step 1: Validate options
      raw_opts = [required_option: "test", timeout: 1000]
      assert {:ok, validated_opts} = TestAdapter.validate_opts(raw_opts)

      # Step 2: Deliver with validated options
      assert :ok = TestAdapter.deliver(signal, validated_opts)

      # Verify delivery occurred
      assert_receive {:delivered, signal_id, delivered_opts}
      assert signal_id == signal.id
      assert Keyword.get(delivered_opts, :validated) == true
      assert Keyword.get(delivered_opts, :timeout) == 1000
    end

    test "workflow fails if validation fails", %{signal: _signal} do
      # Validation fails
      raw_opts = [fail_validation: true, required_option: "test"]
      assert {:error, :validation_failed} = TestAdapter.validate_opts(raw_opts)

      # Should not attempt delivery with failed validation
      # (In real usage, delivery wouldn't be called if validation fails)
    end

    test "workflow with normalizing adapter", %{signal: signal} do
      raw_opts = [url: "HTTP://API.EXAMPLE.COM/webhook"]

      # Validate and normalize
      assert {:ok, normalized_opts} = NormalizingAdapter.validate_opts(raw_opts)
      assert Keyword.get(normalized_opts, :url) == "http://api.example.com/webhook"
      assert Keyword.get(normalized_opts, :timeout) == 5000
      assert Keyword.get(normalized_opts, :normalized) == true

      # Deliver with normalized options
      assert :ok = NormalizingAdapter.deliver(signal, normalized_opts)
    end
  end

  describe "signal handling" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{message: "test delivery"}
        })

      {:ok, signal: signal}
    end

    test "adapter receives signal with all required fields", %{signal: signal} do
      opts = [required_option: "test", validated: true]
      assert :ok = TestAdapter.deliver(signal, opts)

      assert_receive {:delivered, signal_id, _opts}
      assert signal_id == signal.id

      # Verify signal structure
      assert signal.type == "test.signal"
      assert signal.source == "/test"
      assert signal.data.message == "test delivery"
      assert is_binary(signal.id)
      assert is_binary(signal.time)
    end

    test "adapter handles signal with no data", %{} do
      {:ok, signal_no_data} =
        Signal.new(%{
          type: "test.signal",
          source: "/test"
        })

      opts = [required_option: "test", validated: true]
      assert :ok = TestAdapter.deliver(signal_no_data, opts)
    end

    test "adapter handles signal with complex data", %{} do
      complex_data = %{
        user: %{id: 123, name: "test"},
        metadata: %{version: "1.0", tags: ["important", "urgent"]},
        nested: %{deep: %{value: "test"}}
      }

      {:ok, signal} =
        Signal.new(%{
          type: "complex.signal",
          source: "/test",
          data: complex_data
        })

      opts = [required_option: "test", validated: true]
      assert :ok = TestAdapter.deliver(signal, opts)

      assert_receive {:delivered, signal_id, _opts}
      assert signal_id == signal.id
    end
  end

  describe "error scenarios and edge cases" do
    test "adapter handles nil signal gracefully" do
      opts = [required_option: "test", validated: true]

      # This would typically be caught by type checking, but test defensive coding
      assert_raise FunctionClauseError, fn ->
        TestAdapter.deliver(nil, opts)
      end
    end

    test "adapter handles malformed options" do
      {:ok, _signal} = Signal.new(%{type: "test", source: "/test"})

      # Non-keyword list options should be handled in validate_opts
      assert {:error, :invalid_opts_format} = TestAdapter.validate_opts(%{not: "keyword"})
    end

    test "adapter can handle empty options after validation" do
      {:ok, signal} = Signal.new(%{type: "test", source: "/test"})

      # MinimalAdapter should handle empty options
      assert {:ok, []} = MinimalAdapter.validate_opts([])
      assert :ok = MinimalAdapter.deliver(signal, [])
    end
  end

  describe "concurrent delivery" do
    setup do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{message: "test delivery"}
        })

      {:ok, signal: signal}
    end

    test "adapter handles concurrent deliveries safely", %{signal: signal} do
      opts = [required_option: "test", validated: true]
      test_pid = self()

      # Start multiple delivery processes
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            TestAdapter.deliver(
              signal,
              opts |> Keyword.put(:task_id, i) |> Keyword.put(:test_pid, test_pid)
            )
          end)
        end

      # All should succeed
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      # Should receive all delivery confirmations
      for _i <- 1..10 do
        assert_receive {:delivered, signal_id, delivered_opts}
        assert signal_id == signal.id
        assert Keyword.get(delivered_opts, :task_id) in 1..10
      end
    end
  end
end
