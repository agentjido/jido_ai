defmodule Crontab.CronExpression.Parser do
  @moduledoc """
  Parse string like `* * * * * *` to a `%Crontab.CronExpression{}`.
  """

  alias Crontab.CronExpression

  @type result :: {:ok, CronExpression.t()} | {:error, binary}

  @specials %{
    reboot: %CronExpression{reboot: true},
    yearly: %CronExpression{minute: [0], hour: [0], day: [1], month: [1]},
    annually: %CronExpression{minute: [0], hour: [0], day: [1], month: [1]},
    monthly: %CronExpression{minute: [0], hour: [0], day: [1]},
    weekly: %CronExpression{minute: [0], hour: [0], weekday: [0]},
    daily: %CronExpression{minute: [0], hour: [0]},
    midnight: %CronExpression{minute: [0], hour: [0]},
    hourly: %CronExpression{minute: [0]},
    minutely: %CronExpression{},
    secondly: %CronExpression{extended: true}
  }

  @intervals [
    :minute,
    :hour,
    :day,
    :month,
    :weekday,
    :year
  ]

  @extended_intervals [:second | @intervals]

  @second_values 0..59
  @minute_values 0..59
  @hour_values 0..23
  @day_of_month_values 1..31

  @weekday_values %{
    MON: 1,
    TUE: 2,
    WED: 3,
    THU: 4,
    FRI: 5,
    SAT: 6,
    SUN: 7
  }

  # Sunday can be represented by 0 or 7.
  @full_weekday_values [0] ++ Map.values(@weekday_values)

  @month_values %{
    JAN: 1,
    FEB: 2,
    MAR: 3,
    APR: 4,
    MAY: 5,
    JUN: 6,
    JUL: 7,
    AUG: 8,
    SEP: 9,
    OCT: 10,
    NOV: 11,
    DEC: 12
  }

  @doc """
  Parse string like `* * * * * *` to a `%CronExpression{}`.

  ## Examples

      iex> Crontab.CronExpression.Parser.parse("* * * * *")
      {:ok,
       %Crontab.CronExpression{
         day: [:*],
         hour: [:*],
         minute: [:*],
         month: [:*],
         weekday: [:*],
         year: [:*],
         on_ambiguity: []
       }}

      iex> Crontab.CronExpression.Parser.parse("* * * * *", true)
      {:ok,
       %Crontab.CronExpression{
         extended: true,
         day: [:*],
         hour: [:*],
         minute: [:*],
         month: [:*],
         weekday: [:*],
         year: [:*],
         second: [:*],
         on_ambiguity: []
       }}

      iex> Crontab.CronExpression.Parser.parse("fooo")
      {:error, "Can't parse fooo as minute."}

  """
  @spec parse(binary, boolean, [CronExpression.ambiguity_opt()]) :: result
  def parse(cron_expression, extended \\ false, ambiguity_opts \\ [])

  def parse("@" <> identifier, _, _) do
    special(String.downcase(identifier))
  end

  def parse(cron_expression, is_extended, ambiguity_opts) do
    format = if(is_extended, do: @extended_intervals, else: @intervals)

    interpret(String.split(cron_expression, " "), format, %CronExpression{
      extended: is_extended,
      on_ambiguity: ambiguity_opts
    })
  end

  @doc """
  Parse string like `* * * * * *` to a `%CronExpression{}`.

  ## Examples

      iex> Crontab.CronExpression.Parser.parse!("* * * * *")
      %Crontab.CronExpression{
        day: [:*],
        hour: [:*],
        minute: [:*],
        month: [:*],
        weekday: [:*],
        year: [:*],
        on_ambiguity: []
      }

      iex> Crontab.CronExpression.Parser.parse!("* * * * *", true)
      %Crontab.CronExpression{
        extended: true,
        day: [:*],
        hour: [:*],
        minute: [:*],
        month: [:*],
        weekday: [:*],
        year: [:*],
        second: [:*],
        on_ambiguity: []
      }

      iex> Crontab.CronExpression.Parser.parse!("fooo")
      ** (RuntimeError) Can't parse fooo as minute.

  """
  @spec parse!(binary, boolean, [CronExpression.ambiguity_opt()]) :: CronExpression.t()
  def parse!(cron_expression, extended \\ false, ambiguity_opts \\ []) do
    case parse(cron_expression, extended, ambiguity_opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @spec interpret([binary], [CronExpression.interval()], CronExpression.t()) ::
          {:ok, CronExpression.t()} | {:error, binary}
  defp interpret(
         [head_format | tail_format],
         [head_expression | tail_expression],
         cron_expression
       ) do
    conditions = interpret(head_expression, head_format)

    case conditions do
      {:ok, ok_conditions} ->
        patched_cron_expression = Map.put(cron_expression, head_expression, ok_conditions)
        interpret(tail_format, tail_expression, patched_cron_expression)

      _ ->
        conditions
    end
  end

  defp interpret([], _, cron_expression), do: {:ok, cron_expression}
  defp interpret(_, [], _), do: {:error, "The Cron Format String contains too many parts."}

  @spec interpret(CronExpression.interval(), binary) ::
          {:ok, [CronExpression.value()]} | {:error, binary}
  defp interpret(interval, format) do
    parts = String.split(format, ",")
    tokens = Enum.map(parts, fn part -> tokenize(interval, part) end)

    if get_failed_token(tokens) do
      get_failed_token(tokens)
    else
      {:ok, Enum.map(tokens, fn {:ok, token} -> token end)}
    end
  end

  @spec get_failed_token([{:error, binary}] | CronExpression.value()) :: {:error, binary} | nil
  defp get_failed_token(tokens) do
    Enum.find(tokens, fn token ->
      case token do
        {:error, _} -> true
        _ -> false
      end
    end)
  end

  @spec tokenize(CronExpression.interval(), binary) ::
          {:ok, CronExpression.value()} | {:error, binary}
  defp tokenize(_, "*"), do: {:ok, :*}

  defp tokenize(interval, other) do
    cond do
      String.contains?(other, "/") -> tokenize(interval, :complex_divider, other)
      Regex.match?(~r/^.+-.+$/, other) -> tokenize(interval, :-, other)
      true -> tokenize(interval, :single_value, other)
    end
  end

  @spec tokenize(CronExpression.interval(), :- | :single_value | :complex_divider) ::
          {:ok, CronExpression.value()} | {:error, binary}
  defp tokenize(interval, :-, whole_string) do
    case String.split(whole_string, "-") do
      # negative number given in complex_divider
      ["", num] ->
        clean_value(interval, "-" <> num)

      [min, max] ->
        case {clean_value(interval, min), clean_value(interval, max)} do
          {{:ok, min_value}, {:ok, max_value}} -> {:ok, {:-, min_value, max_value}}
          {{:error, _} = error, _} -> error
          {_, {:error, _} = error} -> error
        end

      _ ->
        {:error, "Can't parse #{whole_string} as a range."}
    end
  end

  defp tokenize(interval, :single_value, value) do
    clean_value(interval, value)
  end

  defp tokenize(interval, :complex_divider, value) do
    [base, divider] = String.split(value, "/")

    # Range increments apply to *, positive single integers, or ranges in <start>-<end> format
    range_tokenization_result = tokenize(interval, :-, base)
    other_tokenization_result = tokenize(interval, base)
    integer_divider = Integer.parse(divider, 10)

    case {range_tokenization_result, other_tokenization_result, integer_divider} do
      # Invalid increment
      {_, _, {_clean_divider, remainder}} when remainder != "" ->
        {:error, "Can't parse #{divider} as increment."}

      # Zero increment
      {_, _, {0, ""}} ->
        {:error, "Can't parse #{divider} as increment."}

      # Found range in <start>-<end> format
      {{:ok, clean_base}, _, {clean_divider, ""}} ->
        {:ok, {:/, clean_base, clean_divider}}

      # Found star (*) range
      {{:error, _}, {:ok, :*}, {clean_divider, ""}} ->
        {:ok, {:/, :*, clean_divider}}

      # Found single simple integer
      {{:error, _}, {:ok, num}, {clean_divider, ""}} ->
        max_value = max_value_for_interval(interval)
        tokenize(interval, :complex_divider, "#{num}-#{max_value}/#{clean_divider}")

      # No valid range or single postive integer found
      {{:error, _} = error, _, _} ->
        error
    end
  end

  @spec max_value_for_interval(interval :: atom()) :: integer()
  defp max_value_for_interval(interval) do
    case interval do
      :second -> last_num_in_range(@second_values)
      :minute -> last_num_in_range(@minute_values)
      :hour -> last_num_in_range(@hour_values)
      :day -> last_num_in_range(@day_of_month_values)
      :month -> @month_values |> Map.values() |> Enum.reduce(&max/2)
      :weekday -> @weekday_values |> Map.values() |> Enum.reduce(&max/2)
      :year -> 3000
    end
  end

  @spec last_num_in_range(Range.t()) :: Range.limit()
  defp last_num_in_range(range) do
    range
    |> Enum.to_list()
    |> List.last()
  end

  @spec clean_value(CronExpression.interval(), binary) ::
          {:ok, CronExpression.value()} | {:error, binary}

  defp clean_value(:second, value) do
    clean_integer_within_range(value, "second", @second_values)
  end

  defp clean_value(:minute, value) do
    clean_integer_within_range(value, "minute", @minute_values)
  end

  defp clean_value(:hour, value) do
    clean_integer_within_range(value, "hour", @hour_values)
  end

  defp clean_value(:weekday, "L"), do: {:ok, 7}

  defp clean_value(:weekday, value) do
    # Sunday can be represented by 0 or 7
    cond do
      String.match?(value, ~r/L$/) ->
        parse_last_week_day(value)

      String.match?(value, ~r/#\d+$/) ->
        parse_nth_week_day(value)

      true ->
        case parse_week_day(value) do
          {:ok, number} ->
            check_within_range(number, "day of week", @full_weekday_values)

          error ->
            error
        end
    end
  end

  defp clean_value(:month, "L"), do: {:ok, 12}

  defp clean_value(:month, value) do
    error_message = "Can't parse #{value} as month."

    result =
      case {fetch_month_value(String.upcase(value)), Integer.parse(value, 10)} do
        # No valid month string or integer
        {:error, :error} -> {:error, error_message}
        # Month specified as string
        {{:ok, number}, :error} -> {:ok, number}
        # Month specified as integer
        {:error, {number, ""}} -> {:ok, number}
        # Integer is followed by an unwanted trailing string
        {:error, {_number, _remainder}} -> {:error, error_message}
      end

    case result do
      {:ok, number} ->
        month_numbers = Map.values(@month_values)
        check_within_range(number, "month", month_numbers)

      error ->
        error
    end
  end

  defp clean_value(:day, "L"), do: {:ok, :L}
  defp clean_value(:day, "LW"), do: {:ok, {:W, :L}}

  defp clean_value(:day, value) do
    if String.match?(value, ~r/W$/) do
      day = binary_part(value, 0, byte_size(value) - 1)

      with {number, ""} <- Integer.parse(day, 10),
           {:ok, number} <- check_within_range(number, "day of month", @day_of_month_values) do
        {:ok, {:W, number}}
      else
        {:error, reason} -> {:error, reason}
        :error -> {:error, "Can't parse #{value} as interval day."}
      end
    else
      clean_integer_within_range(value, "day of month", @day_of_month_values)
    end
  end

  defp clean_value(interval, value) do
    case Integer.parse(value, 10) do
      {number, ""} ->
        {:ok, number}

      :error ->
        {:error, "Can't parse " <> value <> " as interval " <> Atom.to_string(interval) <> "."}
    end
  end

  @spec clean_integer_within_range(binary, binary, Range.t()) ::
          {:ok, CronExpression.value()} | {:error, binary}
  defp clean_integer_within_range(value, field_name, valid_values) do
    case Integer.parse(value, 10) do
      {number, ""} ->
        check_within_range(number, field_name, valid_values)

      _ ->
        {:error, "Can't parse #{value} as #{field_name}."}
    end
  end

  @spec check_within_range(number, binary, Enum.t()) ::
          {:ok, CronExpression.value()} | {:error, binary}
  defp check_within_range(number, field_name, valid_values) do
    if number in valid_values do
      {:ok, number}
    else
      {:error, "Can't parse #{number} as #{field_name}."}
    end
  end

  @spec parse_week_day(binary) :: {:ok, CronExpression.value()} | {:error, binary}
  defp parse_week_day(value) do
    error_message = "Can't parse #{value} as day of week."

    case {fetch_weekday_value(String.upcase(value)), Integer.parse(value, 10)} do
      {:error, :error} -> {:error, error_message}
      {{:ok, number}, :error} -> {:ok, number}
      {:error, {number, ""}} -> {:ok, number}
      {:error, {_number, _remainder}} -> {:error, error_message}
    end
  end

  @spec parse_last_week_day(binary) :: {:ok, CronExpression.value()} | {:error, binary}
  defp parse_last_week_day(value) do
    case parse_week_day(binary_part(value, 0, byte_size(value) - 1)) do
      {:ok, value} ->
        case check_within_range(value, "day of week", @full_weekday_values) do
          {:ok, number} -> {:ok, {:L, number}}
          error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  @spec parse_nth_week_day(binary) :: {:ok, CronExpression.value()} | {:error, binary}
  defp parse_nth_week_day(value) do
    [weekday, n] = String.split(value, "#")

    case parse_week_day(weekday) do
      {:ok, value} ->
        {n_int, ""} = Integer.parse(n)

        case check_within_range(value, "day of week", @full_weekday_values) do
          {:ok, number} ->
            {:ok, {:"#", number, n_int}}

          error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @spec fetch_weekday_value(binary) :: {:ok, integer} | :error
  Enum.map(@weekday_values, fn {weekday, weekday_number} ->
    defp fetch_weekday_value(unquote(to_string(weekday))) do
      {:ok, unquote(weekday_number)}
    end
  end)

  defp fetch_weekday_value(_), do: :error

  @spec fetch_month_value(binary) :: {:ok, integer} | :error
  Enum.map(@month_values, fn {month, month_number} ->
    defp fetch_month_value(unquote(to_string(month))) do
      {:ok, unquote(month_number)}
    end
  end)

  defp fetch_month_value(_), do: :error

  @spec special(binary) :: result
  Enum.map(@specials, fn {special, special_value} ->
    defp special(unquote(to_string(special))) do
      {:ok, unquote(Macro.escape(special_value))}
    end
  end)

  defp special(identifier) do
    {:error, "Special identifier @#{identifier} is undefined."}
  end
end
