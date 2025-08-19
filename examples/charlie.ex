defmodule Jido.CharlieBot do
  #   @moduledoc false
  #   use Jido.Agent,
  #     enforce_keys: [:id, :time_of_day],
  #     fields: [:id, :time_of_day],
  #     schema: [
  #       id: [type: :string, required: true],
  #       time_of_day: [type: {:in, [:morning, :afternoon, :evening, :night]}, required: true]
  #     ],
  #     default_values: [
  #       time_of_day: :morning
  #     ]

  def domain do
    alias __MODULE__.Predicates, as: P
    alias __MODULE__.Transformers, as: T
    alias Jido.HTN.Domain, as: D
    alias Jido.Actions.CharlieBot, as: S

    "CharlieBot"
    |> D.new()
    |> D.compound("root",
      methods: [%{subtasks: ["follow_schedule"]}]
    )
    |> D.compound("follow_schedule",
      methods: [
        %{conditions: [&P.is_morning?/1], subtasks: ["morning_routine", "follow_schedule"]},
        %{conditions: [&P.is_afternoon?/1], subtasks: ["afternoon_routine", "follow_schedule"]},
        %{conditions: [&P.is_evening?/1], subtasks: ["evening_routine", "follow_schedule"]},
        %{subtasks: ["sleep", "follow_schedule"]}
      ]
    )
    |> D.compound("morning_routine",
      methods: [%{subtasks: ["wake_up", "eat_breakfast", "work"]}]
    )
    |> D.compound("afternoon_routine",
      methods: [%{subtasks: ["eat_lunch", "work"]}]
    )
    |> D.compound("evening_routine",
      methods: [%{subtasks: ["eat_dinner", "relax"]}]
    )
    |> D.primitive("wake_up", S.WakeUp)
    |> D.primitive("eat_breakfast", S.Eat)
    |> D.primitive("eat_lunch", S.Eat)
    |> D.primitive("eat_dinner", S.Eat)
    |> D.primitive("work", S.Work)
    |> D.primitive("relax", S.Relax)
    |> D.primitive("sleep", S.Sleep, effects: [&T.advance_time/1])
  end

  defmodule Predicates do
    @moduledoc false
    def is_morning?(bot), do: bot.time_of_day == :morning
    def is_afternoon?(bot), do: bot.time_of_day == :afternoon
    def is_evening?(bot), do: bot.time_of_day == :evening
  end

  defmodule Transformers do
    @moduledoc false
    def advance_time(bot) do
      new_time =
        case bot.time_of_day do
          :morning -> :afternoon
          :afternoon -> :evening
          :evening -> :night
          :night -> :morning
        end

      %{bot | time_of_day: new_time}
    end
  end
end
