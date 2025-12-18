defmodule Jido.Instruction do
  @moduledoc """
  Instructions in Jido represent discrete units of work that can be planned, validated, and executed by agents.
  Think of them as "work orders" that tell agents exactly what needs to be done and how to do it.

  ## Core Concepts

  An Instruction wraps an Action module with everything it needs to execute:
  - The Action to perform (required)
  - Parameters for the action
  - Execution context
  - Runtime options

  ## Structure

  Each Instruction contains:

  ```elixir
  %Instruction{
    id: "inst_abc123",           # Unique identifier
    action: MyApp.Actions.DoTask, # The action module to execute
    params: %{value: 42},        # Parameters for the action
    context: %{user_id: "123"},  # Execution context
    opts: [retry: true],         # Runtime options
  }
  ```

  ## Creating Instructions

  Instructions support multiple creation formats for convenience:

  ### 1. Full Struct
  ```elixir
  %Instruction{
    action: MyApp.Actions.ProcessOrder,
    params: %{order_id: "123"},
    context: %{tenant_id: "456"}
  }
  ```

  ### 2. Action Module Only
  ```elixir
  MyApp.Actions.ProcessOrder
  ```

  ### 3. Action With Parameters
  ```elixir
  {MyApp.Actions.ProcessOrder, %{order_id: "123"}}
  ```

  ### 4. Factory Function
  ```elixir
  Instruction.new!(%{
    action: MyApp.Actions.ProcessOrder,
    params: %{order_id: "123"},
    context: %{tenant_id: "456"}
  })
  ```

  ## Working with Instructions

  ### Normalization

  Convert various input formats to standard instruction structs:

  ```elixir
  # Normalize a single instruction
  {:ok, [instruction]} = Instruction.normalize(MyApp.Actions.ProcessOrder)

  # Normalize with context
  {:ok, instructions} = Instruction.normalize(
    [
      MyApp.Actions.ValidateOrder,
      {MyApp.Actions.ProcessOrder, %{priority: "high"}}
    ],
    %{tenant_id: "123"}  # Shared context
  )
  ```

  ### Validation

  Ensure instructions use allowed actions:

  ```elixir
  allowed_actions = [
    MyApp.Actions.ValidateOrder,
    MyApp.Actions.ProcessOrder
  ]

  :ok = Instruction.validate_allowed_actions(instructions, allowed_actions)
  ```

  ## Common Patterns

  ### 1. Exec Definition
  ```elixir
  instructions = [
    MyApp.Actions.ValidateInput,
    {MyApp.Actions.ProcessData, %{format: "json"}},
    MyApp.Actions.SaveResults
  ]
  ```

  ### 2. Conditional Execution
  ```elixir
  instructions = [
    MyApp.Actions.ValidateOrder,
    {MyApp.Actions.CheckInventory, %{strict: true}},
    # Add fulfillment only if in stock
    if has_stock? do
      {MyApp.Actions.FulfillOrder, %{warehouse: "main"}}
    end
  ]
  |> Enum.reject(&is_nil/1)
  ```

  ### 3. Context Sharing
  ```elixir
  # All instructions share common context
  {:ok, instructions} = Instruction.normalize(
    [ValidateUser, ProcessOrder, NotifyUser],
    %{
      request_id: "req_123",
      tenant_id: "tenant_456",
    }
  )
  ```

  ## See Also

  - `Jido.Action` - Action behavior and implementation
  - `Jido.Runner` - Instruction execution
  - `Jido.Agent` - Agent-based execution
  """
  alias Jido.Error
  alias Jido.Instruction
  use TypedStruct

  @type action_module :: module()
  @type action_params :: map()
  @type action_tuple :: {action_module(), action_params()}
  @type instruction :: action_module() | action_tuple() | t()
  @type instruction_list :: [instruction()]

  typedstruct do
    field(:id, String.t(), default: Jido.Util.generate_id())
    field(:action, module(), enforce: true)
    field(:params, map(), default: %{})
    field(:context, map(), default: %{})
    field(:opts, keyword(), default: [])
  end

  @doc """
  Creates a new Instruction struct from a map or keyword list of attributes.
  Returns the struct directly or raises an error.

  ## Parameters
    * `attrs` - Map or keyword list containing instruction attributes:
      * `:action` - Action module (required)
      * `:params` - Map of parameters (optional, default: %{})
      * `:context` - Context map (optional, default: %{})
      * `:opts` - Keyword list of options (optional, default: [])

  ## Returns
    * `%Instruction{}` - Successfully created instruction

  ## Raises
    * `Jido.Error` - If action is missing or invalid

  ## Examples

      iex> Instruction.new!(%{action: MyAction, params: %{value: 1}})
      %Instruction{action: MyAction, params: %{value: 1}}

      iex> Instruction.new!(action: MyAction)
      %Instruction{action: MyAction}

      iex> Instruction.new!(%{params: %{value: 1}})
      ** (Jido.Error) missing action
  """
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, instruction} ->
        instruction

      {:error, reason} ->
        {:error,
         Error.validation_error("Invalid instruction configuration", %{
           reason: reason
         })}
    end
  end

  @doc """
  Creates a new Instruction struct from a map or keyword list of attributes.

  ## Parameters
    * `attrs` - Map or keyword list containing instruction attributes:
      * `:action` - Action module (required)
      * `:params` - Map of parameters (optional, default: %{})
      * `:context` - Context map (optional, default: %{})
      * `:opts` - Keyword list of options (optional, default: [])
      * `:id` - String identifier (optional, defaults to UUID)

  ## Returns
    * `{:ok, %Instruction{}}` - Successfully created instruction
    * `{:error, :missing_action}` - If action is not provided
    * `{:error, :invalid_action}` - If action is not a module

  ## Examples

      iex> Instruction.new(%{action: MyAction, params: %{value: 1}})
      {:ok, %Instruction{action: MyAction, params: %{value: 1}}}

      iex> Instruction.new(action: MyAction)
      {:ok, %Instruction{action: MyAction}}

      iex> Instruction.new(%{params: %{value: 1}})
      {:error, :missing_action}
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, :missing_action | :invalid_action}
  def new(attrs) when is_list(attrs) do
    new(Map.new(attrs))
  end

  def new(%{action: action} = attrs) when is_atom(action) do
    {:ok,
     %__MODULE__{
       id: Map.get(attrs, :id, Jido.Util.generate_id()),
       action: action,
       params: Map.get(attrs, :params, %{}),
       context: Map.get(attrs, :context, %{}),
       opts: Map.get(attrs, :opts, [])
     }}
  end

  def new(%{action: _}), do: {:error, :invalid_action}
  def new(_), do: {:error, :missing_action}

  @doc """
  Normalizes a single instruction into an instruction struct. Unlike normalize/3,
  this function enforces that the input must be a single instruction and returns
  a single instruction struct rather than a list.

  ## Parameters
    * `input` - One of:
      * Single instruction struct (%Instruction{})
      * Single action module (MyApp.Actions.ProcessOrder)
      * Action tuple with params ({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      * Action tuple with empty params ({MyApp.Actions.ProcessOrder, %{}})
    * `context` - Optional context map to merge into the instruction (default: %{})
    * `opts` - Optional keyword list of options (default: [])

  ## Returns
    * `{:ok, %Instruction{}}` - Successfully normalized instruction
    * `{:error, term()}` - If normalization fails

  ## Examples

      iex> Instruction.normalize_single(MyApp.Actions.ProcessOrder)
      {:ok, %Instruction{action: MyApp.Actions.ProcessOrder}}

      iex> Instruction.normalize_single({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      {:ok, %Instruction{action: MyApp.Actions.ProcessOrder, params: %{order_id: "123"}}}
  """
  @spec normalize_single(instruction(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def normalize_single(input, context \\ %{}, opts \\ [])

  # Already normalized instruction - just merge context and opts
  def normalize_single(%__MODULE__{} = instruction, context, opts) do
    context = context || %{}
    merged_opts = Keyword.merge(instruction.opts, opts)
    {:ok, %{instruction | context: Map.merge(instruction.context, context), opts: merged_opts}}
  end

  # Single action module
  def normalize_single(action, context, opts) when is_atom(action) do
    context = context || %{}
    {:ok, new!(%{action: action, params: %{}, context: context, opts: opts})}
  end

  # Action tuple with params
  def normalize_single({action, params}, context, opts) when is_atom(action) do
    context = context || %{}

    case normalize_params(params) do
      {:ok, normalized_params} ->
        {:ok, new!(%{action: action, params: normalized_params, context: context, opts: opts})}

      error ->
        error
    end
  end

  # Invalid format
  def normalize_single(invalid, _context, _opts) do
    {:error, Error.execution_error("Invalid instruction format", %{instruction: invalid})}
  end

  @doc """
  Normalizes instruction shorthand input into instruction structs. Accepts a variety of input formats
  and returns a list of normalized instruction structs.

  ## Parameters
    * `input` - One of:
      * Single instruction struct (%Instruction{})
      * List of instruction structs
      * Single action module (MyApp.Actions.ProcessOrder)
      * Action tuple with params ({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      * Action tuple with empty params ({MyApp.Actions.ProcessOrder, %{}})
      * Action tuple with context ({MyApp.Actions.ProcessOrder, %{}, %{tenant_id: "123"}})
      * Action tuple with opts ({MyApp.Actions.ProcessOrder, %{}, %{}, [retry: true]})
      * List of any combination of the above formats
    * `context` - Optional context map to merge into all instructions (default: %{})
    * `opts` - Optional keyword list of options (default: [])

  ## Returns
    * `{:ok, [%Instruction{}]}` - List of normalized instruction structs
    * `{:error, term()}` - If normalization fails

  ## Examples

      iex> Instruction.normalize(MyApp.Actions.ProcessOrder)
      {:ok, [%Instruction{action: MyApp.Actions.ProcessOrder}]}

      iex> Instruction.normalize({MyApp.Actions.ProcessOrder, %{order_id: "123"}})
      {:ok, [%Instruction{action: MyApp.Actions.ProcessOrder, params: %{order_id: "123"}}]}

      iex> Instruction.normalize([
      ...>   MyApp.Actions.ValidateOrder,
      ...>   {MyApp.Actions.ProcessOrder, %{priority: "high"}},
      ...>   {MyApp.Actions.NotifyUser, %{}, %{user_id: "123"}}
      ...> ])
      {:ok, [%Instruction{...}, %Instruction{...}, %Instruction{...}]}
  """
  @spec normalize(instruction() | instruction_list(), map(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def normalize(input, context \\ %{}, opts \\ [])

  # Handle lists by recursively normalizing each element
  def normalize(instructions, context, opts) when is_list(instructions) do
    # Check for nested lists first
    if Enum.any?(instructions, &is_list/1) do
      {:error,
       Error.execution_error("Invalid instruction format: nested lists are not allowed", %{
         instructions: instructions
       })}
    else
      context = context || %{}

      instructions
      |> Enum.reduce_while({:ok, []}, fn instruction, {:ok, acc} ->
        case normalize_single(instruction, context, opts) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, list} -> {:ok, Enum.reverse(list)}
        error -> error
      end
    end
  end

  # Single instruction - normalize and wrap in list
  def normalize(instruction, context, opts) do
    case normalize_single(instruction, context, opts) do
      {:ok, normalized} -> {:ok, [normalized]}
      error -> error
    end
  end

  @doc """
  Same as `normalize/3` but raises on error.

  ## Parameters
    * `instruction` - Instruction to normalize
    * `context` - Optional context map to merge
    * `opts` - Optional options to merge

  ## Returns
    * `[t()]` - List of normalized instructions

  ## Raises
    * `Jido.Error` - If instruction cannot be normalized

  ## Examples
      iex> Instruction.normalize!({MyAction, %{value: 42}})
      [%Instruction{action: MyAction, params: %{value: 42}}]

      iex> Instruction.normalize!(MyAction)
      [%Instruction{action: MyAction, params: %{}}]
  """
  @spec normalize(instruction() | instruction_list(), map(), keyword()) :: [t()]
  def normalize!(instruction, context \\ nil, opts \\ []) do
    case normalize(instruction, context, opts) do
      {:ok, instructions} -> instructions
      {:error, error} -> raise error
    end
  end

  @doc """
  Validates that all instructions use allowed actions.

  ## Parameters
    * `instructions` - List of instruction structs
    * `allowed_actions` - List of allowed action modules

  ## Returns
    * `:ok` - All actions are allowed
    * `{:error, term()}` - If any action is not allowed

  ## Examples
      iex> instructions = [%Instruction{action: MyAction}, %Instruction{action: OtherAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      {:error, "Actions not allowed: OtherAction"}

      iex> instructions = [%Instruction{action: MyAction}]
      iex> Instruction.validate_allowed_actions(instructions, [MyAction])
      :ok
  """
  @spec validate_allowed_actions(t() | [t()], [module()]) :: :ok | {:error, term()}
  def validate_allowed_actions(%Instruction{} = instruction, allowed_actions) do
    validate_allowed_actions([instruction], allowed_actions)
  end

  def validate_allowed_actions(instructions, allowed_actions) when is_list(instructions) do
    unregistered =
      instructions
      |> Enum.map(& &1.action)
      |> Enum.reject(&(&1 in allowed_actions))

    if Enum.empty?(unregistered) do
      :ok
    else
      unregistered_str = Enum.join(unregistered, ", ")

      {:error,
       Error.config_error("Actions not allowed: #{unregistered_str}", %{
         actions: unregistered,
         allowed_actions: allowed_actions
       })}
    end
  end

  # Private helpers

  defp normalize_params(nil), do: {:ok, %{}}
  defp normalize_params(params) when is_map(params), do: {:ok, params}

  defp normalize_params(params) when is_list(params) do
    if Keyword.keyword?(params) do
      {:ok, Map.new(params)}
    else
      {:error,
       Error.execution_error(
         "Invalid params format. Params must be a map or keyword list.",
         %{
           params: params,
           expected_format: "%{key: value} or [key: value]"
         }
       )}
    end
  end

  defp normalize_params(invalid) do
    {:error,
     Error.execution_error(
       "Invalid params format. Params must be a map or keyword list.",
       %{
         params: invalid,
         expected_format: "%{key: value} or [key: value]"
       }
     )}
  end
end
