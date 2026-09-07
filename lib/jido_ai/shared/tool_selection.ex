defmodule Jido.AI.Reasoning.ReAct.ToolSelection do
  @moduledoc """
  Helpers for resolving request-scoped tool registries in ReAct.

  This keeps tool selection deterministic across:

  - base strategy/runtime config
  - request-scoped `tools` overrides
  - request-scoped `allowed_tools` allowlists
  """

  alias Jido.AI.ToolAdapter

  @type tools_input :: nil | map() | [module()] | module()
  @type tools_map :: %{String.t() => module()}

  @doc """
  Resolve an effective tool registry from a base registry plus optional overrides.

  `override_tools` replaces the base registry for the current request/run when present.
  `allowed_tools` filters the selected registry by tool name.
  """
  @spec resolve(tools_map(), tools_input(), [String.t()] | nil) ::
          {:ok, tools_map()} | {:error, term()}
  def resolve(base_tools, override_tools \\ nil, allowed_tools \\ nil) when is_map(base_tools) do
    with {:ok, selected_tools} <- select_base_or_override(base_tools, override_tools) do
      filter_allowed(selected_tools, allowed_tools)
    end
  end

  @doc """
  Normalize arbitrary tool input into a validated action map.
  """
  @spec normalize_input(tools_input()) :: {:ok, tools_map()} | {:error, term()}
  def normalize_input(nil), do: {:ok, %{}}

  def normalize_input(%{} = tools) do
    modules = Map.values(tools)

    with :ok <- validate_modules(modules) do
      {:ok, ToolAdapter.to_action_map(tools)}
    end
  end

  def normalize_input(modules) when is_list(modules) do
    with :ok <- validate_modules(modules) do
      {:ok, ToolAdapter.to_action_map(modules)}
    end
  end

  def normalize_input(module) when is_atom(module) do
    with :ok <- validate_modules([module]) do
      {:ok, ToolAdapter.to_action_map(module)}
    end
  end

  def normalize_input(_), do: {:error, :invalid_tools}

  @doc """
  Filter a tool registry by allowed tool names.
  """
  @spec filter_allowed(tools_map(), [String.t()] | nil) :: {:ok, tools_map()} | {:error, term()}
  def filter_allowed(tools, nil) when is_map(tools), do: {:ok, tools}

  def filter_allowed(tools, allowed_tools) when is_map(tools) and is_list(allowed_tools) do
    case normalize_allowed_tools(allowed_tools) do
      {:ok, normalized_allowed} ->
        allowed_set = MapSet.new(normalized_allowed)
        available = Map.keys(tools) |> MapSet.new()
        unknown = MapSet.difference(allowed_set, available) |> MapSet.to_list() |> Enum.sort()

        if unknown == [] do
          {:ok, Map.take(tools, normalized_allowed)}
        else
          {:error, {:unknown_allowed_tools, unknown}}
        end

      {:error, _} = error ->
        error
    end
  end

  def filter_allowed(_tools, _allowed_tools), do: {:error, :invalid_allowed_tools}

  defp select_base_or_override(base_tools, nil), do: {:ok, base_tools}
  defp select_base_or_override(_base_tools, override_tools), do: normalize_input(override_tools)

  defp validate_modules(modules) when is_list(modules) do
    if Enum.any?(modules, &(not is_atom(&1))) do
      {:error, :invalid_tools}
    else
      ToolAdapter.validate_actions(modules)
    end
  end

  defp normalize_allowed_tools(allowed_tools) do
    if Enum.all?(allowed_tools, &is_binary/1) do
      {:ok, allowed_tools}
    else
      {:error, :invalid_allowed_tools}
    end
  end
end
