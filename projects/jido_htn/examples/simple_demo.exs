Mix.install([
  {:jido_htn, path: "../"},
  {:typedstruct, "~> 0.5.3"}
])

defmodule HybridAgent do
  def domain do
    "HybridAgent"
    |> D.new()
    |> D.compound("think",
      methods: [
        %{ subtasks: ["handle_user_input"], conditions: [&user_waiting?/1] },
        %{ subtasks: ["plan_goals"], conditions: [&needs_planning?/1] },
        %{ subtasks: ["execute_primitive"], conditions: [&can_execute?/1] },
        %{ subtasks: ["compress_context", "cognitive_cycle"], conditions: [&context_overload?/1] },
        %{ subtasks: ["wait_for_input"], conditions: [fn agent -> not has_active_goals?(agent) end] }
      ]
    )
    |> D.build!()
  end
  defp user_waiting?(state), do: state.user_waiting
  defp needs_planning?(state), do: state.conversation_history == []
  defp can_execute?(state), do: state.can_execute
  defp context_overload?(state), do: state.context_overload
  defp has_active_goals?(state), do: state.active_goals != []
end
# defmodule HybridAgent do
#   use TypedStruct
#   alias Jido.HTN.Domain, as: D
#   alias Jido.Actions.Basic, as: B
#   @type message :: %{
#     role: :user | :assistant | :tool,
#     content: String.t(),
#     timestamp: DateTime.t()
#   }
#   def world_state do
#     %{
#       conversation_history: []
#     }
#   end

# end

# HybridAgent.domain()

# defmodule Demo do
#   def run do
#     # Define initial world state
#     world_state = %{
#       energy: 100,
#       location: :home,
#       task_complete: false
#     }

#     # Get domain and plan
#     case Jido.HTN.plan(domain(), world_state) do
#       {:ok, plan} ->
#         IO.puts("Generated plan:")

#         Enum.each(plan, fn {action, params} ->
#           IO.puts("  #{inspect(action)} with params #{inspect(params)}")
#         end)

#       {:error, reason} ->
#         IO.puts("Planning failed: #{reason}")
#     end
#   end

#   def domain do
#     alias Jido.HTN.Domain, as: D
#     alias Jido.Actions.Basic, as: B

#     "DemoBot"
#     |> D.new()
#     |> D.compound("root",
#       methods: [%{subtasks: ["do_work"]}]
#     )
#     |> D.compound("do_work",
#       methods: [
#         %{
#           subtasks: ["start_work", "perform_work", "finish_work"],
#           conditions: [&has_energy?/1]
#         }
#       ]
#     )
#     |> D.primitive(
#       "start_work",
#       {B.Log, message: "Starting work"},
#       preconditions: [&at_home?/1],
#       effects: [&decrease_energy/1]
#     )
#     |> D.primitive(
#       "perform_work",
#       {B.RandomDelay, min_ms: 1000, max_ms: 2000},
#       effects: [&do_task/1]
#     )
#     |> D.primitive(
#       "finish_work",
#       {B.Log, message: "Work complete"},
#       effects: [&mark_complete/1]
#     )
#     |> D.allow("start_work", B.Log)
#     |> D.allow("perform_work", B.RandomDelay)
#     |> D.allow("finish_work", B.Log)
#     |> D.build!()
#   end

#   # Predicates
#   defp has_energy?(state), do: state.energy > 20
#   defp at_home?(state), do: state.location == :home

#   # Transformers
#   defp decrease_energy(state), do: %{state | energy: state.energy - 10}
#   defp do_task(state), do: %{state | energy: state.energy - 20}
#   defp mark_complete(state), do: %{state | task_complete: true}
# end

# Demo.run()
