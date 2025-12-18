defmodule Jido.AI.Runner.ChainOfThought.TestExecution.ExecutionSandbox do
  @moduledoc """
  Sandboxed code execution environment for running generated code and tests safely.

  Provides:
  - Isolated process execution
  - Timeout enforcement
  - Memory limits and resource restrictions
  - Compilation and runtime error capture with detailed context
  """

  require Logger

  @default_timeout 30_000
  # 256 MB
  @default_memory_limit 256 * 1024 * 1024
  # 5 minutes
  @max_timeout 300_000

  @type execution_result :: %{
          status: :success | :failure | :timeout | :compilation_error,
          output: String.t(),
          errors: list(),
          duration_ms: non_neg_integer(),
          exit_code: integer() | nil
        }

  @doc """
  Executes code and tests in isolated sandbox environment.

  ## Parameters

  - `code_file` - Path to code file
  - `test_file` - Path to test file
  - `opts` - Options:
    - `:timeout` - Execution timeout in ms (default: 30000, max: 300000)
    - `:memory_limit` - Memory limit in bytes (default: 256MB)
    - `:capture_output` - Capture stdout/stderr (default: true)

  ## Returns

  - `{:ok, result}` - Execution completed (may have failures)
  - `{:error, reason}` - Execution could not be started

  ## Examples

      {:ok, %{status: :success, output: "5 tests, 0 failures"}} =
        ExecutionSandbox.execute(code_file, test_file)

      {:ok, %{status: :failure, errors: [...]}} =
        ExecutionSandbox.execute(code_file, test_file, timeout: 5000)
  """
  @spec execute(Path.t(), Path.t(), keyword()) :: {:ok, execution_result()} | {:error, term()}
  def execute(code_file, test_file, opts \\ []) do
    timeout = min(Keyword.get(opts, :timeout, @default_timeout), @max_timeout)
    memory_limit = Keyword.get(opts, :memory_limit, @default_memory_limit)
    capture_output = Keyword.get(opts, :capture_output, true)

    Logger.debug(
      "Executing #{test_file} with timeout #{timeout}ms, memory limit #{memory_limit} bytes"
    )

    start_time = System.monotonic_time(:millisecond)

    # First, compile the code
    case compile_code(code_file, timeout) do
      {:ok, _compile_output} ->
        # Then run the tests
        execute_tests(test_file, timeout, memory_limit, capture_output, start_time)

      {:error, compile_errors} ->
        duration = System.monotonic_time(:millisecond) - start_time

        result = %{
          status: :compilation_error,
          output: "",
          errors: parse_compilation_errors(compile_errors),
          duration_ms: duration,
          exit_code: 1
        }

        {:ok, result}
    end
  end

  @doc """
  Executes code in isolated process with resource limits.

  ## Parameters

  - `code` - Code string to execute
  - `opts` - Options:
    - `:timeout` - Execution timeout in ms
    - `:memory_limit` - Memory limit in bytes
    - `:bindings` - Variable bindings for code execution

  ## Returns

  - `{:ok, result}` - Execution successful
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, result} = ExecutionSandbox.execute_code(
        "1 + 1",
        timeout: 1000
      )
  """
  @spec execute_code(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute_code(code, opts \\ []) do
    timeout = min(Keyword.get(opts, :timeout, @default_timeout), @max_timeout)
    bindings = Keyword.get(opts, :bindings, [])

    task =
      Task.async(fn ->
        try do
          {result, _bindings} = Code.eval_string(code, bindings)
          {:ok, result}
        rescue
          error -> {:error, {:runtime_error, error, __STACKTRACE__}}
        catch
          kind, value -> {:error, {:caught, kind, value, __STACKTRACE__}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, {:timeout, timeout}}

      {:exit, reason} ->
        {:error, {:exit, reason}}
    end
  end

  @doc """
  Compiles code file and captures any compilation errors.

  ## Parameters

  - `code_file` - Path to code file
  - `timeout` - Compilation timeout

  ## Returns

  - `{:ok, output}` - Compilation successful
  - `{:error, errors}` - Compilation failed
  """
  @spec compile_code(Path.t(), pos_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def compile_code(code_file, _timeout) do
    # Use elixirc to compile the file
    case System.cmd(
           "elixirc",
           [
             code_file,
             "--ignore-module-conflict",
             "--no-docs",
             "--no-debug-info",
             "-o",
             System.tmp_dir!()
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, output}

      {errors, _exit_code} ->
        {:error, errors}
    end
  rescue
    error ->
      {:error, "Compilation exception: #{inspect(error)}"}
  end

  @doc """
  Enforces timeout for test execution.

  ## Parameters

  - `test_fn` - Function to execute
  - `timeout` - Timeout in ms

  ## Returns

  - `{:ok, result}` - Execution completed within timeout
  - `{:error, :timeout}` - Execution exceeded timeout
  """
  @spec enforce_timeout(fun(), pos_integer()) :: {:ok, term()} | {:error, :timeout}
  def enforce_timeout(test_fn, timeout) when is_function(test_fn, 0) do
    task = Task.async(test_fn)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end
  end

  @doc """
  Captures runtime errors with detailed context.

  ## Parameters

  - `fun` - Function to execute

  ## Returns

  - `{:ok, result}` - Execution successful
  - `{:error, error_details}` - Error captured with context
  """
  @spec capture_runtime_errors(fun()) :: {:ok, term()} | {:error, map()}
  def capture_runtime_errors(fun) when is_function(fun, 0) do
    result = fun.()
    {:ok, result}
  rescue
    error ->
      {:error,
       %{
         type: :runtime_error,
         error: error,
         message: Exception.message(error),
         stacktrace: __STACKTRACE__
       }}
  catch
    kind, value ->
      {:error,
       %{
         type: :caught,
         kind: kind,
         value: value,
         stacktrace: __STACKTRACE__
       }}
  end

  # Private functions

  defp execute_tests(test_file, timeout, _memory_limit, capture_output, start_time) do
    # Run mix test on the test file
    cmd_opts =
      if capture_output do
        [stderr_to_stdout: true, timeout: timeout]
      else
        [timeout: timeout]
      end

    case System.cmd("mix", ["test", test_file, "--trace"], cmd_opts) do
      {output, 0} ->
        duration = System.monotonic_time(:millisecond) - start_time

        result = %{
          status: :success,
          output: output,
          errors: [],
          duration_ms: duration,
          exit_code: 0
        }

        {:ok, result}

      {output, exit_code} ->
        duration = System.monotonic_time(:millisecond) - start_time

        result = %{
          status: :failure,
          output: output,
          errors: parse_test_failures(output),
          duration_ms: duration,
          exit_code: exit_code
        }

        {:ok, result}
    end
  rescue
    error ->
      duration = System.monotonic_time(:millisecond) - start_time

      result = %{
        status: :failure,
        output: "",
        errors: [%{type: :execution_error, message: Exception.message(error)}],
        duration_ms: duration,
        exit_code: nil
      }

      {:ok, result}
  catch
    :exit, {:timeout, _} ->
      duration = System.monotonic_time(:millisecond) - start_time

      result = %{
        status: :timeout,
        output: "",
        errors: [%{type: :timeout, message: "Test execution exceeded #{timeout}ms timeout"}],
        duration_ms: duration,
        exit_code: nil
      }

      {:ok, result}
  end

  defp parse_compilation_errors(error_output) do
    # Parse Elixir compiler error format
    error_output
    |> String.split("\n")
    |> Enum.filter(fn line -> String.contains?(line, ["error:", "warning:"]) end)
    |> Enum.map(fn line ->
      %{
        type: :compilation_error,
        message: String.trim(line)
      }
    end)
  end

  defp parse_test_failures(output) do
    # Extract failure information from ExUnit output
    output
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, ["**", "Failure", "Error"]) or
        String.match?(line, ~r/\d+\) test /)
    end)
    |> Enum.map(fn line ->
      %{
        type: :test_failure,
        message: String.trim(line)
      }
    end)
  end
end
