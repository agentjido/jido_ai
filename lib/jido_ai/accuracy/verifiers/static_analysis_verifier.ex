defmodule Jido.AI.Accuracy.Verifiers.StaticAnalysisVerifier do
  @moduledoc """
  Verifier that runs static analysis tools to score code quality.

  This verifier executes linters, type checkers, and other static analysis
  tools to assess code quality without execution.

  ## Usage

      verifier = StaticAnalysisVerifier.new!(%{
        tools: [
          %{name: "credo", command: "mix", args: ["credo"], output_format: :auto}
        ]
      })

  """

  @behaviour Jido.AI.Accuracy.Verifier

  alias Jido.AI.Accuracy.{Candidate, VerificationResult, ToolExecutor}

  @type severity :: :error | :warning | :info | :style | :note
  @type tool :: %{
          name: String.t(),
          command: String.t(),
          args: [String.t()],
          output_format: :json | :text | :auto
        }

  @type t :: %__MODULE__{
          tools: [tool()],
          severity_weights: %{severity() => number()},
          working_dir: String.t() | nil,
          environment: %{optional(String.t()) => String.t()},
          timeout: pos_integer()
        }

  @default_severity_weights %{
    error: 1.0,
    fatal: 1.0,
    warning: 0.5,
    info: 0.1,
    note: 0.1,
    style: 0.05,
    convention: 0.05,
    refactor: 0.1
  }

  defstruct tools: [],
            severity_weights: @default_severity_weights,
            working_dir: nil,
            environment: %{},
            timeout: 30_000

  @doc """
  Creates a new static analysis verifier.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    verifier = struct(__MODULE__, opts)

    with :ok <- validate_tools(verifier.tools),
         :ok <- validate_severity_weights(verifier.severity_weights),
         :ok <- validate_timeout(verifier.timeout),
         :ok <- validate_working_dir(verifier.working_dir) do
      {:ok, verifier}
    end
  end

  @doc """
  Creates a new static analysis verifier, raising on error.
  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, verifier} -> verifier
      {:error, reason} -> raise ArgumentError, "Invalid static analysis verifier: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Verifies a candidate by running static analysis tools.
  """
  @spec verify(t(), Candidate.t(), map()) :: {:ok, VerificationResult.t()} | {:error, term()}
  def verify(%__MODULE__{tools: []} = _verifier, %Candidate{} = candidate, _context) do
    {:ok,
     %VerificationResult{
       candidate_id: candidate.id,
       score: 0.5,
       confidence: 0.0,
       reasoning: "No analysis tools configured",
       metadata: %{tools_run: 0}
     }}
  end

  def verify(%__MODULE__{} = verifier, %Candidate{} = candidate, context) do
    tool_results =
      Enum.map(verifier.tools, fn tool ->
        run_analysis_tool(tool, verifier, candidate, context)
      end)

    all_issues =
      tool_results
      |> Enum.flat_map(fn
        {:ok, issues} -> issues
        _ -> []
      end)

    score = calculate_score_from_issues(all_issues, verifier.severity_weights)
    issues_by_severity = Enum.group_by(all_issues, & &1.severity)

    {:ok,
     %VerificationResult{
       candidate_id: candidate.id,
       score: score,
       confidence: calculate_confidence(all_issues, verifier.tools),
       reasoning: build_reasoning(issues_by_severity, length(verifier.tools)),
       metadata: %{
         issues: all_issues,
         issues_by_severity: Enum.map(issues_by_severity, fn {k, v} -> {k, length(v)} end) |> Map.new(),
         tools_run: length(verifier.tools)
       }
     }}
  end

  @impl true
  @doc """
  Verifies multiple candidates in batch.
  """
  @spec verify_batch(t(), [Candidate.t()], map()) :: {:ok, [VerificationResult.t()]}
  def verify_batch(%__MODULE__{} = verifier, candidates, context) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        {:ok, result} = verify(verifier, candidate, context)
        result
      end)

    {:ok, results}
  end

  @impl true
  @doc """
  Static analysis verifier does not support streaming.
  """
  @spec supports_streaming?() :: false
  def supports_streaming?, do: false

  # Private functions

  defp run_analysis_tool(tool, verifier, _candidate, context) do
    args =
      if file_path = Map.get(context, :file_path) do
        tool.args ++ [file_path]
      else
        tool.args
      end

    opts = [
      timeout: verifier.timeout,
      cd: verifier.working_dir,
      env: verifier.environment
    ]

    case ToolExecutor.run_command(tool.command, args, opts) do
      {:ok, result} ->
        issues = parse_tool_output(result, tool.output_format)
        {:ok, issues}

      {:error, _reason} ->
        {:ok, []}
    end
  end

  defp parse_tool_output(result, format) do
    output = ToolExecutor.capture_output(result)

    # Limit output size to prevent ReDoS and memory issues
    # 1MB limit
    max_output_size = 1_000_000

    output =
      if String.length(output) > max_output_size do
        String.slice(output, 0, max_output_size) <> "\n[output truncated due to size]"
      else
        output
      end

    case format do
      :auto -> detect_and_parse_issues(output)
      :json -> parse_json_issues(output)
      :text -> parse_text_issues(output)
    end
  end

  defp detect_and_parse_issues(output) do
    cond do
      String.starts_with?(String.trim(output), ["{", "["]) -> parse_json_issues(output)
      Regex.match?(~r/\.\w+:\d+:\d+:\s+\w+:/, output) -> parse_text_issues(output)
      true -> []
    end
  end

  defp parse_json_issues(output) do
    trimmed = String.trim(output)

    case Jason.decode(trimmed) do
      {:ok, data} when is_list(data) ->
        Enum.map(data, &parse_json_issue/1)

      {:ok, data} when is_map(data) ->
        case Map.get(data, "issues") do
          nil -> [parse_json_issue(data)]
          issues when is_list(issues) -> Enum.map(issues, &parse_json_issue/1)
        end

      {:error, _} ->
        []
    end
  end

  defp parse_json_issue(issue) when is_map(issue) do
    %{
      severity: parse_json_severity(issue),
      message: Map.get(issue, "message") || Map.get(issue, "msg") || "",
      line: Map.get(issue, "line") || Map.get(issue, "line_number") || 0
    }
  end

  defp parse_json_severity(issue) do
    type = Map.get(issue, "type") || Map.get(issue, "severity") || ""

    cond do
      String.downcase(type) in ["error", "fatal", "critical"] -> :error
      String.downcase(type) in ["warning", "warn"] -> :warning
      String.downcase(type) in ["info", "note", "information"] -> :info
      String.downcase(type) in ["style", "convention"] -> :style
      true -> :warning
    end
  end

  defp parse_text_issues(output) do
    pattern = ~r/.+?:(\d+):(?:(\d+):)?\s+(error|warning|info|style|fatal|note):\s*(.+)/i

    # Wrap regex operation in timeout to prevent ReDoS
    safe_regex_scan(fn -> Regex.scan(pattern, output) end)
    |> Enum.map(fn
      [_, line, col, severity, message] ->
        %{severity: parse_text_severity(severity), line: parse_int(line), column: parse_int(col), message: message}

      [_, line, severity, message] ->
        %{severity: parse_text_severity(severity), line: parse_int(line), column: nil, message: message}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Safe regex execution with timeout to prevent catastrophic backtracking
  defp safe_regex_scan(regex_fn) do
    # Use Task.async with a short timeout to prevent hanging
    task = Task.async(regex_fn)

    case Task.yield(task, 1000) do
      {:ok, result} ->
        result

      {:exit, _reason} ->
        # Task crashed (possibly due to stack overflow from ReDoS)
        []

      nil ->
        # Timeout - task didn't complete in time
        Task.shutdown(task, :brutal_kill)
        []
    end
  catch
    # Catch any other errors (e.g., compile errors from malformed regex)
    _kind, _error -> []
  end

  defp parse_text_severity(severity) when is_binary(severity) do
    case String.downcase(severity) do
      s when s in ["error", "fatal", "err"] -> :error
      s when s in ["warning", "warn"] -> :warning
      s when s in ["info", "note"] -> :info
      s when s in ["style"] -> :style
      _ -> :warning
    end
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp calculate_score_from_issues(issues, weights) do
    penalty =
      Enum.reduce(issues, 0.0, fn issue, acc ->
        weight = Map.get(weights, issue.severity, 0.5)
        acc + weight
      end)

    max(0.0, 1.0 - penalty)
  end

  defp calculate_confidence([], _tools), do: 0.0

  defp calculate_confidence(issues, _tools) do
    issue_count = length(issues)

    cond do
      issue_count == 0 -> 1.0
      issue_count < 5 -> 0.8
      issue_count < 20 -> 0.6
      true -> 0.4
    end
  end

  defp build_reasoning(issues_by_severity, tools_count) do
    if map_size(issues_by_severity) == 0 do
      "No issues found"
    else
      parts =
        Enum.map(issues_by_severity, fn {severity, list} ->
          "#{length(list)} #{severity}"
        end)

      "Found #{Enum.join(parts, ", ")} across #{tools_count} tool(s)"
    end
  end

  # Validation

  defp validate_tools(tools) when is_list(tools) do
    Enum.reduce_while(tools, :ok, fn tool, _acc ->
      if is_map(tool) and is_binary(Map.get(tool, :name)) and
           is_binary(Map.get(tool, :command)) and is_list(Map.get(tool, :args)) do
        {:cont, :ok}
      else
        {:halt, {:error, :invalid_tool_config}}
      end
    end)
  end

  defp validate_tools(_), do: {:error, :invalid_tools}

  defp validate_severity_weights(weights) when is_map(weights) do
    if Enum.all?(weights, fn {k, v} -> is_atom(k) and is_number(v) and v >= 0 end) do
      :ok
    else
      {:error, :invalid_severity_weights}
    end
  end

  defp validate_severity_weights(_), do: {:error, :invalid_severity_weights}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp validate_working_dir(nil), do: :ok

  defp validate_working_dir(path) when is_binary(path) do
    if File.dir?(path), do: :ok, else: {:error, :directory_not_found}
  end

  defp validate_working_dir(_), do: {:error, :invalid_directory}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
