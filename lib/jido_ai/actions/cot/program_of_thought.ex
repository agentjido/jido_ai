defmodule Jido.AI.Actions.CoT.ProgramOfThought do
  @moduledoc """
  Implements Program-of-Thought (PoT) reasoning that separates reasoning from computation.

  PoT generates executable Elixir programs for computational tasks rather than attempting
  reasoning in natural language, providing +8.5% improvement on math benchmarks. The
  implementation focuses on mathematical reasoning, financial calculations, and data
  analysis where precise computation is required.

  ## How it works

  1. **Problem Analysis**: Classifies the problem to determine if it's computational
  2. **Program Generation**: Generates executable Elixir code to solve the problem
  3. **Safe Execution**: Runs the code in a sandboxed environment with resource limits
  4. **Result Integration**: Formats results and generates explanations

  ## Usage

      action = ProgramOfThought.new(%{
        problem: "Calculate compound interest on $1000 at 5% for 10 years",
        domain: :financial
      })

      {:ok, result, agent} = Jido.AI.Runner.Simple.run(agent, action)
      # => result.answer contains computed result
      # => result.program contains generated code
      # => result.explanation contains step-by-step explanation

  ## When to use PoT vs regular CoT

  - Use PoT for: Mathematical calculations, financial computations, data analysis
  - Use regular CoT for: Logical reasoning, planning, general problem solving
  - The problem classifier can automatically route to PoT when appropriate

  ## Safety

  Generated programs are executed in a sandboxed environment with:
  - Timeout enforcement (default: 5 seconds)
  - Memory limits
  - No file system or network access
  - Only safe mathematical operations allowed
  """

  use Jido.Action,
    name: "program_of_thought",
    description: "Solves computational problems by generating and executing programs",
    schema: [
      problem: [
        type: :string,
        required: true,
        doc: "The computational problem to solve"
      ],
      domain: [
        type: :atom,
        required: false,
        doc: "Problem domain (:mathematical, :financial, :scientific, :auto)"
      ],
      timeout: [
        type: :integer,
        required: false,
        default: 5000,
        doc: "Execution timeout in milliseconds"
      ],
      generate_explanation: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Generate explanation of computational steps"
      ],
      validate_result: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Validate result plausibility"
      ],
      model: [
        type: :string,
        required: false,
        doc: "LLM model to use for program generation"
      ]
    ]

  alias Jido.AI.Runner.ProgramOfThought.{
    ProblemClassifier,
    ProgramExecutor,
    ProgramGenerator,
    ResultIntegrator
  }

  require Logger

  @impl true
  def run(params, context) do
    case Map.fetch(params, :problem) do
      {:ok, problem} ->
        domain = Map.get(params, :domain, :auto)
        timeout = Map.get(params, :timeout, 5000)
        generate_explanation = Map.get(params, :generate_explanation, true)
        validate_result = Map.get(params, :validate_result, true)
        model = Map.get(params, :model)

        Logger.debug("Starting Program-of-Thought for problem: #{inspect(problem)}")

        with {:ok, analysis} <- analyze_problem(problem, domain),
             {:ok, program} <- generate_program(problem, analysis, model, context),
             {:ok, execution_result} <- execute_program(program, timeout),
             {:ok, result} <-
               integrate_result(
                 execution_result,
                 program,
                 analysis,
                 generate_explanation,
                 validate_result,
                 model,
                 context
               ) do
          Logger.debug("PoT completed successfully: #{inspect(result.answer)}")

          final_result = %{
            answer: result.answer,
            program: program,
            explanation: result.explanation,
            computational_steps: result.steps,
            domain: analysis.domain,
            execution_time: execution_result.duration_ms,
            validation: result.validation
          }

          {:ok, final_result, context}
        else
          {:error, reason} ->
            Logger.error("PoT failed: #{inspect(reason)}")
            {:error, reason, context}
        end

      :error ->
        {:error, :missing_problem, context}
    end
  end

  # Private functions

  defp analyze_problem(problem, domain) do
    if domain == :auto do
      ProblemClassifier.classify(problem)
    else
      ProblemClassifier.analyze_with_domain(problem, domain)
    end
  end

  defp generate_program(problem, analysis, model, context) do
    opts = [
      domain: analysis.domain,
      complexity: analysis.complexity,
      model: model,
      context: context
    ]

    ProgramGenerator.generate(problem, opts)
  end

  defp execute_program(program, timeout) do
    ProgramExecutor.execute(program, timeout: timeout)
  end

  defp integrate_result(
         execution_result,
         program,
         analysis,
         generate_explanation,
         validate_result,
         model,
         context
       ) do
    opts = [
      program: program,
      analysis: analysis,
      generate_explanation: generate_explanation,
      validate_result: validate_result,
      model: model,
      context: context
    ]

    ResultIntegrator.integrate(execution_result, opts)
  end
end
