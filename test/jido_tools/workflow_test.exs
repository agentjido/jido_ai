defmodule JidoTest.Tools.WorkflowTest do
  use JidoTest.ActionCase, async: true

  # Define a simple LogAction for testing
  defmodule LogAction do
    use Jido.Action,
      name: "log_action",
      description: "Logs a message",
      schema: [
        message: [type: :string, required: true]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{logged: params.message}}
    end
  end

  # Define test modules at the top level
  defmodule ValidWorkflow do
    use Jido.Tools.Workflow,
      name: "valid_workflow",
      description: "A valid test workflow",
      schema: [
        input: [type: :string, required: true]
      ],
      workflow: [
        {:step, [name: "log_step"], [{LogAction, message: "Processing input"}]},
        {:step, [name: "uppercase_step"], [{LogAction, message: "Converting to uppercase"}]}
      ]
  end

  defmodule ConditionalWorkflow do
    use Jido.Tools.Workflow,
      name: "conditional_workflow",
      description: "A workflow with conditional steps",
      schema: [
        input: [type: :string, required: true],
        condition: [type: :boolean, required: true]
      ],
      workflow: [
        {:step, [name: "initial_step"], [{LogAction, message: "Starting workflow"}]},
        {:branch, [name: "condition_check"],
         [
           true,
           {:step, [name: "true_branch"], [{LogAction, message: "Condition was true"}]},
           {:step, [name: "false_branch"], [{LogAction, message: "Condition was false"}]}
         ]},
        {:step, [name: "final_step"], [{LogAction, message: "Finishing workflow"}]}
      ]

    @impl Jido.Tools.Workflow
    def execute_step(
          {:branch, [name: "condition_check"], [_placeholder, true_branch, false_branch]},
          params,
          context
        ) do
      condition_value = params.condition

      if condition_value do
        execute_step(true_branch, params, context)
      else
        execute_step(false_branch, params, context)
      end
    end

    def execute_step(step, params, context) do
      super(step, params, context)
    end
  end

  defmodule ParallelWorkflow do
    use Jido.Tools.Workflow,
      name: "parallel_workflow",
      description: "A workflow with parallel steps",
      schema: [
        input: [type: :string, required: true]
      ],
      workflow: [
        {:step, [name: "initial_step"], [{LogAction, message: "Starting parallel workflow"}]},
        {:parallel, [name: "parallel_steps"],
         [
           {:step, [name: "parallel_1"], [{LogAction, message: "Parallel step 1"}]},
           {:step, [name: "parallel_2"], [{LogAction, message: "Parallel step 2"}]},
           {:step, [name: "parallel_3"], [{LogAction, message: "Parallel step 3"}]}
         ]},
        {:step, [name: "final_step"], [{LogAction, message: "Finished parallel workflow"}]}
      ]
  end

  defmodule ConvergeWorkflow do
    use Jido.Tools.Workflow,
      name: "converge_workflow",
      description: "A workflow with converge steps",
      schema: [
        input: [type: :string, required: true]
      ],
      workflow: [
        {:step, [name: "initial_step"], [{LogAction, message: "Starting"}]},
        {:converge, [name: "converge_step"], [{LogAction, message: "Converging"}]},
        {:step, [name: "final_step"], [{LogAction, message: "Finished"}]}
      ]
  end

  describe "validate_step/1" do
    test "validates valid step list" do
      valid_steps = [
        {:step, [name: "step1"], [{LogAction, message: "test"}]},
        {:branch, [name: "branch1"], [true, {:step, [], []}, {:step, [], []}]},
        {:converge, [name: "converge1"], [{LogAction, message: "test"}]},
        {:parallel, [name: "parallel1"], []}
      ]

      assert {:ok, ^valid_steps} = Jido.Tools.Workflow.validate_step(valid_steps)
    end

    test "rejects invalid step types" do
      invalid_steps = [
        {:invalid_step, [name: "bad"], []}
      ]

      assert {:error, "invalid workflow steps format"} =
               Jido.Tools.Workflow.validate_step(invalid_steps)
    end

    test "rejects malformed step tuples" do
      invalid_steps = [
        {:step, "not_a_list", []},
        {:step, [name: "good"], []},
        "not_a_tuple"
      ]

      assert {:error, "invalid workflow steps format"} =
               Jido.Tools.Workflow.validate_step(invalid_steps)
    end

    test "rejects non-list input" do
      assert {:error, "steps must be a list of tuples"} = Jido.Tools.Workflow.validate_step(%{})

      assert {:error, "steps must be a list of tuples"} =
               Jido.Tools.Workflow.validate_step("string")

      assert {:error, "steps must be a list of tuples"} = Jido.Tools.Workflow.validate_step(nil)
    end

    test "validates empty step list" do
      assert {:ok, []} = Jido.Tools.Workflow.validate_step([])
    end
  end

  describe "WorkflowAction module definition" do
    test "creates a workflow action with valid options" do
      assert ValidWorkflow.name() == "valid_workflow"
      assert ValidWorkflow.description() == "A valid test workflow"
      assert ValidWorkflow.workflow?() == true
      assert length(ValidWorkflow.workflow_steps()) == 2
    end

    test "validates parameters using schema" do
      params = %{}

      assert {:error, error} = ValidWorkflow.validate_params(params)
      assert %Jido.Action.Error.InvalidInputError{} = error
    end

    test "workflow steps are accessible" do
      steps = ValidWorkflow.workflow_steps()
      assert is_list(steps)
      assert length(steps) == 2

      [{:step, metadata1, _}, {:step, metadata2, _}] = steps
      assert metadata1[:name] == "log_step"
      assert metadata2[:name] == "uppercase_step"
    end
  end

  describe "WorkflowAction execution" do
    test "executes a simple workflow" do
      params = %{input: "test input"}
      context = %{}

      assert {:ok, result} = ValidWorkflow.run(params, context)
      assert result.logged == "Converting to uppercase"
    end

    test "executes a conditional workflow with true condition" do
      params = %{input: "test input", condition: true}
      context = %{}

      assert {:ok, result} = ConditionalWorkflow.run(params, context)
      assert result.logged == "Finishing workflow"
    end

    test "executes a conditional workflow with false condition" do
      params = %{input: "test input", condition: false}
      context = %{}

      assert {:ok, result} = ConditionalWorkflow.run(params, context)
      assert result.logged == "Finishing workflow"
    end

    test "executes a workflow with parallel steps" do
      params = %{input: "test input"}
      context = %{}

      assert {:ok, result} = ParallelWorkflow.run(params, context)
      assert result.logged == "Finished parallel workflow"
      assert Map.has_key?(result, :parallel_results)
      assert length(result.parallel_results) == 3
    end

    test "executes a workflow with converge steps" do
      params = %{input: "test input"}
      context = %{}

      assert {:ok, result} = ConvergeWorkflow.run(params, context)
      assert result.logged == "Finished"
    end

    test "handles errors in workflow steps" do
      defmodule ErrorAction do
        use Jido.Action,
          name: "error_action",
          description: "Always fails",
          schema: []

        @impl true
        def run(_params, _context) do
          {:error, "intentional failure"}
        end
      end

      defmodule ErrorWorkflow do
        use Jido.Tools.Workflow,
          name: "error_workflow",
          description: "A workflow that fails",
          schema: [],
          workflow: [
            {:step, [name: "error_step"], [{ErrorAction, []}]}
          ]
      end

      params = %{}
      context = %{}

      assert {:error, error} = ErrorWorkflow.run(params, context)
      assert error == "intentional failure"
    end

    test "handles invalid step types" do
      defmodule InvalidStepWorkflow do
        use Jido.Tools.Workflow,
          name: "invalid_step_workflow",
          description: "A workflow with invalid steps",
          schema: [],
          workflow: [
            {:step, [name: "good_step"], [{LogAction, message: "good"}]}
          ]
      end

      # Test the invalid step handling directly
      params = %{}
      context = %{}

      result = InvalidStepWorkflow.execute_step({:invalid_type, [], []}, params, context)
      assert {:error, error} = result
      assert error.type == :invalid_step
    end
  end

  describe "branch execution" do
    test "executes true branch when condition is true" do
      defmodule TrueBranchWorkflow do
        use Jido.Tools.Workflow,
          name: "true_branch_workflow",
          description: "Tests true branch",
          schema: [],
          workflow: [
            {:branch, [name: "test_branch"],
             [
               true,
               {:step, [name: "true_step"], [{LogAction, message: "true executed"}]},
               {:step, [name: "false_step"], [{LogAction, message: "false executed"}]}
             ]}
          ]
      end

      params = %{}
      context = %{}

      assert {:ok, result} = TrueBranchWorkflow.run(params, context)
      assert result.logged == "true executed"
    end

    test "executes false branch when condition is false" do
      defmodule FalseBranchWorkflow do
        use Jido.Tools.Workflow,
          name: "false_branch_workflow",
          description: "Tests false branch",
          schema: [],
          workflow: [
            {:branch, [name: "test_branch"],
             [
               false,
               {:step, [name: "true_step"], [{LogAction, message: "true executed"}]},
               {:step, [name: "false_step"], [{LogAction, message: "false executed"}]}
             ]}
          ]
      end

      params = %{}
      context = %{}

      assert {:ok, result} = FalseBranchWorkflow.run(params, context)
      assert result.logged == "false executed"
    end

    test "handles invalid branch conditions" do
      defmodule InvalidBranchWorkflow do
        use Jido.Tools.Workflow,
          name: "invalid_branch_workflow",
          description: "Tests invalid branch condition",
          schema: [],
          workflow: [
            {:branch, [name: "invalid_branch"],
             [
               "not_boolean",
               {:step, [name: "true_step"], [{LogAction, message: "true"}]},
               {:step, [name: "false_step"], [{LogAction, message: "false"}]}
             ]}
          ]
      end

      params = %{}
      context = %{}

      assert {:error, error} = InvalidBranchWorkflow.run(params, context)
      assert error.type == :invalid_condition
    end
  end

  describe "WorkflowAction integration" do
    test "supports tool conversion like regular actions" do
      tool = ValidWorkflow.to_tool()

      assert is_map(tool)
      assert Map.has_key?(tool, "name")
      assert Map.has_key?(tool, "description")
      assert Map.has_key?(tool, "parameters")

      assert tool["name"] == "valid_workflow"
      assert tool["description"] == "A valid test workflow"
    end

    test "includes workflow metadata in to_json" do
      json = ValidWorkflow.to_json()

      assert is_map(json)
      assert json.workflow == true
      assert is_list(json.steps)
      assert length(json.steps) == 2
    end

    test "workflow flag is set correctly" do
      assert ValidWorkflow.workflow?() == true
    end
  end

  describe "error handling" do
    test "raises compile error for invalid workflow configuration" do
      assert_raise CompileError, fn ->
        defmodule InvalidWorkflowConfig do
          use Jido.Tools.Workflow,
            name: "invalid_config",
            description: "Invalid workflow",
            workflow: "not_a_list"
        end
      end
    end
  end
end
