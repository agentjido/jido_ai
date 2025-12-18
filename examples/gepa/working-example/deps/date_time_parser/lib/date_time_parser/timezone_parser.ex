defmodule DateTimeParser.TimezoneParser do
  @moduledoc false
  @sources [
    "priv/tzdata2022g/africa",
    "priv/tzdata2022g/antarctica",
    "priv/tzdata2022g/asia",
    "priv/tzdata2022g/australasia",
    "priv/tzdata2022g/etcetera",
    "priv/tzdata2022g/europe",
    "priv/tzdata2022g/northamerica",
    "priv/tzdata2022g/southamerica",
    "priv/tzdata2022g/backward"
  ]
  for source <- @sources, do: @external_resource(source)

  defmodule Zone do
    @moduledoc false
    defstruct [
      :name,
      :utc_offset_sec,
      :utc_offset_hrs,
      :from,
      :until,
      abbreviations: [],
      aliases: []
    ]
  end

  defmodule Rule do
    @moduledoc false
    defstruct [:name, :from, :until, :save, :letter]
  end

  defimpl Inspect, for: Zone do
    import Inspect.Algebra

    def inspect(zone, _opts) do
      concat(["#<TimeZone ", zone.name, " (", zone.utc_offset_hrs, ")", ">"])
    end
  end

  defimpl Inspect, for: Rule do
    import Inspect.Algebra

    def inspect(rule, opts) do
      concat([
        "#<TimeZoneRule ",
        rule.name,
        " ",
        to_doc(rule.from, opts),
        " - ",
        to_doc(rule.until, opts),
        " ",
        to_doc(rule.save, opts),
        ">"
      ])
    end
  end

  def parse(spec \\ read_file()) do
    zones = :ets.new(:zones, [:bag])
    rules = :ets.new(:rules, [:bag])
    parse(String.split(spec, "\n"), %{zones: zones, rules: rules})
  end

  def parse([], meta) do
    spec = [{{:_, :"$1"}, [], [:"$1"]}]
    {:ets.select(meta[:zones], spec), :ets.select(meta[:rules], spec)}
  end

  def parse([empty | rest], meta) when empty in ["#", nil, "", "\n"],
    do: parse(rest, meta)

  def parse(["#" <> _line | rest], meta),
    do: parse(rest, meta)

  def parse(["\n" | rest], meta),
    do: parse(rest, meta)

  def parse(["" | rest], meta),
    do: parse(rest, meta)

  @min ~N[0000-01-01T00:00:00]
  @max ~N[9999-12-31T23:59:59]
  def parse(["Zone" <> line | rest], meta) do
    line = remove_comments(line)
    [name, utcoff, rule, format | until] = String.split(line, ~r/\s/, trim: true, parts: 5)

    until =
      if until && Enum.any?(until), do: String.split(clean(List.first(until)), ~r/\s/, trim: true)

    from =
      case meta[:last] do
        %Zone{} = zone -> zone.until
        _ -> @min
      end

    until = to_dt(until) || @max
    rule_name = clean(rule)
    zone_rules = find_rules(meta[:rules], rule_name, from, until)
    format = clean(format)
    utc_time = utcoff |> clean() |> to_time()

    zone = %Zone{
      name: clean(name),
      utc_offset_sec: to_seconds_after_midnight(utc_time),
      utc_offset_hrs: to_offset(utc_time),
      abbreviations:
        zone_rules
        |> Enum.filter(& &1.letter)
        |> Enum.map(&String.replace(format, "%s", &1.letter))
        |> add_root_abbreviation(format)
        |> Enum.uniq(),
      from: if(from != @min, do: from),
      until: if(until != @max, do: until)
    }

    :ets.insert(meta[:zones], {zone.name, zone})

    parse(rest, Map.put(meta, :last, zone))
  end

  def parse(["Rule" <> line | rest], meta) do
    line = remove_comments(line)

    [name, from_year, to_year, _, mon, on, at, save, letter] =
      String.split(line, ~r/\t/, parts: 9)

    from_ndt = to_dt([clean(from_year), clean(mon), clean(on), clean(at)])

    to_year =
      case to_year do
        "only" -> from_year
        "max" -> "9999"
        v -> v
      end

    to_ndt =
      if clean(to_year) == :infinity,
        do: :infinity,
        else: to_dt([clean(to_year), mon, clean(on), clean(at)])

    rule = %Rule{
      name: name,
      from: from_ndt,
      until: to_ndt,
      save: save |> clean() |> to_time() |> to_seconds_after_midnight(),
      letter: clean(letter)
    }

    :ets.insert(meta[:rules], {rule.name, rule})

    parse(rest, Map.put(meta, :last, rule))
  end

  def parse(["Link" <> line | rest], meta) do
    line = remove_comments(line)
    [target, name] = String.split(line, ~r/\s/, trim: true, parts: 2)
    link_name = clean(name)
    target = clean(target)
    matching = :ets.lookup(meta[:zones], target)

    Enum.each(matching, fn {name, zone} ->
      if link_name not in zone.aliases and zone.name != link_name do
        :ets.delete_object(meta[:zones], {name, zone})
        :ets.insert(meta[:zones], {zone.name, %{zone | aliases: [link_name | zone.aliases]}})
      end
    end)

    parse(rest, Map.delete(meta, :last))
  end

  def parse([line | rest], meta) do
    line = remove_comments(line)

    cond do
      line == "" ->
        parse(rest, meta)

      %Zone{} = last_zone = meta[:last] ->
        parse(["Zone\t#{last_zone.name}\t" <> line | rest], meta)
    end
  end

  defp add_root_abbreviation(abbrevations, format) do
    if String.contains?(format, "%s") do
      abbrevations
    else
      Enum.concat(abbrevations, [format])
    end
  end

  defp find_rules(_rules, nil, _from, _until), do: []

  defp find_rules(rules, rule_name, from, until) do
    rules = :ets.lookup(rules, rule_name)

    Enum.reduce(rules, [], fn {_, rule}, acc ->
      if rule_name == rule.name and
           not (NaiveDateTime.compare(rule.until, from || @min) == :lt or
                  NaiveDateTime.compare(rule.from, until || @max) == :gt) do
        [rule | acc]
      else
        acc
      end
    end)
  end

  @mapping %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }
  for {m, n} <- @mapping do
    defp short_month_to_n(unquote(m)), do: unquote(n)
  end

  defp to_dt(nil), do: nil

  defp to_dt([year]) do
    {year, ""} = Integer.parse(year)
    NaiveDateTime.new!(Date.new!(year, 1, 1), Time.new!(0, 0, 0))
  end

  defp to_dt([year, month]) do
    {year, ""} = Integer.parse(year)
    NaiveDateTime.new!(Date.new!(year, short_month_to_n(month), 1), Time.new!(0, 0, 0))
  end

  defp to_dt([year, month, day]) do
    {year, ""} = Integer.parse(year)
    month = short_month_to_n(month)

    date = handle_kday(year, month, day)
    NaiveDateTime.new!(date, Time.new!(0, 0, 0))
  end

  defp to_dt([year, month, day, "24:00"]) do
    {year, ""} = Integer.parse(year)
    month = short_month_to_n(month)
    date = handle_kday(year, month, day)
    NaiveDateTime.new!(date, Time.new!(23, 59, 0))
  end

  defp to_dt([year, month, day, "24:00u"]) do
    {year, ""} = Integer.parse(year)
    month = short_month_to_n(month)
    date = handle_kday(year, month, day)
    DateTime.new!(date, Time.new!(23, 59, 0), "Etc/UTC")
  end

  defp to_dt([year, month, day, "24:00s"]) do
    {year, ""} = Integer.parse(year)
    month = short_month_to_n(month)
    date = handle_kday(year, month, day)
    NaiveDateTime.new!(date, Time.new!(23, 59, 0))
  end

  # Japan ? wat. kick it to the next day
  defp to_dt([year, "Sep", "Sat>=8", "25:00"]) do
    {year, ""} = Integer.parse(year)
    date = Date.new!(year, 9, 9)
    NaiveDateTime.new!(date, Time.new!(1, 0, 0))
  end

  defp to_dt([year, month, day, time]) do
    {year, ""} = Integer.parse(year)
    month = short_month_to_n(month)
    date = handle_kday(year, month, day)
    [hour, minute | second] = String.split(time, ":", parts: 3, trim: true)

    {second, ""} =
      if Enum.any?(second), do: second |> List.first() |> Integer.parse(), else: {0, ""}

    {hour, ""} = Integer.parse(hour)

    case Integer.parse(minute) do
      {minute, "u"} ->
        DateTime.new!(date, Time.new!(hour, minute, second), "Etc/UTC")

      {minute, note} when note in ["", "s"] ->
        NaiveDateTime.new!(date, Time.new!(hour, minute, second))
    end
  end

  defp handle_kday(year, month, "last" <> day) do
    year
    |> Date.new!(month, 1)
    |> Date.end_of_month()
    |> Kday.last_kday(day_of_week(day))
  end

  defp handle_kday(year, month, <<day_w::binary-size(3), ">=", day_n::binary>>) do
    kday = day_of_week(day_w)
    {day, ""} = Integer.parse(day_n)

    year
    |> Date.new!(month, day)
    |> Kday.kday_on_or_after(kday)
  end

  defp handle_kday(year, month, <<day_w::binary-size(3), "<=", day_n::binary>>) do
    kday = day_of_week(day_w)
    {day, ""} = Integer.parse(day_n)

    year
    |> Date.new!(month, day)
    |> Kday.kday_on_or_before(kday)
  end

  defp handle_kday(year, month, day) do
    {day, ""} = Integer.parse(day)
    Date.new!(year, month, day)
  end

  @mapping %{"Mon" => 1, "Tue" => 2, "Wed" => 3, "Thu" => 4, "Fri" => 5, "Sat" => 6, "Sun" => 7}
  for {d, n} <- @mapping do
    defp day_of_week(unquote(d)), do: unquote(n)
  end

  defp to_time(nil), do: nil
  defp to_time(0), do: 0
  defp to_time(time) when byte_size(time) == 1, do: to_time("0" <> time <> ":00:00")
  defp to_time("-" <> time) when byte_size(time) == 1, do: to_time("-0" <> time <> ":00:00")
  defp to_time(time) when byte_size(time) == 2, do: to_time(time <> ":00:00")
  defp to_time("+" <> time) when byte_size(time) == 2, do: to_time(time <> ":00:00")
  defp to_time("-" <> time) when byte_size(time) == 2, do: to_time("-" <> time <> ":00:00")
  defp to_time(time) when byte_size(time) in [4, 7], do: to_time("0" <> time)
  defp to_time(time) when byte_size(time) == 5, do: to_time(time <> ":00")
  defp to_time("-" <> time) when byte_size(time) == 5, do: to_time("-" <> time <> ":00")
  defp to_time("-" <> time) when byte_size(time) == 7, do: to_time("-0" <> time)
  defp to_time("-" <> time) when byte_size(time) == 8, do: {"-", Time.from_iso8601!(time)}
  defp to_time(time) when byte_size(time) == 8, do: {"+", Time.from_iso8601!(time)}

  defp to_offset({sign, time}) do
    [
      sign,
      String.pad_leading("#{time.hour}", 2, "0"),
      String.pad_leading("#{time.minute}", 2, "0")
    ]
    |> Enum.join()
  end

  defp to_seconds_after_midnight({"-", time}) do
    {seconds, _} = Time.to_seconds_after_midnight(time)
    -seconds
  end

  defp to_seconds_after_midnight({"+", time}) do
    {seconds, _} = Time.to_seconds_after_midnight(time)
    seconds
  end

  defp clean("-"), do: nil
  defp clean(""), do: nil
  defp clean(v) when is_binary(v), do: String.trim(v)
  defp clean(v), do: v

  defp read_file do
    Enum.map_join(@sources, "\n", &File.read!(Application.app_dir(:date_time_parser, &1)))
  end

  defp remove_comments(line),
    do: line |> String.split("#", trim: true, parts: 2) |> List.first() |> String.trim()
end
