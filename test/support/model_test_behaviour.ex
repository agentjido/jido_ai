defmodule Jido.AI.Model.TestBehaviour do
  @moduledoc """
  Behavior for testable AI models in GEPA evaluations.

  This behavior defines the contract for mock models used in testing,
  allowing dynamic generation of model fixtures with configurable outcomes.

  ## Purpose

  During testing, we need to simulate various AI model behaviors without
  making real API calls. This behavior defines the interface that all
  mock models must implement to support comprehensive GEPA testing.

  ## Callbacks

  - `chat_completion/2` - Simulate a chat completion request
  - `calculate_fitness/1` - Calculate fitness score for evaluation result
  - `simulate_execution/2` - Simulate full agent execution
  - `with_failure/2` - Configure mock to return specific failure type
  - `with_timeout/1` - Configure mock to simulate timeout

  ## Example Implementation

      defmodule MockOpenAI do
        @behaviour Jido.AI.Model.TestBehaviour

        @impl true
        def chat_completion(_model, prompt) do
          {:ok, "Mock response for: \#{prompt}"}
        end

        @impl true
        def calculate_fitness(_result), do: 0.85

        @impl true
        def simulate_execution(_model, _opts) do
          {:ok, %{success: true, output: "result"}}
        end

        @impl true
        def with_failure(mock, :timeout), do: %{mock | scenario: :timeout}

        @impl true
        def with_timeout(mock), do: %{mock | scenario: :timeout}
      end
  """

  @doc """
  Simulates a chat completion request to the model.

  ## Parameters
  - `model` - The mock model configuration
  - `prompt` - The prompt string to process

  ## Returns
  - `{:ok, response}` - Successful completion with response string
  - `{:error, reason}` - Failure with error reason
  """
  @callback chat_completion(model :: term(), prompt :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Calculates a fitness score for the given execution result.

  Fitness scores range from 0.0 (worst) to 1.0 (best) and represent
  how well the model performed on the evaluation task.

  ## Parameters
  - `execution_result` - The result of executing the model

  ## Returns
  - Float between 0.0 and 1.0
  """
  @callback calculate_fitness(execution_result :: term()) :: float()

  @doc """
  Simulates a complete agent execution with the model.

  This callback simulates the full lifecycle of an agent evaluation,
  including prompt processing, execution, and result collection.

  ## Parameters
  - `model` - The mock model configuration
  - `opts` - Options for the execution (timeout, task config, etc.)

  ## Returns
  - `{:ok, result}` - Successful execution with result map
  - `{:error, reason}` - Failed execution with error reason
  """
  @callback simulate_execution(model :: term(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Configures the mock to return a specific failure type.

  ## Parameters
  - `mock` - The mock model to configure
  - `failure_type` - Type of failure (`:timeout`, `:error`, `:partial`, etc.)

  ## Returns
  - Updated mock configuration that will fail as specified
  """
  @callback with_failure(mock :: term(), failure_type :: atom()) :: term()

  @doc """
  Configures the mock to simulate a timeout scenario.

  This is a convenience callback equivalent to `with_failure(mock, :timeout)`.

  ## Parameters
  - `mock` - The mock model to configure

  ## Returns
  - Updated mock configuration that will timeout
  """
  @callback with_timeout(mock :: term()) :: term()
end
