defmodule Jido.AI.Accuracy.Critiquers.ToolCritiquer do
  @moduledoc """
  Tool-based critiquer that executes tools to analyze candidates.

  This critiquer runs external tools (linters, type checkers, test runners)
  and aggregates their results into a structured critique.

  ## Configuration

  - `:tools` - List of tool specifications to run
  - `:severity_map` - Mapping from tool results to severity scores
  - `:timeout` - Timeout per tool in ms (default: 30_000)
  - `:working_dir` - Working directory for tool execution

  ## Tool Specification

  Each tool is a map with:
  - `:name` - Tool name for identification
  -:command` - Command to execute
  - `:args` - Arguments to pass (candidate content will be available)
  - `:severity_on_fail` - Severity when tool fails (default: 0.8)

  ## Usage

      # Create critiquer with tools
      critiquer = ToolCritiquer.new!(%{
        tools: [
          %{
            name: "linter",
            command: "mix",
            args: ["credo", "strict"],
            severity_on_fail: 0.7
          }
        ]
      })

      # Critique a candidate
      {:ok, critique} = ToolCritiquer.critique(critiquer, candidate, %{
        file_path: "lib/my_module.ex"
      })

      critique.issues  # => ["Linter warning: ..."]
      critique.severity  # => 0.7

  ## Severity Mapping

  Tool results map to severity:
  - Exit code 0 → No severity (0.0)
  - Exit code non-zero → Tool's `severity_on_fail` (default: 0.8)
  - Timeout → High severity (0.9)
  - Exception → High severity (1.0)

  """

  @behaviour Jido.AI.Accuracy.Critique

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, ToolExecutor}

  @type t :: %__MODULE__{
          tools: [tool_spec()],
          severity_map: severity_map(),
          timeout: pos_integer(),
          working_dir: String.t() | nil
        }

  @type tool_spec :: %{
          name: String.t(),
          command: String.t(),
          args: [String.t()],
          severity_on_fail: number(),
          parse_output: (String.t() -> [String.t()]) | nil
        }

  @type severity_map :: %{
          optional(:timeout) => number(),
          optional(:exception) => number(),
          optional(atom()) => number()
        }

  @default_severity_map %{
    timeout: 0.9,
    exception: 1.0
  }

  defstruct tools: [],
            severity_map: @default_severity_map,
            timeout: 30_000,
            working_dir: nil

  @doc """
  Creates a new tool critiquer.

  ## Options

  - `:tools` - List of tool specifications
  - `:severity_map` - Custom severity mapping
  - `:timeout` - Timeout per tool in ms
  - `:working_dir` - Working directory for execution

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    critiquer = struct(__MODULE__, opts)

    with :ok <- validate_tools(critiquer.tools),
         :ok <- validate_severity_map(critiquer.severity_map),
         :ok <- validate_timeout(critiquer.timeout) do
      {:ok, critiquer}
    end
  end

  @doc """
  Creates a new tool critiquer, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, critiquer} -> critiquer
      {:error, reason} -> raise ArgumentError, "Invalid ToolCritiquer: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Critiques a candidate by running configured tools.

  Tools are executed sequentially and their results are aggregated
  into a single CritiqueResult.

  ## Context Options

  - `:file_path` - Path to file for analysis (used by some tools)
  - `:working_dir` - Override default working directory
  - `:content_only` - Only use candidate content, don't write to file

  """
  @spec critique(t(), Candidate.t(), map()) :: {:ok, CritiqueResult.t()} | {:error, term()}
  def critique(%__MODULE__{tools: []} = _critiquer, %Candidate{} = _candidate, _context) do
    {:ok,
     CritiqueResult.new!(%{
       severity: 0.0,
       issues: [],
       suggestions: [],
       feedback: "No tools configured for critique",
       actionable: false,
       metadata: %{tools_run: 0}
     })}
  end

  def critique(%__MODULE__{} = critiquer, %Candidate{} = candidate, context) do
    working_dir = Map.get(context, :working_dir, critiquer.working_dir)

    tool_results =
      Enum.map(critiquer.tools, fn tool ->
        run_tool(tool, candidate, working_dir, critiquer.timeout)
      end)

    aggregate_results(tool_results, critiquer.severity_map)
  end

  # Private functions

  defp run_tool(tool_spec, candidate, working_dir, timeout) do
    cmd_opts = [
      timeout: timeout,
      cd: working_dir
    ]

    result =
      case ToolExecutor.run_command(tool_spec.command, tool_spec.args, cmd_opts) do
        {:ok, tool_result} ->
          process_tool_result(tool_spec, tool_result, candidate)

        {:error, reason} ->
          %{
            tool_name: tool_spec.name,
            success: false,
            exit_code: nil,
            severity: Map.get(@default_severity_map, :exception, 1.0),
            issues: ["Tool execution failed: #{format_error(reason)}"],
            suggestions: [],
            output: ""
          }
      end

    Map.put(result, :tool, tool_spec.name)
  end

  defp process_tool_result(tool_spec, tool_result, _candidate) do
    success = tool_result.exit_code == 0 and not tool_result.timed_out

    severity =
      cond do
        tool_result.timed_out ->
          0.9

        not success ->
          # Use tool's severity_on_fail, or default to 0.8
          case Map.get(tool_spec, :severity_on_fail) do
            nil -> 0.8
            val when is_number(val) -> val
            _ -> 0.8
          end

        true ->
          0.0
      end

    {issues, suggestions} = parse_tool_output(tool_spec, tool_result, success)

    %{
      tool_name: tool_spec.name,
      success: success,
      exit_code: tool_result.exit_code,
      severity: severity,
      issues: issues,
      suggestions: suggestions,
      output: tool_result.stdout <> tool_result.stderr
    }
  end

  defp parse_tool_output(tool_spec, tool_result, success) do
    output = tool_result.stdout <> tool_result.stderr

    if success do
      {[], []}
    else
      # Use custom parser if provided, otherwise use default
      case Map.get(tool_spec, :parse_output) do
        nil ->
          {default_parse_issues(output, tool_spec.name), default_parse_suggestions(output)}

        parser when is_function(parser) ->
          issues = parser.(output)
          {issues, []}
      end
    end
  end

  defp default_parse_issues(output, tool_name) do
    # Try to extract structured issues from output
    lines =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn line -> line != "" end)

    # Look for common patterns (error:, warning:, etc.)
    issue_lines =
      Enum.filter(lines, fn line ->
        String.contains?(String.downcase(line), ["error", "warning", "fail", "issue"])
      end)

    if Enum.empty?(issue_lines) do
      # Generic issue if no specific pattern found
      ["#{tool_name} reported issues"]
    else
      Enum.take(issue_lines, 10)
    end
  end

  defp default_parse_suggestions(output) do
    # Look for suggestion patterns
    lines = String.split(output, "\n")

    suggestion_lines =
      Enum.filter(lines, fn line ->
        lower = String.downcase(line)
        String.contains?(lower, ["suggest", "fix", "try", "consider", "recommend"])
      end)

    Enum.take(suggestion_lines, 5)
  end

  defp aggregate_results(tool_results, _severity_map) do
    all_issues =
      tool_results
      |> Enum.flat_map(fn r -> r.issues end)
      |> Enum.uniq()

    all_suggestions =
      tool_results
      |> Enum.flat_map(fn r -> r.suggestions end)
      |> Enum.uniq()

    max_severity =
      tool_results
      |> Enum.map(fn r -> r.severity end)
      |> Enum.max(fn -> 0.0 end)

    tools_passed = Enum.count(tool_results, fn r -> r.success end)
    tools_total = length(tool_results)

    feedback = build_feedback(tool_results, tools_passed, tools_total)

    metadata = %{
      tools_run: tools_total,
      tools_passed: tools_passed,
      tool_results: tool_results,
      critiquer: :tool
    }

    {:ok,
     CritiqueResult.new!(%{
       severity: max_severity,
       issues: all_issues,
       suggestions: all_suggestions,
       feedback: feedback,
       actionable: max_severity > 0.3,
       metadata: metadata
     })}
  end

  defp build_feedback(tool_results, passed, total) do
    if passed == total do
      "All tools passed (#{passed}/#{total})"
    else
      failed_tools =
        tool_results
        |> Enum.reject(fn r -> r.success end)
        |> Enum.map_join(", ", fn r -> r.tool_name end)

      "Some tools failed: #{failed_tools} (#{passed}/#{total} passed)"
    end
  end

  # Validation

  defp validate_tools(tools) when is_list(tools) do
    valid =
      Enum.all?(tools, fn tool ->
        is_map(tool) and
          is_binary(Map.get(tool, :name)) and
          is_binary(Map.get(tool, :command)) and
          is_list(Map.get(tool, :args, []))
      end)

    if valid, do: :ok, else: {:error, :invalid_tools}
  end

  defp validate_tools(_), do: {:error, :invalid_tools}

  defp validate_severity_map(map) when is_map(map) do
    valid =
      Enum.all?(map, fn {k, v} ->
        is_atom(k) and is_number(v) and v >= 0.0 and v <= 1.0
      end)

    if valid, do: :ok, else: {:error, :invalid_severity_map}
  end

  defp validate_severity_map(_), do: {:error, :invalid_severity_map}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
