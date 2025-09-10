defmodule ReqLLM.Codec.Helpers do
  @moduledoc false
  # Internal helper for wrapping contexts with provider-specific tagged structs.
  # Not part of the public API.

  alias ReqLLM.{Context, Model}

  @doc false
  @spec wrap(Context.t(), Model.t()) :: term()
  def wrap(%Context{} = ctx, %Model{provider: provider_atom}) do
    {:ok, provider_mod} = ReqLLM.provider(provider_atom)
    provider_mod.wrap_context(ctx)
  end
end
