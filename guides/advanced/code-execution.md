# Code Execution

Code execution capabilities allow AI models to write and run code to solve problems, perform calculations, and analyze data.

## ⚠️ Security Warning

**Code execution is DISABLED by default and requires explicit opt-in.**

Never enable code execution with:
- Untrusted user input
- Production environments without sandboxing
- Sensitive data without isolation
- Public-facing applications

## Overview

Code execution enables models to:
- **Perform Calculations**: Complex math, statistics, data analysis
- **Data Processing**: Parse, transform, visualize data
- **File Operations**: Read, write, process files
- **Problem Solving**: Write and test code solutions

The code runs in the provider's sandboxed environment, not locally.

## Supported Providers

| Provider | Models | Language | Environment |
|----------|--------|----------|-------------|
| **OpenAI** | GPT-4, GPT-3.5 | Python | Sandboxed interpreter |

## Quick Start

```elixir
alias Jido.AI.Features.CodeExecution

# 1. Check safety
case CodeExecution.safety_check() do
  {:ok, :safe} ->
    IO.puts "Environment passes basic safety checks"
  {:error, concerns} ->
    IO.puts "Safety concerns: #{inspect(concerns)}"
end

# 2. Enable code execution (explicit opt-in required)
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{temperature: 0.2},
  :openai,
  enable: true  # Must be true
)

# 3. Query with code execution
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Calculate the first 10 Fibonacci numbers",
  opts
)

# 4. Extract code execution results
{:ok, results} = CodeExecution.extract_results(response.raw, :openai)

Enum.each(results, fn result ->
  IO.puts "Input: #{result.input}"
  IO.puts "Output: #{result.output}"
end)
```

## Security Model

### Default Behavior (Disabled)

```elixir
# Code execution is OFF by default
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Calculate 1234 * 5678"
)

# Model will estimate, not execute code
```

### Explicit Opt-In Required

```elixir
# Must explicitly enable
opts = CodeExecution.build_code_exec_options(
  %{},
  :openai,
  enable: true  # ← Required
)

# Attempting without enable: true returns error
case CodeExecution.build_code_exec_options(%{}, :openai) do
  {:error, :not_enabled} ->
    IO.puts "Code execution not enabled"
end
```

### Safety Checks

```elixir
case CodeExecution.safety_check() do
  {:ok, :safe} ->
    # Basic checks passed
    :ok

  {:error, concerns} ->
    # Concerns detected
    IO.puts "Safety concerns:"
    Enum.each(concerns, &IO.puts/1)
    # ["Running in production environment"]
end
```

## Usage Examples

### Basic Calculations

```elixir
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{},
  :openai,
  enable: true
)

{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Calculate the compound interest on $10,000 at 5% annually for 10 years",
  opts
)

IO.puts response.content
# "Using the formula A = P(1 + r/n)^(nt)..."
# "The final amount is $16,288.95"
```

### Data Analysis

```elixir
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{temperature: 0.1},  # Lower temperature for accuracy
  :openai,
  enable: true
)

data_query = """
Analyze this dataset:
[12, 15, 18, 22, 25, 28, 30, 32, 35, 38]

Calculate:
1. Mean
2. Median
3. Standard deviation
4. Identify any outliers
"""

{:ok, response} = Jido.AI.chat("openai:gpt-4", data_query, opts)

# Extract code results
{:ok, results} = CodeExecution.extract_results(response.raw, :openai)

Enum.each(results, fn result ->
  IO.puts "Code: #{result.input}"
  IO.puts "Result: #{result.output}"
end)
```

### File Processing

```elixir
# Upload file content in the query
csv_data = """
name,age,city
Alice,30,NYC
Bob,25,SF
Carol,35,LA
"""

query = """
Process this CSV data:
#{csv_data}

Calculate:
1. Average age
2. Count by city
3. Create a summary report
"""

{:ok, opts} = CodeExecution.build_code_exec_options(%{}, :openai, enable: true)
{:ok, response} = Jido.AI.chat("openai:gpt-4", query, opts)
```

### Mathematical Proofs

```elixir
{:ok, opts} = CodeExecution.build_code_exec_options(%{}, :openai, enable: true)

{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Verify that the sum of the first n natural numbers is n(n+1)/2 for n=100",
  opts
)

# Model writes and executes verification code
```

## Advanced Patterns

### 1. Controlled Code Execution

Wrap code execution with additional safeguards:

