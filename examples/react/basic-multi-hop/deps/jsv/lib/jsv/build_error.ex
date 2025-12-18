defmodule JSV.BuildError do
  @moduledoc """
  A simple wrapper for errors returned from `JSV.build/2`.
  """

  @inspect_limit 20
  @enforce_keys [:reason, :action, :build_path]
  defexception @enforce_keys

  @doc """
  Wraps the given term as the `reason` in a `#{inspect(__MODULE__)}` struct.

  The `action` should be a `{module, function, [arg1, arg2, ..., argN]}` tuple or
  a mfa tuple whenever possible.
  """

  @spec of(term, term, build_path :: nil | String.t()) :: Exception.t()
  def of(reason, action, build_path \\ nil) do
    %__MODULE__{reason: reason, action: action, build_path: build_path}
  end

  @impl true
  def message(%{action: {m, f, a}} = e) when is_atom(m) and is_atom(f) and (is_list(a) or is_integer(a)) do
    """
    could not build JSON schema at #{e.build_path}

    REASON
    #{inspect(e.reason, pretty: true, limit: @inspect_limit)}

    CONTEXT
    #{Exception.format_mfa(m, f, a)}
    """
  end

  def message(e) do
    "could not build JSON schema at #{e.build_path}, got error: #{inspect(e.reason, limit: @inspect_limit)} for #{inspect(e.action, limit: @inspect_limit)}"
  end
end
