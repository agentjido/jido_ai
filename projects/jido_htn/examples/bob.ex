# defmodule Jido.BobBot do
#   @moduledoc false
#   use Jido.Agent,
#     enforce_keys: [:id, :is_active, :work_count],
#     fields: [:id, :is_active, :work_count],
#     schema: [
#       id: [type: :string, required: true],
#       is_active: [type: :boolean, required: true],
#       work_count: [type: :integer, required: true]
#     ],
#     default_values: [
#       is_active: true,
#       work_count: 0
#     ]

#   alias Jido.HTN

#   def domain do
#     alias __MODULE__.Predicates, as: P
#     alias __MODULE__.Transformers, as: T
#     alias Jido.HTN.Domain, as: D
#     alias Jido.Actions.BobBot, as: S

#     "BobBot"
#     |> D.new()
#     |> D.compound("root",
#       methods: [%{subtasks: ["cycle"]}]
#     )
#     |> D.compound("cycle",
#       methods: [
#         %{conditions: [&P.is_active?/1], subtasks: ["work", "cycle"]},
#         %{subtasks: ["idle", "cycle"]}
#       ]
#     )
#     |> D.primitive(
#       "work",
#       S.Work,
#       effects: [&T.increment_work_count/1, &T.may_deactivate/1]
#     )
#     |> D.primitive(
#       "idle",
#       S.Idle,
#       effects: [&T.may_activate/1]
#     )
#   end

#   defmodule Predicates do
#     @moduledoc false
#     def is_active?(bot), do: bot.is_active
#   end

#   defmodule Transformers do
#     @moduledoc false
#     def increment_work_count(bot), do: %{bot | work_count: bot.work_count + 1}
#     def may_deactivate(bot), do: %{bot | is_active: :rand.uniform() > 0.7}
#     def may_activate(bot), do: %{bot | is_active: :rand.uniform() > 0.3}
#   end
# end