```elixir
defmodule MyApp.SafeCodeExecution do
  alias Jido.AI.Features.CodeExecution

  def execute_with_review(prompt, opts \\ []) do
    # 1. Safety check
    case CodeExecution.safety_check() do
      {:error, concerns} ->
        {:error, {:safety_check_failed, concerns}}

      {:ok, :safe} ->
        # 2. Check environment
        if Mix.env() == :prod and not Keyword.get(opts, :allow_prod, false) do
          {:error, :production_execution_blocked}
        else
          # 3. Enable and execute
          {:ok, code_opts} = CodeExecution.build_code_exec_options(
            %{},
            :openai,
            [enable: true] ++ opts
          )

          # 4. Execute with timeout
          Task.async(fn ->
            Jido.AI.chat("openai:gpt-4", prompt, code_opts)
          end)
          |> Task.await(30_000)  # 30 second timeout
        end
    end
  end
end
```

### 2. Code Review Before Execution

Get model to explain code before running:

```elixir
defmodule MyApp.CodeReview do
  def execute_with_explanation(problem) do
    # Step 1: Get solution plan
    {:ok, plan_response} = Jido.AI.chat(
      "openai:gpt-4",
      """
      Explain how you would solve this problem with code,
      but DO NOT execute the code yet:

      #{problem}
      """,
      %{temperature: 0.2}
    )

    IO.puts "Plan: #{plan_response.content}"

    # Step 2: Ask user to confirm
    if get_user_confirmation() do
      # Step 3: Execute with code interpreter
      {:ok, opts} = CodeExecution.build_code_exec_options(
        %{},
        :openai,
        enable: true
      )

      Jido.AI.chat("openai:gpt-4", problem, opts)
    else
      {:error, :user_cancelled}
    end
  end

  defp get_user_confirmation do
    IO.gets("Execute this code? (y/n): ") |> String.trim() |> String.downcase() == "y"
  end
end
```

### 3. Iterative Problem Solving

Use code execution in a loop for complex problems:

```elixir
defmodule MyApp.IterativeSolver do
  def solve_iteratively(problem, max_iterations \\ 5) do
    {:ok, opts} = CodeExecution.build_code_exec_options(
      %{},
      :openai,
      enable: true
    )

    Enum.reduce_while(1..max_iterations, {:error, :not_solved}, fn iteration, _acc ->
      IO.puts "Attempt #{iteration}/#{max_iterations}"

      case Jido.AI.chat("openai:gpt-4", problem, opts) do
        {:ok, response} ->
          # Check if solution is correct
          if solution_correct?(response) do
            {:halt, {:ok, response}}
          else
            # Refine problem and try again
            refined_problem = refine_problem(problem, response)
            {:cont, {:error, :not_solved}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp solution_correct?(response) do
    # Check if response indicates success
    String.contains?(response.content, ["successfully", "correct", "verified"])
  end

  defp refine_problem(original, previous_response) do
    """
    #{original}

    Previous attempt was incomplete. Please:
    1. Review the previous output
    2. Identify what's missing
    3. Complete the solution

    Previous output: #{previous_response.content}
    """
  end
end
```

### 4. Data Visualization

Generate visualizations with code execution:

```elixir
defmodule MyApp.DataViz do
  def create_visualization(data, chart_type) do
    {:ok, opts} = CodeExecution.build_code_exec_options(
      %{},
      :openai,
      enable: true
    )

    prompt = """
    Create a #{chart_type} visualization for this data:
    #{inspect(data)}

    Use matplotlib and:
    1. Add proper labels
    2. Include a legend
    3. Save to 'output.png'
    """

    case Jido.AI.chat("openai:gpt-4", prompt, opts) do
      {:ok, response} ->
        # Extract file references
        {:ok, results} = CodeExecution.extract_results(response.raw, :openai)

        files = Enum.flat_map(results, & &1.files)
        {:ok, response, files}

      error -> error
    end
  end
end
```

### 5. Unit Test Generation

Generate and run tests for code:

```elixir
defmodule MyApp.TestGenerator do
  def generate_and_test(function_spec) do
    {:ok, opts} = CodeExecution.build_code_exec_options(
      %{},
      :openai,
      enable: true
    )

    prompt = """
    Write a function that #{function_spec}

    Then:
    1. Write comprehensive unit tests
    2. Run the tests
    3. Report results
    """

    {:ok, response} = Jido.AI.chat("openai:gpt-4", prompt, opts)
    {:ok, results} = CodeExecution.extract_results(response.raw, :openai)

    # Check test results
    test_results = Enum.find(results, fn result ->
      String.contains?(result.output, ["PASSED", "FAILED"])
    end)

    case test_results do
      %{output: output} when output =~ "PASSED" ->
        {:ok, :all_tests_passed, response}
      %{output: output} when output =~ "FAILED" ->
        {:error, :tests_failed, response}
      _ ->
        {:error, :no_test_results, response}
    end
  end
end
```

