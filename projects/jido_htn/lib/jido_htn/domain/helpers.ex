defmodule Jido.HTN.Domain.Helpers do
  @moduledoc false
  import DeepMerge, only: [deep_merge: 2]

  @spec merge(map()) :: (map() -> map())
  def merge(changes), do: &deep_merge(&1, changes)

  @spec noop() :: (map() -> map())
  def noop, do: & &1

  @spec op(Jido.HTN.Domain.t(), String.t(), keyword()) ::
          {:ok, (map() -> {:ok, map()} | {:error, String.t()})} | {:error, String.t()}
  def op(domain, workflow_name, opts \\ []) do
    case Map.get(domain.allowed_workflows, workflow_name) do
      nil ->
        {:error, "Workflow #{workflow_name} not allowed in this domain"}

      module ->
        {:ok,
         fn world_state ->
           case module.run(world_state, world_state, opts) do
             {:ok, new_state} -> {:ok, new_state}
             {:error, reason} -> {:error, reason}
             other -> {:error, "Unexpected return from workflow: #{inspect(other)}"}
           end
         end}
    end
  end

  @spec camel_case(String.t()) :: String.t()
  def camel_case(str) do
    ProperCase.camel_case(str, :upper)
  end

  @spec function_to_string(function()) :: String.t()
  def function_to_string({module, opts}) when is_atom(module) and is_list(opts) do
    "{#{Atom.to_string(module)}, #{inspect(opts)}}"
  end

  def function_to_string(func) when is_function(func) do
    info = :erlang.fun_info(func)
    module = info[:module]
    name = info[:name]
    arity = info[:arity]

    cond do
      module == :erl_eval ->
        # Anonymous function
        "&" <> Macro.to_string(quote(do: unquote(func)))

      name == :- ->
        # Local named function
        "&" <>
          Atom.to_string(module) <>
          "." <> Atom.to_string(info[:env][:function]) <> "/" <> to_string(arity)

      true ->
        # Remote named function
        "&" <> Atom.to_string(module) <> "." <> Atom.to_string(name) <> "/" <> to_string(arity)
    end
  end

  def function_to_string(other), do: inspect(other)
end
