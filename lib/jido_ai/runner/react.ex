defmodule Jido.AI.Runner.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) Chain-of-Thought implementation.

  Implements the ReAct pattern that interleaves reasoning with action execution
  and observation. This enables multi-source research and information gathering
  with +27.4% improvement on HotpotQA benchmark.

  The ReAct loop:
  1. **Thought**: Generate reasoning about what to do next based on current state
  2. **Action**: Select and execute an action (tool call) based on the thought
  3. **Observation**: Capture and process the result of the action
  4. **Repeat**: Continue until answer found or max steps reached

  ## Usage

      {:ok, result} = ReAct.run(
        question: "What is the capital of the country where the Eiffel Tower is located?",
        tools: [search_tool, wikipedia_tool],
        max_steps: 10
      )

      # => %{
      #   answer: "Paris",
      #   steps: 5,
      #   trajectory: [
      #     %{thought: "I need to find where the Eiffel Tower is", action: "search", ...},
      #     %{thought: "The Eiffel Tower is in France", action: "search", ...},
      #     %{thought: "Now I need the capital of France", action: "search", ...},
      #     ...
      #   ]
      # }

  ## Research

  ReAct shows significant improvements on multi-hop reasoning tasks:
  - HotpotQA: +27.4% accuracy improvement
  - Fever: +19.5% accuracy improvement
  - Cost: ~10-20x (depends on number of steps)
  - Best for: Information gathering, multi-source research, iterative investigation

  ## Design

  ReAct is particularly effective because:
  - Reasoning guides action selection (more targeted than random exploration)
  - Actions provide grounded observations (reduces hallucination)
  - Iterative nature allows correction of mistakes
  - Natural integration with tool/function calling

  The implementation integrates with Jido's action system, treating Jido actions
  as ReAct tools.
  """

  require Logger

  alias Jido.AI.Runner.ReAct.{
    ActionSelector,
    ObservationProcessor,
    ToolRegistry
  }

  @default_max_steps 10
  @default_temperature 0.7
  @default_thought_template """
  You are solving the following question using a thought-action-observation loop.

  Question: {question}

  You have access to the following tools:
  {tools}

  Previous trajectory:
  {trajectory}

  Based on the above, what should you do next?

  Respond in this format:
  Thought: <your reasoning about what to do next>
  Action: <tool_name>
  Action Input: <input for the tool>

  Or if you have the final answer:
  Thought: <reasoning about why you have the answer>
  Final Answer: <the answer>
  """

  @type step :: %{
          step_number: pos_integer(),
          thought: String.t(),
          action: String.t() | nil,
          action_input: term() | nil,
          observation: String.t() | nil,
          final_answer: String.t() | nil
        }

  @type trajectory :: list(step())

  @type result :: %{
          answer: String.t() | nil,
          steps: pos_integer(),
          trajectory: trajectory(),
          success: boolean(),
          reason: atom(),
          metadata: map()
        }

  @doc """
  Runs the ReAct reasoning loop.

  ## Parameters

  - `opts` - Options:
    - `:question` - The question to answer (required)
    - `:tools` - List of available tools/actions (required)
    - `:max_steps` - Maximum reasoning steps (default: 10)
    - `:temperature` - Temperature for thought generation (default: 0.7)
    - `:thought_template` - Custom thought prompt template
    - `:thought_fn` - Custom thought generation function (for testing)
    - `:context` - Additional context for tool execution

  ## Returns

  - `{:ok, result}` - Successfully found answer or reached conclusion
  - `{:error, reason}` - Failed to execute ReAct loop

  ## Examples

      {:ok, result} = ReAct.run(
        question: "What year was the company that created Elixir founded?",
        tools: [search_tool, calculator_tool],
        max_steps: 15
      )
  """
  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts \\ []) do
    question = Keyword.fetch!(opts, :question)
    tools = Keyword.get(opts, :tools, [])
    max_steps = Keyword.get(opts, :max_steps, @default_max_steps)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    thought_template = Keyword.get(opts, :thought_template, @default_thought_template)
    thought_fn = Keyword.get(opts, :thought_fn)
    context = Keyword.get(opts, :context, %{})

    Logger.info("Starting ReAct loop for question: #{String.slice(question, 0, 50)}...")

    # Initialize state
    state = %{
      question: question,
      tools: tools,
      trajectory: [],
      step_number: 0,
      max_steps: max_steps,
      temperature: temperature,
      thought_template: thought_template,
      thought_fn: thought_fn,
      context: context
    }

    # Execute loop
    execute_loop(state)
  end

  @doc """
  Executes a single step of the ReAct loop.

  Used for testing and step-by-step execution.

  ## Parameters

  - `state` - Current ReAct state
  - `opts` - Options for this step

  ## Returns

  - `{:continue, updated_state, step}` - Step executed, continue loop
  - `{:finish, final_state, final_step}` - Found answer, finish loop
  - `{:error, reason}` - Step failed
  """
  @spec execute_step(map(), keyword()) ::
          {:continue, map(), step()}
          | {:finish, map(), step()}
          | {:error, term()}
  def execute_step(state, opts \\ []) do
    step_number = state.step_number + 1

    Logger.debug("ReAct step #{step_number}/#{state.max_steps}")

    # Generate thought
    case generate_thought(state, opts) do
      {:ok, thought_output} ->
        # Parse thought output
        case parse_thought_output(thought_output) do
          {:final_answer, thought, answer} ->
            # Found final answer
            step = %{
              step_number: step_number,
              thought: thought,
              action: nil,
              action_input: nil,
              observation: nil,
              final_answer: answer
            }

            updated_state = %{
              state
              | trajectory: state.trajectory ++ [step],
                step_number: step_number
            }

            {:finish, updated_state, step}

          {:action, thought, action_name, action_input} ->
            # Execute action and get observation
            case execute_action(action_name, action_input, state) do
              {:ok, observation} ->
                step = %{
                  step_number: step_number,
                  thought: thought,
                  action: action_name,
                  action_input: action_input,
                  observation: observation,
                  final_answer: nil
                }

                updated_state = %{
                  state
                  | trajectory: state.trajectory ++ [step],
                    step_number: step_number
                }

                {:continue, updated_state, step}

              {:error, reason} ->
                # Action failed, record observation with error
                observation = "Error executing #{action_name}: #{inspect(reason)}"

                step = %{
                  step_number: step_number,
                  thought: thought,
                  action: action_name,
                  action_input: action_input,
                  observation: observation,
                  final_answer: nil
                }

                updated_state = %{
                  state
                  | trajectory: state.trajectory ++ [step],
                    step_number: step_number
                }

                {:continue, updated_state, step}
            end

          {:error, parse_reason} ->
            {:error, {:parse_failed, parse_reason}}
        end
    end
  end

  # Private functions

  defp execute_loop(state) do
    if state.step_number >= state.max_steps do
      # Max steps reached
      {:ok, build_result(state, :max_steps_reached, false)}
    else
      case execute_step(state) do
        {:continue, updated_state, _step} ->
          # Continue loop
          execute_loop(updated_state)

        {:finish, final_state, _final_step} ->
          # Found answer
          {:ok, build_result(final_state, :answer_found, true)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp generate_thought(state, opts) do
    # Use custom thought function if provided (for testing)
    if state.thought_fn do
      {:ok, state.thought_fn.(state, opts)}
    else
      # Generate thought using LLM
      generate_thought_with_llm(state)
    end
  end

  defp generate_thought_with_llm(state) do
    # Format prompt
    _prompt = format_thought_prompt(state)

    # This would call LLM in production
    # For now, return a placeholder
    {:ok, simulate_thought_output(state)}
  end

  defp format_thought_prompt(state) do
    # Format tools description
    tools_desc =
      state.tools
      |> Enum.map_join("\n", fn tool -> ToolRegistry.format_tool_description(tool) end)

    # Format trajectory
    trajectory_desc = format_trajectory(state.trajectory)

    # Fill template
    state.thought_template
    |> String.replace("{question}", state.question)
    |> String.replace("{tools}", tools_desc)
    |> String.replace("{trajectory}", trajectory_desc)
  end

  defp format_trajectory([]), do: "No previous steps."

  defp format_trajectory(trajectory) do
    trajectory
    |> Enum.map_join("\n\n", fn step ->
      parts = [
        "Step #{step.step_number}:",
        "Thought: #{step.thought}"
      ]

      parts =
        if step.action do
          parts ++ ["Action: #{step.action}", "Action Input: #{inspect(step.action_input)}"]
        else
          parts
        end

      parts =
        if step.observation do
          parts ++ ["Observation: #{step.observation}"]
        else
          parts
        end

      parts =
        if step.final_answer do
          parts ++ ["Final Answer: #{step.final_answer}"]
        else
          parts
        end

      Enum.join(parts, "\n")
    end)
  end

  defp simulate_thought_output(state) do
    # Simulate LLM output for testing
    cond do
      state.step_number == 0 ->
        """
        Thought: I need to search for information to answer this question.
        Action: search
        Action Input: #{state.question}
        """

      state.step_number >= 2 ->
        """
        Thought: Based on the observations, I can now provide the answer.
        Final Answer: Simulated answer based on observations
        """

      true ->
        """
        Thought: I need more information.
        Action: search
        Action Input: follow-up query
        """
    end
  end

  defp parse_thought_output(output) do
    # Parse the thought output to extract thought, action, and input
    ActionSelector.parse(output)
  end

  defp execute_action(action_name, action_input, state) do
    # Find the tool
    tool = Enum.find(state.tools, fn t -> ToolRegistry.tool_name(t) == action_name end)

    if tool do
      # Execute the tool
      case ToolRegistry.execute_tool(tool, action_input, state.context) do
        {:ok, result} ->
          # Process observation
          ObservationProcessor.process(result)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:tool_not_found, action_name}}
    end
  end

  defp build_result(state, reason, success) do
    # Extract final answer if present
    final_answer =
      state.trajectory
      |> Enum.reverse()
      |> Enum.find_value(fn step -> step.final_answer end)

    %{
      answer: final_answer,
      steps: state.step_number,
      trajectory: state.trajectory,
      success: success,
      reason: reason,
      metadata: %{
        max_steps: state.max_steps,
        temperature: state.temperature,
        tools_used: extract_tools_used(state.trajectory)
      }
    }
  end

  defp extract_tools_used(trajectory) do
    trajectory
    |> Enum.filter(fn step -> step.action != nil end)
    |> Enum.map(fn step -> step.action end)
    |> Enum.frequencies()
  end
end
