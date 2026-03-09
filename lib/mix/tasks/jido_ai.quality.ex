defmodule Mix.Tasks.JidoAi.Quality do
  @shortdoc "Run final stable quality checkpoint and traceability closure validation"

  @moduledoc """
  **Maintainers only.**

  Runs the final stable quality checkpoint for backlog closure.

  By default this task runs:
  - Fast gate: `mix precommit`
  - Full gate: `mix test --exclude flaky`, `mix doctor --summary`, `mix docs`, `mix coveralls`
  - Traceability closure: every matrix row has a `feat(story): ST-...` commit

  ## Options

      --traceability-file PATH   Matrix file path (default: specs/stories/00_traceability_matrix.md)
      --git-log-file PATH        Use fixture git-log subjects from file instead of local git history
      --allow-missing IDS        Comma-separated story IDs allowed to be missing in commit history
      --skip-fast                Skip fast gate command set
      --skip-full                Skip full gate command set
      --traceability-only        Run traceability closure check only

  ## Examples

      mix jido_ai.quality
      mix jido_ai.quality --traceability-only
      mix jido_ai.quality --allow-missing ST-QAL-001
  """

  use Mix.Task

  alias Jido.AI.Quality.Checkpoint

  @default_traceability_file "specs/stories/00_traceability_matrix.md"

  @option_strict [
    traceability_file: :string,
    git_log_file: :string,
    allow_missing: :string,
    skip_fast: :boolean,
    skip_full: :boolean,
    traceability_only: :boolean
  ]

  @option_aliases [
    t: :traceability_file,
    g: :git_log_file,
    a: :allow_missing
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _args, invalid} =
      OptionParser.parse(argv, strict: @option_strict, aliases: @option_aliases)

    if invalid != [] do
      Mix.raise("Unknown options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end

    config = build_config(opts)
    run_checkpoint(config)
  end

  defp run_checkpoint(config) do
    timings = []

    timings =
      if config.run_fast_gate do
        run_gate("fast", Checkpoint.fast_gate_commands(), timings)
      else
        timings
      end

    timings =
      if config.run_full_gate do
        full_commands = Checkpoint.full_gate_commands()
        run_gate("full", full_commands, timings)
      else
        timings
      end

    traceability_result = run_traceability_check(config)
    print_summary(timings, traceability_result, config)
  end

  defp run_gate(gate_name, commands, timings) do
    Mix.shell().info("")
    Mix.shell().info("==> Running #{gate_name} gate")

    Enum.each(commands, fn command ->
      Mix.shell().info("-> #{command.label}")
    end)

    case Checkpoint.run_commands(commands) do
      {:ok, command_timings} ->
        timings ++ command_timings

      {:error, failure} ->
        Mix.raise("""
        Quality checkpoint failed while running #{failure.label}
        command: #{failure.cmd} #{Enum.join(failure.args, " ")}
        exit status: #{failure.status}
        elapsed_ms: #{failure.elapsed_ms}
        """)
    end
  end

  defp run_traceability_check(config) do
    Mix.shell().info("")
    Mix.shell().info("==> Verifying traceability closure")

    with {:ok, traceability_story_ids} <- Checkpoint.read_traceability_story_ids(config.traceability_file),
         {:ok, commit_story_ids} <- read_commit_story_ids(config),
         {:ok, result} <-
           Checkpoint.verify_traceability(traceability_story_ids, commit_story_ids, allow_missing: config.allow_missing) do
      result
    else
      {:error, {:read_git_log_file_failed, reason}} ->
        Mix.raise("Unable to read --git-log-file: #{inspect(reason)}")

      {:error, {:git_log_failed, status, output}} ->
        Mix.raise("git log failed with status #{status}:\n#{output}")

      {:error, :enoent} ->
        Mix.raise("Traceability file not found: #{config.traceability_file}")

      {:error, result} when is_map(result) ->
        Mix.raise("""
        Traceability closure failed.
        Missing story commit IDs: #{Enum.join(result.missing_story_ids, ", ")}
        Matrix rows: #{length(result.traceability_story_ids)}
        Story commits: #{length(result.commit_story_ids)}
        """)
    end
  end

  defp read_commit_story_ids(config) do
    case config.git_log_file do
      nil ->
        Checkpoint.read_story_commit_ids(File.cwd!())

      path ->
        case File.read(path) do
          {:ok, content} ->
            {:ok, Checkpoint.story_ids_from_git_log(content)}

          {:error, reason} ->
            {:error, {:read_git_log_file_failed, reason}}
        end
    end
  end

  defp print_summary(timings, traceability_result, config) do
    totals = Checkpoint.gate_totals(timings)

    Mix.shell().info("")
    Mix.shell().info("==> Final checkpoint summary")

    Enum.each(timings, fn timing ->
      Mix.shell().info("[#{timing.gate}] #{timing.label}: #{format_duration(timing.elapsed_ms)}")
    end)

    Mix.shell().info("Fast gate total: #{format_duration(totals.fast)}")
    Mix.shell().info("Full gate total: #{format_duration(totals.full)}")
    Mix.shell().info("Traceability rows: #{length(traceability_result.traceability_story_ids)}")
    Mix.shell().info("Story commits: #{length(traceability_result.commit_story_ids)}")

    if config.allow_missing != [] do
      Mix.shell().info("Allowed missing story IDs: #{Enum.join(config.allow_missing, ", ")}")
    end

    Mix.shell().info("Traceability closure: PASS")
  end

  defp format_duration(elapsed_ms) do
    seconds = elapsed_ms / 1000
    "#{elapsed_ms}ms (#{:erlang.float_to_binary(seconds, decimals: 2)}s)"
  end

  defp build_config(opts) do
    allow_missing =
      opts
      |> Keyword.get(:allow_missing, "")
      |> split_story_ids()
      |> normalize_story_ids!()

    traceability_only = opts[:traceability_only] || false

    %{
      traceability_file: opts[:traceability_file] || @default_traceability_file,
      git_log_file: opts[:git_log_file],
      allow_missing: allow_missing,
      run_fast_gate: not traceability_only and not (opts[:skip_fast] || false),
      run_full_gate: not traceability_only and not (opts[:skip_full] || false)
    }
  end

  defp split_story_ids(csv) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_story_ids!(story_ids) do
    case Checkpoint.normalize_story_ids(story_ids) do
      {:ok, normalized} -> normalized
      {:error, invalid} -> Mix.raise("Invalid --allow-missing story IDs: #{Enum.join(invalid, ", ")}")
    end
  end
end
