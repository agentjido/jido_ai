defmodule Jido.AI.Agent.Codec do
  @moduledoc """
  Stores the authoring boundary of a graph-first AI Agent.

  Version 1 stores the normal Jido Agent definition without its generated AI
  request route or Toolset extension. The `ai` object stores trusted references
  to the root reasoning Flow and the Agent-local tool Actions. When present,
  its `config` object stores the root Flow input defaults from the reasoning
  block.

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
         {:ok, reasoning, config} <- reasoning(definition),
         {:ok, actions, base_extensions} <- tools(definition),
         {:ok, reasoning_reference} <- Registry.encode_reference(registry, :flow, reasoning),
         {:ok, tool_references} <- encode_tools(actions, registry),
         {:ok, stored_config} <- encode_config(config, reasoning),
         base = %{definition | routes: [], extensions: base_extensions},
         {:ok, %{"definition" => fields}} <- Jido.Agent.Codec.encode_document(base, registry) do
      ai =
        %{"reasoning" => reasoning_reference, "tools" => tool_references}
        |> put_config(stored_config)

      {:ok,
       %{
         "type" => "jido.ai.agent",
         "vsn" => 1,
         "definition" => fields,
         "ai" => ai
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
         %{"definition" => fields, "ai" => ai} <- document,
         :ok <- ai_object(ai),
         %{"reasoning" => reference, "tools" => tool_references} <- ai,
         :ok <- empty_routes(fields),
         {:ok, base} <- decode_base(fields, registry),
         {:ok, reasoning} <- resolve_reasoning(reference, registry),
         {:ok, config} <- decode_config(Map.get(ai, "config", %{}), reasoning),
         {:ok, actions} <- resolve_tools(tool_references, registry),
         {:ok, definition} <- restore_ai(base, reasoning, config, actions) do
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
        {:ok, target, Map.get(route, :defaults, %{})}

      _route ->
        invalid_agent()
    end
  end

  defp reasoning(%Agent{}), do: invalid_agent()

  defp tools(%Agent{extensions: extensions}) do
    {toolsets, other} = Enum.split_with(extensions, &(&1.provider == Jido.AI.Toolset))

    case toolsets do
      [%{data: %{actions: actions}}] ->
        with :ok <- Jido.AI.Toolset.validate(actions), do: {:ok, actions, other}

      _other ->
        invalid_agent()
    end
  end

  defp encode_tools(actions, registry) do
    actions
    |> Enum.reduce_while({:ok, []}, fn action, {:ok, references} ->
      case Registry.encode_reference(registry, :action, action) do
        {:ok, reference} -> {:cont, {:ok, [reference | references]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> then(fn
      {:ok, references} -> {:ok, Enum.reverse(references)}
      error -> error
    end)
  end

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

  defp ai_object(%{} = ai) when not is_struct(ai) do
    keys = Map.keys(ai)
    missing = ["reasoning", "tools"] -- keys
    unknown = keys -- ["reasoning", "tools", "config"]

    if missing == [] and unknown == [],
      do: :ok,
      else: failure(:invalid_document, ["ai"], "Unknown or missing AI configuration fields")
  end

  defp ai_object(_ai),
    do: failure(:invalid_document, ["ai"], "AI configuration must be a map")

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

  defp resolve_tools(references, registry) when is_list(references) do
    references
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {reference, index}, {:ok, actions} ->
      case Registry.decode_reference(registry, reference, :action) do
        {:ok, action} -> {:cont, {:ok, [action | actions]}}
        {:error, error} -> {:halt, {:error, [issue(error, ["ai", "tools", index])]}}
      end
    end)
    |> then(fn
      {:ok, actions} ->
        actions = Enum.reverse(actions)

        case Jido.AI.Toolset.validate(actions) do
          :ok -> {:ok, actions}
          {:error, reason} -> failure(:invalid_tools, ["ai", "tools"], inspect(reason))
        end

      error ->
        error
    end)
  end

  defp resolve_tools(_references, _registry),
    do: failure(:invalid_tools, ["ai", "tools"], "AI Agent tools must be a list")

  defp restore_ai(%Agent{} = base, reasoning, config, actions) do
    route = %{
      path: @request_type,
      as: :request,
      defaults: config,
      handler: %{kind: :flow, target: reasoning},
      state: %{source: :output, path: [:state]},
      reply: %{type: @response_type, from: %{source: :output, path: [:response]}}
    }

    toolset = %{
      id: Jido.AI.Toolset.id(),
      provider: Jido.AI.Toolset,
      vsn: Jido.AI.Toolset.vsn(),
      data: %{actions: actions}
    }

    result =
      base
      |> Map.from_struct()
      |> Map.put(:routes, [route])
      |> Map.update!(:extensions, &(&1 ++ [toolset]))
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

  defp put_config(ai, config) when map_size(config) == 0, do: ai
  defp put_config(ai, config), do: Map.put(ai, "config", config)

  defp encode_config(config, reasoning) do
    case Jido.AI.Agent.Config.encode(config, reasoning) do
      {:ok, config} ->
        {:ok, config}

      {:error, reason} ->
        Jido.Agent.Error.fail(
          :invalid_ai_config,
          [:routes, 0, :defaults],
          "AI reasoning defaults are invalid",
          %{reason: reason}
        )
    end
  end

  defp decode_config(config, reasoning) when is_map(config) and not is_struct(config) do
    case Jido.AI.Agent.Config.decode(config, reasoning) do
      {:ok, config} ->
        {:ok, config}

      {:error, reason} ->
        failure(
          :invalid_ai_config,
          ["ai", "config"],
          "AI reasoning configuration is invalid",
          %{reason: inspect(reason)}
        )
    end
  end

  defp decode_config(_config, _reasoning) do
    failure(:invalid_ai_config, ["ai", "config"], "AI reasoning configuration must be a map")
  end
end
