defmodule Jido.AI.Runner.ProgramOfThought.ProgramGenerator do
  @moduledoc """
  Generates executable Elixir programs for solving computational problems.

  Creates self-contained programs that:
  - Perform step-by-step calculations
  - Include necessary mathematical functions
  - Have clear output format
  - Are safe to execute in sandbox

  ## Program Structure

  Generated programs follow this structure:

      defmodule Solution do
        def solve do
          # Step 1: Parse inputs
          # Step 2: Perform calculations
          # Step 3: Format result
          result
        end

        # Helper functions as needed
      end

  ## Example

      iex> ProgramGenerator.generate("Calculate 15% of 240", domain: :mathematical)
      {:ok, program_code}

  The generated code will look like:

      defmodule Solution do
        def solve do
          # Calculate 15% of 240
          number = 240
          percentage = 15
          result = number * (percentage / 100)
          result
        end
      end
  """

  require Logger

  alias Jido.AI.Actions.ReqLlm.ChatCompletion

  @doc """
  Generates an executable program for the given problem.

  ## Options

  - `:domain` - Problem domain (:mathematical, :financial, :scientific)
  - `:complexity` - Problem complexity (:low, :medium, :high)
  - `:model` - LLM model to use for generation
  - `:context` - Agent context for LLM calls
  """
  @spec generate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(problem, opts \\ []) do
    domain = Keyword.get(opts, :domain, :mathematical)
    complexity = Keyword.get(opts, :complexity, :medium)
    model = Keyword.get(opts, :model)
    context = Keyword.get(opts, :context, %{})

    Logger.debug("Generating program for domain: #{domain}, complexity: #{complexity}")

    # Build generation prompt
    prompt = build_generation_prompt(problem, domain, complexity)

    # Call LLM to generate program
    case call_llm(prompt, model, context) do
      {:ok, program_text} ->
        # Extract and validate program
        case extract_and_validate_program(program_text) do
          {:ok, program} ->
            Logger.debug("Successfully generated program (#{byte_size(program)} bytes)")
            {:ok, program}

          {:error, reason} ->
            Logger.error("Program validation failed: #{inspect(reason)}")
            {:error, {:invalid_program, reason}}
        end

      {:error, reason} ->
        Logger.error("LLM call failed: #{inspect(reason)}")
        {:error, {:generation_failed, reason}}
    end
  end

  # Private functions

  defp build_generation_prompt(problem, domain, complexity) do
    """
    Generate a self-contained Elixir program to solve the following computational problem.

    ## Problem
    #{problem}

    ## Domain
    #{domain}

    ## Complexity
    #{complexity}

    ## Requirements

    1. Create a module named `Solution` with a `solve/0` function
    2. The `solve/0` function should return the final answer
    3. Include step-by-step calculations with comments
    4. Use appropriate mathematical functions from Elixir's :math module
    5. Handle edge cases and ensure numerical stability
    6. Return a simple value (number, string, or simple data structure)

    ## Available Functions

    You can use these Elixir/Erlang functions:
    - Arithmetic: `+`, `-`, `*`, `/`, `div`, `rem`
    - Math: `:math.pow/2`, `:math.sqrt/1`, `:math.log/1`, `:math.exp/1`
    - Rounding: `round/1`, `trunc/1`, `Float.round/2`
    - Lists: `Enum.sum/1`, `Enum.count/1`, `Enum.map/2`, `Enum.reduce/3`

    ## Example Structure

    ```elixir
    defmodule Solution do
      def solve do
        # Step 1: Define the problem parameters
        principal = 1000
        rate = 0.05
        time = 10

        # Step 2: Calculate compound interest
        # A = P(1 + r)^t
        amount = principal * :math.pow(1 + rate, time)

        # Step 3: Calculate interest earned
        interest = amount - principal

        # Step 4: Round to 2 decimal places
        Float.round(interest, 2)
      end
    end
    ```

    #{domain_specific_guidance(domain)}

    Now generate the complete Elixir program. Provide ONLY the code in a code block:

    ```elixir
    # Your complete solution here
    ```

    Make sure the code is:
    - Complete and executable
    - Well-commented
    - Numerically correct
    - Safe (no file I/O, no network calls, no infinite loops)
    """
  end

  defp domain_specific_guidance(:mathematical) do
    """
    ## Mathematical Domain Guidance

    - Use precise numerical methods
    - Consider floating point precision
    - Handle division by zero
    - Use appropriate rounding
    """
  end

  defp domain_specific_guidance(:financial) do
    """
    ## Financial Domain Guidance

    - Round to 2 decimal places for currency
    - Handle percentages correctly (divide by 100)
    - Use compound interest formula: A = P(1 + r/n)^(nt)
    - Consider time value of money
    """
  end

  defp domain_specific_guidance(:scientific) do
    """
    ## Scientific Domain Guidance

    - Include proper unit conversions
    - Use scientific notation where appropriate
    - Consider significant figures
    - Apply relevant physics formulas correctly
    """
  end

  defp domain_specific_guidance(_) do
    ""
  end

  defp call_llm(prompt, model_name, context) do
    model = model_name || get_default_model(context)

    params = %{
      model: model,
      messages: [
        %{role: "system", content: system_message()},
        %{role: "user", content: prompt}
      ],
      temperature: 0.2,
      # Low temperature for precise code
      max_tokens: 1500
    }

    try do
      case ChatCompletion.run(params, context) do
        {:ok, result, _context} ->
          content = extract_content(result)
          {:ok, content}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error ->
        {:error, {:llm_error, error}}
    end
  end

  defp system_message do
    """
    You are an expert Elixir programmer specializing in computational problem solving.

    Your task is to generate precise, executable Elixir programs that solve
    computational problems through step-by-step calculations.

    Rules:
    1. Always use the Solution module with a solve/0 function
    2. Include clear comments explaining each step
    3. Use proper Elixir syntax and idioms
    4. Ensure numerical accuracy
    5. No external dependencies
    6. No file I/O or network operations
    7. No infinite loops or recursion without base cases
    8. Return simple, clear answers

    Focus on correctness and clarity over cleverness.
    """
  end

  defp extract_content(result) do
    case result do
      %{content: content} -> content
      %{message: %{content: content}} -> content
      %{choices: [%{message: %{content: content}} | _]} -> content
      _ -> inspect(result)
    end
  end

  defp extract_and_validate_program(text) do
    # Extract code from markdown code block
    code =
      case Regex.run(~r/```elixir\s+(.*?)\s+```/s, text) do
        [_, extracted_code] -> String.trim(extracted_code)
        nil -> String.trim(text)
      end

    # Validate program structure
    with :ok <- validate_has_module(code),
         :ok <- validate_has_solve_function(code),
         :ok <- validate_safe_code(code) do
      {:ok, code}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_has_module(code) do
    if Regex.match?(~r/defmodule\s+Solution\s+do/, code) do
      :ok
    else
      {:error, :missing_solution_module}
    end
  end

  defp validate_has_solve_function(code) do
    if Regex.match?(~r/def\s+solve\s*(\(\s*\))?\s+do/, code) do
      :ok
    else
      {:error, :missing_solve_function}
    end
  end

  defp validate_safe_code(code) do
    # Check for unsafe operations
    unsafe_patterns = [
      {~r/File\./, :file_io_detected},
      {~r/System\./, :system_call_detected},
      {~r/Code\.eval/, :code_eval_detected},
      {~r/spawn|Task\./, :process_spawn_detected},
      {~r/Agent\.|GenServer\./, :stateful_process_detected}
    ]

    case Enum.find(unsafe_patterns, fn {pattern, _reason} ->
           Regex.match?(pattern, code)
         end) do
      nil ->
        :ok

      {_pattern, reason} ->
        {:error, reason}
    end
  end

  defp get_default_model(context) do
    Map.get(context, :default_model, "gpt-4")
  end
end
