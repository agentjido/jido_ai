# defmodule Jido.SimpleBot do
#   @moduledoc false
#   alias Jido.HTN
#   alias Jido.Agent.PlanFrame

#   require Logger

#   @enforce_keys [:id, :battery_level, :location, :has_reported]
#   defstruct [:id, :battery_level, :location, :has_reported]

#   @type t :: %__MODULE__{
#           id: String.t(),
#           battery_level: integer(),
#           location: :home | :work,
#           has_reported: boolean()
#         }

#   @schema NimbleOptions.new!(
#             id: [type: :string, required: true],
#             battery_level: [type: :integer, required: true],
#             location: [type: {:in, [:home, :work]}, required: true],
#             has_reported: [type: :boolean, required: true]
#           )

#   def new(id) do
#     %__MODULE__{
#       id: id,
#       battery_level: 100,
#       location: :home,
#       has_reported: false
#     }
#   end

#   def validate(%__MODULE__{} = bot) do
#     known_keys = Keyword.keys(@schema.schema)
#     {known_params, unknown_params} = Map.split(Map.from_struct(bot), known_keys)

#     case NimbleOptions.validate(Enum.to_list(known_params), @schema) do
#       {:ok, validated_params} ->
#         merged_params = Map.merge(unknown_params, Map.new(validated_params))
#         {:ok, struct(__MODULE__, merged_params)}

#       {:error, %NimbleOptions.ValidationError{} = error} ->
#         {:error, Exception.message(error)}
#     end
#   end

#   def update(%__MODULE__{} = bot, attrs) do
#     updated_bot = struct(bot, attrs)

#     case validate(updated_bot) do
#       {:ok, _} -> {:ok, updated_bot}
#       error -> error
#     end
#   end

#   def plan(%__MODULE__{} = bot) do
#     with {:ok, validated_bot} <- validate(bot),
#          domain <- domain(),
#          {:ok, plan} <- HTN.plan(domain, validated_bot) do
#       %PlanFrame{bot: validated_bot, plan: plan}
#     else
#       error -> error
#     end
#   end

#   def run(%PlanFrame{bot: bot, plan: plan}) do
#     Jido.Runner.run(bot, plan)
#   end

#   # def run(plan, bot) do
#   #   case Chain.chain(plan, bot) do
#   #     {:ok, final_state} ->
#   #       Logger.info("Plan executed successfully. New state: #{inspect(final_state)}")
#   #       {:ok, final_state}

#   #     {:error, reason} ->
#   #       Logger.error("Plan execution failed: #{inspect(reason)}")
#   #       {:error, reason}
#   #   end
#   # end

#   def log(from_state, to_state) do
#     Logger.info("State transition", from: from_state, to: to_state)
#   end

#   def handle_signal(signal, state) do
#     Logger.info("Received signal", signal: signal, state: state)
#     {:ok, state}
#   end

#   defp domain do
#     alias __MODULE__.Predicates, as: P
#     alias __MODULE__.Transformers, as: T
#     alias Jido.HTN.Domain, as: D
#     alias Jido.Actions.Simplebot, as: S

