defmodule Jido.AI.Actions.Skill.LoadResource do
  @moduledoc """
  Loads one text resource from an activated skill.

  The action uses the same runtime session as `load_skill`. It cannot access a
  skill that is not active in that session. It applies the resource policy that
  was stored during activation.

  Filesystem skills load by `relative_path` and retain the legacy `path` alias.
  Runtime specs configured with `:resource_provider` load by opaque
  `resource_id`; the provider is invoked on every authorized load and its output
  is validated before returning text to the model.
  """

  use Jido.Action,
    name: "load_skill_resource",
    description: """
    Loads one UTF-8 text resource from an activated skill. Use resource_id for
    provider-backed runtime skills. Use relative_path for filesystem skills;
    path remains accepted as a compatibility alias.
    """,
    category: "ai",
    tags: ["skills", "resources", "lazy-loading"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        name: Zoi.string(description: "The activated skill name"),
        resource_id:
          Zoi.string(description: "Opaque provider resource ID from the skill listing")
          |> Zoi.optional(),
        relative_path:
          Zoi.string(description: "A relative filesystem resource path from the skill listing")
          |> Zoi.optional(),
        path: Zoi.string(description: "Compatibility alias for relative_path") |> Zoi.optional()
      })
      |> Zoi.refine({__MODULE__, :validate_resource_selector, []})

  alias Jido.AI.Actions.Skill.RuntimeContext
  alias Jido.AI.Skill.{Activation, ResourcePolicy, ResourceProvider, Resources}
  alias Jido.AI.Validation

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @max_path_length 1_024
  @selector_error "exactly one of resource_id, relative_path, or path is required"

  @doc false
  @spec validate_resource_selector(map(), keyword()) :: :ok | {:error, String.t()}
  def validate_resource_selector(params, opts \\ [])

  def validate_resource_selector(params, _opts) when is_map(params) do
    selector_count =
      [:resource_id, :relative_path, :path]
      |> Enum.count(fn key -> present_selector?(Map.get(params, key)) end)

    if selector_count == 1, do: :ok, else: {:error, @selector_error}
  end

  def validate_resource_selector(_params, _opts), do: {:error, @selector_error}

  @impl Jido.Action
  def run(params, context) when is_map(params) do
    context = if is_map(context), do: context, else: %{}

    with {:ok, name} <- validate_name(param(params, :name)),
         {:ok, activation} <- activated_skill(name, context),
         {:ok, selector} <- validate_selector(params, activation) do
      load_resource(name, selector, activation, context)
    end
  end

  def run(_params, _context) do
    {:error, %{type: :invalid_params, message: "Parameters must be a map"}}
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp present_selector?(value), do: not is_nil(value)

  defp validate_name(name) do
    case Validation.validate_string(name, max_length: @max_name_length, allow_empty: false) do
      {:ok, name} ->
        if Regex.match?(@name_regex, name) do
          {:ok, name}
        else
          invalid_name(:invalid_format)
        end

      {:error, reason} ->
        invalid_name(reason)
    end
  end

  defp validate_path(path) do
    case Validation.validate_string(path, max_length: @max_path_length, allow_empty: false) do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> invalid_path(path, reason)
    end
  end

  defp validate_resource_id(resource_id) do
    case ResourceProvider.validate_resource_id(resource_id) do
      :ok -> {:ok, resource_id}
      {:error, reason} -> invalid_resource_id(resource_id, reason)
    end
  end

  defp validate_selector(params, %{resource_backend: :provider}) do
    case {param(params, :resource_id), param(params, :relative_path), param(params, :path)} do
      {resource_id, nil, nil} ->
        validate_resource_id(resource_id)

      {_resource_id, _relative_path, _path} ->
        invalid_resource_id(param(params, :resource_id), :invalid_provider_selector)
    end
  end

  defp validate_selector(params, %{resource_backend: :filesystem}) do
    case {param(params, :resource_id), param(params, :relative_path), param(params, :path)} do
      {nil, relative_path, nil} ->
        validate_path(relative_path)

      {nil, nil, path} ->
        validate_path(path)

      {_resource_id, _relative_path, _path} ->
        invalid_path(param(params, :relative_path) || param(params, :path), :invalid_filesystem_selector)
    end
  end

  defp validate_selector(params, _activation) do
    case {param(params, :resource_id), param(params, :relative_path), param(params, :path)} do
      {nil, relative_path, nil} -> validate_path(relative_path)
      {nil, nil, path} -> validate_path(path)
      {resource_id, nil, nil} -> validate_resource_id(resource_id)
      _ -> invalid_path(nil, :invalid_resource_selector)
    end
  end

  defp activated_skill(name, context) do
    opts = [session_id: RuntimeContext.session_id(context)]

    case Activation.get_context(name, opts) do
      {:ok, activation} ->
        {:ok, activation}

      {:error, :not_activated} ->
        {:error,
         %{
           type: :skill_not_activated,
           message: "Skill '#{name}' is not activated in this session",
           skill: name
         }}
    end
  end

  defp load_resource(name, resource_id, %{resource_provider: %{provider: provider}} = activation, context) do
    policy = Map.get(activation, :resource_policy, ResourcePolicy.default())

    with :ok <- authorize_provider_resource(resource_id, activation),
         {:ok, resource} <- ResourceProvider.load(provider, activation.skill, resource_id, policy, context) do
      {:ok, format_loaded_resource(name, resource)}
    else
      {:error, reason} ->
        provider_resource_error(name, resource_id, reason)
    end
  end

  defp load_resource(name, path, %{root_dir: root_dir} = activation, _context) when is_binary(root_dir) do
    policy = Map.get(activation, :resource_policy, ResourcePolicy.default())

    case Resources.load_text(root_dir, path, policy) do
      {:ok, resource} ->
        {:ok, format_loaded_resource(name, resource)}

      {:error, reason} ->
        resource_error(name, path, reason)
    end
  end

  defp load_resource(name, path, _activation, _context), do: resource_error(name, path, :not_found)

  defp format_loaded_resource(name, %{resource_id: resource_id} = resource) do
    %{
      skill: name,
      resource_id: resource_id,
      content: resource.content,
      size: resource.size,
      mime_type: resource.mime_type
    }
  end

  defp format_loaded_resource(name, %{relative_path: path} = resource) do
    %{
      skill: name,
      path: path,
      content: resource.content,
      size: resource.size
    }
  end

  defp invalid_name(reason) do
    {:error, %{type: :invalid_skill_name, message: "Invalid skill name", reason: reason}}
  end

  defp invalid_path(path, reason) do
    {:error,
     %{
       type: :invalid_resource_path,
       message: "Invalid resource path",
       path: path,
       reason: reason
     }}
  end

  defp invalid_resource_id(resource_id, reason) do
    {:error,
     %{
       type: :invalid_resource_id,
       message: "Invalid provider resource ID",
       resource_id: resource_id,
       reason: reason
     }}
  end

  defp authorize_provider_resource(resource_id, activation) do
    ids = Map.get(activation, :provider_resource_ids, MapSet.new())

    if MapSet.member?(ids, resource_id) do
      :ok
    else
      {:error, :not_found}
    end
  end

  defp resource_error(name, path, reason)
       when reason in [:path_traversal, :invalid_resource_path, :resource_path_changed] do
    {:error,
     %{
       type: :invalid_resource_path,
       message: "Resource path is not valid for skill '#{name}'",
       skill: name,
       path: path,
       reason: reason
     }}
  end

  defp resource_error(name, path, reason) do
    resource_error(name, :path, path, "Resource '#{path}'", "resource '#{path}'", reason)
  end

  defp provider_resource_error(name, resource_id, :resource_id_mismatch) do
    {:error,
     %{
       type: :resource_load_failed,
       message: "Provider returned a mismatched resource ID for skill '#{name}'",
       skill: name,
       resource_id: resource_id,
       reason: :resource_id_mismatch
     }}
  end

  defp provider_resource_error(name, resource_id, reason) do
    resource_error(
      name,
      :resource_id,
      resource_id,
      "Provider resource ID '#{resource_id}'",
      "provider resource ID '#{resource_id}'",
      reason
    )
  end

  defp resource_error(name, selector_key, selector, subject, _load_subject, :not_found) do
    error_with_selector(
      %{
        type: :resource_not_found,
        message: "#{subject} was not found for skill '#{name}'",
        skill: name
      },
      selector_key,
      selector
    )
  end

  defp resource_error(
         name,
         selector_key,
         selector,
         subject,
         _load_subject,
         {:resource_too_large, kind, size, limit}
       ) do
    error_with_selector(
      %{
        type: :resource_too_large,
        message: "#{subject} exceeds the #{kind} limit",
        skill: name,
        limit_kind: kind,
        size: size,
        limit: limit
      },
      selector_key,
      selector
    )
  end

  defp resource_error(name, selector_key, selector, subject, _load_subject, :binary_resource) do
    error_with_selector(
      %{
        type: :binary_resource,
        message: "#{subject} is not safe UTF-8 text",
        skill: name
      },
      selector_key,
      selector
    )
  end

  defp resource_error(name, selector_key, selector, _subject, load_subject, reason) do
    error_with_selector(
      %{
        type: :resource_load_failed,
        message: "Could not load #{load_subject} for skill '#{name}'",
        skill: name,
        reason: reason
      },
      selector_key,
      selector
    )
  end

  defp error_with_selector(error, selector_key, selector),
    do: {:error, Map.put(error, selector_key, selector)}
end
