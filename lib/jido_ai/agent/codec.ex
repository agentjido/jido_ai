defmodule Jido.AI.Agent.Codec do
  @moduledoc """
  Stores the authoring boundary of a graph-first AI Agent.

  Version 1 stores the normal Jido Agent definition without its generated AI
  request route. The `ai` object stores one trusted reference to the root
  reasoning Flow. Import restores that Flow as the direct request route.

  Use this codec explicitly when encoding because an AI Agent is also a normal
  `Jido.Agent` value:

      Jido.Authoring.encode_json(agent,
        registry: registry,
        codec: Jido.AI.Agent.Codec
      )
  """

  alias Jido.Agent
  alias Jido.Authoring.{Issue, Registry}

  @request_type "jido.ai.request"
  @response_type "jido.ai.response"

  @doc false
  @spec __jido_authoring_codec__() :: %{type: String.t(), vsn: pos_integer()}
  def __jido_authoring_codec__, do: %{type: "jido.ai.agent", vsn: 1}

  @doc false
  @spec encode_document(term(), Registry.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def encode_document(source, %Registry{} = registry) do
    with {:ok, definition} <- definition(source),
         {:ok, reasoning} <- reasoning(definition),
         {:ok, reasoning_reference} <- Registry.encode_reference(registry, :flow, reasoning),
         base = %{definition | routes: []},
         {:ok, %{"definition" => fields}} <- Jido.Agent.Codec.encode_document(base, registry) do
      {:ok,
       %{
         "type" => "jido.ai.agent",
         "vsn" => 1,
         "definition" => fields,
         "ai" => %{"reasoning" => reasoning_reference}
       }}
    end
  end

  def encode_document(_source, _registry) do
    Jido.Agent.Error.fail(
      :invalid_registry,
      [],
      "AI Agent codec registry must be a Jido.Authoring.Registry"
    )
  end

  @doc false
  @spec decode_document(term(), Registry.t()) ::
          {:ok, Agent.definition()} | {:error, [Issue.t()]}
  def decode_document(document, %Registry{} = registry) do
    with :ok <- document(document),
         %{"definition" => fields, "ai" => %{"reasoning" => reference}} <- document,
         :ok <- empty_routes(fields),
         {:ok, base} <- decode_base(fields, registry),
         {:ok, reasoning} <- resolve_reasoning(reference, registry),
         {:ok, definition} <- restore_route(base, reasoning) do
      {:ok, definition}
    else
      {:error, issues} when is_list(issues) -> {:error, issues}
      _other -> failure(:invalid_document, [], "Invalid AI Agent document")
    end
  end

  def decode_document(_document, _registry) do
    failure(
      :invalid_registry,
      [],
      "AI Agent codec registry must be a Jido.Authoring.Registry"
    )
  end

  defp definition(%Agent{} = source) do
    with {:ok, source} <- Agent.validate(source), do: {:ok, Agent.definition(source)}
  end

  defp definition(source) when is_atom(source) and source not in [nil, true, false] do
    {:ok, Agent.definition(source)}
  rescue
    error -> {:error, error}
  end

  defp definition(source) when is_map(source) and not is_struct(source), do: Agent.define(source)

  defp definition(_source) do
    Jido.Agent.Error.fail(
      :invalid_definition,
      [],
      "Expected an AI Agent definition, instance, or module"
    )
  end

  defp reasoning(%Agent{routes: [route]}) do
    case route do
      %{
        path: @request_type,
        handler: %{kind: :flow, target: target},
        state: %{source: :output, path: [:state]},
        reply: %{type: @response_type, from: %{source: :output, path: [:response]}}
      } ->
        {:ok, target}

      _route ->
        invalid_agent()
    end
  end

  defp reasoning(%Agent{}), do: invalid_agent()

  defp invalid_agent do
    Jido.Agent.Error.fail(
      :invalid_ai_agent,
      [:routes],
      "AI Agent must contain one graph-first request route"
    )
  end

  defp document(%{"type" => "jido.ai.agent", "vsn" => 1} = document) do
    object(document, ~w(type vsn definition ai))
  end

  defp document(%{"type" => "jido.ai.agent", "vsn" => version}) do
    failure(
      :unsupported_document,
      ["vsn"],
      "AI Agent document version is not supported",
      %{vsn: version, supported_vsns: [1]}
    )
  end

  defp document(_document),
    do: failure(:invalid_document, [], "Expected a jido.ai.agent document")

  defp object(value, fields) when is_map(value) and not is_struct(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(fields),
      do: :ok,
      else: failure(:invalid_document, [], "Unknown or missing AI Agent document fields")
  end

  defp object(_value, _fields),
    do: failure(:invalid_document, [], "AI Agent document must be a map")

  defp empty_routes(%{"routes" => []}), do: :ok

  defp empty_routes(_fields) do
    failure(
      :invalid_document,
      ["definition", "routes"],
      "AI Agent definition routes must be generated from the ai object"
    )
  end

  defp decode_base(fields, registry) do
    Jido.Agent.Codec.decode_document(
      %{"type" => "jido.agent.definition", "vsn" => 1, "definition" => fields},
      registry
    )
  end

  defp resolve_reasoning(reference, registry) do
    case Registry.decode_reference(registry, reference, :flow) do
      {:ok, reasoning} -> {:ok, reasoning}
      {:error, error} -> {:error, [issue(error, ["ai", "reasoning"])]}
    end
  end

  defp restore_route(%Agent{} = base, reasoning) do
    route = %{
      path: @request_type,
      as: :request,
      defaults: %{},
      handler: %{kind: :flow, target: reasoning},
      state: %{source: :output, path: [:state]},
      reply: %{type: @response_type, from: %{source: :output, path: [:response]}}
    }

    result =
      base
      |> Map.from_struct()
      |> Map.put(:routes, [route])
      |> Agent.define()

    case result do
      {:ok, definition} -> {:ok, definition}
      {:error, error} -> {:error, [issue(error, ["definition", "routes"])]}
    end
  end

  defp issue(%Issue{} = issue, path), do: %{issue | path: path ++ issue.path}

  defp issue(%Registry.Error{} = error, path) do
    Issue.new(:reference, path, Exception.message(error), details: error.details)
  end

  defp issue(error, path) do
    fields = if is_map(error), do: error, else: %{}
    details = if is_map(Map.get(fields, :details)), do: fields.details, else: %{}

    message =
      if Map.get(fields, :__exception__),
        do: Exception.message(error),
        else: inspect(error)

    error_path =
      fields
      |> Map.get(:path, [])
      |> Enum.map(fn
        segment when is_atom(segment) -> Atom.to_string(segment)
        segment -> segment
      end)

    Issue.new(
      Map.get(fields, :code) || :invalid_document,
      path ++ error_path,
      message,
      details: details
    )
  end

  defp failure(code, path, message, details \\ %{}),
    do: {:error, [Issue.new(code, path, message, details: details)]}
end
