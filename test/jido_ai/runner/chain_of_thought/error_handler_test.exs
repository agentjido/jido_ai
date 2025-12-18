defmodule Jido.AI.Runner.ChainOfThought.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.ErrorHandler
  alias Jido.AI.Runner.ChainOfThought.ErrorHandler.{Error, RetryConfig}
  alias Jido.AI.Runner.ChainOfThought.OutcomeValidator.ValidationResult

  describe "categorize_error/1" do
    test "categorizes atom errors" do
      assert ErrorHandler.categorize_error({:error, :timeout}) == :llm_error
      assert ErrorHandler.categorize_error({:error, :rate_limit}) == :llm_error
      assert ErrorHandler.categorize_error({:error, :parsing_error}) == :llm_error
      assert ErrorHandler.categorize_error({:error, :api_error}) == :llm_error
    end

    test "categorizes execution errors" do
      assert ErrorHandler.categorize_error({:error, :action_error}) == :execution_error
      assert ErrorHandler.categorize_error({:error, :validation_error}) == :execution_error
      assert ErrorHandler.categorize_error({:error, :unexpected_outcome}) == :execution_error
    end

    test "categorizes config errors" do
      assert ErrorHandler.categorize_error({:error, :invalid_config}) == :config_error
      assert ErrorHandler.categorize_error({:error, :missing_parameter}) == :config_error
      assert ErrorHandler.categorize_error({:error, :invalid_mode}) == :config_error
    end

    test "categorizes unknown errors" do
      assert ErrorHandler.categorize_error({:error, :something_weird}) == :unknown_error
      assert ErrorHandler.categorize_error(:not_an_error_tuple) == :unknown_error
    end

    test "categorizes exceptions" do
      exception = %RuntimeError{message: "test"}
      assert ErrorHandler.categorize_error({:error, exception}) == :llm_error
    end
  end

  describe "create_error/3" do
    test "creates error with full context" do
      error =
        ErrorHandler.create_error(:llm_error, :timeout,
          operation: "reasoning_generation",
          step: 1
        )

      assert error.category == :llm_error
      assert error.reason == :timeout
      assert error.context.operation == "reasoning_generation"
      assert error.context.step == 1
      assert %DateTime{} = error.timestamp
    end

    test "sets recoverable flag based on error type" do
      error1 = ErrorHandler.create_error(:llm_error, :timeout)
      assert error1.recoverable? == true

      error2 = ErrorHandler.create_error(:config_error, :invalid_mode)
      assert error2.recoverable? == false
    end

    test "stores original error if provided" do
      original = {:error, "original reason"}
      error = ErrorHandler.create_error(:llm_error, :timeout, original_error: original)

      assert error.original_error == original
    end
  end

  describe "recoverable?/2" do
    test "LLM errors are generally recoverable" do
      assert ErrorHandler.recoverable?(:llm_error, :timeout) == true
      assert ErrorHandler.recoverable?(:llm_error, :rate_limit) == true
      assert ErrorHandler.recoverable?(:llm_error, :api_error) == true
    end

    test "execution errors are recoverable" do
      assert ErrorHandler.recoverable?(:execution_error, :action_error) == true
      assert ErrorHandler.recoverable?(:execution_error, :unexpected_outcome) == true
    end

    test "config errors are not recoverable" do
      assert ErrorHandler.recoverable?(:config_error, :invalid_mode) == false
      assert ErrorHandler.recoverable?(:config_error, :missing_parameter) == false
    end
  end

  describe "select_recovery_strategy/1" do
    test "selects retry for transient LLM errors" do
      error = %Error{category: :llm_error, reason: :timeout, timestamp: DateTime.utc_now()}
      assert ErrorHandler.select_recovery_strategy(error) == :retry

      error = %Error{category: :llm_error, reason: :rate_limit, timestamp: DateTime.utc_now()}
      assert ErrorHandler.select_recovery_strategy(error) == :retry
    end

    test "selects fallback_direct for LLM errors" do
      error = %Error{category: :llm_error, reason: :parsing_error, timestamp: DateTime.utc_now()}
      assert ErrorHandler.select_recovery_strategy(error) == :fallback_direct
    end

    test "selects skip_continue for execution errors" do
      error = %Error{
        category: :execution_error,
        reason: :action_error,
        timestamp: DateTime.utc_now()
      }

      assert ErrorHandler.select_recovery_strategy(error) == :skip_continue

      error = %Error{
        category: :execution_error,
        reason: :unexpected_outcome,
        timestamp: DateTime.utc_now()
      }

      assert ErrorHandler.select_recovery_strategy(error) == :skip_continue
    end

    test "selects fail_fast for config errors" do
      error = %Error{
        category: :config_error,
        reason: :invalid_mode,
        timestamp: DateTime.utc_now()
      }

      assert ErrorHandler.select_recovery_strategy(error) == :fail_fast
    end
  end

  describe "with_retry/2" do
    test "succeeds on first attempt" do
      operation = fn -> {:ok, :success} end

      assert {:ok, :success} = ErrorHandler.with_retry(operation, max_retries: 3)
    end

    test "retries on failure and eventually succeeds" do
      # Use Agent to track attempts
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      operation = fn ->
        count = Agent.get_and_update(agent, fn c -> {c, c + 1} end)

        if count < 2 do
          {:error, :temporary_failure}
        else
          {:ok, :success}
        end
      end

      assert {:ok, :success} =
               ErrorHandler.with_retry(operation, max_retries: 3, initial_delay_ms: 10)

      Agent.stop(agent)
    end

    test "returns error after max retries" do
      operation = fn -> {:error, :persistent_failure} end

      assert {:error, %Error{} = error} =
               ErrorHandler.with_retry(operation, max_retries: 2, initial_delay_ms: 10)

      assert error.category == :unknown_error
      assert error.reason == :persistent_failure
      assert error.context.attempts == 3
    end

    test "respects initial delay" do
      start_time = System.monotonic_time(:millisecond)
      operation = fn -> {:error, :fail} end

      ErrorHandler.with_retry(operation, max_retries: 1, initial_delay_ms: 100, jitter?: false)

      elapsed = System.monotonic_time(:millisecond) - start_time
      # Should have at least one 100ms delay
      assert elapsed >= 100
    end
  end

  describe "handle_error/3" do
    test "handles structured error with retry strategy" do
      error = ErrorHandler.create_error(:llm_error, :timeout)

      # Create a successful retry function
      retry_fn = fn -> {:ok, :recovered} end

      result =
        ErrorHandler.handle_error(error, %{},
          strategy: :retry,
          retry_fn: retry_fn,
          max_retries: 1
        )

      assert {:ok, :recovered} = result
    end

    test "handles fallback_direct strategy" do
      error = ErrorHandler.create_error(:llm_error, :parsing_error)
      fallback_fn = fn -> {:ok, :fallback_agent, []} end

      result =
        ErrorHandler.handle_error(error, %{},
          strategy: :fallback_direct,
          fallback_fn: fallback_fn
        )

      assert {:ok, :fallback_agent, []} = result
    end

    test "handles skip_continue strategy" do
      error = ErrorHandler.create_error(:execution_error, :action_error)

      result = ErrorHandler.handle_error(error, %{step: 1}, strategy: :skip_continue)

      assert {:ok, :skipped} = result
    end

    test "handles fail_fast strategy" do
      error = ErrorHandler.create_error(:config_error, :invalid_mode)

      result = ErrorHandler.handle_error(error, %{}, strategy: :fail_fast)

      assert {:error, %Error{recovery_strategy: :fail_fast}} = result
    end

    test "auto-selects strategy when not provided" do
      error = ErrorHandler.create_error(:llm_error, :timeout)
      retry_fn = fn -> {:ok, :recovered} end

      # Should auto-select retry strategy for timeout
      result = ErrorHandler.handle_error(error, %{}, retry_fn: retry_fn, max_retries: 1)

      assert {:ok, :recovered} = result
    end

    test "wraps unstructured errors" do
      result = ErrorHandler.handle_error({:error, :some_error}, %{}, strategy: :fail_fast)

      assert {:error, %Error{}} = result
    end
  end

  describe "handle_unexpected_outcome/2" do
    test "continues by default for unexpected outcomes" do
      validation = %ValidationResult{
        matches_expectation: false,
        expected_outcome: "success",
        actual_outcome: "error",
        confidence: 0.0
      }

      assert :continue = ErrorHandler.handle_unexpected_outcome(validation, %{})
    end

    test "continues when strategy is skip_continue" do
      validation = %ValidationResult{
        matches_expectation: false,
        expected_outcome: "success",
        actual_outcome: "error",
        confidence: 0.0
      }

      config = %{unexpected_outcome_strategy: :skip_continue}
      assert :continue = ErrorHandler.handle_unexpected_outcome(validation, config)
    end

    test "fails fast when strategy is fail_fast" do
      validation = %ValidationResult{
        matches_expectation: false,
        expected_outcome: "success",
        actual_outcome: "error",
        confidence: 0.0
      }

      config = %{unexpected_outcome_strategy: :fail_fast}
      assert {:error, %Error{}} = ErrorHandler.handle_unexpected_outcome(validation, config)
    end
  end

  describe "log_error/2" do
    test "logs error without raising" do
      error =
        ErrorHandler.create_error(:llm_error, :timeout,
          operation: "reasoning_generation",
          step: 1
        )

      # Should not raise
      assert :ok = ErrorHandler.log_error(error)
    end

    test "logs error with additional context" do
      error = ErrorHandler.create_error(:llm_error, :timeout)

      assert :ok = ErrorHandler.log_error(error, operation: "test", step: 1)
    end

    test "logs unstructured errors" do
      assert :ok = ErrorHandler.log_error({:error, :some_error}, operation: "test")
    end
  end

  describe "Error struct" do
    test "has default values" do
      error = %Error{category: :llm_error, reason: :timeout, timestamp: DateTime.utc_now()}

      assert error.context == %{}
      assert error.recoverable? == true
      assert error.recovery_attempted? == false
      assert error.recovery_strategy == nil
      assert error.original_error == nil
    end
  end

  describe "RetryConfig struct" do
    test "has default values" do
      config = %RetryConfig{}

      assert config.max_retries == 3
      assert config.initial_delay_ms == 1000
      assert config.max_delay_ms == 30_000
      assert config.backoff_factor == 2.0
      assert config.jitter? == true
    end
  end
end
