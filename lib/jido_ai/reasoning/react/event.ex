defmodule Jido.AI.Reasoning.ReAct.Event do
  @moduledoc """
  Deprecated compatibility wrapper for `Jido.AI.Runtime.Event`.

  ReAct streams now emit `Jido.AI.Runtime.Event` directly. Use the canonical
  runtime event module for new code.
  """

  alias Jido.AI.Runtime.Event, as: RuntimeEvent

  @type t :: RuntimeEvent.t()

  @deprecated "Use Jido.AI.Runtime.Event.schema/0 instead"
  @doc false
  defdelegate schema(), to: RuntimeEvent

  @deprecated "Use Jido.AI.Runtime.Event.kinds/0 instead"
  @spec kinds() :: [atom()]
  defdelegate kinds(), to: RuntimeEvent

  @deprecated "Use Jido.AI.Runtime.Event.new/1 instead"
  @spec new(map()) :: RuntimeEvent.t()
  defdelegate new(attrs), to: RuntimeEvent
end
