defmodule ReqAI.Tool do
  @moduledoc """
  Represents a tool/function that can be called by AI models.

  Tools enable AI models to call external functions, perform actions, and retrieve information.
  Each tool has a name, description, parameters schema, and a callback function to execute.

  ## Basic Usage

      # Create a simple tool
      {:ok, tool} = ReqAI.Tool.new(
        name: "get_weather",
        description: "Get current weather for a location",
        parameters: [
          location: [type: :string, required: true, doc: "City name"]
        ],
        callback: {WeatherService, :get_current_weather}
      )

      # Execute the tool
      {:ok, result} = ReqAI.Tool.execute(tool, %{location: "San Francisco"})

  ## Parameters Schema

  Parameters are defined using NimbleOptions-compatible keyword lists:

      parameters: [
        location: [type: :string, required: true, doc: "City name"],
        units: [type: :string, default: "celsius", doc: "Temperature units"]
      ]

  ## Callback Formats

  Multiple callback formats are supported:

      # Module and function (args passed as single argument)
      callback: {MyModule, :my_function}

      # Module, function, and additional args (prepended to input)
      callback: {MyModule, :my_function, [:extra, :args]}

      # Anonymous function
      callback: fn args -> {:ok, "result"} end

  ## Tool Definition Examples

      # Weather tool with validation
      weather_tool = ReqAI.Tool.new!(
        name: "get_weather",
        description: "Get weather information for a location",
        parameters: [
          location: [type: :string, required: true, doc: "City or location name"],
          units: [type: :string, default: "metric", doc: "Temperature units (metric/imperial)"]
        ],
        callback: {WeatherAPI, :fetch_weather}
      )

      # Calculator tool with multiple parameters
      calc_tool = ReqAI.Tool.new!(
        name: "calculate",
        description: "Perform mathematical calculations",
        parameters: [
          operation: [type: :string, required: true, doc: "Math operation (+, -, *, /)"],
          a: [type: :number, required: true, doc: "First number"],
          b: [type: :number, required: true, doc: "Second number"]
        ],
        callback: fn %{operation: op, a: a, b: b} ->
          case op do
            "+" -> {:ok, a + b}
            "-" -> {:ok, a - b}
            "*" -> {:ok, a * b}
            "/" when b != 0 -> {:ok, a / b}
            "/" -> {:error, "Division by zero"}
            _ -> {:error, "Unknown operation"}
          end
        end
      )

  ## JSON Schema Export

  Tools can be exported to JSON Schema format for LLM integration:

      json_schema = ReqAI.Tool.to_json_schema(tool)
      # Returns OpenAI function calling compatible schema

  """

  use TypedStruct

  @type callback_mfa :: {module(), atom()} | {module(), atom(), list()}
  @type callback_fun :: (map() -> {:ok, term()} | {:error, term()})
  @type callback :: callback_mfa() | callback_fun()

  typedstruct enforce: true do
    @typedoc "A tool definition for AI model function calling"

    field(:name, String.t(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:parameters, keyword() | nil, default: [])
    field(:callback, callback(), enforce: true)
    field(:schema, NimbleOptions.t() | nil, default: nil)
  end

  @type tool_opts :: [
          name: String.t(),
          description: String.t(),
          parameters: keyword(),
          callback: callback()
        ]

  # NimbleOptions schema for tool creation validation
  @tool_schema NimbleOptions.new!(
                 name: [
                   type: :string,
                   required: true,
                   doc: "Tool name (must be valid identifier)"
                 ],
                 description: [
                   type: :string,
                   required: true,
                   doc: "Tool description for AI model"
                 ],
                 parameters: [
                   type: :keyword_list,
                   default: [],
                   doc: "Parameter schema as keyword list"
                 ],
                 callback: [
                   type: :any,
                   required: true,
                   doc: "Callback function or MFA tuple"
                 ]
               )

  @doc """
  Creates a new Tool from the given options.

  ## Parameters

    * `opts` - Tool options as keyword list

  ## Options

    * `:name` - Tool name (required, must be valid identifier)
    * `:description` - Tool description for AI model (required)
    * `:parameters` - Parameter schema as NimbleOptions keyword list (optional)
    * `:callback` - Callback function or MFA tuple (required)

  ## Examples

      {:ok, tool} = ReqAI.Tool.new(
        name: "get_weather",
        description: "Get current weather",
        parameters: [
          location: [type: :string, required: true]
        ],
        callback: {WeatherService, :get_weather}
      )

  """
  @spec new(tool_opts()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @tool_schema),
         :ok <- validate_name(validated_opts[:name]),
         :ok <- validate_callback(validated_opts[:callback]),
         {:ok, parameter_schema} <- build_parameter_schema(validated_opts[:parameters]) do
      tool = %__MODULE__{
        name: validated_opts[:name],
        description: validated_opts[:description],
        parameters: validated_opts[:parameters],
        callback: validated_opts[:callback],
        schema: parameter_schema
      }

      {:ok, tool}
    else
      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :invalid_options,
           reason: Exception.message(error),
           context: []
         )}

      {:error, reason} when is_binary(reason) ->
        {:error, ReqAI.Error.Invalid.Parameter.exception(parameter: reason)}

      error ->
        error
    end
  end

  def new(_) do
    {:error,
     ReqAI.Error.Invalid.Parameter.exception(parameter: "Tool options must be a keyword list")}
  end

  @doc """
  Creates a new Tool from the given options, raising on error.

  See `new/1` for details.

  ## Examples

      tool = ReqAI.Tool.new!(
        name: "get_weather",
        description: "Get current weather",
        callback: {WeatherService, :get_weather}
      )

  """
  @spec new!(tool_opts()) :: t() | no_return()
  def new!(opts) do
    case new(opts) do
      {:ok, tool} -> tool
      {:error, error} -> raise error
    end
  end

  @doc """
  Executes a tool with the given input parameters.

  Validates input parameters against the tool's schema and calls the callback function.
  The callback is expected to return `{:ok, result}` or `{:error, reason}`.

  ## Parameters

    * `tool` - Tool struct
    * `input` - Input parameters as map

  ## Examples

      {:ok, result} = ReqAI.Tool.execute(tool, %{location: "San Francisco"})
      #=> {:ok, %{temperature: 72, conditions: "sunny"}}

      {:error, reason} = ReqAI.Tool.execute(tool, %{invalid: "params"})
      #=> {:error, %ReqAI.Error.Validation.Error{...}}

  """
  @spec execute(t(), map()) :: {:ok, term()} | {:error, term()}
  def execute(%__MODULE__{} = tool, input) when is_map(input) do
    with {:ok, validated_input} <- validate_input(tool, input) do
      call_callback(tool.callback, validated_input)
    end
  end

  def execute(%__MODULE__{}, input) do
    {:error,
     ReqAI.Error.Invalid.Parameter.exception(
       parameter: "Input must be a map, got: #{inspect(input)}"
     )}
  end

  @doc """
  Executes a tool with the given input parameters, raising on error.

  See `execute/2` for details.

  ## Examples

      result = ReqAI.Tool.execute!(tool, %{location: "San Francisco"})
      #=> %{temperature: 72, conditions: "sunny"}

  """
  @spec execute!(t(), map()) :: term() | no_return()
  def execute!(tool, input) do
    case execute(tool, input) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Converts a Tool to JSON Schema format for LLM integration.

  Returns a map containing OpenAI function calling compatible schema with
  tool name, description, and parameter definitions.

  ## Examples

      tool = ReqAI.Tool.new!(
        name: "get_weather",
        description: "Get current weather",
        parameters: [
          location: [type: :string, required: true, doc: "City name"],
          units: [type: :string, default: "celsius", doc: "Temperature units"]
        ],
        callback: {WeatherService, :get_weather}
      )

      json_schema = ReqAI.Tool.to_json_schema(tool)
      #=> %{
      #     "type" => "function",
      #     "function" => %{
      #       "name" => "get_weather",
      #       "description" => "Get current weather",
      #       "parameters" => %{
      #         "type" => "object",
      #         "properties" => %{
      #           "location" => %{"type" => "string", "description" => "City name"},
      #           "units" => %{"type" => "string", "description" => "Temperature units"}
      #         },
      #         "required" => ["location"]
      #       }
      #     }
      #   }

  """
  @spec to_json_schema(t()) :: map()
  def to_json_schema(%__MODULE__{} = tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => tool.name,
        "description" => tool.description,
        "parameters" => parameters_to_json_schema(tool.parameters)
      }
    }
  end

  @doc """
  Validates a tool name for compliance with function calling standards.

  Tool names must be valid identifiers (alphanumeric + underscores, start with letter/underscore).

  ## Examples

      ReqAI.Tool.valid_name?("get_weather")
      #=> true

      ReqAI.Tool.valid_name?("123invalid")
      #=> false

  """
  @spec valid_name?(String.t()) :: boolean()
  def valid_name?(name) when is_binary(name) do
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) and String.length(name) <= 64
  end

  def valid_name?(_), do: false

  # Private functions

  defp validate_name(name) do
    if valid_name?(name) do
      :ok
    else
      {:error,
       "Invalid tool name: #{inspect(name)}. Must be valid identifier (alphanumeric + underscore, max 64 chars)"}
    end
  end

  defp validate_callback({module, function}) when is_atom(module) and is_atom(function) do
    if function_exported?(module, function, 1) do
      :ok
    else
      {:error, "Callback function #{module}.#{function}/1 does not exist"}
    end
  end

  defp validate_callback({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args) do
    arity = length(args) + 1

    if function_exported?(module, function, arity) do
      :ok
    else
      {:error, "Callback function #{module}.#{function}/#{arity} does not exist"}
    end
  end

  defp validate_callback(fun) when is_function(fun, 1), do: :ok

  defp validate_callback(callback) do
    {:error,
     "Invalid callback: #{inspect(callback)}. Must be {module, function}, {module, function, args}, or function/1"}
  end

  defp build_parameter_schema([]), do: {:ok, nil}

  defp build_parameter_schema(parameters) when is_list(parameters) do
    try do
      {:ok, NimbleOptions.new!(parameters)}
    rescue
      e ->
        {:error, "Invalid parameter schema: #{Exception.message(e)}"}
    end
  end

  defp validate_input(%__MODULE__{schema: nil}, input), do: {:ok, input}

  defp validate_input(%__MODULE__{schema: schema}, input) do
    # Convert string keys to atoms for validation
    normalized_input = normalize_input_keys(input)

    case NimbleOptions.validate(normalized_input, schema) do
      {:ok, validated_input} ->
        {:ok, validated_input}

      {:error, error} ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :parameter_validation,
           reason: Exception.message(error),
           context: [input: input]
         )}
    end
  end

  defp normalize_input_keys(input) when is_map(input) do
    Map.new(input, fn
      {key, value} when is_binary(key) ->
        try do
          {String.to_existing_atom(key), value}
        rescue
          ArgumentError -> {String.to_atom(key), value}
        end

      {key, value} ->
        {key, value}
    end)
  end

  defp call_callback({module, function}, input) do
    try do
      apply(module, function, [input])
    rescue
      error ->
        {:error, "Callback execution failed: #{Exception.message(error)}"}
    end
  end

  defp call_callback({module, function, args}, input) do
    try do
      apply(module, function, args ++ [input])
    rescue
      error ->
        {:error, "Callback execution failed: #{Exception.message(error)}"}
    end
  end

  defp call_callback(fun, input) when is_function(fun, 1) do
    try do
      fun.(input)
    rescue
      error ->
        {:error, "Callback execution failed: #{Exception.message(error)}"}
    end
  end

  defp parameters_to_json_schema([]), do: %{"type" => "object", "properties" => %{}}

  defp parameters_to_json_schema(parameters) do
    {properties, required} =
      Enum.reduce(parameters, {%{}, []}, fn {key, opts}, {props_acc, req_acc} ->
        property_name = to_string(key)
        json_prop = nimble_type_to_json_schema(opts[:type] || :string, opts)

        new_props = Map.put(props_acc, property_name, json_prop)
        new_req = if opts[:required], do: [property_name | req_acc], else: req_acc

        {new_props, new_req}
      end)

    schema = %{
      "type" => "object",
      "properties" => properties
    }

    if required == [] do
      schema
    else
      Map.put(schema, "required", Enum.reverse(required))
    end
  end

  defp nimble_type_to_json_schema(type, opts) do
    base_schema =
      case type do
        :string ->
          %{"type" => "string"}

        :integer ->
          %{"type" => "integer"}

        :pos_integer ->
          %{"type" => "integer", "minimum" => 1}

        :float ->
          %{"type" => "number"}

        :number ->
          %{"type" => "number"}

        :boolean ->
          %{"type" => "boolean"}

        {:list, :string} ->
          %{"type" => "array", "items" => %{"type" => "string"}}

        {:list, :integer} ->
          %{"type" => "array", "items" => %{"type" => "integer"}}

        {:list, item_type} ->
          %{"type" => "array", "items" => nimble_type_to_json_schema(item_type, %{})}

        :map ->
          %{"type" => "object"}

        _ ->
          %{"type" => "string"}
      end

    case opts[:doc] do
      nil -> base_schema
      doc -> Map.put(base_schema, "description", doc)
    end
  end
end
