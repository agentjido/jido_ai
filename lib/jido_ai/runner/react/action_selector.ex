defmodule Jido.AI.Runner.ReAct.ActionSelector do
  @moduledoc """
  Parses thought outputs to extract actions and their parameters.

  The ActionSelector analyzes LLM-generated thoughts to:
  - Identify when an action should be taken
  - Extract the action name and parameters
  - Detect when a final answer has been reached
  - Handle various thought output formats

  ## Expected Formats

  The parser handles multiple thought output formats:

  ### Standard Format
  ```
  Thought: <reasoning>
  Action: <tool_name>
  Action Input: <parameters>
  ```

  ### Final Answer Format
  ```
  Thought: <reasoning>
  Final Answer: <answer>
  ```

  ### Alternative Formats
  ```
  Thought: <reasoning>
  Action: <tool_name>(<parameters>)
  ```

  ## Examples

      ActionSelector.parse(\"\"\"
      Thought: I need to search for information about Elixir.
      Action: search
      Action Input: Elixir programming language
      \"\"\")
      # => {:action, "I need to search...", "search", "Elixir programming language"}

      ActionSelector.parse(\"\"\"
      Thought: Based on the search results, the answer is clear.
      Final Answer: Elixir was created by José Valim
      \"\"\")
      # => {:final_answer, "Based on the search results...", "Elixir was created by José Valim"}
  """

  @doc """
  Parses thought output to extract action or final answer.

  ## Parameters

  - `output` - The LLM-generated thought output

  ## Returns

  - `{:action, thought, action_name, action_input}` - Action to execute
  - `{:final_answer, thought, answer}` - Final answer reached
  - `{:error, reason}` - Failed to parse output
  """
  @spec parse(String.t()) ::
          {:action, String.t(), String.t(), term()}
          | {:final_answer, String.t(), String.t()}
          | {:error, term()}
  def parse(output) when is_binary(output) do
    # Try to extract thought
    case extract_thought(output) do
      {:ok, thought} ->
        # Check if this is a final answer
        case extract_final_answer(output) do
          {:ok, answer} ->
            {:final_answer, thought, answer}

          :not_found ->
            # Try to extract action
            case extract_action(output) do
              {:ok, action_name, action_input} ->
                {:action, thought, action_name, action_input}

              {:error, reason} ->
                {:error, {:action_extraction_failed, reason}}
            end
        end

      {:error, reason} ->
        {:error, {:thought_extraction_failed, reason}}
    end
  end

  @doc """
  Extracts action name and parameters from various formats.

  Handles:
  - Standard format: "Action: name\\nAction Input: params"
  - Function format: "Action: name(params)"
  - JSON format: "Action: {\"name\": \"...\", \"input\": \"...\"}"

  ## Returns

  - `{:ok, action_name, action_input}` - Successfully extracted
  - `{:error, reason}` - Failed to extract
  """
  @spec extract_action(String.t()) :: {:ok, String.t(), term()} | {:error, term()}
  def extract_action(output) do
    # Try standard format first
    case extract_standard_action(output) do
      {:ok, name, input} ->
        {:ok, name, input}

      :not_found ->
        # Try function call format
        case extract_function_action(output) do
          {:ok, name, input} ->
            {:ok, name, input}

          :not_found ->
            # Try JSON format
            case extract_json_action(output) do
              {:ok, name, input} ->
                {:ok, name, input}

              :not_found ->
                {:error, :no_action_found}
            end
        end
    end
  end

  @doc """
  Validates action against available tools.

  ## Parameters

  - `action_name` - The action name to validate
  - `tools` - List of available tools

  ## Returns

  - `:ok` - Action is valid
  - `{:error, :invalid_action}` - Action not found in tools
  """
  @spec validate_action(String.t(), list()) :: :ok | {:error, :invalid_action}
  def validate_action(action_name, tools) do
    tool_names =
      Enum.map(tools, fn tool ->
        cond do
          is_map(tool) and Map.has_key?(tool, :name) -> tool.name
          is_map(tool) and Map.has_key?(tool, "name") -> tool["name"]
          is_binary(tool) -> tool
          true -> nil
        end
      end)

    if action_name in tool_names do
      :ok
    else
      {:error, :invalid_action}
    end
  end

  # Private functions

  defp extract_thought(output) do
    # Match "Thought: <text>" pattern
    case Regex.run(~r/Thought:\s*(.+?)(?:\n|$)/s, output, capture: :all_but_first) do
      [thought] -> {:ok, String.trim(thought)}
      nil -> {:error, :no_thought_found}
    end
  end

  defp extract_final_answer(output) do
    # Match "Final Answer: <text>" pattern
    case Regex.run(~r/Final Answer:\s*(.+)/s, output, capture: :all_but_first) do
      [answer] -> {:ok, String.trim(answer)}
      nil -> :not_found
    end
  end

  defp extract_standard_action(output) do
    # Match "Action: <name>\nAction Input: <input>" pattern
    action_pattern = ~r/Action:\s*([^\n]+)/
    input_pattern = ~r/Action Input:\s*(.+)/s

    with [action_name] <- Regex.run(action_pattern, output, capture: :all_but_first),
         [action_input] <- Regex.run(input_pattern, output, capture: :all_but_first) do
      {:ok, String.trim(action_name), String.trim(action_input)}
    else
      _ -> :not_found
    end
  end

  defp extract_function_action(output) do
    # Match "Action: function_name(parameters)" pattern
    case Regex.run(~r/Action:\s*(\w+)\s*\(([^)]*)\)/, output, capture: :all_but_first) do
      [name, params] -> {:ok, String.trim(name), String.trim(params)}
      nil -> :not_found
    end
  end

  defp extract_json_action(output) do
    # Try to find JSON object with action and input
    case Regex.run(~r/Action:\s*(\{.+?\})/s, output, capture: :all_but_first) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, %{"name" => name, "input" => input}} ->
            {:ok, name, input}

          {:ok, %{"action" => name, "input" => input}} ->
            {:ok, name, input}

          _ ->
            :not_found
        end

      nil ->
        :not_found
    end
  end
end
