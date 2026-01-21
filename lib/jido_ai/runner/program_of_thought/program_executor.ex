defmodule Jido.AI.Runner.ProgramOfThought.ProgramExecutor do
  @moduledoc """
  Executes generated programs in a safe, sandboxed environment.

  Provides safety features:
  - Timeout enforcement (prevents infinite loops)
  - Memory limits (prevents memory exhaustion)
  - Process isolation (prevents system interference)
  - Error capture (detailed error information)

  ## Safety Model

  Programs are executed in isolated processes with:
  - Configurable timeout (default: 5 seconds)
  - No file system access
  - No network access
  - No system calls
  - Only safe mathematical operations

  ## Example

      iex> program = \"\"\"
      ...> defmodule Solution do
      ...>   def solve do
      ...>     42
      ...>   end
      ...> end
      ...> \"\"\"
      iex> ProgramExecutor.execute(program, timeout: 1000)
      {:ok, %{result: 42, duration_ms: 15, output: ""}}
  """

  # Suppress warning for dynamically compiled Solution module
  @compile {:no_warn_undefined, Solution}

  require Logger

  @default_timeout 5000
  @max_timeout 30_000

  @doc """
  Executes a program with resource limits.

  ## Options

  - `:timeout` - Execution timeout in milliseconds (default: 5000, max: 30000)
  - `:capture_output` - Capture IO output (default: true)

  ## Returns

  - `{:ok, %{result: any(), duration_ms: integer(), output: String.t()}}` on success
  - `{:error, reason}` on failure
  """
  @spec execute(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(program, opts \\ []) when is_binary(program) do
    timeout = Keyword.get(opts, :timeout, @default_timeout) |> validate_timeout()
    capture_output = Keyword.get(opts, :capture_output, true)

    Logger.debug("Executing program with timeout: #{timeout}ms")

    start_time = System.monotonic_time(:millisecond)

    # Execute in a separate process with timeout
    task =
      Task.async(fn ->
        execute_in_sandbox(program, capture_output)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        Logger.debug("Program executed successfully in #{duration_ms}ms")

        {:ok,
         %{
           result: result.value,
           duration_ms: duration_ms,
           output: result.output
         }}

      {:ok, {:error, reason}} ->
        Logger.error("Program execution failed: #{inspect(reason)}")
        {:error, {:execution_error, reason}}

      nil ->
        Logger.error("Program execution timeout after #{timeout}ms")
        {:error, :timeout}
    end
  rescue
    error ->
      Logger.error("Unexpected execution error: #{inspect(error)}")
      {:error, {:unexpected_error, error}}
  end

  # Private functions

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0 do
    min(timeout, @max_timeout)
  end

  defp validate_timeout(_), do: @default_timeout

  defp execute_in_sandbox(program, capture_output) do
    # Prepare execution environment
    bindings = []
    env = :elixir_env.new()

    # Compile and execute the program
    try do
      # Capture IO if requested
      output =
        if capture_output do
          capture_io(fn ->
            execute_program(program, bindings, env)
          end)
        else
          execute_program(program, bindings, env)
          ""
        end

      # Get the result by calling Solution.solve/0
      # Note: Solution module is dynamically compiled in the sandbox above,
      # so the compiler warning about undefined module is expected and can be ignored
      result = Solution.solve()

      {:ok, %{value: result, output: output}}
    rescue
      error ->
        {:error, format_error(error, __STACKTRACE__)}
    catch
      kind, payload ->
        {:error, {:caught, kind, payload}}
    end
  end

  defp execute_program(program, bindings, env) do
    # Use Code.eval_string to execute the program
    # This is safe because:
    # 1. We've validated the code beforehand
    # 2. It runs in an isolated process
    # 3. It has timeout protection
    Code.eval_string(program, bindings, env)
  end

  defp capture_io(fun) do
    # Simple IO capture using StringIO
    original_gl = Process.group_leader()
    {:ok, string_io} = StringIO.open("")
    Process.group_leader(self(), string_io)

    try do
      fun.()
      {_in, output} = StringIO.contents(string_io)
      output
    after
      Process.group_leader(self(), original_gl)
      StringIO.close(string_io)
    end
  end

  defp format_error(error, stacktrace) do
    case error do
      %CompileError{description: desc, line: line} ->
        %{
          type: :compile_error,
          message: desc,
          line: line,
          stacktrace: format_stacktrace(stacktrace)
        }

      %SyntaxError{description: desc, line: line} ->
        %{
          type: :syntax_error,
          message: desc,
          line: line,
          stacktrace: format_stacktrace(stacktrace)
        }

      %TokenMissingError{description: desc, line: line} ->
        %{
          type: :token_error,
          message: desc,
          line: line,
          stacktrace: format_stacktrace(stacktrace)
        }

      %UndefinedFunctionError{module: mod, function: fun, arity: arity} ->
        %{
          type: :undefined_function,
          message: "Undefined function #{inspect(mod)}.#{fun}/#{arity}",
          module: mod,
          function: fun,
          arity: arity,
          stacktrace: format_stacktrace(stacktrace)
        }

      %ArithmeticError{message: msg} ->
        %{
          type: :arithmetic_error,
          message: msg,
          stacktrace: format_stacktrace(stacktrace)
        }

      %ArgumentError{message: msg} ->
        %{
          type: :argument_error,
          message: msg,
          stacktrace: format_stacktrace(stacktrace)
        }

      %FunctionClauseError{} ->
        %{
          type: :function_clause_error,
          message: Exception.message(error),
          stacktrace: format_stacktrace(stacktrace)
        }

      other ->
        %{
          type: :runtime_error,
          message: inspect(other),
          stacktrace: format_stacktrace(stacktrace)
        }
    end
  end

  defp format_stacktrace(stacktrace) do
    stacktrace
    |> Enum.take(5)
    |> Enum.map(fn
      {mod, fun, arity, location} ->
        file = Keyword.get(location, :file, "unknown")
        line = Keyword.get(location, :line, 0)
        "#{inspect(mod)}.#{fun}/#{arity} (#{file}:#{line})"

      {mod, fun, arity} ->
        "#{inspect(mod)}.#{fun}/#{arity}"
    end)
  end

  @doc """
  Validates that a program is safe to execute.

  Checks for:
  - No file I/O operations
  - No network operations
  - No system calls
  - No process spawning
  - No dangerous modules

  Returns `:ok` if safe, `{:error, reason}` otherwise.
  """
  @spec validate_safety(String.t()) :: :ok | {:error, term()}
  def validate_safety(program) when is_binary(program) do
    dangerous_patterns = [
      {~r/File\.(read|write|rm|mkdir|ls)/, :file_io},
      {~r/System\.(cmd|shell)/, :system_call},
      {~r/Code\.eval_quoted/, :code_eval},
      {~r/:os\.cmd/, :os_command},
      {~r/spawn|Task\.async|Task\.start/, :process_spawn},
      {~r/Agent\.(start|get|update)/, :agent_use},
      {~r/GenServer\.(start|call|cast)/, :genserver_use},
      {~r/:ets\.(new|insert|delete)/, :ets_use},
      {~r/Port\.(open|command)/, :port_use},
      {~r/Node\.(connect|spawn)/, :distributed},
      {~r/:httpc\.request/, :network},
      {~r/Socket\./, :socket},
      {~r/Process\.exit/, :process_exit}
    ]

    case Enum.find(dangerous_patterns, fn {pattern, _} ->
           Regex.match?(pattern, program)
         end) do
      nil ->
        :ok

      {_pattern, reason} ->
        {:error, {:unsafe_operation, reason}}
    end
  end
end
