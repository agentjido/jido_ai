defmodule Jido.AI.Agent do
  @moduledoc false

  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.Agent, unquote(opts)
      alias Jido.AI.AgentRestore

      @impl true
      def restore(data, ctx) do
        AgentRestore.restore(__MODULE__, data, ctx)
      end
    end
  end
end
