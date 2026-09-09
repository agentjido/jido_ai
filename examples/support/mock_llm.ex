defmodule JidoAI.Examples.MockLLM do
  @moduledoc "Example entry point for the shared package test server."
  def child_spec(opts), do: %{Jido.AI.Test.MockLLM.child_spec(opts) | id: __MODULE__}
  defdelegate start_link(opts), to: Jido.AI.Test.MockLLM
  defdelegate model(), to: Jido.AI.Test.MockLLM
  defdelegate model(id), to: Jido.AI.Test.MockLLM
  defdelegate options(server), to: Jido.AI.Test.MockLLM
  defdelegate options(server, operation), to: Jido.AI.Test.MockLLM
  defdelegate report(server), to: Jido.AI.Test.MockLLM
  defdelegate release(server, tag), to: Jido.AI.Test.MockLLM
end
