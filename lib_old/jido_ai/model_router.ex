defmodule Jido.AI.ModelRouter do
  @moduledoc false

  alias Jido.AI.Profile

  @doc false
  def select(%Profile{model_router: nil} = profile, _request, _context), do: {:ok, profile}

  def select(%Profile{model_router: router} = profile, request, context) do
    result = invoke(router.module, request, public_context(context))

    case result do
      {:ok, role} -> select_role(profile, role)
      {:error, _reason} when not is_nil(router.fallback) -> select_role(profile, router.fallback)
      {:error, _reason} = error -> error
      _ -> Profile.error("models.router", "Router must return a declared model role")
    end
  rescue
    error ->
      if profile.model_router.fallback,
        do: select_role(profile, profile.model_router.fallback),
        else: {:error, error}
  end

  defp invoke(module, request, context) do
    if function_exported?(module, :route, 2),
      do: module.route(request, context),
      else: module.select(request, context)
  end

  defp select_role(profile, role) do
    role = normalize_role(role, Map.keys(profile.models))

    if Map.has_key?(profile.models, role),
      do: {:ok, put_in(profile.reasoning.model, role)},
      else: Profile.error("models.router", "Router returned an unknown model role")
  end

  defp normalize_role(role, roles) when is_binary(role),
    do: Enum.find(roles, role, &(Atom.to_string(&1) == role))

  defp normalize_role(role, _roles), do: role

  defp public_context(context) do
    context
    |> Jido.AI.ToolContext.runtime()
    |> Map.take([:request_id, :tenant_id, :user_id, :locale, :timezone, :metadata])
  end
end
