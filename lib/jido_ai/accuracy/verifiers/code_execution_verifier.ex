defmodule Jido.AI.Accuracy.Verifiers.CodeExecutionVerifier do
  @moduledoc """
  Verifier that executes code to verify correctness.

  This verifier runs code candidates in a controlled environment and scores
  them based on execution success. Useful for:
  - Code generation tasks
  - Algorithm implementation verification
  - Output validation for computations
  - Runtime error detection

  ## Execution Modes

  ### Direct Execution

  Executes code directly on the host system (fastest, least secure):

      verifier = CodeExecutionVerifier.new!(%{
        timeout: 5000,
        sandbox: :none
      })

  ### Docker Sandbox

  Executes code in an isolated Docker container:

      verifier = CodeExecutionVerifier.new!(%{
        timeout: 5000,
        sandbox: :docker
      })

  ### Podman Sandbox

  Executes code in an isolated Podman container (rootless):

      verifier = CodeExecutionVerifier.new!(%{
        timeout: 5000,
        sandbox: :podman
      })

  ## Usage

      # Create verifier
      verifier = CodeExecutionVerifier.new!(%{
        language: :python,
        timeout: 5000
      })

      # Verify a code candidate
      candidate = Candidate.new!(%{
        content: \"\"\"
        def add(a, b):
            return a + b
        print(add(2, 3))
        \"\"\"
      })

      {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{
        expected_output: "5"
      })

      # Check result
      result.score  # => 1.0 (execution succeeded)
      result.reasoning  # => "Code executed successfully"

  ## Score Values

  - `1.0` - Code executed successfully (exit code 0)
  - `0.5` - Code executed with non-fatal issues (exit code non-zero but output found)
  - `0.0` - Code failed to execute (syntax error, runtime error, timeout)

  ## Security Considerations

  - **Default sandbox is `:none`** for backward compatibility, but logs a warning
  - **Production deployments should use sandboxing** - Set `JIDO_DEFAULT_SANDBOX=docker`
    or `JIDO_DEFAULT_SANDBOX=podman` environment variable, or configure via
    `config :jido_ai, :default_code_sandbox, :docker`
  - **Set appropriate timeouts** - Prevent infinite loops and resource exhaustion
  - **Validate working directories** - Prevent file system access outside designated areas
  - **Sanitize environment variables** - Don't pass secrets to executed code

  ## Production Configuration

  To enforce sandboxed execution in production, configure the default sandbox
  via application config or environment variable:

      # config/config.exs
      config :jido_ai, :default_code_sandbox, :docker

      # Or via environment variable
      export JIDO_DEFAULT_SANDBOX=docker

  This prevents accidental use of unsafe execution in production deployments.

  ## Language Support

  The verifier detects the language from:
  1. The `:language` config option
  2. Code file extensions (if present)
  3. Shebang lines
  4. Common code patterns

  Supported language hints:
  - `:python` - Execute with `python3 -c`
  - `:javascript` - Execute with `node -e`
  - `:elixir` - Execute with `elixir -e`
  - `:ruby` - Execute with `ruby -e`
  - `:bash` - Execute with `bash -c`
  - `:auto` - Auto-detect from code

  """

  @behaviour Jido.AI.Accuracy.Verifier

  alias Jido.AI.Accuracy.{Candidate, ToolExecutor, VerificationResult}

  @type sandbox_type :: :none | :docker | :podman
  @type language :: :python | :javascript | :elixir | :ruby | :bash | :auto
  @type t :: %__MODULE__{
          timeout: pos_integer(),
          sandbox: sandbox_type(),
          working_dir: String.t() | nil,
          environment: %{optional(String.t()) => String.t()},
          language: language()
        }

  defstruct timeout: 5000,
            sandbox: nil,
            working_dir: nil,
            environment: %{},
            language: :auto

  @doc """
  Creates a new code execution verifier from the given attributes.

  ## Options

  - `:timeout` - Execution timeout in milliseconds (default: 5000)
  - `:sandbox` - Sandbox type (:none, :docker, :podman, default: :none)
  - `:working_dir` - Working directory for execution (default: nil)
  - `:environment` - Environment variables for execution (default: %{})
  - `:language` - Programming language hint (default: :auto)

  ## Returns

  - `{:ok, verifier}` - Success
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> CodeExecutionVerifier.new(%{language: :python})
      {:ok, %CodeExecutionVerifier{language: :python}}

      iex> CodeExecutionVerifier.new(%{sandbox: :docker})
      {:ok, %CodeExecutionVerifier{sandbox: :docker}}

      iex> CodeExecutionVerifier.new(%{timeout: -1})
      {:error, :invalid_timeout}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    # Determine default sandbox based on application config or environment
    default_sandbox = get_default_sandbox()

    # Merge opts with defaults, preferring explicit :sandbox from opts
    opts = Map.new(opts)
    sandbox = Map.get(opts, :sandbox, default_sandbox)
    opts = Map.put(opts, :sandbox, sandbox)

    verifier = struct(__MODULE__, opts)

    with :ok <- validate_timeout(verifier.timeout),
         :ok <- validate_sandbox(verifier.sandbox, opts),
         :ok <- validate_language(verifier.language),
         :ok <- validate_working_dir(verifier.working_dir) do
      # Log warning if using unsafe sandbox
      if verifier.sandbox == :none do
        require Logger

        Logger.warning("""
        [SECURITY] CodeExecutionVerifier using sandbox: :none
        This allows arbitrary code execution on the host system!
        Ensure this is intentional and only used in trusted environments.
        Consider using sandbox: :docker or :podman instead.
        """)
      end

      {:ok, verifier}
    end
  end

  # Get default sandbox from application config or environment variable
  defp get_default_sandbox do
    cond do
      # Application config takes precedence
      Application.get_env(:jido_ai, :default_code_sandbox) != nil ->
        Application.get_env(:jido_ai, :default_code_sandbox)

      # Environment variable for backwards compatibility and testing
      System.get_env("JIDO_DEFAULT_SANDBOX") ->
        case System.get_env("JIDO_DEFAULT_SANDBOX") do
          "docker" -> :docker
          "podman" -> :podman
          "none" -> :none
          _ -> :docker
        end

      # Default to :none for backward compatibility, but with warning
      true ->
        :none
    end
  end

  @doc """
  Creates a new code execution verifier, raising on error.

  ## Examples

      iex> CodeExecutionVerifier.new!(%{language: :python})
      %CodeExecutionVerifier{language: :python}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, verifier} -> verifier
      {:error, reason} -> raise ArgumentError, "Invalid code execution verifier: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Verifies a code candidate by executing it.

  Extracts code from the candidate content and executes it.
  Returns a score based on execution success:
  - 1.0: Successful execution (exit code 0)
  - 0.5: Non-zero exit code but produced output
  - 0.0: Execution failed (syntax error, timeout, etc.)

  ## Examples

      iex> verifier = CodeExecutionVerifier.new!(%{language: :python})
      iex> candidate = Candidate.new!(%{content: "print('hello')"})
      iex> {:ok, result} = CodeExecutionVerifier.verify(verifier, candidate, %{})
      iex> result.score
      1.0

  """
  @spec verify(t(), Candidate.t(), map()) :: {:ok, VerificationResult.t()} | {:error, term()}
  def verify(%__MODULE__{} = verifier, %Candidate{} = candidate, context) do
    code = extract_code(candidate.content)

    if String.trim(code) == "" do
      {:ok, empty_result(candidate, "No code found in candidate")}
    else
      language = detect_language(verifier.language, code, candidate)

      case execute_code(verifier, code, language) do
        {:ok, result} ->
          score = calculate_score(result, language)
          reasoning = build_reasoning(result, language)

          verification_result = %VerificationResult{
            candidate_id: candidate.id,
            score: score,
            confidence: calculate_confidence(result),
            reasoning: reasoning,
            metadata: %{
              exit_code: result.exit_code,
              stdout: result.stdout,
              stderr: result.stderr,
              timed_out: result.timed_out,
              language: language,
              duration_ms: result.duration_ms
            }
          }

          # Check for expected output if provided
          verification_result = apply_expected_output_check(verification_result, context)

          {:ok, verification_result}

        {:error, reason} ->
          {:ok, error_result(candidate, reason, language)}
      end
    end
  end

  @impl true
  @doc """
  Verifies multiple code candidates in batch.

  Each candidate is executed independently.

  ## Examples

      iex> verifier = CodeExecutionVerifier.new!(%{language: :python})
      iex> candidates = [
      ...>   Candidate.new!(%{id: "1", content: "print(1)"}),
      ...>   Candidate.new!(%{id: "2", content: "print(2)"})
      ...> ]
      iex> {:ok, results} = CodeExecutionVerifier.verify_batch(verifier, candidates, %{})
      iex> length(results)
      2

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
  Code execution verifier does not support streaming.

  """
  @spec supports_streaming?() :: false
  def supports_streaming?, do: false

  # Private functions

  defp extract_code(content) when is_binary(content) do
    content
    |> String.trim()
    |> extract_code_blocks()
    |> case do
      "" -> content
      extracted -> extracted
    end
  end

  # Extract code from markdown code blocks
  defp extract_code_blocks(content) do
    # Match ```language ... ``` blocks
    regex = ~r/```[\w]*\n([\s\S]*?)```/U

    case Regex.run(regex, content) do
      [_, code] -> String.trim(code)
      nil -> ""
    end
  end

  defp detect_language(:auto, code, _candidate) do
    case Regex.run(~r/^#!\s*(\S+)/, code) do
      [_, shebang] -> language_from_shebang(shebang, code)
      _ -> detect_from_code_patterns(code)
    end
  end

  defp detect_language(language, _code, _candidate), do: language

  defp language_from_shebang("/usr/bin/env python3", _code), do: :python
  defp language_from_shebang("/usr/bin/python3", _code), do: :python
  defp language_from_shebang("/usr/bin/env node", _code), do: :javascript
  defp language_from_shebang("/usr/bin/node", _code), do: :javascript
  defp language_from_shebang("/usr/bin/env elixir", _code), do: :elixir
  defp language_from_shebang("/usr/bin/elixir", _code), do: :elixir
  defp language_from_shebang("/usr/bin/env ruby", _code), do: :ruby
  defp language_from_shebang("/usr/bin/ruby", _code), do: :ruby
  defp language_from_shebang("/bin/bash", _code), do: :bash
  defp language_from_shebang("/usr/bin/env bash", _code), do: :bash
  defp language_from_shebang(_shebang, code), do: detect_from_code_patterns(code)

  defp detect_from_code_patterns(code) do
    cond do
      python_pattern?(code) -> :python
      javascript_pattern?(code) -> :javascript
      elixir_pattern?(code) -> :elixir
      ruby_pattern?(code) -> :ruby
      true -> :python
    end
  end

  defp python_pattern?(code), do: String.contains?(code, "def ") and String.contains?(code, "return ")
  defp javascript_pattern?(code), do: String.contains?(code, "function ") or String.contains?(code, "const ")
  defp elixir_pattern?(code), do: String.contains?(code, "defmodule ") or String.contains?(code, "defp ")
  defp ruby_pattern?(code), do: String.contains?(code, "def ") and String.contains?(code, "end")

  defp execute_code(verifier, code, language) do
    {command, args} = build_command(language, code)

    opts = [
      timeout: verifier.timeout,
      cd: verifier.working_dir,
      env: verifier.environment,
      sandbox: verifier.sandbox
    ]

    ToolExecutor.run_command(command, args, opts)
  end

  defp build_command(:python, code), do: {"python3", ["-c", code]}
  defp build_command(:javascript, code), do: {"node", ["-e", code]}
  defp build_command(:elixir, code), do: {"elixir", ["-e", code]}
  defp build_command(:ruby, code), do: {"ruby", ["-e", code]}
  defp build_command(:bash, code), do: {"bash", ["-c", code]}
  # Default to Python
  defp build_command(_, code), do: {"python3", ["-c", code]}

  defp calculate_score(%{exit_code: 0, timed_out: false}, _language), do: 1.0
  defp calculate_score(%{exit_code: _, timed_out: true}, _language), do: 0.0

  defp calculate_score(result, language) do
    output = combined_output(result)

    cond do
      output == "" ->
        0.0

      error_output?(output, language) ->
        0.0

      true ->
        0.5
    end
  end

  defp combined_output(%{stdout: stdout, stderr: stderr}) do
    [stdout, stderr]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp error_output?(output, :python) do
    Regex.match?(
      ~r/Traceback \(most recent call last\)|\bSyntaxError:|\bIndentationError:|\bNameError:|\bTypeError:/,
      output
    )
  end

  defp error_output?(output, :javascript) do
    Regex.match?(~r/\bSyntaxError:|\bReferenceError:|\bTypeError:|\bRangeError:/, output)
  end

  defp error_output?(output, :elixir) do
    Regex.match?(~r/^\*\* \([^)]+Error\)/m, output)
  end

  defp error_output?(output, :ruby) do
    Regex.match?(~r/\bSyntaxError:|\bNameError:|\bNoMethodError:|\bTypeError:/, output)
  end

  defp error_output?(output, :bash) do
    Regex.match?(~r/^bash: /m, output)
  end

  defp error_output?(output, _language) do
    Regex.match?(~r/\bSyntaxError:|\bTraceback\b/, output)
  end

  defp calculate_confidence(%{timed_out: true}), do: 0.0
  defp calculate_confidence(%{exit_code: 0}), do: 1.0
  defp calculate_confidence(_), do: 0.5

  defp build_reasoning(result, language) do
    base = "Executed #{language} code"

    base =
      if result.timed_out do
        "#{base} (timed out after #{result.duration_ms}ms)"
      else
        "#{base} (exit code: #{result.exit_code})"
      end

    if result.stderr == "" do
      base
    else
      "#{base}. stderr: #{String.trim(result.stderr)}"
    end
  end

  defp check_expected_output(result, expected) do
    actual = result.metadata.stdout |> String.trim()

    # Check if expected output is in the actual output
    score =
      if String.contains?(actual, expected) do
        1.0
      else
        0.0
      end

    %{result | score: score}
  end

  defp empty_result(candidate, reasoning) do
    %VerificationResult{
      candidate_id: candidate.id,
      score: 0.0,
      confidence: 0.0,
      reasoning: reasoning
    }
  end

  defp error_result(candidate, reason, language) do
    %VerificationResult{
      candidate_id: candidate.id,
      score: 0.0,
      confidence: 0.0,
      reasoning: "Failed to execute #{language} code: #{format_error(reason)}",
      metadata: %{error: reason, language: language}
    }
  end

  # Validation

  defp apply_expected_output_check(result, context) do
    if expected_output = Map.get(context, :expected_output) do
      check_expected_output(result, expected_output)
    else
      result
    end
  end

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp validate_sandbox(sandbox, _opts) when sandbox in [:none, :docker, :podman], do: :ok
  defp validate_sandbox(_sandbox, _opts), do: {:error, :invalid_sandbox}

  defp validate_language(lang) when lang in [:python, :javascript, :elixir, :ruby, :bash, :auto], do: :ok
  defp validate_language(_), do: {:error, :invalid_language}

  defp validate_working_dir(nil), do: :ok

  defp validate_working_dir(path) when is_binary(path) do
    if File.dir?(path), do: :ok, else: {:error, :directory_not_found}
  end

  defp validate_working_dir(_), do: {:error, :invalid_directory}
  defp format_error(atom) when is_atom(atom), do: atom
end
