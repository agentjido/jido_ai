defmodule Jido.AI.ToolSource do
  @moduledoc "Static declarations for tools that need an adapter or planning step."

  alias Jido.AI.Profile

  @kinds [:ash_resource, :mcp_tools, :browser, :catalog, :skill, :load_path, :subagent, :handoff]
  @module_kinds %{
    ash_resource: :ash_resources,
    catalog: :catalogs,
    skill: :skills,
    subagent: :agents,
    handoff: :agents
  }
  @reference_fields %{
    ash_resource: :resource,
    mcp_tools: :endpoint,
    browser: :name,
    catalog: :catalog,
    skill: :skill,
    load_path: :path,
    subagent: :agent,
    handoff: :agent
  }
  @common [
    :kind,
    :ref,
    :as,
    :description,
    :timeout,
    :forward_context,
    :idempotency,
    :approval,
    :metadata
  ]
  @specific %{
    ash_resource: [:resource, :actions],
    mcp_tools: [
      :endpoint,
      :prefix,
      :tools,
      :discover,
      :required,
      :transport,
      :client_info,
      :protocol_version,
      :capabilities,
      :timeouts
    ],
    browser: [:name, :mode, :allow],
    catalog: [:catalog, :prefix, :max_calls, :max_parallel_calls, :require_read_only],
    skill: [:skill],
    load_path: [
      :path,
      :trust,
      :resource_policy,
      :resource_provider,
      :max_depth,
      :max_directories,
      :exclude_directories
    ],
    subagent: [:agent, :result],
    handoff: [:agent, :target]
  }

  @doc false
  def kinds, do: @kinds

  @doc false
  def source_input?(%{} = value) do
    case value |> fetch(:kind) |> normalize_kind() do
      {:ok, kind} -> kind in @kinds
      _ -> false
    end
  end

  def source_input?(_), do: false

  @doc "Validates inert tool-source declarations without discovery or I/O."
  def new(values, registries \\ %{})

  def new(values, registries) when is_list(values) do
    with {:ok, sources} <- Profile.traverse(values, &source(&1, registries)) do
      identities = Enum.map(sources, &identity/1)

      if identities == Enum.uniq(identities),
        do: {:ok, sources},
        else: Profile.error("tools", "Duplicate tool source")
    end
  end

  def new(_, _), do: Profile.error("tools", "Expected a tool-source list")

  @doc false
  def registry_kind(kind), do: Map.get(@module_kinds, kind)

  @doc false
  def reference_field(kind), do: Map.fetch!(@reference_fields, kind)

  defp source(value, registries) do
    with {:ok, attrs} <- input_map(value),
         {:ok, kind} <- kind(fetch(attrs, :kind)),
         {:ok, attrs} <- Profile.fields(attrs, @common ++ Map.fetch!(@specific, kind), "tools.#{kind}"),
         attrs = normalize_reference(attrs, kind),
         {:ok, ref} <- reference(kind, attrs[:ref], registries),
         attrs = attrs |> Map.put(:kind, kind) |> Map.put(:ref, ref) |> drop_reference_field(kind),
         {:ok, attrs} <- normalize_options(attrs),
         attrs = defaults(kind) |> Map.merge(attrs),
         :ok <- validate(kind, attrs),
         :ok <- static(attrs) do
      {:ok, attrs}
    end
  end

  defp input_map(%{} = value) when not is_struct(value), do: {:ok, value}

  defp input_map(value) when is_list(value) do
    cond do
      not Keyword.keyword?(value) ->
        Profile.error("tools", "Expected a map")

      duplicate_keyword_keys?(value) ->
        Profile.error("tools", "Duplicate tool-source key")

      true ->
        {:ok, Map.new(value)}
    end
  end

  defp input_map(_), do: Profile.error("tools", "Expected a map")

  defp duplicate_keyword_keys?(value) do
    keys = Keyword.keys(value)
    length(keys) != length(Enum.uniq(keys))
  end

  defp kind(value) do
    case normalize_kind(value) do
      {:ok, kind} when kind in @kinds -> {:ok, kind}
      _ -> Profile.error("tools.kind", "Expected a supported tool-source kind")
    end
  end

  defp normalize_kind(value) when is_atom(value), do: {:ok, value}

  defp normalize_kind(value) when is_binary(value) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == value)) do
      nil -> :error
      kind -> {:ok, kind}
    end
  end

  defp normalize_kind(_), do: :error

  defp normalize_reference(attrs, kind) do
    field = reference_field(kind)
    ref = Map.get(attrs, :ref, Map.get(attrs, field))
    Map.put(attrs, :ref, ref)
  end

  defp drop_reference_field(attrs, kind) do
    Map.delete(attrs, reference_field(kind))
  end

  defp reference(kind, value, registries) when is_map_key(@module_kinds, kind) do
    cond do
      is_atom(value) and value not in [nil, true, false] -> compiled(value, kind)
      is_binary(value) -> registry(registries, Map.fetch!(@module_kinds, kind), value)
      true -> Profile.error("tools.#{kind}.ref", "Expected a module or registered reference")
    end
  end

  defp reference(:load_path, value, _registries) when is_binary(value) and value != "", do: {:ok, value}

  defp reference(kind, value, _registries)
       when kind in [:mcp_tools, :browser] and (is_binary(value) or is_atom(value)) and
              value not in [nil, true, false],
       do: {:ok, to_string(value)}

  defp reference(kind, _value, _registries),
    do: Profile.error("tools.#{kind}.ref", "Expected a static reference")

  defp compiled(module, kind) do
    if match?({:module, _}, Code.ensure_compiled(module)),
      do: {:ok, module},
      else: Profile.error("tools.#{kind}.ref", "Module is not available")
  end

  defp registry(registries, kind, id) when is_map(registries) do
    values = Map.get(registries, kind, Map.get(registries, Atom.to_string(kind), %{}))

    case values do
      %{} ->
        case Map.fetch(values, id) do
          {:ok, module} -> compiled(module, kind)
          :error -> Profile.error("registries.#{kind}", "Unknown reference #{inspect(id)}")
        end

      _ ->
        Profile.error("registries.#{kind}", "Expected a reference map")
    end
  end

  defp registry(_, kind, id),
    do: Profile.error("registries.#{kind}", "Unknown reference #{inspect(id)}")

  defp normalize_options(attrs) do
    with {:ok, forward_context} <- context_policy(Map.get(attrs, :forward_context, :public)),
         {:ok, idempotency} <- known(Map.get(attrs, :idempotency, :idempotent), [:idempotent, :unsafe_once]),
         {:ok, mode} <- optional_known(attrs[:mode], [:read_only, :read_write]),
         {:ok, result} <- optional_known(attrs[:result], [:structured, :content]),
         {:ok, target} <- optional_known(attrs[:target], [:auto]) do
      attrs =
        attrs
        |> Map.put(:forward_context, forward_context)
        |> Map.put(:idempotency, idempotency)
        |> normalize_name(:as)
        |> normalize_names(:actions)
        |> normalize_names(:tools)
        |> normalize_static_map(:metadata)
        |> normalize_static_map(:capabilities)
        |> normalize_static_map(:timeouts)
        |> normalize_static_map(:client_info)
        |> normalize_static(:approval)
        |> maybe_put(:mode, mode)
        |> maybe_put(:result, result)
        |> maybe_put(:target, target)

      {:ok, attrs}
    end
  end

  defp context_policy(value) when value in [:all, :public, :none], do: {:ok, value}
  defp context_policy(value) when value in ["all", "public", "none"], do: known(value, [:all, :public, :none])

  defp context_policy(%{} = value) do
    Enum.find_value([:only, :except], fn kind ->
      fields = Map.get(value, kind, Map.get(value, Atom.to_string(kind)))
      if is_list(fields), do: context_fields(kind, fields)
    end) || Profile.error("tools.forward_context", "Expected a context policy")
  end

  defp context_policy({kind, fields}) when kind in [:only, :except] and is_list(fields),
    do: context_fields(kind, fields)

  defp context_policy(_), do: Profile.error("tools.forward_context", "Expected a context policy")

  defp context_fields(kind, fields) do
    Profile.traverse(fields, fn
      field when is_atom(field) ->
        {:ok, field}

      field when is_binary(field) ->
        try do
          {:ok, String.to_existing_atom(field)}
        rescue
          ArgumentError -> Profile.error("tools.forward_context", "Expected host-defined fields")
        end

      _ ->
        Profile.error("tools.forward_context", "Expected host-defined fields")
    end)
    |> case do
      {:ok, fields} -> {:ok, {kind, fields}}
      error -> error
    end
  end

  defp known(value, allowed) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: Profile.error("tools", "Expected a known option")
  end

  defp known(value, allowed) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> Profile.error("tools", "Expected a known option")
      option -> {:ok, option}
    end
  end

  defp known(_, _), do: Profile.error("tools", "Expected a known option")
  defp optional_known(nil, _allowed), do: {:ok, nil}
  defp optional_known(value, allowed), do: known(value, allowed)

  defp validate(:ash_resource, attrs) do
    if is_list(attrs[:actions]) and Enum.all?(attrs[:actions], &name?/1),
      do: :ok,
      else: Profile.error("tools.ash_resource.actions", "Expected a static action allowlist")
  end

  defp validate(:mcp_tools, attrs) do
    if is_binary(attrs.prefix) and is_list(attrs.tools) and is_boolean(attrs.discover) and
         is_boolean(attrs.required) and optional_positive?(attrs[:timeout]) and is_map(attrs.capabilities) and
         is_map(attrs.timeouts),
       do: :ok,
       else: Profile.error("tools.mcp_tools", "Expected valid static MCP options")
  end

  defp validate(:browser, attrs) do
    write_allowed? = attrs.mode == :read_only or attrs[:approval] not in [nil, false]

    if attrs.mode in [:read_only, :read_write] and is_list(attrs.allow) and
         Enum.all?(attrs.allow, &is_binary/1) and write_allowed?,
       do: :ok,
       else: Profile.error("tools.browser", "Expected a mode, URL allowlist, and approval for write access")
  end

  defp validate(:catalog, attrs) do
    if is_binary(attrs.prefix) and positive?(attrs.timeout) and positive?(attrs.max_calls) and
         positive?(attrs.max_parallel_calls) and is_boolean(attrs.require_read_only),
       do: :ok,
       else: Profile.error("tools.catalog", "Expected valid catalog limits")
  end

  defp validate(:subagent, attrs) do
    if positive?(attrs.timeout) and attrs.result in [:structured, :content],
      do: :ok,
      else: Profile.error("tools.subagent", "Expected a timeout and result mode")
  end

  defp validate(:handoff, _attrs), do: :ok
  defp validate(:skill, _attrs), do: :ok
  defp validate(:load_path, _attrs), do: :ok

  defp static(attrs) do
    case Jido.Action.validate_static_data(attrs) do
      :ok -> :ok
      {:error, reason} -> Profile.error("tools", reason)
    end
  end

  defp defaults(:ash_resource), do: %{actions: [], metadata: %{}}

  defp defaults(:mcp_tools),
    do: %{prefix: "", tools: [], discover: false, required: false, capabilities: %{}, timeouts: %{}, metadata: %{}}

  defp defaults(:browser), do: %{mode: :read_only, allow: [], metadata: %{}}

  defp defaults(:catalog),
    do: %{
      prefix: "catalog_",
      timeout: 1_500,
      max_calls: 12,
      max_parallel_calls: 8,
      require_read_only: true,
      metadata: %{}
    }

  defp defaults(:subagent), do: %{timeout: 30_000, result: :structured, metadata: %{}}
  defp defaults(_), do: %{metadata: %{}}

  defp identity(source), do: {source.kind, source.ref, source[:as]}
  defp name?(value), do: is_atom(value) or (is_binary(value) and value != "")
  defp positive?(value), do: is_integer(value) and value > 0
  defp optional_positive?(nil), do: true
  defp optional_positive?(value), do: positive?(value)

  defp normalize_name(attrs, key) do
    case Map.get(attrs, key) do
      value when is_atom(value) and value not in [nil, true, false] -> Map.put(attrs, key, Atom.to_string(value))
      _ -> attrs
    end
  end

  defp normalize_names(attrs, key) do
    case Map.get(attrs, key) do
      values when is_list(values) ->
        Map.put(attrs, key, Enum.map(values, &if(is_atom(&1), do: Atom.to_string(&1), else: &1)))

      _ ->
        attrs
    end
  end

  defp normalize_static_map(attrs, key) do
    case Map.get(attrs, key) do
      value when is_map(value) -> Map.put(attrs, key, Profile.portable_data(value))
      _ -> attrs
    end
  end

  defp normalize_static(attrs, key) do
    if Map.has_key?(attrs, key),
      do: Map.update!(attrs, key, &Profile.portable_data/1),
      else: attrs
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
