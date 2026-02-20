defmodule Jido.AI.Quality.Checkpoint do
  @moduledoc """
  Final stable quality checkpoint helpers.

  The checkpoint runs fast/full gate command sets, captures timing metrics,
  and verifies traceability closure between story matrix rows and story commits.
  """

  @type gate :: :fast | :full

  @type command_spec :: %{
          required(:gate) => gate(),
          required(:label) => String.t(),
          required(:cmd) => String.t(),
          required(:args) => [String.t()]
        }

  @type command_timing :: %{
          required(:gate) => gate(),
          required(:label) => String.t(),
          required(:elapsed_ms) => non_neg_integer()
        }

  @type command_failure :: %{
          required(:gate) => gate(),
          required(:label) => String.t(),
          required(:cmd) => String.t(),
          required(:args) => [String.t()],
          required(:status) => non_neg_integer(),
          required(:elapsed_ms) => non_neg_integer()
        }

  @type traceability_result :: %{
          required(:traceability_story_ids) => [String.t()],
          required(:commit_story_ids) => [String.t()],
          required(:missing_story_ids) => [String.t()]
        }

  @story_id_pattern ~r/^ST-[A-Z]+-[0-9]{3}$/
  @traceability_row_pattern ~r/^\| (ST-[A-Z]+-[0-9]{3}) \|/m
  @story_commit_pattern ~r/^feat\(story\): (ST-[A-Z]+-[0-9]{3})\b/m

  @example_spot_check_tests [
    "test/jido_ai/skill/runtime_contracts_test.exs",
    "test/jido_ai/examples/weather_strategy_suite_test.exs",
    "test/jido_ai/plugins/chat_docs_contract_test.exs",
    "test/jido_ai/skills/llm/actions/chat_action_test.exs"
  ]

  @doc """
  Canonical fast gate command set.
  """
  @spec fast_gate_commands() :: [command_spec()]
  def fast_gate_commands do
    [
      %{gate: :fast, label: "mix precommit", cmd: "mix", args: ["precommit"]}
    ]
  end

  @doc """
  Canonical full gate command set.

  Set `include_examples: false` to skip example spot-check command.
  """
  @spec full_gate_commands(keyword()) :: [command_spec()]
  def full_gate_commands(opts \\ []) do
    include_examples? = Keyword.get(opts, :include_examples, true)

    commands = [
      %{gate: :full, label: "mix test --exclude flaky", cmd: "mix", args: ["test", "--exclude", "flaky"]},
      %{gate: :full, label: "mix doctor --summary", cmd: "mix", args: ["doctor", "--summary"]},
      %{gate: :full, label: "mix docs", cmd: "mix", args: ["docs"]},
      %{gate: :full, label: "mix coveralls", cmd: "mix", args: ["coveralls"]}
    ]

    if include_examples? do
      commands ++
        [
          %{
            gate: :full,
            label: "mix test (example spot checks)",
            cmd: "mix",
            args: ["test" | @example_spot_check_tests]
          }
        ]
    else
      commands
    end
  end

  @doc """
  Returns the representative example test files used by full gate spot-checks.
  """
  @spec example_spot_check_tests() :: [String.t()]
  def example_spot_check_tests, do: @example_spot_check_tests

  @doc """
  Runs each command in order and returns timing records.
  """
  @spec run_commands([command_spec()], keyword()) :: {:ok, [command_timing()]} | {:error, command_failure()}
  def run_commands(commands, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    commands
    |> Enum.reduce_while({:ok, []}, fn command, {:ok, timings} ->
      case run_command(command, cwd: cwd) do
        {:ok, timing} -> {:cont, {:ok, [timing | timings]}}
        {:error, failure} -> {:halt, {:error, failure}}
      end
    end)
    |> case do
      {:ok, timings} -> {:ok, Enum.reverse(timings)}
      {:error, failure} -> {:error, failure}
    end
  end

  @doc """
  Runs a single command and captures elapsed milliseconds.
  """
  @spec run_command(command_spec(), keyword()) :: {:ok, command_timing()} | {:error, command_failure()}
  def run_command(command, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    started = System.monotonic_time(:millisecond)

    {_result, status} =
      System.cmd(command.cmd, command.args,
        cd: cwd,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    elapsed_ms = System.monotonic_time(:millisecond) - started

    if status == 0 do
      {:ok, %{gate: command.gate, label: command.label, elapsed_ms: elapsed_ms}}
    else
      {:error,
       %{
         gate: command.gate,
         label: command.label,
         cmd: command.cmd,
         args: command.args,
         status: status,
         elapsed_ms: elapsed_ms
       }}
    end
  end

  @doc """
  Reads and parses story IDs from a traceability matrix file.
  """
  @spec read_traceability_story_ids(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def read_traceability_story_ids(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, story_ids_from_traceability(content)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses story IDs from traceability matrix markdown content.
  """
  @spec story_ids_from_traceability(String.t()) :: [String.t()]
  def story_ids_from_traceability(markdown) do
    Regex.scan(@traceability_row_pattern, markdown, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Reads and parses story IDs from local git commit subjects.
  """
  @spec read_story_commit_ids(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def read_story_commit_ids(repo_path \\ ".") do
    case System.cmd("git", ["log", "--pretty=format:%s"], cd: repo_path, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, story_ids_from_git_log(output)}

      {output, status} ->
        {:error, {:git_log_failed, status, output}}
    end
  end

  @doc """
  Parses story IDs from git subject lines matching `feat(story): ST-...`.
  """
  @spec story_ids_from_git_log(String.t()) :: [String.t()]
  def story_ids_from_git_log(log_output) do
    Regex.scan(@story_commit_pattern, log_output, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns missing story IDs from traceability after accounting for commit IDs and allowed gaps.
  """
  @spec missing_story_ids([String.t()], [String.t()], keyword()) :: [String.t()]
  def missing_story_ids(traceability_story_ids, commit_story_ids, opts \\ []) do
    allowed_missing = opts |> Keyword.get(:allow_missing, []) |> MapSet.new()
    commit_story_set = MapSet.new(commit_story_ids)

    traceability_story_ids
    |> Enum.reject(fn story_id ->
      MapSet.member?(commit_story_set, story_id) or MapSet.member?(allowed_missing, story_id)
    end)
    |> Enum.sort()
  end

  @doc """
  Verifies traceability closure and returns result details.
  """
  @spec verify_traceability([String.t()], [String.t()], keyword()) ::
          {:ok, traceability_result()} | {:error, traceability_result()}
  def verify_traceability(traceability_story_ids, commit_story_ids, opts \\ []) do
    missing_story_ids = missing_story_ids(traceability_story_ids, commit_story_ids, opts)

    result = %{
      traceability_story_ids: traceability_story_ids,
      commit_story_ids: commit_story_ids,
      missing_story_ids: missing_story_ids
    }

    if missing_story_ids == [] do
      {:ok, result}
    else
      {:error, result}
    end
  end

  @doc """
  Sums command timings into fast/full gate totals.
  """
  @spec gate_totals([command_timing()]) :: %{fast: non_neg_integer(), full: non_neg_integer()}
  def gate_totals(timings) do
    Enum.reduce(timings, %{fast: 0, full: 0}, fn timing, totals ->
      Map.update!(totals, timing.gate, &(&1 + timing.elapsed_ms))
    end)
  end

  @doc """
  Validates story ID format and returns normalized IDs.
  """
  @spec normalize_story_ids([String.t()]) :: {:ok, [String.t()]} | {:error, [String.t()]}
  def normalize_story_ids(story_ids) do
    normalized =
      story_ids
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    invalid = Enum.reject(normalized, &Regex.match?(@story_id_pattern, &1))

    if invalid == [] do
      {:ok, normalized}
    else
      {:error, invalid}
    end
  end
end
