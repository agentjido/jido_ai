defmodule Crontab.Scheduler do
  @moduledoc """
  This module provides the functionality to retrieve the next run date or the
  previous run date from a `%CronExpression{}`.
  """

  import Crontab.DateChecker

  alias Crontab.CronExpression
  alias Crontab.DateHelper

  @typep maybe(success, error) :: {:ok, success} | {:error, error}
  @typep ambiguity_opts :: [CronExpression.ambiguity_opt()]

  @type date :: DateTime.t() | NaiveDateTime.t()
  @type direction :: :increment | :decrement
  @type result :: maybe(date, any)

  @max_runs Application.compile_env(:crontab, :max_runs, 10_000)

  @doc """
  This function provides the functionality to retrieve the next run date from a
  `%Crontab.CronExpression{}`.

  ## Examples

      iex> Crontab.Scheduler.get_next_run_date(%Crontab.CronExpression{}, ~N[2002-01-13 23:00:07])
      {:ok, ~N[2002-01-13 23:01:00]}

      iex> Crontab.Scheduler.get_next_run_date(
      ...>   %Crontab.CronExpression{year: [{:/, :*, 9}]},
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      {:ok, ~N[2007-01-01 00:00:00]}

      iex> Crontab.Scheduler.get_next_run_date(%Crontab.CronExpression{reboot: true})
      ** (RuntimeError) Special identifier @reboot is not supported.

  """
  @spec get_next_run_date(CronExpression.t(), date, integer) :: result
  def get_next_run_date(cron_expression, date \\ NaiveDateTime.utc_now(), max_runs \\ @max_runs)

  def get_next_run_date(%CronExpression{reboot: true}, _, _),
    do: raise("Special identifier @reboot is not supported.")

  def get_next_run_date(
        %CronExpression{extended: false, on_ambiguity: ambiguity_opts} = cron_expression,
        date,
        max_runs
      ) do
    case get_run_date(
           cron_expression,
           clean_date(date, :seconds, ambiguity_opts),
           max_runs,
           :increment,
           ambiguity_opts
         ) do
      {:ok, date} -> {:ok, date}
      {:error, _} = error -> error
    end
  end

  def get_next_run_date(
        %CronExpression{extended: true, on_ambiguity: ambiguity_opts} = cron_expression,
        date,
        max_runs
      ) do
    get_run_date(
      cron_expression,
      clean_date(date, :microseconds, ambiguity_opts),
      max_runs,
      :increment,
      ambiguity_opts
    )
  end

  @doc """
  This function provides the functionality to retrieve the next run date from a
  `%Crontab.CronExpression{}`.

  ### Examples

      iex> Crontab.Scheduler.get_next_run_date!(%Crontab.CronExpression{}, ~N[2002-01-13 23:00:07])
      ~N[2002-01-13 23:01:00]

      iex> Crontab.Scheduler.get_next_run_date!(
      ...>   %Crontab.CronExpression{year: [1990]},
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      ** (RuntimeError) No compliant date was found for your interval.

      iex> Crontab.Scheduler.get_next_run_date!(
      ...>   %Crontab.CronExpression{year: [{:/, :*, 9}]},
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      ~N[2007-01-01 00:00:00]

      iex> Crontab.Scheduler.get_next_run_date!(%Crontab.CronExpression{reboot: true})
      ** (RuntimeError) Special identifier @reboot is not supported.

  """
  @spec get_next_run_date!(CronExpression.t(), date, integer) :: date
  def get_next_run_date!(cron_expression, date \\ NaiveDateTime.utc_now(), max_runs \\ @max_runs) do
    case get_next_run_date(cron_expression, date, max_runs) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Find the next execution dates relative to a given date from a `%CronExpression{}`.

  ## Examples

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_next_run_dates(
      ...>     %Crontab.CronExpression{extended: true},
      ...>     ~N[2016-12-17 00:00:00]
      ...>   ),
      ...>   3
      ...> )
      [
        ~N[2016-12-17 00:00:00],
        ~N[2016-12-17 00:00:01],
        ~N[2016-12-17 00:00:02]
      ]

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_next_run_dates(
      ...>     %Crontab.CronExpression{},
      ...>     ~N[2016-12-17 00:00:00]
      ...>   ),
      ...>   3
      ...> )
      [
        ~N[2016-12-17 00:00:00],
        ~N[2016-12-17 00:01:00],
        ~N[2016-12-17 00:02:00]
      ]

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_next_run_dates(
      ...>     %Crontab.CronExpression{
      ...>       year: [2017],
      ...>       month: [1],
      ...>       day: [1],
      ...>       hour: [0],
      ...>       minute: [1]
      ...>     },
      ...>     ~N[2016-12-17 00:00:00]
      ...>   ),
      ...>   3
      ...> )
      [~N[2017-01-01 00:01:00]]

      iex> Enum.take(Crontab.Scheduler.get_next_run_dates(%Crontab.CronExpression{reboot: true}), 3)
      ** (RuntimeError) Special identifier @reboot is not supported.

  """
  @spec get_next_run_dates(CronExpression.t(), date) :: Enumerable.t()
  def get_next_run_dates(cron_expression, date \\ NaiveDateTime.utc_now())

  def get_next_run_dates(%CronExpression{extended: false, on_ambiguity: opts} = cron_expr, date),
    do: _get_next_run_dates(cron_expr, date, &DateHelper.shift(&1, 1, :minute, opts))

  def get_next_run_dates(%CronExpression{extended: true, on_ambiguity: opts} = cron_expr, date),
    do: _get_next_run_dates(cron_expr, date, &DateHelper.shift(&1, 1, :second, opts))

  @spec _get_next_run_dates(CronExpression.t(), date(), function) :: Enumerable.t()
  defp _get_next_run_dates(cron_expression, date, advance_date) do
    Stream.unfold(date, fn previous_date ->
      case get_next_run_date(cron_expression, previous_date) do
        {:ok, new_date} -> {new_date, advance_date.(new_date)}
        _ -> nil
      end
    end)
  end

  @doc """
  This function provides the functionality to retrieve the previous run date
  from a `%Crontab.CronExpression{}`.

  ## Examples

      iex> Crontab.Scheduler.get_previous_run_date(
      ...>   %Crontab.CronExpression{},
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      {:ok, ~N[2002-01-13 23:00:00]}

      iex> Crontab.Scheduler.get_previous_run_date(
      ...>   %Crontab.CronExpression{
      ...>     year: [{:/, :*, 9}]
      ...>   },
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      {:ok, ~N[1998-12-31 23:59:00]}

      iex> Crontab.Scheduler.get_previous_run_date(%Crontab.CronExpression{reboot: true})
      ** (RuntimeError) Special identifier @reboot is not supported.

  """
  @spec get_previous_run_date(CronExpression.t(), date, integer) :: result
  def get_previous_run_date(cron_expr, date \\ NaiveDateTime.utc_now(), max_runs \\ @max_runs)

  def get_previous_run_date(%CronExpression{reboot: true}, _, _),
    do: raise("Special identifier @reboot is not supported.")

  def get_previous_run_date(
        %CronExpression{extended: false, on_ambiguity: ambiguity_opts} = cron_expr,
        date,
        max_runs
      ) do
    case get_run_date(cron_expr, date, max_runs, :decrement, ambiguity_opts) do
      {:ok, date} -> {:ok, DateHelper.beginning_of(date, :minute)}
      {:error, _} = error -> error
    end
  end

  def get_previous_run_date(
        %CronExpression{extended: true, on_ambiguity: ambiguity_opts} = cron_expr,
        date,
        max_runs
      ) do
    get_run_date(cron_expr, date, max_runs, :decrement, ambiguity_opts)
  end

  @doc """
  This function provides the functionality to retrieve the previous run date
  from a `%Crontab.CronExpression{}`.

  ## Examples

      iex> Crontab.Scheduler.get_previous_run_date!(
      ...>   %Crontab.CronExpression{},
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      ~N[2002-01-13 23:00:00]

      iex> Crontab.Scheduler.get_previous_run_date!(
      ...>   %Crontab.CronExpression{year: [2100]},
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      ** (RuntimeError) No compliant date was found for your interval.

      iex> Crontab.Scheduler.get_previous_run_date!(
      ...>   %Crontab.CronExpression{
      ...>     year: [{:/, :*, 9}]
      ...>   },
      ...>   ~N[2002-01-13 23:00:07]
      ...> )
      ~N[1998-12-31 23:59:00]

      iex> Crontab.Scheduler.get_previous_run_date!(%Crontab.CronExpression{reboot: true})
      ** (RuntimeError) Special identifier @reboot is not supported.

  """
  @spec get_previous_run_date!(CronExpression.t(), date, integer) :: date
  def get_previous_run_date!(
        cron_expression,
        date \\ NaiveDateTime.utc_now(),
        max_runs \\ @max_runs
      ) do
    case get_previous_run_date(cron_expression, date, max_runs) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Find the previous n execution dates relative to a given date from a `%CronExpression{}`.

  ## Examples

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_previous_run_dates(
      ...>     %Crontab.CronExpression{extended: true},
      ...>     ~N[2016-12-17 00:00:00]
      ...>   ),
      ...>   3
      ...> )
      [
        ~N[2016-12-17 00:00:00],
        ~N[2016-12-16 23:59:59],
        ~N[2016-12-16 23:59:58]
      ]

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_previous_run_dates(
      ...>     %Crontab.CronExpression{},
      ...>     ~N[2016-12-17 00:00:00]
      ...>   ),
      ...>   3
      ...> )
      [
        ~N[2016-12-17 00:00:00],
        ~N[2016-12-16 23:59:00],
        ~N[2016-12-16 23:58:00]
      ]

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_previous_run_dates(
      ...>     %Crontab.CronExpression{
      ...>       year: [2017],
      ...>       month: [1],
      ...>       day: [1],
      ...>       hour: [0],
      ...>       minute: [1]
      ...>     },
      ...>     ~N[2016-12-17 00:00:00]
      ...>   ),
      ...>   3
      ...> )
      []

      iex> Enum.take(
      ...>   Crontab.Scheduler.get_previous_run_dates(%Crontab.CronExpression{reboot: true}),
      ...>   3
      ...> )
      ** (RuntimeError) Special identifier @reboot is not supported.

  """
  @spec get_previous_run_dates(CronExpression.t(), date) :: Enumerable.t()
  def get_previous_run_dates(cron_expression, date \\ NaiveDateTime.utc_now())

  def get_previous_run_dates(
        %CronExpression{extended: false, on_ambiguity: ambiguity_opts} = cron_expr,
        date
      ) do
    _get_previous_run_dates(cron_expr, date, &DateHelper.shift(&1, -1, :minute, ambiguity_opts))
  end

  def get_previous_run_dates(
        %CronExpression{extended: true, on_ambiguity: ambiguity_opts} = cron_expression,
        date
      ) do
    _get_previous_run_dates(
      cron_expression,
      date,
      &DateHelper.shift(&1, -1, :second, ambiguity_opts)
    )
  end

  @spec _get_previous_run_dates(CronExpression.t(), NaiveDateTime.t(), function) :: Enumerable.t()
  defp _get_previous_run_dates(cron_expression, date, advance_date) do
    Stream.unfold(date, fn previous_date ->
      case get_previous_run_date(cron_expression, previous_date) do
        {:ok, new_date} -> {new_date, advance_date.(new_date)}
        _ -> nil
      end
    end)
  end

  @spec get_run_date(
          CronExpression.t() | CronExpression.condition_list(),
          date,
          integer,
          direction,
          ambiguity_opts
        ) :: result
  defp get_run_date(_, _, 0, _, _) do
    {:error, "No compliant date was found for your interval."}
  end

  defp get_run_date(
         %CronExpression{extended: false} = cron_expression,
         date,
         max_runs,
         direction,
         ambiguity_opts
       ) do
    cron_expression
    |> CronExpression.to_condition_list()
    |> Keyword.delete(:ambiguity_opts)
    |> Enum.reverse()
    |> get_run_date(DateHelper.beginning_of(date, :minute), max_runs, direction, ambiguity_opts)
  end

  defp get_run_date(
         %CronExpression{extended: true} = cron_expression,
         date,
         max_runs,
         direction,
         ambiguity_opts
       ) do
    cron_expression
    |> CronExpression.to_condition_list()
    |> Keyword.delete(:ambiguity_opts)
    |> Enum.reverse()
    |> get_run_date(DateHelper.beginning_of(date, :second), max_runs, direction, ambiguity_opts)
  end

  defp get_run_date(conditions, date, max_runs, direction, ambiguity_opts) do
    case search_and_correct_date(conditions, date, direction, ambiguity_opts) do
      {:ok, corrected_date} ->
        {:ok, corrected_date}

      {:error, :impossible} ->
        {:error, "No compliant date was found for your interval."}

      {:error, {:not_found, corrected_date}} ->
        get_run_date(conditions, corrected_date, max_runs - 1, direction, ambiguity_opts)
    end
  end

  @spec search_and_correct_date(CronExpression.condition_list(), date, direction, ambiguity_opts) ::
          maybe(date, {:not_found, date} | :impossible)

  defp search_and_correct_date([{:year, [target_year]} | _], %{year: from_year}, :increment, _)
       when is_integer(target_year) and target_year < from_year do
    {:error, :impossible}
  end

  defp search_and_correct_date([{:year, [target_year]} | _], %{year: from_year}, :decrement, _)
       when is_integer(target_year) and target_year > from_year do
    {:error, :impossible}
  end

  defp search_and_correct_date([{interval, conditions} | tail], date, direction, ambiguity_opts) do
    if matches_date?(interval, conditions, date, ambiguity_opts) do
      search_and_correct_date(tail, date, direction, ambiguity_opts)
    else
      case correct_date(interval, date, direction, ambiguity_opts) do
        {:ok, corrected_date} ->
          {:error, {:not_found, corrected_date}}

        # Prevent to reach lower bound (year 0)
        {:error, _} ->
          {:error, {:not_found, date}}
      end
    end
  end

  defp search_and_correct_date([], date, _, _), do: {:ok, date}

  @spec correct_date(CronExpression.interval(), date, direction, ambiguity_opts) ::
          maybe(NaiveDateTime.t(), any)

  defp correct_date(:second, date, :increment, ambiguity_opts),
    do: {:ok, DateHelper.shift(date, 1, :second, ambiguity_opts)}

  defp correct_date(:minute, date, :increment, ambiguity_opts),
    do:
      {:ok,
       date |> DateHelper.shift(1, :minute, ambiguity_opts) |> DateHelper.beginning_of(:minute)}

  defp correct_date(:hour, date, :increment, ambiguity_opts),
    do:
      {:ok, date |> DateHelper.shift(1, :hour, ambiguity_opts) |> DateHelper.beginning_of(:hour)}

  defp correct_date(:day, date, :increment, ambiguity_opts),
    do: {:ok, date |> DateHelper.shift(1, :day, ambiguity_opts) |> DateHelper.beginning_of(:day)}

  defp correct_date(:month, date, :increment, _ambiguity_opts),
    do: {:ok, date |> DateHelper.inc_month() |> DateHelper.beginning_of(:month)}

  defp correct_date(:weekday, date, :increment, ambiguity_opts),
    do: {:ok, date |> DateHelper.shift(1, :day, ambiguity_opts) |> DateHelper.beginning_of(:day)}

  defp correct_date(:year, %{year: 9_999}, :increment, _ambiguity_opts),
    do: {:error, :upper_bound}

  defp correct_date(:year, date, :increment, _ambiguity_opts),
    do: {:ok, date |> DateHelper.inc_year() |> DateHelper.beginning_of(:year)}

  defp correct_date(:second, date, :decrement, ambiguity_opts),
    do:
      {:ok,
       date |> DateHelper.shift(-1, :second, ambiguity_opts) |> DateHelper.beginning_of(:second)}

  defp correct_date(:minute, date, :decrement, ambiguity_opts),
    do:
      {:ok,
       date
       |> DateHelper.shift(-1, :minute, ambiguity_opts)
       |> DateHelper.end_of(:minute)
       |> DateHelper.beginning_of(:second)}

  defp correct_date(:hour, date, :decrement, ambiguity_opts),
    do:
      {:ok,
       date
       |> DateHelper.shift(-1, :hour, ambiguity_opts)
       |> DateHelper.end_of(:hour)
       |> DateHelper.beginning_of(:second)}

  defp correct_date(:day, date, :decrement, ambiguity_opts),
    do:
      {:ok,
       date
       |> DateHelper.shift(-1, :day, ambiguity_opts)
       |> DateHelper.end_of(:day)
       |> DateHelper.beginning_of(:second)}

  defp correct_date(:month, date, :decrement, _ambiguity_opts),
    do:
      {:ok,
       date
       |> DateHelper.dec_month()
       |> DateHelper.end_of(:month)
       |> DateHelper.beginning_of(:second)}

  defp correct_date(:weekday, date, :decrement, ambiguity_opts),
    do:
      {:ok,
       date
       |> DateHelper.shift(-1, :day, ambiguity_opts)
       |> DateHelper.end_of(:day)
       |> DateHelper.beginning_of(:second)}

  defp correct_date(:year, %{year: 0}, :decrement, _), do: {:error, :lower_bound}

  defp correct_date(:year, date, :decrement, _ambiguity_opts),
    do:
      {:ok,
       date
       |> DateHelper.dec_year()
       |> DateHelper.end_of(:year)
       |> DateHelper.beginning_of(:second)}

  @spec clean_date(date, :seconds | :microseconds, ambiguity_opts) :: date
  defp clean_date(%{microsecond: {0, _}} = date, :microseconds, _), do: date

  defp clean_date(date, :microseconds, ambiguity_opts) do
    date
    |> Map.put(:microsecond, {0, 0})
    |> DateHelper.shift(1, :second, ambiguity_opts)
  end

  defp clean_date(date, :seconds, ambiguity_opts) do
    clean_microseconds = clean_date(date, :microseconds, ambiguity_opts)

    case clean_microseconds do
      %{second: 0} -> clean_microseconds
      _ -> DateHelper.shift(clean_microseconds, 1, :minute, ambiguity_opts)
    end
  end
end
