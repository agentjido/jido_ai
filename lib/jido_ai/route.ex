defmodule Jido.AI.Route do
  @moduledoc """
  Resolves one Agent route that has a reply projection.

  A route reference is `{agent, input_type}`. The agent can be a compiled
  Agent module, an Agent definition, or an Agent instance. The input type is
  the exact Signal type for one request.
  """

  alias Jido.Agent
  alias Jido.Signal

  @enforce_keys [
    :definition,
    :route,
    :input_type,
    :input_schema,
    :reply_schema
  ]
  defstruct @enforce_keys

  @type ref :: {module() | Agent.t(), String.t()}

  @type t :: %__MODULE__{
          definition: Agent.definition(),
          route: map(),
          input_type: String.t(),
          input_schema: Zoi.schema(),
          reply_schema: Zoi.schema()
        }

  @doc "Resolves and validates one routed reply contract."
  @spec resolve(ref()) :: {:ok, t()} | {:error, :invalid_route_contract}
  def resolve({agent, input_type}) when is_binary(input_type) and byte_size(input_type) > 0 do
    with {:ok, definition} <- definition(agent),
         {:ok, route} <- Jido.Agent.Route.select(definition, input_type),
         {:ok, input_schema} <- input_schema(route),
         {:ok, reply_schema} <- reply_schema(route) do
      {:ok,
       %__MODULE__{
         definition: definition,
         route: route,
         input_type: input_type,
         input_schema: input_schema,
         reply_schema: reply_schema
       }}
    else
      _error -> {:error, :invalid_route_contract}
    end
  end

  def resolve(_ref), do: {:error, :invalid_route_contract}

  @doc "Builds the correlated reply Signal that a Thread or Session records."
  @spec reply(t(), Signal.t(), term()) :: {:ok, Signal.t()} | {:error, term()}
  def reply(%__MODULE__{} = contract, %Signal{} = request, data) do
    with {:ok, data} <- Zoi.parse(contract.reply_schema, data),
         {:ok, reply} <-
           Signal.new(contract.route.reply.type, data, source: contract.definition.signal_source),
         {:ok, _request, trace} <- Signal.Trace.ensure(request),
         {:ok, reply} <- Signal.Trace.put(reply, trace) do
      Signal.put_context(reply, "jidocausationid", request.id)
    end
  end

  @doc "Validates reply data and returns the normalized value."
  @spec reply_data(t(), term()) :: {:ok, term()} | {:error, term()}
  def reply_data(%__MODULE__{} = contract, data),
    do: Zoi.parse(contract.reply_schema, data)

  defp definition(%Agent{} = agent) do
    definition = Agent.definition(agent)

    case Agent.validate(definition) do
      {:ok, definition} -> {:ok, definition}
      {:error, _reason} -> {:error, :invalid_route_contract}
    end
  end

  defp definition(module) when is_atom(module) and module not in [nil, true, false] do
    definition = Agent.definition(module)

    case Agent.validate(definition) do
      {:ok, definition} -> {:ok, definition}
      {:error, _reason} -> {:error, :invalid_route_contract}
    end
  rescue
    _error -> {:error, :invalid_route_contract}
  end

  defp definition(_agent), do: {:error, :invalid_route_contract}

  defp input_schema(%{handler: %{kind: kind, target: target}})
       when kind in [:action, :flow] do
    schema(target, :schema)
  end

  defp input_schema(_route), do: {:error, :invalid_route_contract}

  defp reply_schema(%{
         handler: %{kind: kind, target: target},
         reply: %{from: %{source: :output, path: path}}
       })
       when kind in [:action, :flow] and is_list(path) do
    with {:ok, schema} <- schema(target, :output_schema),
         do: schema_at(schema, path)
  end

  defp reply_schema(_route), do: {:error, :invalid_route_contract}

  defp schema(target, function) do
    if Code.ensure_loaded?(target) and function_exported?(target, function, 0) do
      schema = apply(target, function, [])

      if is_struct(schema) and Zoi.Type.impl_for(schema) != nil,
        do: {:ok, schema},
        else: {:error, :invalid_route_contract}
    else
      {:error, :invalid_route_contract}
    end
  rescue
    _error -> {:error, :invalid_route_contract}
  end

  defp schema_at(schema, []), do: {:ok, schema}

  defp schema_at(%{__struct__: type, fields: fields}, [key | rest])
       when type in [Zoi.Types.Map, Zoi.Types.Struct] and is_list(fields) do
    case Enum.find(fields, fn {declared_key, _schema} -> declared_key == key end) do
      {_key, schema} -> schema_at(schema, rest)
      nil -> {:error, :invalid_route_contract}
    end
  end

  defp schema_at(_schema, _path), do: {:error, :invalid_route_contract}
end