#     "SimpleBot"
#     |> D.new()
#     |> D.compound("root",
#       methods: [%{subtasks: ["cycle"]}]
#     )
#     |> D.compound("cycle",
#       methods: [
#         %{conditions: [&P.battery_full?/1], subtasks: ["work_cycle"]},
#         %{conditions: [&P.battery_low?/1], subtasks: ["home_cycle"]},
#         %{subtasks: ["work_cycle"]}
#       ]
#     )
#     |> D.compound("work_cycle",
#       methods: [
#         %{conditions: [&P.at_home?/1], subtasks: ["move_to_work"]},
#         %{conditions: [&P.at_work?/1, &P.not_has_reported?/1], subtasks: ["report"]},
#         %{
#           conditions: [&P.at_work?/1, &P.has_reported?/1, &P.can_work?/1],
#           subtasks: ["do_work"]
#         },
#         %{conditions: [&P.at_work?/1, &P.battery_low?/1], subtasks: ["move_to_home"]},
#         # Fallback
#         %{subtasks: ["idle"]}
#       ]
#     )
#     |> D.compound("home_cycle",
#       methods: [
#         %{conditions: [&P.at_work?/1], subtasks: ["move_to_home"]},
#         %{conditions: [&P.at_home?/1, &P.battery_full?/1], subtasks: ["move_to_work"]},
#         %{conditions: [&P.at_home?/1], subtasks: ["recharge_cycle"]},
#         # Fallback
#         %{subtasks: ["idle"]}
#       ]
#     )
#     |> D.compound("recharge_cycle",
#       methods: [
#         %{conditions: [&P.battery_full?/1], subtasks: []},
#         %{subtasks: ["recharge", "recharge_cycle"]}
#       ]
#     )
#     |> D.primitive(
#       "recharge",
#       S.Recharge,
#       preconditions: [&P.at_home?/1],
#       effects: [&T.charge_battery/1]
#     )
#     |> D.primitive(
#       "move_to_work",
#       {S.Move, [destination: :work]},
#       preconditions: [&P.at_home?/1],
#       effects: [&T.move_to_work/1]
#     )
#     |> D.primitive(
#       "move_to_home",
#       {S.Move, [destination: :home]},
#       preconditions: [&P.at_work?/1],
#       effects: [&T.move_to_home/1]
#     )
#     |> D.primitive(
#       "report",
#       S.Report,
#       preconditions: [&P.at_work?/1, &P.not_has_reported?/1],
#       effects: [&T.set_reported_true/1]
#     )
#     |> D.primitive(
#       "do_work",
#       S.DoWork,
#       preconditions: [&P.at_work?/1, &P.has_reported?/1, &P.can_work?/1],
#       effects: [&T.do_work/1]
#     )
#     |> D.primitive(
#       "idle",
#       S.Idle,
#       preconditions: [],
#       effects: []
#     )
#     |> D.allow("MoveToWork", S.Move)
#     |> D.allow("MoveToHome", S.Move)
#     |> D.allow("Report", S.Report)
#     |> D.allow("DoWork", S.DoWork)
#     |> D.allow("Recharge", S.Recharge)
#     |> D.allow("Idle", S.Idle)
#     |> D.build!()
#   end

#   defmodule Predicates do
#     @moduledoc "Predicate functions for SimpleBot state"

#     def battery_low?(bot), do: bot.battery_level <= 30
#     def battery_full?(bot), do: bot.battery_level == 100
#     def battery_charged?(bot), do: bot.battery_level > 90
#     def can_work?(bot), do: bot.battery_level > 30
#     def at_location?(bot, location), do: bot.location == location
#     def has_reported?(bot), do: bot.has_reported
#     def not_has_reported?(bot), do: not has_reported?(bot)

#     def at_work?(bot), do: at_location?(bot, :work)
#     def at_home?(bot), do: at_location?(bot, :home)
#   end

#   defmodule Transformers do
#     @moduledoc "Transformer functions for SimpleBot state"

#     def move_to(bot, location) do
#       %{bot | location: location, battery_level: max(bot.battery_level - 10, 0)}
#     end

#     def set_reported(bot, reported), do: %{bot | has_reported: reported}
#     def do_work(bot), do: %{bot | battery_level: max(bot.battery_level - 20, 0)}

#     def charge_battery(bot) do
#       new_level = min(bot.battery_level + 10, 100)
#       %{bot | battery_level: new_level}
#     end

#     def move_to_work(bot), do: move_to(bot, :work)
#     def move_to_home(bot), do: move_to(bot, :home)
#     def set_reported_true(bot), do: set_reported(bot, true)
#     def set_reported_false(bot), do: set_reported(bot, false)
#   end
# end
