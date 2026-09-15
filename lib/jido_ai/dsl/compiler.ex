defmodule Jido.AI.DSL.Compiler do
  @moduledoc false

  defmacro __before_compile__(_env) do
    quote location: :keep do
      @doc "Returns all canonical AI profiles by ID."
      def ai_profiles, do: Jido.AI.Agent.profiles(__MODULE__)

      @doc "Returns one canonical AI profile."
      def ai_profile(id), do: Jido.AI.Agent.profile(__MODULE__, id)
    end
  end
end
