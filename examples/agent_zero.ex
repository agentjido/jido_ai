# defmodule AgentZeroDomain do
#   @behaviour EBoss.Planners.HTN.DomainBehaviour

#   alias EBoss.Planners.HTN.Domain

#   defmodule Predicates do
#     def has_user_message?(state), do: state.user_message != nil
#     def has_memories?(state), do: length(state.memories) > 0
#     def intervention_needed?(state), do: state.intervention_message != nil
#     def task_completed?(state), do: state.task_completed
#     def tool_execution_needed?(state), do: state.tool_execution_needed
#   end

#   defmodule Transformers do
#     def process_user_message(state), do: %{state | user_message: nil}
#     def process_memories(state), do: %{state | memories: []}
#     def handle_intervention(state), do: %{state | intervention_message: nil}
#     def mark_task_completed(state), do: %{state | task_completed: true}
#     def reset_tool_execution(state), do: %{state | tool_execution_needed: false}
#   end

#   @impl true
#   def predicates, do: Predicates

#   @impl true
#   def transformers, do: Transformers

#   @impl true
#   def init(_opts \\ []) do
#     alias Predicates, as: P
#     alias Transformers, as: T

#     domain =
#       Domain.new("AgentZero")
#       |> Domain.compound("root",
#         methods: [%{subtasks: ["agent_loop"]}]
#       )
#       |> Domain.compound("agent_loop",
#         methods: [
#           %{conditions: [&P.task_completed?/1], subtasks: []},
#           %{
#             conditions: [&P.intervention_needed?/1],
#             subtasks: ["handle_intervention", "agent_loop"]
#           },
#           %{
#             conditions: [&P.has_user_message?/1],
#             subtasks: [
#               "process_user_message",
#               "fetch_memories",
#               "generate_response",
#               "process_tools",
#               "agent_loop"
#             ]
#           },
#           %{subtasks: ["agent_loop"]}
#         ]
#       )
#       |> Domain.primitive("process_user_message",
#         preconditions: [&P.has_user_message?/1],
#         task: {AgentZero.ProcessUserMessageWorkflow, params: %{}},
#         effects: [&T.process_user_message/1]
#       )
#       |> Domain.primitive("fetch_memories",
#         task: {AgentZero.FetchMemoriesWorkflow, params: %{}},
#         effects: []
#       )
#       |> Domain.primitive("generate_response",
#         task: {AgentZero.GenerateResponseWorkflow, params: %{}},
#         effects: []
#       )
#       |> Domain.compound("process_tools",
#         methods: [
#           %{
#             conditions: [&P.tool_execution_needed?/1],
#             subtasks: ["execute_tool", "process_tools"]
#           },
#           %{subtasks: []}
#         ]
#       )
#       |> Domain.primitive("execute_tool",
#         preconditions: [&P.tool_execution_needed?/1],
#         task: {AgentZero.ExecuteToolWorkflow, params: %{}},
#         effects: [&T.reset_tool_execution/1]
#       )
#       |> Domain.primitive("handle_intervention",
#         preconditions: [&P.intervention_needed?/1],
#         task: {AgentZero.HandleInterventionWorkflow, params: %{}},
#         effects: [&T.handle_intervention/1]
#       )

#     {:ok, domain}
#   end
# end
