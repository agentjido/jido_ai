defmodule DateTimeParser.TimezoneAbbreviations do
  @moduledoc """
  Fetch timezone information by name or by abbreviations. This is designed
  to power parsing strings with timezone abbreviations and offsets in them.
  """

  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  @beginning_at Application.compile_env(
                  :date_time_parser,
                  :include_zones_from,
                  ~N[2020-01-01 00:00:00]
                )
  {zones, rules} = DateTimeParser.TimezoneParser.parse()

  @zones Enum.filter(zones, fn zone ->
           is_nil(zone.until) || NaiveDateTime.compare(zone.until, @beginning_at) == :gt
         end)

  @rules rules

  @default_offset_preferences %{
    "+0000" => "Etc/UTC",
    "+0100" => "Etc/GMT-1",
    "+0200" => "Etc/GMT-2",
    "+0300" => "Etc/GMT-3",
    "+0400" => "Etc/GMT-4",
    "+0500" => "Etc/GMT-5",
    "+0530" => "Asia/Colombo",
    "+0600" => "Etc/GMT-6",
    "+0700" => "Etc/GMT-7",
    "+0800" => "Etc/GMT-8",
    "+0900" => "Etc/GMT-9",
    "+0930" => "Australia/Adelaide",
    "+1000" => "Etc/GMT-10",
    "+1100" => "Etc/GMT-11",
    "+1200" => "Etc/GMT-12",
    "+1300" => "Etc/GMT-13",
    "+1400" => "Etc/GMT-14",
    "-0000" => "Etc/UTC",
    "-0100" => "Etc/GMT+1",
    "-0200" => "Etc/GMT+2",
    "-0300" => "Etc/GMT+3",
    "-0400" => "Etc/GMT+4",
    "-0500" => "Etc/GMT+5",
    "-0530" => "America/Belize",
    "-0600" => "Etc/GMT+6",
    "-0700" => "Etc/GMT+7",
    "-0800" => "Etc/GMT+8",
    "-0900" => "Etc/GMT+9",
    "-1000" => "Etc/GMT+10",
    "-1100" => "Etc/GMT+11"
  }

  @default_abbreviation_preferences %{
    # Preferred GMT where possible, then USA, otherwise most populous.
    "+01/+00" => "Africa/Casablanca",
    "+02" => "Etc/GMT-2",
    "+03" => "Etc/GMT-3",
    "+04" => "Etc/GMT-4",
    "+04/+05" => "Asia/Baku",
    "+05" => "Etc/GMT-5",
    "+06" => "Etc/GMT-6",
    "+07" => "Etc/GMT-7",
    "+08" => "Etc/GMT-8",
    "+08/+09" => "Asia/Ulaanbaatar",
    "+09" => "Etc/GMT-9",
    "+10" => "Etc/GMT-10",
    "+11" => "Etc/GMT-11",
    "+1130" => "Pacific/Norfolk",
    "+11/+12" => "Pacific/Noumea",
    "+12" => "Etc/GMT-12",
    "+1215" => "Pacific/Chatham",
    "+12/+13" => "Pacific/Fiji",
    "+13" => "Etc/GMT-13",
    "+13/+14" => "Pacific/Tongatapu",
    "+14" => "Etc/GMT-14",
    "-01" => "Etc/GMT+1",
    "-01/+00" => "Atlantic/Azores",
    "-02" => "Etc/GMT+2",
    "-02/-01" => "Europe/Lisbon",
    "-03" => "Etc/GMT+3",
    "-03/-02" => "America/Buenos_Aires",
    "-04" => "Etc/GMT+4",
    "-0430" => "America/Caracas",
    "-04/-03" => "America/Santiago",
    "-05" => "Etc/GMT+5",
    "-05/-04" => "America/Bogota",
    "-06/-05" => "Pacific/Galapagos",
    "-08" => "Etc/GMT+8",
    "-09" => "Etc/GMT+9",
    "-10" => "Etc/GMT+10",
    "-11" => "Etc/GMT+11",
    # Australia
    "AWST" => "Australia/Perth",
    "ACWST" => "Australia/Eucla",
    "ACT" => "Australia/Adelaide",
    "ACDT" => "Australia/Adelaide",
    "ACST" => "Australia/Adelaide",
    "CAST" => "Australia/Adelaide",
    "AET" => "Australia/Sydney",
    "AEST" => "Australia/Sydney",
    "AEDT" => "Australia/Sydney",
    "LHDT" => "Australia/Lord_Howe",
    "NZMT" => "Pacific/Auckland",
    "NZDT" => "Pacific/Auckland",
    "HMT" => "Etc/GMT+5",
    "PMMT" => "Pacific/Bougainville",
    # Americas
    "EMT" => "Pacific/Easter",
    "QMT" => "America/Guayaquil",
    "NDDT" => "Canada/Newfoundland",
    "NWT" => "Canada/Newfoundland",
    "ADT" => "America/Halifax",
    "AWT" => "America/Halifax",
    "ADDT" => "America/Goose_Bay",
    "PPMT" => "America/Port-au-Prince",
    "ALASKA" => "America/New_York",
    "AST" => "Canada/Atlantic",
    "APT" => "Canada/Atlantic",
    "YDT" => "Canada/Yukon",
    "YST" => "Canada/Yukon",
    "YDDT" => "Canada/Yukon",
    "CHST" => "Pacific/Guam",
    "AHST" => "America/Anchorage",
    "AHDT" => "America/Anchorage",
    "YWT" => "Canada/Yukon",
    "YPT" => "Canada/Yukon",
    "AKDT" => "America/Anchorage",
    "AKST" => "America/Anchorage",
    "CENTRAL" => "America/Chicago",
    "CDT" => "America/Chicago",
    "SJMT" => "America/Costa_Rica",
    "CST" => "America/Chicago",
    "CT" => "America/Chicago",
    "CWT" => "America/Belize",
    "CPT" => "America/Belize",
    "CMT" => "America/Buenos_Aires",
    "EASTERN" => "America/New_York",
    "EDT" => "America/New_York",
    "EST" => "America/New_York",
    "ET" => "America/New_York",
    "HAWAII" => "America/New_York",
    "HST" => "Pacific/Honolulu",
    "HPT" => "Pacific/Honolulu",
    "HAT" => "Pacific/Honolulu",
    "HADT" => "Pacific/Honolulu",
    "HAST" => "Pacific/Honolulu",
    "HWT" => "Pacific/Honolulu",
    "MOUNTAIN" => "America/New_York",
    "MDT" => "America/Denver",
    "MST" => "America/Denver",
    "MT" => "America/Denver",
    "PACIFIC" => "America/New_York",
    "PDT" => "America/Los_Angeles",
    "PST" => "America/Los_Angeles",
    "SDMT" => "America/Santo_Domingo",
    "PT" => "America/Los_Angeles",
    "FFMT" => "America/Martinique",
    # Europe
    "BT/BST" => "Europe/London",
    "BMT/BST" => "Europe/London",
    "GMT/BST" => "Europe/London",
    "WMT" => "Europe/Warsaw",
    "AMT" => "Asia/Yerevan",
    "PMT" => "Europe/Paris",
    "LST" => "Europe/Riga",
    "BMT" => "Europe/London",
    "BST" => "Europe/London",
    "BDST" => "Europe/London",
    "BT" => "Europe/London",
    "DMT" => "Europe/Dublin",
    "RMT" => "Europe/Rome",
    "IMT" => "Europe/Istanbul",
    "CET/CEST" => "CET",
    "CEST" => "CET",
    "CEMT" => "Europe/Berlin",
    "CET" => "CET",
    "EET/EEST" => "EET",
    "EEST" => "EET",
    "EET" => "EET",
    "WET/WEST" => "WET",
    "WEST" => "WET",
    "WET" => "WET",
    "WEMT" => "WET",
    "GMT" => "Etc/UTC",
    "GMT/IST" => "Etc/UTC",
    # Africa
    "WAT" => "Africa/Lagos",
    "WAST" => "Africa/Lagos",
    "CAT" => "Africa/Maputo",
    # Asia
    "JMT" => "Asia/Jerusalem",
    "MMT" => "Asia/Yangon",
    "NPT" => "Asia/Katmandu",
    "PLMT" => "Asia/Ho_Chi_Minh",
    "MSK/MSD" => "Europe/Moscow",
    "FMT" => "Atlantic/Madeira",
    "MSDT" => "Europe/Moscow",
    "MDST" => "Europe/Moscow",
    "MSK" => "Europe/Moscow",
    "MSD" => "Europe/Moscow",
    "GST" => "Asia/Dubai",
    "IST" => "Asia/Kolkata",
    "KST" => "Asia/Seoul",
    "WIB" => "Asia/Jakarta",
    "TBMT" => "Asia/Tbilisi",
    "HKT" => "Asia/Hong_Kong",
    "HKWT" => "Asia/Hong_Kong"
  }

  def rules, do: @rules
  def zones, do: @zones

  def zones(%NaiveDateTime{} = ndt) do
    Enum.filter(zones(), fn zone -> within_rule_timespan(zone.from, zone.until, ndt) end)
  end

  def rules_by_name(name), do: Enum.filter(rules(), &(&1.name == name))

  def zones_by_name(name, opts \\ []) do
    date = Keyword.get(opts, :at, NaiveDateTime.utc_now())

    Enum.filter(zones(), fn candidate_zone ->
      (candidate_zone.name == name or name in candidate_zone.aliases) &&
        within_rule_timespan(candidate_zone.from, candidate_zone.until, date)
    end)
  end

  def zones_by_offset(offset, opts \\ [])

  def zones_by_offset(offset, opts) do
    offset = normalize_offset(offset)
    date = Keyword.get(opts, :at, NaiveDateTime.utc_now())

    Enum.filter(zones(), fn candidate_zone ->
      candidate_zone.utc_offset_hrs == offset &&
        within_rule_timespan(candidate_zone.from, candidate_zone.until, date)
    end)
  end

  def zone_by_offset(offset, opts \\ [])

  def zone_by_offset(offset, opts) do
    offset = normalize_offset(offset)

    Enum.find_value(
      [
        fn -> zones_by_offset(offset, opts) end,
        fn ->
          offset_preferences =
            Map.merge(@default_offset_preferences, Keyword.get(opts, :assume_tz_offsets, %{}))

          zones_by_name(offset_preferences[offset] || offset, opts)
        end
      ],
      fn fun ->
        case fun.() do
          [zone] -> zone
          _ -> false
        end
      end
    )
  end

  defp normalize_offset("-" <> offset),
    do: "-" <> String.pad_trailing(String.trim(offset, " "), 4, "0")

  defp normalize_offset("+" <> offset),
    do: "+" <> String.pad_trailing(String.trim(offset, " "), 4, "0")

  # Antartica/Troll has an abbreviation of +00 which confuses things for UTC
  def all_abbreviations(ndt \\ NaiveDateTime.utc_now()) do
    ndt
    |> zones()
    |> Enum.flat_map(fn zone -> Enum.reject(zone.abbreviations, &(&1 == "+00")) end)
    |> Enum.uniq()
  end

  def zone_by_abbreviation(abbreviation, opts \\ [])

  def zone_by_abbreviation(abbreviation, opts) do
    Enum.find_value(
      [
        fn -> zones_by_abbreviation(abbreviation, opts) end,
        fn ->
          tz_preferences =
            Map.merge(
              @default_abbreviation_preferences,
              Keyword.get(opts, :assume_tz_abbreviations, %{})
            )

          zones_by_name(tz_preferences[abbreviation] || abbreviation, opts)
        end
      ],
      fn fun ->
        case fun.() do
          [zone] -> zone
          _ -> false
        end
      end
    )
  end

  def zones_by_abbreviation(abbreviation, opts \\ []) do
    tz_preferences =
      Map.merge(
        @default_abbreviation_preferences,
        Keyword.get(opts, :assume_tz_abbreviations, %{})
      )

    date = Keyword.get(opts, :at, NaiveDateTime.utc_now())
    name = tz_preferences[abbreviation]

    Enum.filter(zones(), fn candidate_zone ->
      (abbreviation in candidate_zone.abbreviations || candidate_zone.name == name) &&
        within_rule_timespan(candidate_zone.from, candidate_zone.until, date)
    end)
  end

  @doc false
  def ambiguous_abbreviations(return \\ :name, date \\ NaiveDateTime.utc_now()) do
    zones()
    |> Enum.reduce(%{}, fn zone, acc ->
      if within_rule_timespan(zone.from, zone.until, date) do
        Enum.reduce(zone.abbreviations, acc, fn abbr, acc2 ->
          update_in(acc2, [abbr], &[zone | &1 || []])
        end)
      else
        acc
      end
    end)
    |> Enum.map(fn {abbr, zones} ->
      {abbr,
       {
         zones |> Enum.map(& &1.utc_offset_sec) |> Enum.uniq() |> Enum.count() == 1,
         if return == :zone do
           zones
         else
           Enum.map(zones, &Map.get(&1, return))
         end
       }}
    end)
    |> Enum.filter(fn {_abbr, {_, zones}} -> length(zones) > 1 end)
    |> Enum.into(%{})
  end

  @doc false
  def ambiguous_offsets(return \\ :name, date \\ NaiveDateTime.utc_now()) do
    zones()
    |> Enum.reduce(%{}, fn zone, acc ->
      if within_rule_timespan(zone.from, zone.until, date) do
        update_in(acc, [zone.utc_offset_hrs], &[zone | &1 || []])
      else
        acc
      end
    end)
    |> Enum.map(fn {abbr, zones} ->
      {abbr,
       if return == :zone do
         zones
       else
         Enum.map(zones, &Map.get(&1, return))
       end}
    end)
    |> Enum.filter(fn {_abbr, zones} -> length(zones) > 1 end)
    |> Enum.into(%{})
  end

  defp within_rule_timespan(from, until, date) do
    case {from, until} do
      {nil, nil} ->
        true

      {nil, until} ->
        NaiveDateTime.compare(until, date) == :gt

      {from, nil} ->
        NaiveDateTime.compare(from, date) == :lt

      {from, until} ->
        NaiveDateTime.compare(from, date) == :lt &&
          NaiveDateTime.compare(until, date) == :gt
    end
  end

  @doc """
  Default offsets

  ```
  #{inspect(@default_offset_preferences, pretty: true, limit: :infinity)}
  ```
  """
  def default_offsets, do: @default_offset_preferences

  @doc """
  Default abbreviations

  ```
  #{inspect(@default_abbreviation_preferences, pretty: true, limit: :infinity)}
  ```
  """
  def default_abbreviations, do: @default_abbreviation_preferences
end
