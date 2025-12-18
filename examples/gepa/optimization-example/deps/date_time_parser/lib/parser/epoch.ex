defmodule DateTimeParser.Parser.Epoch do
  @moduledoc """
  Parses a Unix Epoch timestamp. This is gated by the number of present digits. It must contain 10
  or 11 seconds, with an optional subsecond up to 10 digits. Negative epoch timestamps are
  supported.
  """
  @behaviour DateTimeParser.Parser

  @max_subsecond_digits 6
  @one_second_in_microseconds (1 * :math.pow(10, 6)) |> trunc()
  @epoch_regex ~r|\A(?<sign>-)?(?<seconds>\d{10,11})(?:\.(?<subseconds>\d{1,10}))?\z|

  @impl DateTimeParser.Parser
  def preflight(%{string: string} = parser) do
    case Regex.named_captures(@epoch_regex, string) do
      nil -> {:error, :not_compatible}
      results -> {:ok, %{parser | preflight: results}}
    end
  end

  @impl DateTimeParser.Parser
  def parse(%{preflight: preflight} = parser) do
    %{"sign" => sign, "seconds" => raw_seconds, "subseconds" => raw_subseconds} = preflight
    is_negative = sign == "-"
    has_subseconds = raw_subseconds != ""

    with {:ok, seconds} <- parse_seconds(raw_seconds, is_negative, has_subseconds),
         {:ok, subseconds} <- parse_subseconds(raw_subseconds, is_negative) do
      from_tokens(parser, {seconds, subseconds})
    end
  end

  @spec parse_seconds(String.t(), boolean(), boolean()) ::
          {:ok, integer()}
  defp parse_seconds(raw_seconds, is_negative, has_subseconds)

  defp parse_seconds(raw_seconds, true, true) do
    with {:ok, seconds} <- parse_seconds(raw_seconds, true, false) do
      {:ok, seconds - 1}
    end
  end

  defp parse_seconds(raw_seconds, true, false) do
    with {:ok, seconds} <- parse_seconds(raw_seconds, false, false) do
      {:ok, seconds * -1}
    end
  end

  defp parse_seconds(raw_seconds, false, _) do
    with {seconds, ""} <- Integer.parse(raw_seconds) do
      {:ok, seconds}
    end
  end

  @spec parse_subseconds(String.t(), boolean()) :: {:ok, {integer(), integer()}}
  defp parse_subseconds("", _), do: {:ok, {0, 0}}

  defp parse_subseconds(raw_subseconds, true) do
    with {:ok, {truncated_microseconds, number_of_subsecond_digits}} <-
           parse_subseconds(raw_subseconds, false) do
      negative_truncated_microseconds =
        if truncated_microseconds > 0 do
          @one_second_in_microseconds - truncated_microseconds
        else
          truncated_microseconds
        end

      {:ok, {negative_truncated_microseconds, number_of_subsecond_digits}}
    end
  end

  defp parse_subseconds(raw_subseconds, false) do
    with {subseconds, ""} <- Float.parse("0.#{raw_subseconds}") do
      microseconds = (subseconds * :math.pow(10, 6)) |> trunc()
      precision = min(String.length(raw_subseconds), @max_subsecond_digits)

      truncated_microseconds =
        microseconds
        |> Integer.digits()
        |> Enum.take(@max_subsecond_digits)
        |> Integer.undigits()

      {:ok, {truncated_microseconds, precision}}
    end
  end

  defp from_tokens(%{context: context}, {seconds, {microseconds, precision}}) do
    truncated_microseconds =
      microseconds
      |> Integer.digits()
      |> Enum.take(@max_subsecond_digits)
      |> Integer.undigits()

    with {:ok, datetime} <- DateTime.from_unix(seconds) do
      for_context(context, %{datetime | microsecond: {truncated_microseconds, precision}})
    end
  end

  defp for_context(:best, result) do
    DateTimeParser.Parser.first_ok(
      [
        fn -> for_context(:datetime, result) end,
        fn -> for_context(:date, result) end,
        fn -> for_context(:time, result) end
      ],
      "cannot convert #{inspect(result)} to context :best"
    )
  end

  defp for_context(:datetime, datetime), do: {:ok, datetime}
  defp for_context(:date, datetime), do: {:ok, DateTime.to_date(datetime)}
  defp for_context(:time, datetime), do: {:ok, DateTime.to_time(datetime)}

  defp for_context(context, result) do
    {:error, "cannot convert #{inspect(result)} to context #{context}"}
  end
end
