defmodule JidoTest.HTN.DomainBuildTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask
  @moduletag :capture_log
  describe "new/1" do
    test "creates a new domain with the given name" do
      assert {:ok, domain} = "Test Domain" |> Domain.new() |> Domain.build()
      assert %Domain{name: "Test Domain"} = domain
      assert domain.tasks == %{}
      assert domain.allowed_workflows == %{}
      assert domain.callbacks == %{}
    end

    test "returns an error for invalid name" do
      assert {:error, "Domain name must be a string: 123"} = 123 |> Domain.new() |> Domain.build()
    end
  end

  describe "add_compound_task/3" do
    test "adds a compound task to the domain" do
      condition = fn _ -> true end

      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("compound_task",
          methods: [
            %{conditions: [condition], subtasks: ["subtask1", "subtask2"]}
          ]
        )
        |> Domain.build()

      assert %CompoundTask{name: "compound_task"} = domain.tasks["compound_task"]
      assert length(domain.tasks["compound_task"].methods) == 1

      [method] = domain.tasks["compound_task"].methods
      assert %Method{} = method
      assert length(method.conditions) == 1
      assert hd(method.conditions) == condition
      assert method.subtasks == ["subtask1", "subtask2"]
    end

    test "returns an error for invalid task name" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound(123, methods: [])
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid task name: 123"
    end
  end

  describe "add_primitive_task/4" do
    test "adds a primitive task to the domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("primitive_task", {TestModule, []}, preconditions: [fn _ -> true end])
        |> Domain.build()

      assert %PrimitiveTask{name: "primitive_task"} = domain.tasks["primitive_task"]
      assert domain.tasks["primitive_task"].task == {TestModule, []}
      assert length(domain.tasks["primitive_task"].preconditions) == 1
    end

    # test "returns an error for invalid task name" do
    #   assert {:error, _} =
    #            "Test Domain"
    #            |> Domain.new()
    #            |> Domain.primitive(123, {TestModule, []})
    #            |> Domain.build()
    # end
  end

  describe "allow_workflow/3" do
    test "allows an workflow in the domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.allow("TestWorkflow", TestModule)
        |> Domain.build()

      assert domain.allowed_workflows["TestWorkflow"] == TestModule
    end

    test "returns an error for invalid workflow name" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.allow(123, TestModule)
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid workflow name: 123"
    end

    test "returns an error for invalid module" do
      {:error, error_message} =
        "Test Domain"
        |> Domain.new()
        |> Domain.allow("test", "not_a_module")
        |> Domain.build()

      assert error_message =~ "Invalid workflow module: \"not_a_module\""
    end
  end

  describe "add_callback/3" do
    test "adds a callback to the domain" do
      callback = fn _ -> true end

      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("test_callback", callback)
        |> Domain.build()

      assert domain.callbacks["test_callback"] == callback
    end

    test "returns an error for invalid callback name" do
      result =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback(123, fn _ -> true end)
        |> Domain.build()

      assert {:error, error_message} = result
      assert error_message =~ "Invalid callback name: 123"
    end

    test "returns an error for invalid callback function" do
      {:error, error_message} =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("test", "not_a_function")
        |> Domain.build()

      assert error_message =~ "Invalid callback function: \"not_a_function\""
    end
  end

  describe "get_primitive_task/2" do
    test "retrieves a primitive task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("primitive_task", {TestModule, []})
        |> Domain.build()

      assert {:ok, %PrimitiveTask{name: "primitive_task"}} =
               Domain.get_primitive(domain, "primitive_task")
    end

    test "returns an error for non-existent task" do
      {:ok, domain} = "Test Domain" |> Domain.new() |> Domain.build()
      assert {:error, _} = Domain.get_primitive(domain, "non_existent")
    end

    test "returns an error for compound task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("compound_task")
        |> Domain.build()

      assert {:error, _} = Domain.get_primitive(domain, "compound_task")
    end
  end

  describe "get_compound_task/2" do
    test "retrieves a compound task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("compound_task")
        |> Domain.build()

      assert {:ok, %CompoundTask{name: "compound_task"}} =
               Domain.get_compound(domain, "compound_task")
    end

    test "returns an error for non-existent task" do
      {:ok, domain} = "Test Domain" |> Domain.new() |> Domain.build()
      assert {:error, _} = Domain.get_compound(domain, "non_existent")
    end

    test "returns an error for primitive task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("primitive_task", {TestModule, []})
        |> Domain.build()

      assert {:error, _} = Domain.get_compound(domain, "primitive_task")
    end
  end

  describe "replace_task/3" do
    test "replaces an existing task" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.primitive("task", {TestModule, []})
        |> Domain.build()

      new_task = PrimitiveTask.new("task", {NewTestModule, []})
      {:ok, updated_domain} = Domain.replace(domain, "task", new_task)

      assert updated_domain.tasks["task"] == new_task
    end

    test "returns an error for non-existent task" do
      {:ok, domain} = "Test Domain" |> Domain.new() |> Domain.build()
      new_task = PrimitiveTask.new("new_task", {TestModule, []})

      assert {:error, _} = Domain.replace(domain, "non_existent", new_task)
    end
  end

  describe "list_tasks/1" do
    test "lists all task names in the domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("task1")
        |> Domain.primitive("task2", {TestModule, []})
        |> Domain.build()

      assert domain |> Domain.list_tasks() |> Enum.sort() == ["task1", "task2"]
    end
  end

  describe "list_allowed_workflows/1" do
    test "lists all allowed workflows in the domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.allow("Op1", TestModule1)
        |> Domain.allow("Op2", TestModule2)
        |> Domain.build()

      assert domain |> Domain.list_allowed_workflows() |> Enum.sort() == ["Op1", "Op2"]
    end
  end

  describe "list_callbacks/1" do
    test "lists all callback names in the domain" do
      {:ok, domain} =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("callback1", fn _ -> true end)
        |> Domain.callback("callback2", fn _ -> false end)
        |> Domain.build()

      assert domain |> Domain.list_callbacks() |> Enum.sort() == ["callback1", "callback2"]
    end
  end
end
