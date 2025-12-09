defmodule Jido.AI.Actions.CoT.GenerateElixirCode do
  @moduledoc """
  Generates Elixir code from structured Chain-of-Thought reasoning.

  This action implements structured CoT code generation that aligns reasoning
  structure with program structure, improving code quality by 13.79% over
  unstructured CoT approaches.

  The generation process:
  1. Analyzes requirements to identify program structures
  2. Selects appropriate reasoning template (sequence, branch, loop, functional)
  3. Generates structured reasoning following the template
  4. Translates reasoning to idiomatic Elixir code
  5. Generates specs, docs, and typespecs

  ## Usage

      action = GenerateElixirCode.new(%{
        requirements: "Create a function that filters and transforms a list",
        function_name: "process_items",
        module_name: "MyApp.Processor"
      })

      {:ok, result, agent} = Jido.AI.Runner.Simple.run(agent, action)
      # => result.code contains generated Elixir code
  """

  use Jido.Action,
    name: "generate_elixir_code",
    description: "Generates Elixir code using structured Chain-of-Thought reasoning",
    schema: [
      requirements: [
        type: :string,
        required: true,
        doc: "Description of what the code should do"
      ],
      function_name: [
        type: :string,
        required: false,
        doc: "Name of the function to generate"
      ],
      module_name: [
        type: :string,
        required: false,
        doc: "Module name for the generated code"
      ],
      template_type: [
        type: :atom,
        required: false,
        doc: "Specific template to use (:sequence, :branch, :loop, :functional)"
      ],
      generate_specs: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Generate @spec annotations"
      ],
      generate_docs: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Generate @doc documentation"
      ],
      model: [
        type: :string,
        required: false,
        doc: "LLM model to use for code generation"
      ]
    ]

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Runner.ChainOfThought.StructuredCode.{ProgramAnalyzer, ReasoningTemplates}

  @impl true
  def run(params, context) do
    case Map.fetch(params, :requirements) do
      {:ok, requirements} ->
        template_type = Map.get(params, :template_type)
        generate_specs = Map.get(params, :generate_specs, true)
        generate_docs = Map.get(params, :generate_docs, true)
        model = Map.get(params, :model)

        with {:ok, analysis} <- ProgramAnalyzer.analyze(requirements),
             {:ok, template} <- get_reasoning_template(analysis, template_type),
             {:ok, reasoning} <-
               generate_structured_reasoning(requirements, template, model, context),
             {:ok, code} <-
               translate_to_code(reasoning, analysis, params, generate_specs, generate_docs) do
          result = %{
            code: code,
            reasoning: reasoning,
            analysis: analysis,
            template: template.type,
            elixir_patterns: analysis.elixir_patterns
          }

          {:ok, result, context}
        else
          {:error, reason} -> {:error, reason, context}
        end

      :error ->
        {:error, :missing_requirements, context}
    end
  end

  # Private functions

  defp get_reasoning_template(analysis, prefer_type) do
    opts = if prefer_type, do: [prefer: prefer_type], else: []
    template = ReasoningTemplates.get_template(analysis, opts)
    {:ok, template}
  end

  defp generate_structured_reasoning(requirements, template, model, context) do
    # Format template as prompt
    prompt = ReasoningTemplates.format_template(template, requirements)

    # Add instruction for structured thinking
    full_prompt = """
    #{prompt}

    Now, follow the template above to reason through the solution step by step.
    Be specific and concrete in each section. Focus on Elixir-specific patterns
    and idiomatic code.

    After completing your reasoning, provide a summary of your approach.
    """

    # Call LLM for reasoning generation
    model_name = model || get_default_model(context)

    case call_llm(full_prompt, model_name, context) do
      {:ok, reasoning_text} ->
        {:ok, parse_reasoning(reasoning_text, template)}

      {:error, reason} ->
        {:error, {:reasoning_generation_failed, reason}}
    end
  end

  defp translate_to_code(reasoning, analysis, params, generate_specs, generate_docs) do
    function_name = Map.get(params, :function_name, "process")
    module_name = Map.get(params, :module_name)

    # Build prompt for code generation
    prompt =
      build_code_generation_prompt(
        reasoning,
        analysis,
        function_name,
        generate_specs,
        generate_docs
      )

    # Call LLM for code generation
    model_name = Map.get(params, :model)

    case call_llm(prompt, model_name, %{}) do
      {:ok, code_text} ->
        # Extract code from response
        code = extract_code_block(code_text)

        # Wrap in module if specified
        final_code =
          if module_name do
            wrap_in_module(code, module_name)
          else
            code
          end

        {:ok, final_code}

      {:error, reason} ->
        {:error, {:code_generation_failed, reason}}
    end
  end

  defp parse_reasoning(text, template) do
    # Parse reasoning text into structured format
    %{
      raw: text,
      template_type: template.type,
      sections: extract_sections(text, template.sections)
    }
  end

  defp extract_sections(text, section_names) do
    # Simple extraction: look for section headers
    sections =
      Enum.reduce(section_names, %{}, fn section, acc ->
        # Try to find section in text
        section_text = extract_section_text(text, section)
        Map.put(acc, section, section_text)
      end)

    sections
  end

  defp extract_section_text(text, section_name) do
    # Look for markdown header with section name
    regex = ~r/##\s+#{section_name}\s+(.*?)(?=##|\z)/s

    case Regex.run(regex, text) do
      [_, content] -> String.trim(content)
      nil -> ""
    end
  end

  defp build_code_generation_prompt(
         reasoning,
         analysis,
         function_name,
         generate_specs,
         generate_docs
       ) do
    """
    Based on the following structured reasoning, generate idiomatic Elixir code.

    ## Reasoning
    #{reasoning.raw}

    ## Program Analysis
    - Structures: #{inspect(analysis.structures)}
    - Control Flow: #{inspect(analysis.control_flow.type)}
    - Data Flow: #{inspect(analysis.data_flow.transformations)}
    - Elixir Patterns: #{inspect(analysis.elixir_patterns)}

    ## Code Generation Requirements

    Function name: `#{function_name}`

    Generate code that:
    1. Follows the reasoning structure exactly
    2. Uses idiomatic Elixir patterns (#{Enum.join(analysis.elixir_patterns, ", ")})
    3. Includes proper error handling
    4. Uses pattern matching where appropriate
    5. Leverages the pipe operator for sequences
    #{if generate_specs, do: "6. Includes @spec type specifications", else: ""}
    #{if generate_docs, do: "7. Includes @doc documentation", else: ""}

    Provide ONLY the Elixir code, wrapped in a code block:

    ```elixir
    # Your code here
    ```

    Make sure the code is complete, correct, and follows Elixir best practices.
    """
  end

  defp extract_code_block(text) do
    # Extract code from markdown code block
    case Regex.run(~r/```elixir\s+(.*?)\s+```/s, text) do
      [_, code] -> String.trim(code)
      nil -> String.trim(text)
    end
  end

  defp wrap_in_module(code, module_name) do
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      Generated code using structured Chain-of-Thought reasoning.
      \"\"\"

    #{indent_code(code, 2)}
    end
    """
  end

  defp indent_code(code, spaces) do
    indent = String.duplicate(" ", spaces)

    code
    |> String.split("\n")
    |> Enum.map_join("\n", &"#{indent}#{&1}")
  end

  defp call_llm(prompt, model_name, context) do
    # Check if we have chat completion action available
    model = model_name || get_default_model(context)

    # Build chat completion params
    params = %{
      model: model,
      messages: [
        %{role: "system", content: system_message()},
        %{role: "user", content: prompt}
      ],
      temperature: 0.2,
      max_tokens: 2000
    }

    # Try to use Jido.AI.Actions.ReqLlm.ChatCompletion if available
    try do
      case ChatCompletion.run(params, context) do
        {:ok, result, _context} ->
          # Extract content from response
          content =
            case result do
              %{content: content} -> content
              %{message: %{content: content}} -> content
              %{choices: [%{message: %{content: content}} | _]} -> content
              _ -> inspect(result)
            end

          {:ok, content}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      _ ->
        # Fallback: return a placeholder or error
        {:error, :llm_unavailable}
    end
  end

  defp system_message do
    """
    You are an expert Elixir developer specializing in functional programming and
    idiomatic Elixir code. You write clean, maintainable, and efficient code that
    follows Elixir best practices.

    When generating code:
    - Use pattern matching instead of conditionals where possible
    - Leverage the pipe operator for data transformations
    - Use Enum functions for collection operations
    - Employ guard clauses for function constraints
    - Handle errors with {:ok, result} / {:error, reason} tuples
    - Write clear, descriptive function and variable names
    - Include type specs and documentation
    """
  end

  defp get_default_model(context) do
    # Try to get model from context, otherwise use default
    Map.get(context, :default_model, "gpt-4")
  end
end
