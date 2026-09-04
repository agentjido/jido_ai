defmodule Jido.AI.Actions.Skill.LoadResource do
  @moduledoc """
  Loads one text resource from an activated skill.

  The action uses the same runtime session as `load_skill`. It cannot access a
  skill that is not active in that session. It applies the resource policy that
  was stored during activation.
  """

  use Jido.Action,
    name: "load_skill_resource",
    description: """
    Loads one UTF-8 text file from an activated skill by relative resource path.
    Call load_skill before this action.
    """,
    category: "ai",
    tags: ["skills", "resources", "lazy-loading"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        name: Zoi.string(description: "The activated skill name"),
        path: Zoi.string(description: "A relative resource path from the skill listing")
      })

  alias Jido.AI.Actions.Skill.RuntimeContext
  alias Jido.AI.Skill.{Activation, ResourcePolicy, Resources}
  alias Jido.AI.Validation

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @max_path_length 1_024

  @impl Jido.Action
  def run(params, context) when is_map(params) do
    context = if is_map(context), do: context, else: %{}

    with {:ok, name} <- validate_name(param(params, :name)),
         {:ok, path} <- validate_path(param(params, :path)),
         {:ok, activation} <- activated_skill(name, context) do
      load_resource(name, path, activation)
    end
  end

  def run(_params, _context) do
    {:error, %{type: :invalid_params, message: "Parameters must be a map"}}
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

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

  defp load_resource(name, path, %{root_dir: root_dir} = activation) when is_binary(root_dir) do
    policy = Map.get(activation, :resource_policy, ResourcePolicy.default())

    case Resources.load_text(root_dir, path, policy) do
      {:ok, resource} ->
        {:ok,
         %{
           skill: name,
           path: resource.relative_path,
           content: resource.content,
           size: resource.size
         }}

      {:error, reason} ->
        resource_error(name, path, reason)
    end
  end

  defp load_resource(name, path, _activation), do: resource_error(name, path, :not_found)

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

  defp resource_error(name, path, :not_found) do
    {:error,
     %{
       type: :resource_not_found,
       message: "Resource '#{path}' was not found for skill '#{name}'",
       skill: name,
       path: path
     }}
  end

  defp resource_error(name, path, {:resource_too_large, kind, size, limit}) do
    {:error,
     %{
       type: :resource_too_large,
       message: "Resource '#{path}' exceeds the #{kind} limit",
       skill: name,
       path: path,
       limit_kind: kind,
       size: size,
       limit: limit
     }}
  end

  defp resource_error(name, path, :binary_resource) do
    {:error,
     %{
       type: :binary_resource,
       message: "Resource '#{path}' is not safe UTF-8 text",
       skill: name,
       path: path
     }}
  end

  defp resource_error(name, path, reason) do
    {:error,
     %{
       type: :resource_load_failed,
       message: "Could not load resource '#{path}' for skill '#{name}'",
       skill: name,
       path: path,
       reason: reason
     }}
  end
end
