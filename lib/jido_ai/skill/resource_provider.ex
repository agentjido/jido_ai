defmodule Jido.AI.Skill.ResourceProvider do
  @moduledoc """
  Invokes and validates host callbacks that provide runtime skill resources.

  Providers are only used for runtime specs supplied through Agent Skills
  integration. Filesystem skills continue to use `Jido.AI.Skill.Resources`.

  Supported provider forms are:

  - `fn request, context -> result end`
  - `{Module, :function}`
  - `{Module, :function, extra_args}`

  Providers receive canonical requests:

      %{operation: :list, skill: spec, policy: policy}
      %{operation: :load, skill: spec, resource_id: resource_id, policy: policy}

  Valid results are:

      {:ok, %{resources: [%{id: id, name: name, size: size}], complete: boolean()}}
      {:ok, %{resource_id: resource_id, content: text, size: non_neg_integer()}}
      {:error, term()}

  List entries require `id`, `name`, and `size`. Optional fields are `type`,
  `modified`, `mime_type`, and `metadata`. The `resources` field is the complete
  aggregate listing. `scripts`, `references`, and `assets` are filtered views of
  the same entries, so entries intentionally appear in both the aggregate list
  and their typed view. IDs are scoped to the activated skill and provider
  binding. Loading by an ID that was not present in the activated post-policy
  listing is rejected before the provider is called, including when the provider
  reported an incomplete listing.

  Jido validates and normalizes every result, reapplies `ResourcePolicy`, rejects
  entries that cannot be encoded for listing, rejects malformed identifiers and
  binary content, and invokes the provider on every resource load so content
  remains fresh. Listing truncation is ordered: the first entry that violates
  count, declared-size, or encoded-listing limits is excluded, as is everything
  after it. Resource IDs are opaque and are never parsed, normalized, joined,
  sorted, or interpreted.
  """

  alias Jido.AI.Actions.Skill.LoadSkill
  alias Jido.AI.Skill.{ResourcePolicy, Resources, Spec}

  @context_provider_key :__jido_ai_skill_resource_provider__
  @epoch DateTime.from_unix!(0)
  @max_resource_id_bytes 1_024
  @max_resource_name_bytes 1_024

  @type provider :: (map(), map() -> term()) | {module(), atom()} | {module(), atom(), [term()]}
  @type binding :: %{provider: provider(), context: map()}
  @type resource_info :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:size) => non_neg_integer(),
          required(:modified) => DateTime.t(),
          optional(:type) => atom() | String.t() | nil,
          optional(:mime_type) => String.t() | nil,
          optional(:metadata) => map()
        }
  @type resource_listing :: %{
          resources: [resource_info()],
          scripts: [resource_info()],
          references: [resource_info()],
          assets: [resource_info()],
          complete: boolean(),
          truncated: boolean(),
          truncation_reasons: [atom()],
          limits: map()
        }

  @doc false
  @spec context_provider_key() :: atom()
  def context_provider_key, do: @context_provider_key

  @doc """
  Validates a provider form.
  """
  @spec validate(provider() | nil) :: {:ok, provider() | nil} | {:error, term()}
  def validate(nil), do: {:ok, nil}
  def validate(provider) when is_function(provider, 2), do: {:ok, provider}

  def validate({module, function}) when is_atom(module) and is_atom(function),
    do: validate({module, function, []})

  def validate({module, function, extra_args})
      when is_atom(module) and is_atom(function) and is_list(extra_args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 2 + length(extra_args)) do
      {:ok, {module, function, extra_args}}
    else
      {:error, {:invalid_resource_provider, :undefined_function}}
    end
  end

  def validate(_provider), do: {:error, {:invalid_resource_provider, :invalid_form}}

  defp public_context(context) when is_map(context) do
    Enum.reduce(reserved_context_keys(), context, fn key, acc ->
      acc
      |> Map.delete(key)
      |> Map.delete(Atom.to_string(key))
    end)
  end

  defp public_context(_context), do: %{}

  defp reserved_context_keys do
    [
      LoadSkill.context_skills_key(),
      Resources.context_policy_key(),
      @context_provider_key
    ]
  end

  @doc """
  Lists provider-backed resources with opaque IDs.
  """
  @spec list(provider(), Spec.t(), ResourcePolicy.t(), map()) :: {:ok, resource_listing()} | {:error, term()}
  def list(provider, %Spec{} = spec, %ResourcePolicy{} = policy, context) do
    request = %{operation: :list, skill: spec, policy: policy}

    with {:ok, result} <- invoke(provider, request, public_context(context)),
         {:ok, response} <- validate_list_result(result) do
      build_listing_from_entries(response.resources, policy, provider_complete?: response.complete)
    end
  end

  @doc """
  Loads one provider-backed UTF-8 text resource by opaque ID.
  """
  @spec load(provider(), Spec.t(), String.t(), ResourcePolicy.t(), map()) ::
          {:ok, %{content: String.t(), resource_id: String.t(), size: non_neg_integer(), mime_type: String.t() | nil}}
          | {:error, term()}
  def load(provider, %Spec{} = spec, resource_id, %ResourcePolicy{} = policy, context) when is_binary(resource_id) do
    with :ok <- validate_resource_id(resource_id),
         request = %{operation: :load, skill: spec, resource_id: resource_id, policy: policy},
         {:ok, result} <- invoke(provider, request, public_context(context)),
         {:ok, resource} <- validate_load_result(result, resource_id),
         :ok <- Resources.validate_loaded_text(loaded_resource(resource), policy) do
      {:ok, resource}
    end
  end

  def load(_provider, %Spec{}, _resource_id, %ResourcePolicy{}, _context), do: {:error, :invalid_resource_id}

  defp invoke(provider, request, context) do
    result =
      case provider do
        fun when is_function(fun, 2) -> fun.(request, context)
        {module, function} -> apply(module, function, [request, context])
        {module, function, extra_args} -> apply(module, function, [request, context | extra_args])
      end

    case result do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:resource_provider_failed, reason}}
      other -> {:error, {:malformed_resource_provider_result, other}}
    end
  rescue
    error -> {:error, {:resource_provider_failed, {error.__struct__, Exception.message(error)}}}
  catch
    kind, reason -> {:error, {:resource_provider_failed, {kind, reason}}}
  end

  defp validate_list_result(%{resources: resources, complete: complete?})
       when is_list(resources) and is_boolean(complete?) do
    {:ok, %{resources: resources, complete: complete?}}
  end

  defp validate_list_result(_result), do: {:error, :malformed_resource_listing}

  defp build_listing_from_entries(entries, policy, opts) when is_list(entries) do
    provider_complete? = Keyword.get(opts, :provider_complete?, true)

    with {:ok, resources} <- normalize_resource_entries(entries),
         {:ok, selected, reasons} <- apply_listing_policy(resources, policy) do
      reasons =
        if provider_complete? do
          reasons
        else
          MapSet.put(reasons, :provider_incomplete)
        end

      {:ok, build_listing(selected, reasons, policy)}
    end
  end

  defp normalize_resource_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn entry, {:ok, resources, ids} ->
      with {:ok, resource} <- normalize_resource_entry(entry),
           :ok <- reject_duplicate_resource_id(resource.id, ids) do
        {:cont, {:ok, [resource | resources], MapSet.put(ids, resource.id)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resources, _ids} -> {:ok, Enum.reverse(resources)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_resource_entry(entry) when is_map(entry) do
    id = fetch_entry_value(entry, :id)
    name = fetch_entry_value(entry, :name)
    size = fetch_entry_value(entry, :size)
    type = fetch_entry_value(entry, :type)
    modified = default_if_nil(fetch_entry_value(entry, :modified), @epoch)
    mime_type = fetch_entry_value(entry, :mime_type)
    metadata = default_if_nil(fetch_entry_value(entry, :metadata), %{})

    with :ok <- validate_resource_id(id),
         :ok <- validate_resource_name(name),
         :ok <- valid_size(size),
         :ok <- valid_type(type),
         :ok <- valid_modified(modified),
         :ok <- valid_optional_string(:mime_type, mime_type),
         :ok <- valid_metadata(metadata) do
      {:ok,
       %{
         id: id,
         name: name,
         type: type,
         size: size,
         modified: modified,
         mime_type: mime_type,
         metadata: metadata
       }}
    end
  end

  defp normalize_resource_entry(_entry), do: {:error, :malformed_resource_entry}

  defp fetch_entry_value(entry, key), do: Map.get(entry, key, Map.get(entry, Atom.to_string(key)))

  defp default_if_nil(nil, default), do: default
  defp default_if_nil(value, _default), do: value

  @doc false
  @spec validate_resource_id(term()) :: :ok | {:error, :invalid_resource_id}
  def validate_resource_id(id) when is_binary(id) do
    cond do
      id == "" -> {:error, :invalid_resource_id}
      byte_size(id) > @max_resource_id_bytes -> {:error, :invalid_resource_id}
      not String.valid?(id) -> {:error, :invalid_resource_id}
      true -> :ok
    end
  end

  def validate_resource_id(_id), do: {:error, :invalid_resource_id}

  defp validate_resource_name(name) when is_binary(name) do
    cond do
      String.trim(name) == "" -> {:error, :malformed_resource_entry}
      byte_size(name) > @max_resource_name_bytes -> {:error, :malformed_resource_entry}
      not String.valid?(name) -> {:error, :malformed_resource_entry}
      true -> :ok
    end
  end

  defp validate_resource_name(_name), do: {:error, :malformed_resource_entry}

  defp valid_size(size) when is_integer(size) and size >= 0, do: :ok
  defp valid_size(_size), do: {:error, :malformed_resource_entry}

  defp valid_type(nil), do: :ok
  defp valid_type(type) when type in [:script, :reference, :asset], do: :ok
  defp valid_type(type) when type in ["script", "reference", "asset"], do: :ok
  defp valid_type(_type), do: {:error, :malformed_resource_entry}

  defp valid_modified(%DateTime{}), do: :ok
  defp valid_modified(_modified), do: {:error, :malformed_resource_entry}

  defp valid_optional_string(_key, nil), do: :ok

  defp valid_optional_string(_key, value) when is_binary(value) do
    if String.valid?(value), do: :ok, else: {:error, :malformed_resource_entry}
  end

  defp valid_optional_string(_key, _value), do: {:error, :malformed_resource_entry}

  defp valid_metadata(metadata) when is_map(metadata), do: :ok
  defp valid_metadata(_metadata), do: {:error, :malformed_resource_entry}

  defp reject_duplicate_resource_id(id, ids) do
    if MapSet.member?(ids, id), do: {:error, :duplicate_resource_id}, else: :ok
  end

  defp apply_listing_policy(resources, policy) do
    result =
      Enum.reduce_while(resources, {[], 0, MapSet.new()}, fn resource, {selected, count, reasons} ->
        cond do
          count >= policy.max_resources ->
            {:halt, {selected, count, MapSet.put(reasons, :max_resources)}}

          resource.size > policy.max_file_bytes ->
            {:halt, {selected, count, MapSet.put(reasons, :max_file_bytes)}}

          true ->
            candidate = Enum.reverse([resource | selected])

            case listing_payload_size(candidate) do
              {:ok, payload_size} when payload_size > policy.max_listing_bytes ->
                {:halt, {selected, count, MapSet.put(reasons, :max_listing_bytes)}}

              {:ok, _payload_size} ->
                {:cont, {[resource | selected], count + 1, reasons}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
        end
      end)

    case result do
      {:error, reason} -> {:error, reason}
      {selected, _count, reasons} -> {:ok, Enum.reverse(selected), reasons}
    end
  end

  defp listing_payload_size(resources) do
    case Jason.encode(resources) do
      {:ok, payload} -> {:ok, byte_size(payload)}
      {:error, _reason} -> {:error, :malformed_resource_listing}
    end
  end

  defp build_listing(resources, reasons, policy) do
    reasons = reasons |> MapSet.to_list() |> Enum.sort()

    %{
      resources: resources,
      scripts: resources_in_group(resources, :script),
      references: resources_in_group(resources, :reference),
      assets: resources_in_group(resources, :asset),
      complete: reasons == [],
      truncated: reasons != [],
      truncation_reasons: reasons,
      limits: ResourcePolicy.to_map(policy)
    }
  end

  defp resources_in_group(resources, type) do
    Enum.filter(resources, &(normalize_type(&1.type) == type))
  end

  defp normalize_type("script"), do: :script
  defp normalize_type("reference"), do: :reference
  defp normalize_type("asset"), do: :asset
  defp normalize_type(type), do: type

  defp validate_load_result(result, requested_id) when is_map(result) do
    content = fetch_entry_value(result, :content)
    resource_id = fetch_entry_value(result, :resource_id)
    size = fetch_entry_value(result, :size)
    mime_type = fetch_entry_value(result, :mime_type)

    with :ok <- validate_load_shape(content, size),
         :ok <- validate_resource_id(resource_id),
         :ok <- matching_id(resource_id, requested_id),
         :ok <- valid_optional_string(:mime_type, mime_type),
         :ok <- matching_size(content, size) do
      {:ok, %{content: content, resource_id: resource_id, size: size, mime_type: mime_type}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_load_result(_result, _requested_id), do: {:error, :malformed_resource}

  defp loaded_resource(resource) do
    %{
      content: resource.content,
      size: resource.size,
      mime_type: resource.mime_type,
      selector: {:resource_id, resource.resource_id}
    }
  end

  defp validate_load_shape(content, size) when is_binary(content) and is_integer(size) and size >= 0, do: :ok
  defp validate_load_shape(_content, _size), do: {:error, :malformed_resource}

  defp matching_id(id, id), do: :ok
  defp matching_id(_id, _requested_id), do: {:error, :resource_id_mismatch}

  defp matching_size(content, size) do
    if byte_size(content) == size do
      :ok
    else
      {:error, :resource_size_mismatch}
    end
  end
end