## Best Practices

### 1. Use Low Temperature

```elixir
# ✅ Good: Low temperature for code execution
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{temperature: 0.1},  # More deterministic
  :openai,
  enable: true
)

# ❌ Bad: High temperature makes code less reliable
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{temperature: 0.9},  # Too creative for code
  :openai,
  enable: true
)
```

### 2. Set Timeouts

```elixir
# Protect against long-running code
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{},
  :openai,
  enable: true,
  timeout: 30  # 30 seconds max
)
```

### 3. Validate Results

```elixir
defmodule MyApp.ResultValidator do
  def execute_and_validate(prompt, expected_type) do
    {:ok, opts} = CodeExecution.build_code_exec_options(%{}, :openai, enable: true)
    {:ok, response} = Jido.AI.chat("openai:gpt-4", prompt, opts)
    {:ok, results} = CodeExecution.extract_results(response.raw, :openai)

    case validate_type(results, expected_type) do
      :ok -> {:ok, results}
      {:error, reason} -> {:error, reason, results}
    end
  end

  defp validate_type(results, :number) do
    if Enum.all?(results, fn r -> r.output =~ ~r/^\d+(\.\d+)?$/ end) do
      :ok
    else
      {:error, :invalid_number_output}
    end
  end

  defp validate_type(_, _), do: :ok
end
```

### 4. Environment Checks

```elixir
defmodule MyApp.EnvironmentCheck do
  def safe_execute(prompt) do
    cond do
      Mix.env() == :prod ->
        {:error, "Code execution blocked in production"}

      Application.get_env(:my_app, :code_execution_enabled, false) != true ->
        {:error, "Code execution not enabled in config"}

      true ->
        {:ok, opts} = CodeExecution.build_code_exec_options(%{}, :openai, enable: true)
        Jido.AI.chat("openai:gpt-4", prompt, opts)
    end
  end
end
```

### 5. Log All Executions

```elixir
defmodule MyApp.AuditedCodeExecution do
  require Logger

  def execute(prompt, user_id) do
    execution_id = generate_execution_id()

    Logger.info("Code execution requested", %{
      execution_id: execution_id,
      user_id: user_id,
      prompt: prompt,
      timestamp: DateTime.utc_now()
    })

    {:ok, opts} = CodeExecution.build_code_exec_options(%{}, :openai, enable: true)

    result = Jido.AI.chat("openai:gpt-4", prompt, opts)

    Logger.info("Code execution completed", %{
      execution_id: execution_id,
      success: match?({:ok, _}, result)
    })

    result
  end

  defp generate_execution_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end
```

## Troubleshooting

### Code Execution Not Enabled Error

```elixir
# Error
{:error, :not_enabled}

# Solution: Must explicitly enable
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{},
  :openai,
  enable: true  # ← Add this
)
```

### Unsupported Provider

```elixir
# Check support before enabling
if CodeExecution.supports?(model) do
  # Enable code execution
else
  IO.puts "This provider doesn't support code execution"
  IO.puts "Try: openai:gpt-4 or openai:gpt-3.5-turbo"
end
```

### Timeout Errors

```elixir
# Increase timeout for long-running code
{:ok, opts} = CodeExecution.build_code_exec_options(
  %{},
  :openai,
  enable: true,
  timeout: 60  # 60 seconds
)
```

### No Code Results

```elixir
# Model may have explained without executing
# Be explicit in prompt
prompt = """
Use the code interpreter to calculate (DO NOT estimate):
#{problem}
"""
```

## Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **OpenAI Code Interpreter** | Sandboxed, simple, integrated | Limited to Python, provider-dependent |
| **Local Execution** | Full control, any language | Security risks, complexity |
| **External Sandbox** | Isolated, customizable | Additional infrastructure |
| **Pre-computed** | Fast, safe | Limited flexibility |

## Next Steps

- [Plugins](plugins.md) - Integrate external tools
- [RAG Integration](rag-integration.md) - Document-enhanced responses
- [Fine-Tuning](fine-tuning.md) - Custom models
- [Provider Matrix](../providers/provider-matrix.md) - Compare providers
