defmodule JidoTest.HTN.DomainValidateTest do
  use ExUnit.Case, async: true

  # alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  # alias Jido.HTN.Method
  # alias Jido.HTN.PrimitiveTask
  @moduletag :capture_log
  defmodule TestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  defmodule AnotherTestAction do
    @moduledoc false
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "validate/1" do
    test "validates a correct domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects duplicate task names" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task", {TestAction, []})
        |> Domain.compound("task", methods: [])
        |> Domain.build()
        |> Domain.validate()

      assert {:error, error_message} = result
      assert error_message =~ "Task name 'task' already exists in the domain"
    end

    test "detects undefined subtasks" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["undefined_subtask"]}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Subtask 'undefined_subtask' does not refer to a valid task"
    end

    test "detects disallowed actions" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task", {TestAction, []})
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain must contain at least one allowed workflow"
    end

    test "detects duplicate callbacks" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("callback", fn _ -> true end)
        |> Domain.callback("callback", fn _ -> false end)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain must contain at least one task"
    end

    # test "detects invalid primitive task structure" do
    #   result =
    #     "Test Domain"
    #     |> Domain.new()
    #     |> Domain.primitive("task", {"not_a_module", []})
    #     |> Domain.allow("not_a_module", TestAction)
    #     |> Domain.build()
    #     |> Domain.validate()

    #   assert {:error, error_message} = result
    #   assert error_message =~ "Invalid action: \"not_a_module\""
    # end

    test "validates a domain with multiple tasks and workflows" do
      {:ok, domain} =
        "Complex Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask1", "subtask2"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.primitive("subtask2", {AnotherTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects missing root task" do
      result =
        "No Root Domain"
        |> Domain.new()
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain must have at least one root task"
    end

    test "validates naming conventions" do
      result =
        "Invalid Names Domain"
        |> Domain.new()
        |> Domain.compound("Root", methods: [%{subtasks: ["Sub_Task"]}])
        |> Domain.primitive("Sub_Task", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("Root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Invalid names found: Root, Sub_Task"
    end

    test "detects invalid callback signatures" do
      result =
        "Invalid Callback Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("invalid_callback", fn _, _ -> true end)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid callback function"
    end

    test "validates a domain with callbacks" do
      {:ok, domain} =
        "Callback Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
        |> Domain.primitive("subtask", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("valid_callback", fn _ -> true end)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects methods without subtasks" do
      result =
        "Empty Method Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: []}])
        |> Domain.allow("TestAction", TestAction)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Compound task 'root' has methods without subtasks"
    end

    test "validates a domain with multiple compound tasks" do
      {:ok, domain} =
        "Multi-Compound Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["subtask1", "compound2"]}])
        |> Domain.compound("compound2", methods: [%{subtasks: ["subtask2"]}])
        |> Domain.primitive("subtask1", {TestAction, []})
        |> Domain.primitive("subtask2", {AnotherTestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.allow("AnotherTestAction", AnotherTestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)
    end

    test "detects name conflicts between tasks and callbacks" do
      result =
        "Conflict Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["conflict"]}])
        |> Domain.primitive("conflict", {TestAction, []})
        |> Domain.allow("TestAction", TestAction)
        |> Domain.callback("conflict", fn _ -> true end)
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Domain contains duplicate names: conflict"
    end

    test "validates cost and duration in primitive tasks" do
      # Test valid cost and duration
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, cost: 10, duration: 1000)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)

      # Test negative cost
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, cost: -1)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Cost must be non-negative"

      # Test negative duration
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, duration: -1)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Duration must be non-negative"

      # Test invalid cost type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, cost: "invalid")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Cost must be an integer"

      # Test invalid duration type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task"]}])
        |> Domain.primitive("task", {TestAction, []}, duration: "invalid")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error_message]} = result
      assert error_message =~ "Duration must be an integer"
    end

    test "validates costs and durations" do
      # Test invalid cost
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: -1)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, errors} = result

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Cost must be non-negative")
             )

      # Test invalid duration
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, duration: -1000)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, errors} = result

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Duration must be non-negative")
             )

      # Test both invalid
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: -1, duration: -1000)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, errors} = result

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Cost must be non-negative")
             )

      assert Enum.any?(
               errors,
               &(&1 =~ "Invalid task structure for 'task1': Duration must be non-negative")
             )

      # Test valid values
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, cost: 0, duration: 0)
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert :ok = result
    end

    test "validates scheduling constraints" do
      # Test valid constraints
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: 1000, latest_end_time: 2000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()

      assert :ok = Domain.validate(domain)

      # Test invalid earliest_start_time type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: "1000"}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': earliest_start_time must be an integer"

      # Test invalid latest_end_time type
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{latest_end_time: "2000"}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': latest_end_time must be an integer"

      # Test negative earliest_start_time
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: -1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result

      assert error =~
               "Invalid task structure for 'task1': earliest_start_time must be non-negative"

      # Test negative latest_end_time
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{latest_end_time: -2000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': latest_end_time must be non-negative"

      # Test earliest_start_time > latest_end_time
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{earliest_start_time: 2000, latest_end_time: 1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result

      assert error =~
               "Invalid task structure for 'task1': earliest_start_time cannot be greater than latest_end_time"

      # Test invalid constraint keys
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []},
          scheduling_constraints: %{invalid_key: 1000}
        )
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result

      assert error =~
               "Invalid task structure for 'task1': scheduling_constraints can only contain earliest_start_time and latest_end_time"

      # Test non-map constraints
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", {TestAction, []}, scheduling_constraints: "invalid")
        |> Domain.allow("TestAction", TestAction)
        |> Domain.root("root")
        |> Domain.build()
        |> Domain.validate()

      assert {:error, [error]} = result
      assert error =~ "Invalid task structure for 'task1': scheduling_constraints must be a map"
    end
  end
end
