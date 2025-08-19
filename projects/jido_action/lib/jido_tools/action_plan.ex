defmodule Jido.Tools.ActionPlan do
  @moduledoc """
  A behavior and macro for creating actions that execute Jido Plans.

  Provides a standardized way to create actions that build and execute plans
  with configurable plan building and result transformation.

  ## Usage

  ```elixir
  defmodule MyWorkflowAction do
    use Jido.Tools.ActionPlan,
      name: "my_workflow",
      description: "Executes a multi-step workflow"

    @impl Jido.Tools.ActionPlan
    def build(params, context) do
      Plan.new(context: context)
      |> Plan.add(:fetch, MyApp.FetchAction, params)
      |> Plan.add(:validate, MyApp.ValidateAction, depends_on: :fetch)
      |> Plan.add(:save, MyApp.SaveAction, depends_on: :validate)
    end

    @impl Jido.Tools.ActionPlan
    def transform_result(result) do
      # Optional: Transform the execution result
      {:ok, %{workflow_result: result}}
    end
  end
  ```

  ## Callbacks

  - `build/2` (required) - Build the Plan struct from params and context
  - `transform_result/1` (optional) - Transform the execution result
  """

  alias Jido.Exec
  alias Jido.Plan

  @doc """
  Required callback for building a Plan struct.

  Takes the action parameters and context and returns a Plan struct
  that will be executed.
  """
  @callback build(params :: map(), context :: map()) :: Plan.t()

  @doc """
  Optional callback for transforming the execution result.

  Takes the plan execution result and returns a transformed result.
  """
  @callback transform_result(map()) :: {:ok, map()} | {:error, any()}

  # Make transform_result optional
  @optional_callbacks [transform_result: 1]

  @doc """
  Macro for setting up a module as an ActionPlan with plan execution capabilities.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Tools.ActionPlan
      # Pass all options to the base Action
      use Jido.Action, unquote(opts)

      # Implement the behavior

      # Implement the run function that builds and executes the plan
      @impl Jido.Action
      def run(params, context) do
        # Build the plan using the required callback
        plan = build(params, context)

        # Execute the plan
        case execute_plan(plan, params, context) do
          {:ok, result} ->
            # Transform the result using the optional callback
            transform_result(result)

          {:error, reason} ->
            {:error, reason}
        end
      end

      # Default implementation for transform_result
      @impl Jido.Tools.ActionPlan
      def transform_result(result) do
        {:ok, result}
      end

      # Allow transform_result to be overridden
      defoverridable transform_result: 1

      # Private helper function to execute the plan
      defp execute_plan(plan, params, context) do
        # Normalize the plan to get execution phases
        case Plan.execution_phases(plan) do
          {:ok, phases} ->
            # Execute each phase in order
            execute_phases(phases, plan, params, context, %{})

          {:error, reason} ->
            {:error, reason}
        end
      end

      # Execute phases sequentially
      defp execute_phases([], _plan, _params, _context, results) do
        {:ok, results}
      end

      defp execute_phases([phase | remaining_phases], plan, params, context, results) do
        case execute_phase(phase, plan, params, context, results) do
          {:ok, phase_results} ->
            # Merge phase results and continue
            updated_results = Map.merge(results, phase_results)
            # Flatten the phase results to pass individual step results as top-level params
            flattened_results =
              Enum.reduce(phase_results, %{}, fn {_step_name, step_result}, acc ->
                Map.merge(acc, step_result)
              end)

            updated_params = Map.merge(params, flattened_results)
            execute_phases(remaining_phases, plan, updated_params, context, updated_results)

          {:error, reason} ->
            {:error, reason}
        end
      end

      # Execute a single phase (can be parallel)
      defp execute_phase(step_names, plan, params, context, _results) when is_list(step_names) do
        # Execute all steps in this phase
        step_results =
          step_names
          |> Enum.map(fn step_name ->
            case Map.get(plan.steps, step_name) do
              nil ->
                {:error, %{type: :step_not_found, step_name: step_name}}

              plan_instruction ->
                execute_step(plan_instruction, params, context)
            end
          end)

        # Check if any step failed
        case Enum.find(step_results, fn result -> match?({:error, _}, result) end) do
          nil ->
            # All steps succeeded, collect results
            phase_results =
              step_results
              |> Enum.zip(step_names)
              |> Enum.reduce(%{}, fn
                {{:ok, result}, step_name}, acc ->
                  Map.put(acc, step_name, result)

                {{:error, _}, _step_name}, acc ->
                  acc
              end)

            {:ok, phase_results}

          {:error, reason} ->
            {:error, reason}
        end
      end

      # Execute a single step
      defp execute_step(plan_instruction, params, context) do
        instruction = plan_instruction.instruction
        action = instruction.action

        # Merge instruction params with current params (instruction params take precedence)
        merged_params = Map.merge(params, instruction.params)

        # Use Jido.Exec to run the action with proper error handling, retries, etc.
        case Exec.run(action, merged_params, context, instruction.opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            {:error,
             %{
               type: :step_execution_failed,
               step_name: plan_instruction.name,
               reason: reason
             }}

          other ->
            {:error,
             %{
               type: :invalid_result,
               step_name: plan_instruction.name,
               message: "Action returned unexpected value: #{inspect(other)}"
             }}
        end
      end
    end
  end
end
