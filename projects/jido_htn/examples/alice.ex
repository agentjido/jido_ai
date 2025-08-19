# defmodule Jido.ExampleAgents.Alice do
#   @moduledoc false
#   use Jido.Bot,
#     enforce_keys: [:id, :cycle_count],
#     fields: [:id, :cycle_count],
#     schema: [
#       id: [type: :string, required: true],
#       cycle_count: [type: :integer, required: true]
#     ],
#     default_values: [
#       cycle_count: 0
#     ]

#   require Logger
#   alias Jido.HTN

#   def domain do
#     alias Jido.HTN.Domain, as: D
#     alias Jido.Actions.Basic, as: S

#     "Alice"
#     |> D.new()
#     |> D.compound("root",
#       methods: [%{subtasks: ["cycle"]}]
#     )
#     |> D.compound("cycle",
#       methods: [
#         # Method 1: Start with even count
#         %{
#           subtasks: ["log_even", "sleep", "increment_cycle_count", "cycle"],
#           conditions: [&can_continue_cycle?/1, &cycle_count_even?/1]
#         },
#         # Method 2: Start with odd count
#         %{
#           subtasks: ["log_odd", "sleep", "increment_cycle_count", "cycle"],
#           conditions: [&can_continue_cycle?/1, &cycle_count_odd?/1]
#         },
#         # Method 3: Termination
#         %{
#           subtasks: [],
#           conditions: [&should_terminate_cycle?/1]
#         }
#       ]
#     )
#     |> D.primitive(
#       "sleep",
#       {S.Sleep, duration_ms: 10}
#     )
#     |> D.primitive(
#       "increment_cycle_count",
#       S.IncrementCycle,
#       effects: [&increment_cycle_count/1]
#     )
#     |> D.primitive(
#       "log_even",
#       {S.Log, message: "Cycle count is even"},
#       preconditions: [&cycle_count_even?/1]
#     )
#     |> D.primitive(
#       "log_odd",
#       {S.Log, message: "Cycle count is odd"},
#       preconditions: [&cycle_count_odd?/1]
#     )
#     |> D.allow("sleep", S.Sleep)
#     |> D.allow("log_even", S.Log)
#     |> D.allow("log_odd", S.Log)
#     |> D.build!()
#   end

#   def increment_cycle_count(%{cycle_count: count}), do: %{cycle_count: count + 1}
#   def can_continue_cycle?(%{cycle_count: count}), do: count < 10
#   def should_terminate_cycle?(%{cycle_count: count}), do: count >= 10
#   def cycle_count_even?(%{cycle_count: count}), do: rem(count, 2) == 0
#   def cycle_count_odd?(%{cycle_count: count}), do: rem(count, 2) == 1
# end
