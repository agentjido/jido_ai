defmodule Crontab.CronExpression.Composer do
  @moduledoc """
  Generate from `%CronExpression{}` to `* * * * * *`.
  """

  alias Crontab.CronExpression

  @type opts :: [
          skip_year: boolean
        ]

  @doc """
  Generate from `%Crontab.CronExpression{}` to `* * * * * *`.

  Available options:

    - skip_year: boolean
      If set to `true`, do not add the year to the expression.
      This means that `%Crontab.CronExpression{}` will return `* * * * *`.

  ## Examples

      iex> Crontab.CronExpression.Composer.compose(%Crontab.CronExpression{})
      "* * * * * *"

      iex> Crontab.CronExpression.Composer.compose(%Crontab.CronExpression{
      ...>   minute: [9, {:-, 4, 6}, {:/, :*, 9}]
      ...> })
      "9,4-6,*/9 * * * * *"

      iex> Crontab.CronExpression.Composer.compose(%Crontab.CronExpression{reboot: true})
      "@reboot"

      iex> Crontab.CronExpression.Composer.compose(%Crontab.CronExpression{}, skip_year: true)
      "* * * * *"

      iex> Crontab.CronExpression.Composer.compose(
      ...>   %Crontab.CronExpression{minute: [9, {:-, 4, 6}, {:/, :*, 9}]},
      ...>   skip_year: true
      ...> )
      "9,4-6,*/9 * * * *"
  """
  @spec compose(CronExpression.t()) :: binary
  @spec compose(CronExpression.t(), opts) :: binary
  def compose(cron_expression, opts \\ [])

  def compose(%CronExpression{reboot: true}, _) do
    "@reboot"
  end

  def compose(%CronExpression{} = cron_expression, opts) do
    cron_expression
    |> CronExpression.to_condition_list()
    |> compose_interval(Map.new(opts))
    |> Enum.join(" ")
  end

  @spec compose_interval(CronExpression.condition_list(), map) :: [binary]
  defp compose_interval([{:year, _} | tail], %{skip_year: true} = opts) do
    compose_interval(tail, opts)
  end

  defp compose_interval([{:ambiguity_opts, _} | tail], opts), do: compose_interval(tail, opts)

  defp compose_interval([{_, conditions} | tail], opts) do
    [
      Enum.map_join(conditions, ",", fn condition -> compose_condition(condition) end)
      | compose_interval(tail, opts)
    ]
  end

  defp compose_interval([], _), do: []

  @spec compose_condition(CronExpression.value()) :: binary
  defp compose_condition(:*), do: "*"
  defp compose_condition(:L), do: "L"
  defp compose_condition(:W), do: "W"
  defp compose_condition({:W, base}), do: compose_condition(base) <> "W"
  defp compose_condition({:L, base}), do: compose_condition(base) <> "L"

  defp compose_condition({:"#", weekday, n}),
    do: compose_condition(weekday) <> "#" <> compose_condition(n)

  defp compose_condition({:/, base, divider}),
    do: compose_condition(base) <> "/" <> Integer.to_string(divider)

  defp compose_condition({:-, min, max}),
    do: Integer.to_string(min) <> "-" <> Integer.to_string(max)

  defp compose_condition(number) when is_number(number), do: Integer.to_string(number)
end
