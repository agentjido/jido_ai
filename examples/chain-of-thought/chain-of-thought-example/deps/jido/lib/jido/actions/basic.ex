defmodule Jido.Actions.Basic do
  @moduledoc """
  A collection of basic actions for common actions.

  This module provides a set of simple, reusable actions:
  - Sleep: Pauses execution for a specified duration
  - Log: Logs a message with a specified level
  - Todo: Logs a todo item as a placeholder or reminder
  - RandomSleep: Introduces a random delay within a specified range
  - Increment: Increments a value by 1
  - Decrement: Decrements a value by 1
  - Noop: No operation, returns input unchanged
  - Today: Returns the current date in specified format
  """

  alias Jido.Action

  defmodule Sleep do
    @moduledoc false
    use Action,
      name: "sleep_action",
      description: "Sleeps for a specified duration",
      schema: [
        duration_ms: [
          type: :non_neg_integer,
          default: 1000,
          doc: "Duration to sleep in milliseconds"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{duration_ms: duration} = params, _ctx) do
      Process.sleep(duration)
      {:ok, params}
    end
  end

  defmodule Log do
    @moduledoc false
    use Action,
      name: "log_action",
      description: "Logs a message with a specified level",
      schema: [
        level: [type: {:in, [:debug, :info, :warning, :error]}, default: :info, doc: "Log level"],
        message: [type: :string, required: true, doc: "Message to log"]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) when map_size(params) == 0 do
      Logger.info("Current time: #{DateTime.utc_now()}")
      {:ok, params}
    end

    def run(%{level: level, message: message} = params, _ctx) do
      case level do
        :debug -> Logger.debug(message)
        :info -> Logger.info(message)
        :warning -> Logger.warning(message)
        :error -> Logger.error(message)
      end

      {:ok, params}
    end
  end

  defmodule Todo do
    @moduledoc false
    use Action,
      name: "todo_action",
      description: "A placeholder for a todo item",
      schema: [
        todo: [type: :string, required: true, doc: "Todo item description"]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{todo: todo} = params, _ctx) do
      Logger.debug("TODO Action: #{todo}")
      {:ok, params}
    end
  end

  defmodule RandomSleep do
    @moduledoc false
    use Action,
      name: "random_sleep_action",
      description: "Introduces a random sleep within a specified range",
      schema: [
        min_ms: [
          type: :non_neg_integer,
          required: true,
          doc: "Minimum sleep duration in milliseconds"
        ],
        max_ms: [
          type: :non_neg_integer,
          required: true,
          doc: "Maximum sleep duration in milliseconds"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{min_ms: min, max_ms: max} = params, _ctx) do
      delay = Enum.random(min..max)
      Process.sleep(delay)
      {:ok, Map.put(params, :actual_delay, delay)}
    end
  end

  defmodule Increment do
    @moduledoc false
    use Action,
      name: "increment_action",
      description: "Increments a value by 1",
      schema: [
        value: [type: :integer, required: true, doc: "Value to increment"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      {:ok, Map.put(params, :value, value + 1)}
    end
  end

  defmodule Decrement do
    @moduledoc false
    use Action,
      name: "decrement_action",
      description: "Decrements a value by 1",
      schema: [
        value: [type: :integer, required: true, doc: "Value to decrement"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      {:ok, Map.put(params, :value, value - 1)}
    end
  end

  defmodule Noop do
    @moduledoc false
    use Action,
      name: "noop_action",
      description: "No operation, returns input unchanged",
      schema: []

    @spec run(map(), map()) :: {:ok, map()}
    def run(params, _ctx) do
      {:ok, params}
    end
  end

  defmodule Inspect do
    @moduledoc false
    use Action,
      name: "inspect_action",
      description: "Inspects a value",
      schema: [
        value: [type: :any, required: true, doc: "Value to inspect"]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value} = params, _ctx) do
      # credo:disable-for-next-line Credo.Check.Warning.IoInspect
      IO.inspect(value, label: "Inspect action output")
      {:ok, params}
    end
  end

  defmodule Today do
    @moduledoc false
    use Action,
      name: "today",
      description: "Returns today's date in specified format",
      schema: [
        format: [
          type: {:in, [:iso8601, :basic, :human]},
          default: :iso8601,
          doc: "Format for the date output (:iso8601, :basic, or :human)"
        ]
      ]

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{format: format} = params, _ctx) do
      today = Date.utc_today()

      formatted_date =
        case format do
          :iso8601 -> Date.to_iso8601(today)
          :basic -> "#{today.year}-#{today.month}-#{today.day}"
          :human -> Calendar.strftime(today, "%B %d, %Y")
        end

      {:ok, Map.put(params, :date, formatted_date)}
    end
  end
end
