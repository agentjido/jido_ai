defmodule Jido.AI.Portable do
  @moduledoc false
  import Kernel, except: [inspect: 1]

  alias Jido.AI.Agent
  alias Jido.AI.Profile

  @version 1

  def inspect(source, opts \\ []) do
    with {:ok, profiles} <- profiles(source),
         {:ok, selected} <- select_profiles(profiles, opts[:profile]) do
      {:ok, Map.new(selected, fn {id, profile} -> {id, safe_profile(profile)} end)}
    end
  end

  def preflight(source, request, opts \\ []) do
    with {:ok, profiles} <- profiles(source),
         {:ok, [{id, profile}]} <- select_profiles(profiles, opts[:profile]),
         {:ok, profile} <- Jido.AI.ModelRouter.select(profile, request_view(request), %{}),
         entry <- profile.models[profile.reasoning.model],
         {:ok, model} <- resolve_model(entry.model) do
      {:ok,
       %{
         profile: id,
         instructions: instruction_view(profile.instructions),
         model: model,
         model_role: profile.reasoning.model,
         models: Map.new(profile.models, fn {role, value} -> {role, value.model} end),
         reasoning: profile.reasoning,
         tools: Enum.map(profile.tools, &Map.take(&1, [:name, :description, :timeout, :metadata])),
         tool_sources: Enum.map(profile.tool_sources, &safe_tool_source/1),
         controls: profile.controls,
         result: profile.result,
         memory: profile.memory,
         observability: profile.observability
       }}
    else
      {:ok, _many} -> Profile.error("profile", "Select one AI profile")
      error -> error
    end
  end

  # Rich model records require the core Codec Registry; public model IDs must
  # not silently discard record-specific options during export.
  def export(source, format, opts \\ [])

  def export(source, format, opts) when format in [:map, :json, :yaml] do
    registries = Keyword.get(opts, :registries, %{})

    with {:ok, document} <- document(source, registries) do
      encode(document, format)
    end
  end

  def export(_source, format, _opts),
    do: Profile.error("export", "Unsupported format #{Kernel.inspect(format)}")

  def import(input, opts \\ []) do
    with {:ok, document} <- decode(input),
         :ok <- version(document) do
      registries = Keyword.get(opts, :registries, %{})
      import_document(document, registries)
    end
  end

  defp profiles(%Profile{} = profile), do: {:ok, %{profile.id => profile}}

  defp profiles(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0),
      do: {:ok, Agent.profiles(module)},
      else: Profile.error("agent", "Expected an Agent module, definition, or Profile")
  end

  defp profiles(%Jido.Agent{} = agent), do: {:ok, Agent.profiles(agent)}
  defp profiles(_), do: Profile.error("agent", "Expected an Agent module, definition, or Profile")

  defp select_profiles(profiles, nil), do: {:ok, Enum.sort(profiles)}

  defp select_profiles(profiles, id) do
    case Map.fetch(profiles, id) do
      {:ok, profile} -> {:ok, [{id, profile}]}
      :error -> Profile.error("profile", "Unknown AI profile #{Kernel.inspect(id)}")
    end
  end

  defp safe_profile(profile) do
    profile
    |> Map.from_struct()
    |> Map.drop([:tool_context, :effect_policy, :tool_interceptor])
    |> Map.update!(:instructions, &instruction_view/1)
    |> Map.update!(:models, fn models ->
      Map.new(models, fn {role, entry} ->
        {role, entry |> Map.drop([:provider_options]) |> Map.put(:provider_options, :redacted)}
      end)
    end)
    |> Map.update!(:tools, fn tools ->
      Enum.map(tools, &(&1 |> Map.drop([:target, :approval]) |> Map.put(:target, target_view(&1.target))))
    end)
    |> Map.update!(:tool_sources, &Enum.map(&1, fn source -> safe_tool_source(source) end))
  end

  defp safe_tool_source(source),
    do: source |> Map.drop([:transport, :approval, :resource_provider]) |> Map.put(:ref, target_view(source.ref))

  defp instruction_view(nil), do: :default
  defp instruction_view(text) when is_binary(text), do: text
  defp instruction_view(module) when is_atom(module), do: %{action: target_view(module)}

  defp target_view(module) when is_atom(module), do: Kernel.inspect(module)
  defp target_view(value) when is_binary(value), do: value
  defp target_view(%Jido.Flow{name: name}), do: name
  defp target_view(_), do: :registered

  defp request_view(request) when is_binary(request), do: %{query: request}
  defp request_view(request) when is_map(request), do: Map.take(request, [:query, "query", :metadata, "metadata"])
  defp request_view(_), do: %{}

  defp resolve_model(model) do
    {:ok, Jido.AI.Models.resolve(model)}
  rescue
    error in ArgumentError -> Profile.error("model", Exception.message(error))
  end

  defp document(%Profile{} = profile, registries) do
    with {:ok, value} <- export_profile(profile, registries) do
      {:ok, %{"version" => @version, "profile" => value}}
    end
  end

  defp document(source, registries) do
    with {:ok, definition} <- definition(source),
         {:ok, profiles} <- profiles(source),
         {:ok, schema} <- reference(registries, :schemas, definition.schema, "agent.schema"),
         {:ok, portable_profiles} <-
           traverse(profiles, fn {id, profile} ->
             with {:ok, value} <- export_profile(profile, registries),
                  do: {:ok, {Atom.to_string(id), Map.delete(value, "id")}}
           end) do
      routes =
        definition.routes
        |> Enum.flat_map(&portable_route/1)
        |> Enum.sort_by(& &1["type"])

      {:ok,
       %{
         "version" => @version,
         "agent" => %{
           "name" => definition.name,
           "description" => definition.description,
           "metadata" => definition.metadata,
           "schema" => %{"ref" => schema},
           "profiles" => Map.new(portable_profiles),
           "routes" => routes
         }
       }}
    end
  end

  defp definition(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0),
      do: {:ok, module.definition()},
      else: Profile.error("agent", "Expected an Agent module or definition")
  end

  defp definition(%Jido.Agent{} = agent), do: {:ok, agent}
  defp definition(_), do: Profile.error("agent", "Expected an Agent module or definition")

  defp export_profile(profile, registries) do
    with :ok <- exportable_models(profile),
         {:ok, instructions} <- export_instructions(profile.instructions, registries),
         {:ok, models} <- export_models(profile, registries),
         {:ok, tools} <- traverse(profile.tools, &export_tool(&1, registries)),
         {:ok, tool_sources} <- traverse(profile.tool_sources, &export_tool_source(&1, registries)),
         {:ok, controls} <- export_controls(profile.controls, registries),
         {:ok, result} <- export_result(profile.result, registries) do
      {:ok,
       compact(%{
         "id" => Atom.to_string(profile.id),
         "instructions" => instructions,
         "models" => models,
         "reasoning" => stringify(profile.reasoning),
         "tools" => tools ++ tool_sources,
         "controls" => controls,
         "result" => result,
         "memory" => stringify(profile.memory),
         "observability" => public_observability(profile.observability),
         "metadata" => profile.metadata
       })}
    end
  end

  defp export_instructions(nil, _registries), do: {:ok, nil}
  defp export_instructions(text, _registries) when is_binary(text), do: {:ok, text}

  defp export_instructions(module, registries) do
    with {:ok, ref} <- reference(registries, :actions, module, "instructions"),
         do: {:ok, %{"action" => ref}}
  end

  defp exportable_models(profile) do
    case Enum.find(profile.models, fn {_role, entry} -> is_struct(entry.model) end) do
      nil ->
        :ok

      {role, _} ->
        Profile.error(
          "models.#{role}.model",
          "Rich model records require core Agent Codec with a Registry; public export accepts model IDs"
        )
    end
  end

  defp export_models(profile, registries) do
    entries =
      Map.new(profile.models, fn {role, entry} ->
        generation = %{
          "temperature" => entry.generation[:temperature],
          "max_tokens" => entry.generation[:max_tokens],
          "timeout" => entry.generation[:receive_timeout]
        }

        value =
          generation
          |> Map.merge(%{
            "model" => portable_model(entry.model),
            "provider_options" => portable(entry.provider_options),
            "metadata" => entry.metadata
          })
          |> compact()

        {Atom.to_string(role), if(map_size(value) == 1, do: value["model"], else: value)}
      end)

    with {:ok, router} <- export_router(profile.model_router, registries) do
      {:ok, compact(%{"entries" => entries, "router" => router})}
    end
  end

  defp export_router(nil, _registries), do: {:ok, nil}

  defp export_router(router, registries) do
    with {:ok, ref} <- reference(registries, :model_routers, router.module, "models.router") do
      {:ok,
       compact(%{
         "ref" => ref,
         "fallback" => if(router.fallback, do: Atom.to_string(router.fallback))
       })}
    end
  end

  defp export_tool(tool, registries) do
    kind = tool_kind(tool.target)
    registry = if kind == "flow", do: :flows, else: :actions

    with {:ok, ref} <- reference(registries, registry, tool.target, "tools") do
      {:ok,
       tool
       |> Map.drop([:target])
       |> stringify()
       |> Map.merge(%{"kind" => kind, "ref" => ref})
       |> compact()}
    end
  end

  defp tool_kind(%Jido.Flow{}), do: "flow"

  defp tool_kind(module) when is_atom(module) do
    case Jido.Executable.resolve(module) do
      {:ok, %{kind: :flow}} -> "flow"
      _ -> "action"
    end
  end

  defp export_tool_source(source, registries) do
    with {:ok, ref} <- export_tool_source_ref(source, registries) do
      {:ok,
       source
       |> Map.drop([:kind, :ref, :transport, :resource_provider])
       |> stringify()
       |> Map.merge(%{"kind" => Atom.to_string(source.kind), "ref" => ref})
       |> compact()}
    end
  end

  defp export_tool_source_ref(source, registries) do
    case Jido.AI.ToolSource.registry_kind(source.kind) do
      nil -> {:ok, portable(source.ref)}
      kind -> reference(registries, kind, source.ref, "tools.#{source.kind}")
    end
  end

  defp export_controls(controls, registries) do
    stages = [:input, :model, :operation, :output]

    with {:ok, pairs} <-
           traverse(stages, fn stage ->
             with {:ok, values} <-
                    traverse(controls[stage], &export_control(&1, registries)) do
               {:ok, {Atom.to_string(stage), values}}
             end
           end) do
      limits = controls |> Map.drop([:input, :model, :operation, :output]) |> stringify()
      {:ok, Map.merge(limits, Map.new(pairs))}
    end
  end

  defp export_control(%{module: module, when: match}, registries) do
    with {:ok, ref} <- reference(registries, :controls, module, "controls"),
         do: {:ok, %{"ref" => ref, "when" => portable(match)}}
  end

  defp export_control(module, registries) do
    with {:ok, ref} <- reference(registries, :controls, module, "controls"),
         do: {:ok, %{"ref" => ref}}
  end

  defp export_result(result, registries) do
    with {:ok, schema} <- optional_reference(registries, :schemas, result.schema, "result.schema"),
         {:ok, repair} <-
           optional_reference(registries, :actions, result[:repair_action], "result.repair_action") do
      {:ok,
       result
       |> Map.drop([:schema, :repair_fun, :repair_action])
       |> stringify()
       |> then(fn value ->
         value
         |> maybe_put("schema", schema && %{"ref" => schema})
         |> maybe_put("repair_action", repair && %{"ref" => repair})
       end)}
    end
  end

  defp portable_route(%{path: path, target: {target, %{profile_id: id}}})
       when target == Jido.AI.Orchestration.Start,
       do: [%{"type" => path, "target" => %{"ai" => Atom.to_string(id)}}]

  defp portable_route(_route), do: []

  defp reference(registries, kind, value, path) do
    values = Map.get(registries, kind, Map.get(registries, Atom.to_string(kind), %{}))

    case Enum.find(values, fn {_id, target} -> reference_matches?(kind, target, value) end) do
      {id, _} -> {:ok, to_string(id)}
      nil -> Profile.error(path, "No portable registry name")
    end
  end

  defp reference_matches?(:schemas, target, value), do: target == value or schema_value(target) == value
  defp reference_matches?(_kind, target, value), do: target == value

  defp optional_reference(_registries, _kind, nil, _path), do: {:ok, nil}
  defp optional_reference(registries, kind, value, path), do: reference(registries, kind, value, path)

  defp encode(document, :map), do: {:ok, document}

  defp encode(document, format) when format in [:json, :yaml] do
    case Jason.encode(document, pretty: true) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> Profile.error("export", Exception.message(reason))
    end
  end

  defp decode(input) when is_map(input) and not is_struct(input), do: {:ok, input}

  defp decode(input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> yaml(input)
    end
  end

  defp decode(_), do: Profile.error("import", "Expected a map, JSON document, or YAML document")

  defp yaml(input) do
    case YamlElixir.read_from_string(input) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> Profile.error("import", Kernel.inspect(reason))
    end
  end

  defp version(document) do
    if get(document, "version") == @version,
      do: :ok,
      else: Profile.error("version", "Expected portable format version #{@version}")
  end

  defp import_document(document, registries) do
    cond do
      is_map(get(document, "profile")) -> import_profile(get(document, "profile"), registries)
      is_map(get(document, "agent")) -> import_agent(get(document, "agent"), registries)
      true -> Profile.error("import", "Expected an agent or profile document")
    end
  end

  defp import_profile(value, registries), do: Profile.new(value, registries: registries)

  defp import_agent(value, registries) do
    with {:ok, schema} <- resolve_ref(registries, :schemas, get(value, "schema"), "agent.schema"),
         {:ok, profiles} <- import_profiles(get(value, "profiles"), registries),
         {:ok, routes} <- import_routes(get(value, "routes", [])) do
      attrs = %{
        name: get(value, "name"),
        description: get(value, "description"),
        metadata: get(value, "metadata", %{}),
        schema: schema_value(schema),
        routes: routes
      }

      Jido.AI.Authoring.lower(attrs, profiles)
    end
  end

  defp import_profiles(values, registries) when is_map(values) do
    traverse(values, fn {id, value} ->
      value = Map.put(value, "id", to_string(id))
      Profile.new(value, registries: registries)
    end)
  end

  defp import_profiles(_, _), do: Profile.error("agent.profiles", "Expected a profile map")

  defp import_routes(routes) when is_list(routes) do
    traverse(routes, fn route ->
      with path when is_binary(path) <- get(route, "type"),
           %{} = target <- get(route, "target"),
           id when is_binary(id) <- get(target, "ai"),
           {:ok, id} <- existing_atom(id, "routes.target.ai") do
        {:ok, {path, Jido.AI.Authoring.ai(id), []}}
      else
        {:error, _} = error -> error
        _ -> Profile.error("routes", "Expected an AI route")
      end
    end)
  end

  defp import_routes(_), do: Profile.error("routes", "Expected a route list")

  defp resolve_ref(registries, kind, value, path) do
    ref = if is_map(value), do: get(value, "ref")
    values = Map.get(registries, kind, Map.get(registries, Atom.to_string(kind), %{}))

    case values do
      %{} ->
        case Map.fetch(values, ref) do
          {:ok, target} -> {:ok, target}
          :error -> Profile.error(path, "Unknown reference #{Kernel.inspect(ref)}")
        end

      _ ->
        Profile.error(path, "Expected a reference registry")
    end
  end

  defp schema_value(module) when is_atom(module) do
    if function_exported?(module, :schema, 0), do: module.schema(), else: module
  end

  defp schema_value(value), do: value

  defp existing_atom(value, path) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> Profile.error(path, "Expected a host-defined atom")
  end

  defp public_observability(value) do
    value
    |> Map.new(fn {key, flag} -> {key |> Atom.to_string() |> String.trim_trailing("?"), flag} end)
  end

  defp stringify(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {to_string(key), portable(item)} end)
  end

  defp portable(nil), do: nil
  defp portable(value) when is_boolean(value), do: value
  defp portable(value) when is_atom(value), do: Atom.to_string(value)
  defp portable({kind, fields}) when kind in [:only, :except], do: %{Atom.to_string(kind) => portable(fields)}
  defp portable(value) when is_map(value), do: stringify(value)
  defp portable(value) when is_list(value), do: Enum.map(value, &portable/1)
  defp portable(value), do: value

  defp portable_model(value) when is_atom(value), do: Atom.to_string(value)
  defp portable_model(value), do: portable(value)

  defp compact(map), do: Map.reject(map, fn {_key, value} -> value in [nil, %{}, []] end)
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get(map, key, default \\ nil) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case Enum.find(Map.keys(map), &(is_atom(&1) and Atom.to_string(&1) == key)) do
          nil -> default
          atom -> Map.get(map, atom)
        end
    end
  end

  defp traverse(values, fun) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end
end
