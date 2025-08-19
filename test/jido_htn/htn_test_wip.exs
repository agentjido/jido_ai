defmodule JidoTest.HTNTest do
  use ExUnit.Case, async: true

  alias Jido.HTN
  alias Jido.HTN.CompoundTask
  alias Jido.HTN.Domain
  alias Jido.HTN.Domain.Builder
  alias Jido.HTN.PrimitiveTask
  alias JidoTest.SimpleBot
  @moduletag :capture_log

  describe "HTN domain builder" do
    test "create a new domain" do
      "Test Domain"
      |> Domain.new()
      |> Domain.compound("root", methods: [%{subtasks: ["subtask"]}])
      |> Domain.primitive("subtask", {TestAction, []})
      |> Domain.allow("TestAction", TestAction)
      |> Domain.build()
    end
  end

  describe "decompose_primitive/4" do
    test "successfully decomposes a primitive task" do
      domain = %Domain{
        callbacks: %{
          "precond" => fn _ -> true end,
          "effect" => fn state -> Map.put(state, :effect_applied, true) end
        }
      }

      task = %PrimitiveTask{
        name: "test_task",
        preconditions: ["precond"],
        effects: ["effect"]
      }

      world_state = %{}
      current_plan = []

      {:ok, new_plan, new_world_state, debug_node} =
        HTN.decompose_primitive(domain, task, world_state, current_plan)

      assert length(new_plan) == 1
      assert new_world_state == %{effect_applied: true}
      assert debug_node == {:primitive, "test_task", true, [{"precond", true}]}
    end

    test "fails when preconditions are not met" do
      domain = %Domain{
        callbacks: %{
          "precond" => fn _ -> false end
        }
      }

      task = %PrimitiveTask{
        name: "test_task",
        preconditions: ["precond"],
        effects: []
      }

      world_state = %{}
      current_plan = []

      {:error, reason, debug_node} =
        HTN.decompose_primitive(domain, task, world_state, current_plan)

      assert reason =~ "Precondition not met"
      assert debug_node == {:primitive, "test_task", false, [{"precond", false}]}
    end
  end

  describe "decompose_compound/7" do
    test "successfully decomposes a compound task" do
      domain = %Domain{
        tasks: %{
          "subtask" => %PrimitiveTask{
            name: "subtask",
            preconditions: [],
            effects: []
          }
        },
        callbacks: %{}
      }

      task = %CompoundTask{
        name: "compound_task",
        methods: [
          %{name: "method1", conditions: [], subtasks: ["subtask"]}
        ]
      }

      world_state = %{}
      current_plan = []
      mtr = []

      {:ok, new_plan, new_world_state, debug_tree} =
        HTN.decompose_compound(domain, task, world_state, current_plan, mtr, 0, false)

      assert length(new_plan) == 1
      assert new_world_state == %{}

      assert debug_tree ==
               {:compound, "compound_task", true,
                [{true, "method1", [], {:primitive, "subtask", true, []}}]}
    end

    test "fails when no valid method is found" do
      domain = %Domain{
        callbacks: %{
          "condition" => fn _ -> false end
        }
      }

      task = %CompoundTask{
        name: "compound_task",
        methods: [
          %{name: "method1", conditions: ["condition"], subtasks: []}
        ]
      }

      world_state = %{}
      current_plan = []
      mtr = []

      {:error, reason, debug_tree} =
        HTN.decompose_compound(domain, task, world_state, current_plan, mtr, 0, false)

      assert reason == "Method failed"

      assert debug_tree ==
               {:compound, "compound_task", false,
                [{false, "method1", [{"condition", false}], {:empty, "", false}}]}
    end
  end

  # describe "preconditions_met?/3" do
  #   test "all preconditions are met" do
  #     domain = %Domain{
  #       callbacks: %{
  #         "precond1" => fn _ -> true end,
  #         "precond2" => fn _ -> true end
  #       }
  #     }

  #     preconditions = ["precond1", "precond2"]
  #     world_state = %{}

  #     {result, condition_results} = HTN.preconditions_met?(domain, preconditions, world_state)

  #     assert result == true
  #     assert condition_results == [{"precond1", true}, {"precond2", true}]
  #   end

  #   test "some preconditions are not met" do
  #     domain = %Domain{
  #       callbacks: %{
  #         "precond1" => fn _ -> true end,
  #         "precond2" => fn _ -> false end
  #       }
  #     }

  #     preconditions = ["precond1", "precond2"]
  #     world_state = %{}

  #     {result, condition_results} = HTN.preconditions_met?(domain, preconditions, world_state)

  #     assert result == false
  #     assert condition_results == [{"precond1", true}, {"precond2", false}]
  #   end
  # end

  # describe "apply_effects/3" do
  #   test "applies all effects to the world state" do
  #     domain = %Domain{
  #       callbacks: %{
  #         "effect1" => fn state -> Map.put(state, :effect1, true) end,
  #         "effect2" => fn state -> Map.put(state, :effect2, true) end
  #       }
  #     }

  #     effects = ["effect1", "effect2", fn state -> Map.put(state, :custom_effect, true) end]
  #     initial_state = %{}

  #     result = HTN.apply_effects(domain, effects, initial_state)

  #     assert result == %{
  #              effect1: true,
  #              effect2: true,
  #              custom_effect: true
  #            }
  #   end
  # end

  # describe "effects_to_functions/2" do
  #   test "convert effects to functions" do
  #     domain = %Domain{
  #       callbacks: %{
  #         "effect1" => fn state -> Map.put(state, :effect1, true) end,
  #         "effect2" => fn state -> Map.put(state, :effect2, true) end,
  #         "effect3" => fn state -> Map.put(state, :effect3, true) end
  #       }
  #     }

  #     effects = [
  #       "effect1",
  #       "effect2",
  #       fn state -> Map.put(state, :custom_effect, true) end,
  #       "effect3"
  #     ]

  #     result = HTN.effects_to_functions(domain, effects)

  #     assert length(result) == 4
  #     assert Enum.all?(result, &is_function(&1, 1))

  #     initial_state = %{}
  #     final_state = Enum.reduce(result, initial_state, fn effect, state -> effect.(state) end)

  #     assert final_state == %{
  #              effect1: true,
  #              effect2: true,
  #              effect3: true,
  #              custom_effect: true
  #            }
  #   end
  # end
end
