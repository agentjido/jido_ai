defmodule Jido.AI.Plugins.Quota.AgentServer do
  @moduledoc false
  def admit(_runtime, admission, _opts), do: Jido.AI.Plugins.Quota.admit_input(admission)
end
