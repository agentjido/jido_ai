defmodule Crontab.DateHelper do
  @moduledoc false
  alias Crontab.CronExpression, as: CronExpr

  @typep ambiguity_opts :: [CronExpr.ambiguity_opt()]
  @type unit :: :year | :month | :day | :hour | :minute | :second | :microsecond

  @type date :: NaiveDateTime.t() | DateTime.t()

  @units [
    {:year, {nil, nil}},
    {:month, {1, 12}},
    {:day, {1, :end_of_month}},
    {:hour, {0, 23}},
    {:minute, {0, 59}},
    {:second, {0, 59}},
    {:microsecond, {{0, 0}, {999_999, 6}}}
  ]

  @doc """
  Get Start of a period of a date.

  ## Examples

      iex> Crontab.DateHelper.beginning_of(~N[2016-03-14 01:45:45.123], :year)
      ~N[2016-01-01 00:00:00]

      iex> Crontab.DateHelper.beginning_of(~U[2016-03-14 01:45:45.123Z], :year)
      ~U[2016-01-01 00:00:00Z]

  """
  @spec beginning_of(date, unit :: unit) :: date when date: date
  def beginning_of(date, unit) do
    _beginning_of(date, proceeding_units(unit))
  end

  @doc """
  Get the end of a period of a date.

  ## Examples

      iex> Crontab.DateHelper.end_of(~N[2016-03-14 01:45:45.123], :year)
      ~N[2016-12-31 23:59:59.999999]

      iex> Crontab.DateHelper.end_of(~U[2016-03-14 01:45:45.123Z], :year)
      ~U[2016-12-31 23:59:59.999999Z]

  """
  @spec end_of(date, unit :: unit) :: date when date: date
  def end_of(date, unit) do
    _end_of(date, proceeding_units(unit))
  end

  @doc """
  Find last occurrence of weekday in month

  ### Examples:

      iex> Crontab.DateHelper.last_weekday(~N[2016-03-14 01:45:45.123], 6)
      26

      iex> Crontab.DateHelper.last_weekday(~U[2016-03-14 01:45:45.123Z], 6)
      26

  """
  @spec last_weekday(date :: date, day_of_week :: Calendar.day_of_week()) :: Calendar.day()
  def last_weekday(date, weekday) do
    date
    |> end_of(:month)
    |> last_weekday(weekday, :end)
  end

  @doc """
  Find nth weekday of month

  ### Examples:

      iex> Crontab.DateHelper.nth_weekday(~N[2016-03-14 01:45:45.123], 6, 2)
      12

      iex> Crontab.DateHelper.nth_weekday(~U[2016-03-14 01:45:45.123Z], 6, 2)
      12

  """
  @spec nth_weekday(date :: date, weekday :: Calendar.day_of_week(), n :: pos_integer) ::
          Calendar.day() | nil
  def nth_weekday(%{month: month} = date, weekday, n),
    do: find_nth_weekday(%{date | day: 1}, month, weekday, n)

  @doc """
  Find last occurrence of weekday in month

  ### Examples:

      iex> Crontab.DateHelper.last_weekday_of_month(~N[2016-03-14 01:45:45.123])
      31

      iex> Crontab.DateHelper.last_weekday_of_month(~U[2016-03-14 01:45:45.123Z])
      31

  """
  @spec last_weekday_of_month(date :: date()) :: Calendar.day()
  def last_weekday_of_month(date), do: last_weekday_of_month(end_of(date, :month), :end)

  @doc """
  Find next occurrence of weekday relative to date

  ### Examples:

      iex> Crontab.DateHelper.next_weekday_to(~N[2016-03-14 01:45:45.123])
      14

      iex> Crontab.DateHelper.next_weekday_to(~U[2016-03-14 01:45:45.123Z])
      14

  """
  @spec next_weekday_to(date :: date) :: Calendar.day()
  def next_weekday_to(date) do
    weekday = Date.day_of_week(date)
    next_day = shift(date, 1, :day)
    previous_day = shift(date, -1, :day)

    cond do
      weekday == 7 && next_day.month == date.month -> next_day.day
      weekday == 7 -> shift(date, -2, :day).day
      weekday == 6 && previous_day.month == date.month -> previous_day.day
      weekday == 6 -> shift(date, 2, :day).day
      true -> date.day
    end
  end

  @doc """
  Increment Year

  ### Examples:

      iex> Crontab.DateHelper.inc_year(~N[2016-03-14 01:45:45.123])
      ~N[2017-03-14 01:45:45.123]

      iex> Crontab.DateHelper.inc_year(~U[2016-03-14 01:45:45.123Z])
      ~U[2017-03-14 01:45:45.123Z]

  """
  @spec inc_year(date) :: date when date: date
  def inc_year(%{month: 2, day: 29} = date), do: shift(date, 365, :day)

  def inc_year(%{month: month} = date) do
    candidate = shift(date, 365, :day)
    date_leap_year_before_mar? = Date.leap_year?(date) and month < 3
    candidate_leap_year_after_feb? = Date.leap_year?(candidate) and month > 2
    adjustment = if candidate_leap_year_after_feb? or date_leap_year_before_mar?, do: 1, else: 0
    shift(candidate, adjustment, :day)
  end

  @doc """
  Decrement Year

  ### Examples:

      iex> Crontab.DateHelper.dec_year(~N[2016-03-14 01:45:45.123])
      ~N[2015-03-14 01:45:45.123]

      iex> Crontab.DateHelper.dec_year(~U[2016-03-14 01:45:45.123Z])
      ~U[2015-03-14 01:45:45.123Z]

  """
  @spec dec_year(date) :: date when date: date
  def dec_year(%{month: 2, day: 29} = date), do: shift(date, -366, :day)

  def dec_year(%{month: month} = date) do
    candidate = shift(date, -365, :day)
    date_leap_year_after_mar? = Date.leap_year?(date) and month > 2
    candidate_leap_year_before_feb? = Date.leap_year?(candidate) and month < 3
    adjustment = if date_leap_year_after_mar? or candidate_leap_year_before_feb?, do: -1, else: 0
    shift(candidate, adjustment, :day)
  end

  @doc """
  Increment Month

  ### Examples:

      iex> Crontab.DateHelper.inc_month(~N[2016-03-14 01:45:45.123])
      ~N[2016-04-01 01:45:45.123]

      iex> Crontab.DateHelper.inc_month(~U[2016-03-14 01:45:45.123Z])
      ~U[2016-04-01 01:45:45.123Z]

  """
  @spec inc_month(date) :: date when date: date
  def inc_month(%{year: year, month: month, day: day} = date) do
    days =
      year
      |> Date.new!(month, day)
      |> Date.days_in_month()

    shift(date, days + 1 - day, :day)
  end

  @doc """
  Decrement Month

  ### Examples:

      iex> Crontab.DateHelper.dec_month(~N[2016-03-14 01:45:45.123])
      ~N[2016-02-14 01:45:45.123]

      iex> Crontab.DateHelper.dec_month(~U[2016-03-14 01:45:45.123Z])
      ~U[2016-02-14 01:45:45.123Z]

      iex> Crontab.DateHelper.dec_month(~N[2011-05-31 23:59:59])
      ~N[2011-04-30 23:59:59]

  """
  @spec dec_month(date) :: date when date: date
  def dec_month(%{year: year, month: month, day: day} = date) do
    days_in_last_month = year |> Date.new!(month, 1) |> Date.add(-1) |> Date.days_in_month()
    shift(date, -(day + max(days_in_last_month - day, 0)), :day)
  end

  @spec _beginning_of(date, [{unit, {any, any}}]) :: date when date: date
  defp _beginning_of(date, [{unit, {lower, _}} | tail]) do
    _beginning_of(Map.put(date, unit, lower), tail)
  end

  defp _beginning_of(date, []), do: date

  @spec _end_of(date, [{unit, {any, any}}]) :: date when date: date
  defp _end_of(date, [{unit, {_, :end_of_month}} | tail]) do
    upper = Date.days_in_month(date)
    _end_of(Map.put(date, unit, upper), tail)
  end

  defp _end_of(date, [{unit, {_, upper}} | tail]) do
    _end_of(Map.put(date, unit, upper), tail)
  end

  defp _end_of(date, []), do: date

  @spec proceeding_units(unit) :: [{unit, {any, any}}]
  defp proceeding_units(unit) do
    [_ | units] =
      @units
      |> Enum.reduce([], fn {key, value}, acc ->
        cond do
          Enum.count(acc) > 0 ->
            [{key, value} | acc]

          key == unit ->
            [{key, value}]

          true ->
            []
        end
      end)
      |> Enum.reverse()

    units
  end

  @spec find_nth_weekday(
          date :: date,
          month :: Calendar.month(),
          weekday :: Calendar.day_of_week(),
          n :: non_neg_integer()
        ) :: Calendar.day() | nil
  defp find_nth_weekday(%{month: month} = date, month, weekday, n) do
    modifier =
      if Date.day_of_week(date) == weekday,
        do: n - 1,
        else: n

    if modifier == 0,
      do: date.day,
      else: find_nth_weekday(shift(date, 1, :day), month, weekday, modifier)
  end

  defp find_nth_weekday(_, _, _, _), do: nil

  @spec last_weekday_of_month(date :: date(), position :: :end) :: Calendar.day()
  defp last_weekday_of_month(%{day: day} = date, :end) do
    if Date.day_of_week(date) > 5 do
      last_weekday_of_month(shift(date, -1, :day), :end)
    else
      day
    end
  end

  @spec last_weekday(date :: date, weekday :: Calendar.day_of_week(), position :: :end) ::
          Calendar.day()
  defp last_weekday(%{day: day} = date, weekday, :end) do
    if Date.day_of_week(date) == weekday do
      day
    else
      last_weekday(shift(date, -1, :day), weekday, :end)
    end
  end

  @doc false
  @spec shift(date, integer, unit, ambiguity_opts) :: date
  def shift(dt, amt, unit, ambiguity_opts \\ [])

  def shift(%NaiveDateTime{} = dt, amt, unit, _), do: NaiveDateTime.add(dt, amt, unit)

  def shift(dt, amt, unit, _) when unit == :day do
    candidate = DateTime.add(dt, amt, unit)

    cond do
      dt.std_offset == candidate.std_offset ->
        candidate

      dt.std_offset < candidate.std_offset ->
        DateTime.add(candidate, -candidate.std_offset, :second)

      true ->
        DateTime.add(candidate, dt.std_offset, :second)
    end
  end

  def shift(dt, amt, unit, ambiguity_opts) do
    case DateTime.from_naive(DateTime.add(dt, amt, unit), dt.time_zone) do
      {:ambiguous, earlier, later} ->
        resolve_ambiguity(
          DateTime.before?(dt, earlier),
          earlier,
          later,
          amt,
          unit,
          ambiguity_opts
        )

      {:ok, candidate} ->
        candidate
    end
  end

  def resolve_ambiguity(_, _, later, _, _, [:subsequent]), do: later
  def resolve_ambiguity(true, earlier, _, _, _, [:prior, :subsequent]), do: earlier
  def resolve_ambiguity(false, _, later, _, _, [:prior, :subsequent]), do: later
  def resolve_ambiguity(true, earlier, _, _, _, [:prior]), do: earlier

  def resolve_ambiguity(false, _, later, amt, unit, [:prior] = opts),
    do: shift(later, amt, unit, opts)

  def resolve_ambiguity(_, _, later, amt, unit, []), do: shift(later, amt, unit, [])
end
