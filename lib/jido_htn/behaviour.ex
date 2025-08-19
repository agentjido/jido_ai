defmodule Jido.Planner do
  @moduledoc false
  @callback plan(domain :: map(), world_state :: map()) ::
              {:ok, list(Jido.Operations.Envelope.t())} | {:error, term()}
end

defmodule Jido.HTN.DomainBehaviour do
  @moduledoc false
  @callback init(opts :: keyword()) :: {:ok, Jido.HTN.Domain.t()} | {:error, term()}
  @callback predicates() :: module()
  @callback transformers() :: module()
end
