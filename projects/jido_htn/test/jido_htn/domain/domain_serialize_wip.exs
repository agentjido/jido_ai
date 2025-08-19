defmodule JidoTest.HTN.DomainSerializeTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.Serializer
  alias Jido.HTN.Method
  alias Jido.HTN.PrimitiveTask
  @moduletag :capture_log
  defmodule TestModule do
    @moduledoc false
    def test_function(_), do: true
    def run(_, _, _), do: {:ok, %{}}
  end

  describe "Domain serialization and deserialization" do
    test "serializes and deserializes a domain with all components" do
      {:ok, domain} =
        "TestDomain"
        |> Domain.new()
        |> Domain.compound("compound_task",
          methods: [
            %Method{
              conditions: [&TestModule.test_function/1],
              subtasks: ["primitive_task"]
            }
          ]
        )
        |> Domain.primitive("primitive_task", {TestModule, []},
          preconditions: [&TestModule.test_function/1],
          effects: [fn _ -> %{} end],
          expected_effects: [fn _ -> %{} end]
        )
        |> Domain.allow("test_op", TestModule)
        |> Domain.callback("test_callback", &TestModule.test_function/1)
        |> Domain.build()

      serialized = Serializer.serialize(domain)
      {:ok, deserialized} = Serializer.deserialize(serialized)

      assert domain.name == deserialized.name
      assert map_size(domain.tasks) == map_size(deserialized.tasks)
      assert map_size(domain.allowed_workflows) == map_size(deserialized.allowed_workflows)
      assert map_size(domain.callbacks) == map_size(deserialized.callbacks)

      assert %CompoundTask{} = deserialized.tasks["compound_task"]
      assert length(deserialized.tasks["compound_task"].methods) == 1
      assert %PrimitiveTask{} = deserialized.tasks["primitive_task"]
      assert {TestModule, []} == deserialized.tasks["primitive_task"].task
      assert Map.has_key?(deserialized.allowed_workflows, "test_op")
      assert Map.has_key?(deserialized.callbacks, "test_callback")

      # Test deserialized functions
      compound_task_condition =
        List.first(List.first(deserialized.tasks["compound_task"].methods).conditions)

      assert is_function(compound_task_condition)
      assert compound_task_condition.(%{})

      primitive_task_precondition = List.first(deserialized.tasks["primitive_task"].preconditions)
      assert is_function(primitive_task_precondition)
      assert primitive_task_precondition.(%{})
    end

    test "handles complex functions in conditions and effects" do
      complex_function = fn state ->
        case state do
          %{a: a, b: b} when a > b -> true
          _ -> false
        end
      end

      {:ok, domain} =
        "ComplexDomain"
        |> Domain.new()
        |> Domain.primitive("complex_task", {TestModule, []},
          preconditions: [complex_function],
          effects: [complex_function]
        )
        |> Domain.build()

      serialized = Serializer.serialize(domain)
      {:ok, deserialized} = Serializer.deserialize(serialized)

      assert %PrimitiveTask{} = deserialized.tasks["complex_task"]
      assert length(deserialized.tasks["complex_task"].preconditions) == 1
      assert length(deserialized.tasks["complex_task"].effects) == 1

      deserialized_func = List.first(deserialized.tasks["complex_task"].preconditions)
      assert is_function(deserialized_func)
      assert deserialized_func.(%{a: 2, b: 1}) == true
      assert deserialized_func.(%{a: 1, b: 2}) == false
    end

    test "handles empty domain" do
      {:ok, empty_domain} = "EmptyDomain" |> Domain.new() |> Domain.build()
      serialized = Serializer.serialize(empty_domain)
      {:ok, deserialized} = Serializer.deserialize(serialized)

      assert empty_domain.name == deserialized.name
      assert Enum.empty?(deserialized.tasks)
      assert Enum.empty?(deserialized.allowed_workflows)
      assert Enum.empty?(deserialized.callbacks)
    end

    test "fails to deserialize non-existent module" do
      serialized =
        ~s({"name":"TestDomain","tasks":{},"allowed_workflows":{"test_op":"NonExistentModule"},"callbacks":{}})

      assert {:error, _} = Serializer.deserialize(serialized)
    end
  end
end
