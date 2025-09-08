defmodule ReqLLM.Capability.Adapter do
  @moduledoc """
  Behaviour that every concrete capability module must implement.

  It was previously defined in `ReqLLM.Capability` but has been moved
  here to keep the public façade (ReqLLM.Capability) free of callbacks.
  """

  @callback id() :: atom()

  @callback advertised?(ReqLLM.Model.t()) :: boolean()

  @callback verify(ReqLLM.Model.t(), keyword()) ::
              {:ok, term()} | {:error, term()}
end
