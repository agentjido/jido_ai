defmodule ReqLLM.Test.CapabilityStubs do
  @moduledoc """
  Mock capability modules for testing without network calls.

  These capability modules implement the ReqLLM.Capability.Adapter behavior
  with predictable responses for testing verification workflows, timing,
  and result handling patterns.
  """

  defmodule FastPassingCapability do
    @moduledoc """
    A capability that always passes quickly for testing successful flows.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :fast_passing

    @impl true
    def advertised?(_model), do: true

    @impl true
    def verify(_model, _opts) do
      {:ok, %{test: "success", response: "Fast passing test"}}
    end
  end

  defmodule FastFailingCapability do
    @moduledoc """
    A capability that always fails quickly for testing error handling.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :fast_failing

    @impl true
    def advertised?(_model), do: true

    @impl true
    def verify(_model, _opts) do
      {:error, "test failure"}
    end
  end

  defmodule SlowCapability do
    @moduledoc """
    A capability with artificial latency for testing timing measurements.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :slow_capability

    @impl true
    def advertised?(_model), do: true

    @impl true
    def verify(_model, opts) do
      # Configurable sleep duration for testing
      sleep_ms = Keyword.get(opts, :sleep_ms, 10)
      :timer.sleep(sleep_ms)
      {:ok, %{test: "delayed", sleep_ms: sleep_ms}}
    end
  end

  defmodule ConditionalCapability do
    @moduledoc """
    A capability that passes or fails based on model capabilities.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :conditional_capability

    @impl true
    def advertised?(model) do
      # Only advertised if model supports tool calling
      Map.get(model.capabilities || %{}, :tool_call?, false)
    end

    @impl true
    def verify(model, _opts) do
      if advertised?(model) do
        {:ok, %{test: "conditional_success"}}
      else
        {:error, "capability not supported by model"}
      end
    end
  end

  defmodule ThrowingCapability do
    @moduledoc """
    A capability that throws exceptions for testing error handling.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :throwing_capability

    @impl true
    def advertised?(_model), do: true

    @impl true
    def verify(_model, opts) do
      exception_type = Keyword.get(opts, :exception, RuntimeError)
      message = Keyword.get(opts, :message, "Test exception")
      raise exception_type, message
    end
  end

  defmodule TimeoutCapability do
    @moduledoc """
    A capability that sleeps longer than typical test timeouts.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :timeout_capability

    @impl true
    def advertised?(_model), do: true

    @impl true
    def verify(_model, opts) do
      # Default to a long sleep that would exceed most test timeouts
      sleep_ms = Keyword.get(opts, :sleep_ms, 5_000)
      :timer.sleep(sleep_ms)
      {:ok, %{test: "timeout_test"}}
    end
  end

  defmodule ConfigurableCapability do
    @moduledoc """
    A capability with configurable behavior for flexible testing scenarios.
    """

    @behaviour ReqLLM.Capability.Adapter

    @impl true
    def id, do: :configurable_capability

    @impl true
    def advertised?(model) do
      # Can be configured via model test_config field
      get_in(Map.get(model, :test_config, %{}), [:advertised]) || true
    end

    @impl true
    def verify(model, _opts) do
      # Extract test config from model struct fields, not metadata
      config = Map.get(model, :test_config, %{})
      
      # Configurable sleep
      if sleep_ms = config[:sleep_ms] do
        :timer.sleep(sleep_ms)
      end

      # Configurable result
      case config[:result] do
        :error ->
          {:error, config[:error_message] || "configurable error"}
        :exception ->
          raise config[:exception] || "configurable exception"
        _ ->
          {:ok, Map.merge(%{test: "configurable_success"}, config[:data] || %{})}
      end
    end
  end

  @doc """
  Returns all available test capability modules for discovery testing.

  ## Examples

      iex> capabilities = ReqLLM.Test.CapabilityStubs.all_capabilities()
      iex> assert FastPassingCapability in capabilities
      iex> assert FastFailingCapability in capabilities

  """
  @spec all_capabilities() :: [module()]
  def all_capabilities do
    [
      FastPassingCapability,
      FastFailingCapability,
      SlowCapability,
      ConditionalCapability,
      ThrowingCapability,
      TimeoutCapability,
      ConfigurableCapability
    ]
  end

  @doc """
  Returns only capabilities that should pass for positive testing.

  ## Examples

      iex> capabilities = ReqLLM.Test.CapabilityStubs.passing_capabilities()
      iex> assert FastPassingCapability in capabilities
      iex> refute FastFailingCapability in capabilities

  """
  @spec passing_capabilities() :: [module()]
  def passing_capabilities do
    [FastPassingCapability, SlowCapability]
  end

  @doc """
  Returns only capabilities that should fail for negative testing.

  ## Examples

      iex> capabilities = ReqLLM.Test.CapabilityStubs.failing_capabilities()
      iex> assert FastFailingCapability in capabilities
      iex> refute FastPassingCapability in capabilities

  """
  @spec failing_capabilities() :: [module()]
  def failing_capabilities do
    [FastFailingCapability]
  end

  @doc """
  Creates a test model configured to work with specific capability stubs.

  ## Examples

      iex> model = ReqLLM.Test.CapabilityStubs.model_for_capabilities([:fast_passing, :conditional_capability])
      iex> assert ConditionalCapability.advertised?(model) == true

  """
  @spec model_for_capabilities([atom()], keyword()) :: ReqLLM.Model.t()
  def model_for_capabilities(capability_ids, opts \\ []) do
    capabilities = %{
      tool_call?: :conditional_capability in capability_ids,
      reasoning?: :reasoning_capability in capability_ids,
      supports_temperature?: true
    }

    # Create base model
    model = ReqLLM.Test.Fixtures.test_model(
      "test",
      "stub-model",
      capabilities: capabilities
    )

    # Add test config if needed for configurable capability
    if :configurable_capability in capability_ids do
      test_config = Keyword.get(opts, :configurable_config, %{})
      Map.put(model, :test_config, test_config)
    else
      model
    end
  end
end
