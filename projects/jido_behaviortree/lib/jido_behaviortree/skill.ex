defmodule Jido.BehaviorTree.Skill do
  @moduledoc """
  A behavior tree skill that can be converted to AI-compatible tool definitions.

  This module allows behavior trees to be exposed as skills that can be executed
  by AI systems. The behavior tree is wrapped in a skill interface that provides
  parameter validation, execution, and result formatting.

  ## Features

  - Convert behavior trees to LLM-compatible tool definitions
  - Parameter validation and type checking
  - Automatic blackboard management
  - Execution result formatting
  - Error handling and reporting

  ## Example Usage

      # Create a behavior tree
      tree = Jido.BehaviorTree.Tree.new(root_node)
      
      # Create a skill from the tree
      skill = Jido.BehaviorTree.Skill.new(
        "process_user_data",
        tree,
        "Processes user data through a behavior tree",
        schema: [
          user_id: [type: :integer, required: true],
          data: [type: :map, required: true]
        ]
      )
      
      # Convert to tool format
      tool_def = skill.to_tool()
      
      # Execute the skill
      {:ok, result} = skill.run(%{user_id: 123, data: %{name: "John"}}, %{})
  """

  use TypedStruct

  alias Jido.BehaviorTree.{Tree, Agent, Blackboard}

  typedstruct do
    @typedoc "A behavior tree skill definition"
    field(:name, String.t(), enforce: true)
    field(:description, String.t(), default: "")
    field(:tree, Tree.t(), enforce: true)
    field(:schema, keyword(), default: [])
    field(:output_schema, keyword(), default: [])
    field(:timeout, non_neg_integer(), default: 30_000)
    field(:auto_mode, boolean(), default: false)
    field(:interval, non_neg_integer(), default: 1000)
  end

  @doc """
  Creates a new behavior tree skill.

  ## Options

  - `:schema` - NimbleOptions schema for input validation (default: [])
  - `:output_schema` - NimbleOptions schema for output validation (default: [])
  - `:timeout` - Execution timeout in milliseconds (default: 30_000)
  - `:auto_mode` - Whether to run in automatic mode (default: false)
  - `:interval` - Tick interval for auto mode in milliseconds (default: 1000)

  ## Examples

      skill = Jido.BehaviorTree.Skill.new(
        "data_processor",
        tree,
        "Processes data using behavior tree logic",
        schema: [
          input_data: [type: :map, required: true]
        ],
        timeout: 10_000
      )

  """
  @spec new(String.t(), Tree.t(), String.t(), keyword()) :: t()
  def new(name, tree, description \\ "", opts \\ []) do
    %__MODULE__{
      name: name,
      description: description,
      tree: tree,
      schema: Keyword.get(opts, :schema, []),
      output_schema: Keyword.get(opts, :output_schema, []),
      timeout: Keyword.get(opts, :timeout, 30_000),
      auto_mode: Keyword.get(opts, :auto_mode, false),
      interval: Keyword.get(opts, :interval, 1000)
    }
  end

  @doc """
  Converts the skill to an AI-compatible tool definition.

  Returns a map that can be used with LLM function calling systems
  like OpenAI's function calling.

  ## Examples

      tool_def = skill.to_tool()
      # %{
      #   "name" => "data_processor",
      #   "description" => "Processes data using behavior tree logic",
      #   "parameters" => %{
      #     "type" => "object",
      #     "properties" => %{...},
      #     "required" => [...]
      #   }
      # }

  """
  @spec to_tool(t()) :: map()
  def to_tool(%__MODULE__{} = skill) do
    %{
      "name" => skill.name,
      "description" => skill.description,
      "parameters" => schema_to_json_schema(skill.schema)
    }
  end

  @doc """
  Executes the behavior tree skill with the given parameters.

  This function starts a behavior tree agent, executes the tree with the
  provided parameters in the blackboard, and returns the final result.

  ## Parameters

  - `params` - Input parameters (will be validated against schema)
  - `context` - Execution context (currently unused but reserved for future use)

  ## Returns

  - `{:ok, result}` - Successful execution with result map
  - `{:error, reason}` - Execution failed with error reason

  ## Examples

      {:ok, result} = Jido.BehaviorTree.Skill.run(skill, %{input_data: %{id: 1}}, %{})

  """
  @spec run(t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run(%__MODULE__{} = skill, params, _context) do
    with {:ok, validated_params} <- validate_params(skill, params),
         {:ok, result} <- execute_tree(skill, validated_params) do
      validate_output(skill, result)
    end
  end

  ## Private Functions

  defp validate_params(%__MODULE__{schema: []}, params), do: {:ok, params}

  defp validate_params(%__MODULE__{schema: schema}, params) do
    case NimbleOptions.validate(Map.to_list(params), schema) do
      {:ok, validated_params} ->
        {:ok, Map.new(validated_params)}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, "Parameter validation failed: #{Exception.message(error)}"}
    end
  end

  defp execute_tree(%__MODULE__{} = skill, params) do
    # Create initial blackboard with input parameters
    initial_blackboard = Blackboard.new(params)

    # Start the agent
    agent_opts = [
      tree: skill.tree,
      blackboard: Blackboard.to_map(initial_blackboard),
      mode: if(skill.auto_mode, do: :auto, else: :manual),
      interval: skill.interval
    ]

    case Agent.start_link(agent_opts) do
      {:ok, agent} ->
        try do
          _result =
            if skill.auto_mode do
              execute_auto_mode(agent, skill.timeout)
            else
              execute_manual_mode(agent, skill.timeout)
            end

          # Get final blackboard
          final_blackboard = Agent.blackboard(agent)

          # Stop the agent
          Agent.halt(agent)
          GenServer.stop(agent)

          {:ok, Blackboard.to_map(final_blackboard)}
        rescue
          error ->
            # Ensure agent is stopped on error
            Agent.halt(agent)
            GenServer.stop(agent)
            {:error, "Execution failed: #{Exception.message(error)}"}
        end

      {:error, reason} ->
        {:error, "Failed to start agent: #{inspect(reason)}"}
    end
  end

  defp execute_auto_mode(_agent, timeout) do
    # In auto mode, just wait for the specified timeout
    # The agent will tick automatically
    Process.sleep(timeout)
    :ok
  end

  defp execute_manual_mode(agent, timeout) do
    # In manual mode, tick until we get a final result or timeout
    end_time = System.monotonic_time(:millisecond) + timeout
    execute_manual_loop(agent, end_time)
  end

  defp execute_manual_loop(agent, end_time) do
    if System.monotonic_time(:millisecond) > end_time do
      {:error, "Execution timed out"}
    else
      case Agent.tick(agent) do
        :success ->
          :ok

        :failure ->
          # Failure is a valid completion state, not an error
          :ok

        {:error, reason} ->
          {:error, "Behavior tree error: #{inspect(reason)}"}

        :running ->
          # Continue ticking
          Process.sleep(10)
          execute_manual_loop(agent, end_time)
      end
    end
  end

  defp validate_output(%__MODULE__{output_schema: []}, result), do: {:ok, result}

  defp validate_output(%__MODULE__{output_schema: schema}, result) do
    case NimbleOptions.validate(Map.to_list(result), schema) do
      {:ok, validated_result} ->
        {:ok, Map.new(validated_result)}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, "Output validation failed: #{Exception.message(error)}"}
    end
  end

  defp schema_to_json_schema([]), do: %{"type" => "object", "properties" => %{}}

  defp schema_to_json_schema(schema) do
    properties =
      schema
      |> Enum.map(fn {key, opts} ->
        {to_string(key), nimble_option_to_json_property(opts)}
      end)
      |> Map.new()

    required =
      schema
      |> Enum.filter(fn {_key, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {key, _opts} -> to_string(key) end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required
    }
  end

  defp nimble_option_to_json_property(opts) do
    type = Keyword.get(opts, :type, :any)
    doc = Keyword.get(opts, :doc, "")

    base_property = %{"description" => doc}

    case type do
      :string -> Map.put(base_property, "type", "string")
      :integer -> Map.put(base_property, "type", "integer")
      :float -> Map.put(base_property, "type", "number")
      :boolean -> Map.put(base_property, "type", "boolean")
      :map -> Map.put(base_property, "type", "object")
      {:list, _} -> Map.put(base_property, "type", "array")
      _ -> Map.put(base_property, "type", "any")
    end
  end
end
