defmodule Jido.AI.Plugins.Retrieval.AgentServer do
  @moduledoc false
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Retrieval.admit_input(admission)
end
