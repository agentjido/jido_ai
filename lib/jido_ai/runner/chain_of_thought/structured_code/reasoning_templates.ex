defmodule Jido.AI.Runner.ChainOfThought.StructuredCode.ReasoningTemplates do
  @moduledoc """
  Structured reasoning templates aligned with Elixir programming patterns.

  Provides:
  - SEQUENCE template for pipeline transformations
  - BRANCH template for pattern matching and conditional logic
  - LOOP template for recursive processing and enumeration
  - FUNCTIONAL PATTERNS template for higher-order functions and composition

  These templates structure reasoning to align with program structure,
  improving code generation accuracy by 13.79% over unstructured CoT.

  ## Usage

      template = ReasoningTemplates.get_template(:sequence, analysis)
      prompt = ReasoningTemplates.format_template(template, requirements)
  """

  alias Jido.AI.Runner.ChainOfThought.StructuredCode.ProgramAnalyzer

  @type template_type :: :sequence | :branch | :loop | :functional | :hybrid
  @type template :: %{
          type: template_type(),
          sections: list(String.t()),
          prompts: map(),
          elixir_patterns: list(atom())
        }

  @doc """
  Gets reasoning template for given analysis.

  ## Parameters

  - `analysis` - Program analysis from ProgramAnalyzer
  - `opts` - Options:
    - `:prefer` - Preferred template type
    - `:include_examples` - Include code examples (default: true)

  ## Returns

  Template map with reasoning structure
  """
  @spec get_template(ProgramAnalyzer.analysis(), keyword()) :: template()
  def get_template(analysis, opts \\ []) do
    prefer = Keyword.get(opts, :prefer)
    include_examples = Keyword.get(opts, :include_examples, true)

    # Select template based on analysis
    type = select_template_type(analysis, prefer)

    # Get template structure
    template = build_template(type, analysis, include_examples)

    template
  end

  @doc """
  Gets SEQUENCE template for pipeline transformations.

  ## Returns

  Template map for sequence reasoning
  """
  @spec sequence_template(keyword()) :: template()
  def sequence_template(opts \\ []) do
    include_examples = Keyword.get(opts, :include_examples, true)

    %{
      type: :sequence,
      sections: [
        "INPUT_ANALYSIS",
        "TRANSFORMATION_STEPS",
        "PIPELINE_DESIGN",
        "ERROR_HANDLING",
        "OUTPUT_SPECIFICATION"
      ],
      prompts: %{
        input_analysis: """
        ## INPUT ANALYSIS
        What is the structure and type of the input data?
        What validations are needed for the input?
        What edge cases should be considered?
        """,
        transformation_steps: """
        ## TRANSFORMATION STEPS
        Break down the transformation into discrete steps:
        1. Step 1: [What transformation?]
        2. Step 2: [What transformation?]
        3. ...

        For each step:
        - What Enum function is most appropriate?
        - What is the input and output type?
        - Are there any side effects?
        """,
        pipeline_design: """
        ## PIPELINE DESIGN
        Design the pipeline using the |> operator:
        ```elixir
        input
        |> step_1()
        |> step_2()
        |> step_3()
        ```

        Consider:
        - Can steps be combined for efficiency?
        - Should any steps be extracted to helper functions?
        - Where should validations occur in the pipeline?
        """,
        error_handling: """
        ## ERROR HANDLING
        What errors can occur in the pipeline?
        Should we use:
        - with syntax for early returns?
        - {:ok, result} / {:error, reason} tuples?
        - Raise exceptions for unexpected cases?
        """,
        output_specification: """
        ## OUTPUT SPECIFICATION
        What is the expected output type and structure?
        How should the output be formatted?
        What guarantees can we provide about the output?
        """
      },
      examples:
        if include_examples do
          %{
            simple: """
            # Example: Transform a list of strings to uppercase and filter non-empty
            ["hello", "", "world"]
            |> Enum.map(&String.upcase/1)
            |> Enum.reject(&(&1 == ""))
            # => ["HELLO", "WORLD"]
            """,
            with_validation: """
            # Example: Pipeline with validation
            def process_data(input) do
              with {:ok, validated} <- validate_input(input),
                   {:ok, transformed} <- transform_data(validated),
                   {:ok, formatted} <- format_output(transformed) do
                {:ok, formatted}
              end
            end
            """
          }
        else
          %{}
        end,
      elixir_patterns: [:pipeline, :enum_functions, :with_syntax]
    }
  end

  @doc """
  Gets BRANCH template for pattern matching and conditional logic.

  ## Returns

  Template map for branch reasoning
  """
  @spec branch_template(keyword()) :: template()
  def branch_template(opts \\ []) do
    include_examples = Keyword.get(opts, :include_examples, true)

    %{
      type: :branch,
      sections: [
        "CONDITION_ANALYSIS",
        "PATTERN_IDENTIFICATION",
        "BRANCH_DESIGN",
        "GUARD_CLAUSES",
        "DEFAULT_CASE"
      ],
      prompts: %{
        condition_analysis: """
        ## CONDITION ANALYSIS
        What conditions determine the different execution paths?
        Are the conditions mutually exclusive?
        What is the natural order for checking conditions?
        """,
        pattern_identification: """
        ## PATTERN IDENTIFICATION
        Can we use pattern matching instead of conditionals?
        What patterns can be matched on:
        - Data structure shape?
        - Value ranges?
        - Type information?
        - Boolean flags?

        Consider matching in function heads vs. case expressions.
        """,
        branch_design: """
        ## BRANCH DESIGN
        Design the branching logic:

        Option 1 - Function clauses with pattern matching:
        ```elixir
        def process(%{type: :a} = data), do: handle_a(data)
        def process(%{type: :b} = data), do: handle_b(data)
        ```

        Option 2 - Case expression:
        ```elixir
        case value do
          pattern1 -> result1
          pattern2 -> result2
          _ -> default
        end
        ```

        Option 3 - Cond for complex conditions:
        ```elixir
        cond do
          condition1 -> result1
          condition2 -> result2
          true -> default
        end
        ```

        Which approach is most appropriate?
        """,
        guard_clauses: """
        ## GUARD CLAUSES
        Can guards improve pattern matching?
        ```elixir
        def process(n) when n > 0, do: :positive
        def process(n) when n < 0, do: :negative
        def process(0), do: :zero
        ```

        What guards are needed:
        - Type checks? (is_integer, is_binary, etc.)
        - Value checks? (>, <, ==, etc.)
        - Combined conditions? (and, or)
        """,
        default_case: """
        ## DEFAULT CASE
        What should happen for unmatched cases?
        - Raise an error?
        - Return default value?
        - Log warning and continue?

        Make sure all cases are covered to avoid FunctionClauseError.
        """
      },
      examples:
        if include_examples do
          %{
            pattern_matching: """
            # Example: Pattern matching in function heads
            def handle_result({:ok, value}), do: process_value(value)
            def handle_result({:error, reason}), do: handle_error(reason)
            def handle_result(nil), do: {:error, :not_found}
            """,
            with_guards: """
            # Example: Pattern matching with guards
            def classify(n) when is_integer(n) and n > 100, do: :large
            def classify(n) when is_integer(n) and n > 10, do: :medium
            def classify(n) when is_integer(n), do: :small
            def classify(_), do: {:error, :not_integer}
            """
          }
        else
          %{}
        end,
      elixir_patterns: [:pattern_matching, :guards, :function_clauses]
    }
  end

  @doc """
  Gets LOOP template for recursive processing and enumeration.

  ## Returns

  Template map for loop reasoning
  """
  @spec loop_template(keyword()) :: template()
  def loop_template(opts \\ []) do
    include_examples = Keyword.get(opts, :include_examples, true)

    %{
      type: :loop,
      sections: [
        "ITERATION_ANALYSIS",
        "APPROACH_SELECTION",
        "BASE_CASE",
        "RECURSIVE_CASE",
        "ACCUMULATOR_DESIGN"
      ],
      prompts: %{
        iteration_analysis: """
        ## ITERATION ANALYSIS
        What needs to be iterated over?
        - Collection (list, map, etc.)?
        - Range of numbers?
        - Until condition is met?

        What happens in each iteration?
        - Transform element?
        - Accumulate result?
        - Side effect?
        """,
        approach_selection: """
        ## APPROACH SELECTION
        Choose the most appropriate approach:

        1. Enum functions (map, filter, reduce, etc.):
           - Best for: Simple transformations on collections
           - Pros: Clear, concise, optimized
           - Cons: Limited to Enumerable types

        2. Recursion:
           - Best for: Tree traversal, custom iteration logic
           - Pros: Flexible, functional
           - Cons: Stack depth limits, more complex

        3. Tail recursion with accumulator:
           - Best for: Large collections, need efficiency
           - Pros: Constant stack space, efficient
           - Cons: More complex than Enum

        Which approach fits best?
        """,
        base_case: """
        ## BASE CASE
        What is the termination condition?
        ```elixir
        def process([]), do: # base case
        def process([head | tail]), do: # recursive case
        ```

        What should the base case return?
        - Empty collection?
        - Accumulated result?
        - Default value?
        """,
        recursive_case: """
        ## RECURSIVE CASE
        How does each iteration work?
        ```elixir
        def process([head | tail]) do
          # Process head
          result = transform(head)

          # Recurse on tail
          [result | process(tail)]
        end
        ```

        Consider:
        - How is head processed?
        - How are results combined?
        - Is tail call optimization possible?
        """,
        accumulator_design: """
        ## ACCUMULATOR DESIGN
        If using accumulator pattern:
        ```elixir
        def process(list), do: do_process(list, initial_acc)

        defp do_process([], acc), do: acc
        defp do_process([head | tail], acc) do
          new_acc = update_accumulator(acc, head)
          do_process(tail, new_acc)
        end
        ```

        What is the accumulator:
        - Type and initial value?
        - How is it updated each iteration?
        - How is it transformed to final result?
        """
      },
      examples:
        if include_examples do
          %{
            enum_approach: """
            # Example: Using Enum
            def sum_squares(numbers) do
              numbers
              |> Enum.map(&(&1 * &1))
              |> Enum.sum()
            end
            """,
            tail_recursion: """
            # Example: Tail recursive sum
            def sum(list), do: sum(list, 0)

            defp sum([], acc), do: acc
            defp sum([head | tail], acc), do: sum(tail, acc + head)
            """
          }
        else
          %{}
        end,
      elixir_patterns: [:recursion, :enum_functions, :tail_recursion]
    }
  end

  @doc """
  Gets FUNCTIONAL template for higher-order functions and composition.

  ## Returns

  Template map for functional patterns reasoning
  """
  @spec functional_template(keyword()) :: template()
  def functional_template(opts \\ []) do
    include_examples = Keyword.get(opts, :include_examples, true)

    %{
      type: :functional,
      sections: [
        "FUNCTION_COMPOSITION",
        "HIGHER_ORDER_FUNCTIONS",
        "PARTIAL_APPLICATION",
        "FUNCTION_CAPTURE",
        "ABSTRACTION_DESIGN"
      ],
      prompts: %{
        function_composition: """
        ## FUNCTION COMPOSITION
        Can the solution be built by composing simpler functions?
        ```elixir
        # Instead of:
        def complex_transform(data) do
          data |> step1() |> step2() |> step3()
        end

        # Consider:
        composed = fn data -> data |> step1() |> step2() |> step3() end
        ```

        What are the atomic functions to compose?
        In what order should they be composed?
        """,
        higher_order_functions: """
        ## HIGHER_ORDER FUNCTIONS
        What functions take or return other functions?
        ```elixir
        # Functions that take functions:
        def apply_transform(data, transform_fn) do
          Enum.map(data, transform_fn)
        end

        # Functions that return functions:
        def make_multiplier(factor) do
          fn x -> x * factor end
        end
        ```

        Benefits:
        - Reusability
        - Configurability
        - Separation of concerns
        """,
        partial_application: """
        ## PARTIAL APPLICATION
        Can we create specialized functions by partially applying arguments?
        ```elixir
        multiply = fn a, b -> a * b end
        double = fn x -> multiply.(2, x) end
        triple = fn x -> multiply.(3, x) end
        ```

        Where would partial application simplify the code?
        """,
        function_capture: """
        ## FUNCTION CAPTURE
        Use capture operator for concise function passing:
        ```elixir
        # Instead of:
        Enum.map(list, fn x -> String.upcase(x) end)

        # Use capture:
        Enum.map(list, &String.upcase/1)

        # Or:
        Enum.map(list, &(&1 * 2))
        ```

        Where can function capture improve readability?
        """,
        abstraction_design: """
        ## ABSTRACTION DESIGN
        What abstractions make the solution clearer?

        Consider:
        - What varies vs. what stays the same?
        - What behavior should be parameterized?
        - What functions are reusable?
        - What level of abstraction is appropriate?

        Balance: Too abstract = complex, Too concrete = duplicate code
        """
      },
      examples:
        if include_examples do
          %{
            composition: """
            # Example: Function composition
            sanitize_and_validate = fn input ->
              input
              |> String.trim()
              |> String.downcase()
              |> validate_format()
            end
            """,
            higher_order: """
            # Example: Higher-order function
            def filter_map(collection, filter_fn, map_fn) do
              collection
              |> Enum.filter(filter_fn)
              |> Enum.map(map_fn)
            end

            # Usage:
            filter_map(users, &(&1.active), &(&1.name))
            """
          }
        else
          %{}
        end,
      elixir_patterns: [:higher_order_functions, :function_composition, :capture_operator]
    }
  end

  @doc """
  Formats template with specific requirements.

  ## Parameters

  - `template` - Template to format
  - `requirements` - Specific code requirements

  ## Returns

  Formatted reasoning prompt
  """
  @spec format_template(template(), String.t()) :: String.t()
  def format_template(template, requirements) do
    """
    # Structured Reasoning: #{String.upcase(to_string(template.type))} Pattern

    ## Requirements
    #{requirements}

    ## Recommended Elixir Patterns
    #{Enum.map_join(template.elixir_patterns, ", ", &to_string/1)}

    #{format_sections(template)}

    #{format_examples(template)}
    """
  end

  # Private functions

  defp select_template_type(analysis, prefer) do
    # If preference specified, use it
    if prefer do
      prefer
    else
      # Select based on analysis
      cond do
        analysis.control_flow.type == :iterative and :pipeline in analysis.elixir_patterns ->
          :sequence

        analysis.control_flow.type == :conditional ->
          :branch

        analysis.control_flow.type in [:iterative, :recursive] ->
          :loop

        :composition in analysis.structures or
            :higher_order_functions in analysis.elixir_patterns ->
          :functional

        # Multiple patterns needed - hybrid approach
        length(analysis.structures) > 2 ->
          :hybrid

        true ->
          :sequence
      end
    end
  end

  defp build_template(type, analysis, include_examples) do
    opts = [include_examples: include_examples]

    base_template =
      case type do
        :sequence -> sequence_template(opts)
        :branch -> branch_template(opts)
        :loop -> loop_template(opts)
        :functional -> functional_template(opts)
        :hybrid -> build_hybrid_template(analysis, opts)
      end

    # Enhance with analysis-specific information
    Map.put(base_template, :analysis, analysis)
  end

  defp build_hybrid_template(analysis, opts) do
    # Combine multiple templates based on analysis
    templates = []

    templates =
      if :pipeline in analysis.elixir_patterns do
        [sequence_template(opts) | templates]
      else
        templates
      end

    templates =
      if analysis.control_flow.type == :conditional do
        [branch_template(opts) | templates]
      else
        templates
      end

    templates =
      if analysis.control_flow.type in [:iterative, :recursive] do
        [loop_template(opts) | templates]
      else
        templates
      end

    # Merge templates
    %{
      type: :hybrid,
      sections:
        templates
        |> Enum.flat_map(& &1.sections)
        |> Enum.uniq(),
      prompts:
        templates
        |> Enum.map(& &1.prompts)
        |> Enum.reduce(%{}, &Map.merge/2),
      examples:
        templates
        |> Enum.map(&Map.get(&1, :examples, %{}))
        |> Enum.reduce(%{}, &Map.merge/2),
      elixir_patterns:
        templates
        |> Enum.flat_map(& &1.elixir_patterns)
        |> Enum.uniq()
    }
  end

  defp format_sections(template) do
    template.sections
    |> Enum.map_join("\n\n", fn section ->
      # Safe atom conversion - only convert if atom already exists
      # This prevents creating arbitrary atoms from template section strings
      section_key =
        try do
          section |> String.downcase() |> String.to_existing_atom()
        rescue
          ArgumentError ->
            # Section string doesn't map to an existing atom key
            # Return nil to skip this section (no corresponding prompt)
            nil
        end

      if section_key do
        Map.get(template.prompts, section_key, "")
      else
        ""
      end
    end)
  end

  defp format_examples(template) do
    examples = Map.get(template, :examples, %{})

    if Enum.empty?(examples) do
      ""
    else
      """
      ## Examples

      #{Enum.map_join(examples, "\n\n", fn {name, code} -> """
        ### #{String.capitalize(to_string(name))}
        #{code}
        """ end)}
      """
    end
  end
end
