defmodule Jido.AI.Runner.GEPA.TestCase do
  @moduledoc """
  Test case template for GEPA evaluations.

  Provides macros for generating tests across multiple model providers
  and scenarios dynamically.

  ## Usage

      defmodule MyGEPATest do
        use ExUnit.Case, async: true
        use Jido.AI.Runner.GEPA.TestCase

        test_with_models "evaluates successfully", [:openai, :anthropic] do
          {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})
          assert result.error == nil
        end
      end

  This will generate 2 tests:
  - "evaluates successfully (openai)"
  - "evaluates successfully (anthropic)"

  Each test will automatically set up the appropriate mock model.
  """

  defmacro __using__(_opts) do
    quote do
      import Jido.AI.Runner.GEPA.TestFixtures
      import Jido.AI.Runner.GEPA.TestHelper
      import Jido.AI.Runner.GEPA.TestCase
      import Mimic

      setup :set_mimic_global
      setup :trap_exits
    end
  end

  @doc false
  def trap_exits(_context) do
    Process.flag(:trap_exit, true)
    :ok
  end

  @doc """
  Generates test cases for each specified model provider.

  Creates a separate test for each provider in the list, automatically
  setting up the appropriate mock model before each test.

  ## Parameters
  - `description` - Base test description (provider name will be appended)
  - `providers` - List of provider atoms (e.g., `[:openai, :anthropic]`)
  - `do: block` - Test code to execute

  ## Options
  You can pass options as a third parameter before the `do:` block:
  - `:scenario` - Scenario to use (default: `:success`)
  - `:fitness` - Fitness score override
  - `:timeout` - Test timeout override

  ## Examples

      test_with_models "basic evaluation", [:openai, :anthropic, :local] do
        {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})
        assert result.error == nil
        assert is_float(result.fitness)
      end

      test_with_models "handles timeout", [:openai], scenario: :timeout do
        {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})
        assert result.error == :timeout
      end
  """
  defmacro test_with_models(description, providers, opts \\ [], do: block) do
    # Extract scenario from opts if provided
    scenario = Keyword.get(opts, :scenario, :success)

    # Generate a test for each provider
    for provider <- providers do
      test_name = "#{description} (#{provider})"

      quote do
        test unquote(test_name) do
          # Set up mock model for this provider
          {:ok, _context} = setup_mock_model(unquote(provider), scenario: unquote(scenario))

          # Execute test block
          unquote(block)
        end
      end
    end
  end

  @doc """
  Generates test cases for each scenario.

  Creates a separate test for each scenario in the list, automatically
  configuring the mock model to behave according to that scenario.

  ## Parameters
  - `description` - Base test description (scenario name will be appended)
  - `scenarios` - List of scenario atoms (e.g., `[:success, :timeout, :failure]`)
  - `do: block` - Test code to execute

  The test block has access to a `scenario` variable containing the current scenario.

  ## Examples

      test_with_scenarios "handles different outcomes", [:success, :timeout, :failure] do
        {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})

        case scenario do
          :success -> assert result.error == nil
          :timeout -> assert result.error == :timeout
          :failure -> assert result.error != nil
        end
      end
  """
  defmacro test_with_scenarios(description, scenarios, do: block) do
    for scenario <- scenarios do
      test_name = "#{description} (#{scenario})"

      quote do
        test unquote(test_name) do
          # Set up mock model with this scenario
          {:ok, _context} = setup_mock_model(:openai, scenario: unquote(scenario))

          # Make scenario available in test block
          var!(scenario) = unquote(scenario)

          # Execute test block
          unquote(block)
        end
      end
    end
  end

  @doc """
  Generates parameterized tests for provider and scenario combinations.

  Creates tests for every combination of providers and scenarios.
  Useful for comprehensive testing across multiple dimensions.

  ## Parameters
  - `description` - Base test description
  - `providers` - List of provider atoms
  - `scenarios` - List of scenario atoms
  - `do: block` - Test code to execute

  The test block has access to both `provider` and `scenario` variables.

  ## Examples

      test_with_combinations "comprehensive test",
        [:openai, :anthropic],
        [:success, :failure] do

        {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})

        # provider and scenario variables are available
        case scenario do
          :success -> assert result.error == nil
          :failure -> assert result.error != nil
        end
      end

  This generates 4 tests:
  - "comprehensive test (openai, success)"
  - "comprehensive test (openai, failure)"
  - "comprehensive test (anthropic, success)"
  - "comprehensive test (anthropic, failure)"
  """
  defmacro test_with_combinations(description, providers, scenarios, do: block) do
    for provider <- providers, scenario <- scenarios do
      test_name = "#{description} (#{provider}, #{scenario})"

      quote do
        test unquote(test_name) do
          # Set up mock model for this provider and scenario
          {:ok, _context} = setup_mock_model(unquote(provider), scenario: unquote(scenario))

          # Make provider and scenario available in test block
          var!(provider) = unquote(provider)
          var!(scenario) = unquote(scenario)

          # Execute test block
          unquote(block)
        end
      end
    end
  end
end
