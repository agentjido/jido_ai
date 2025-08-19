defmodule Kodo.Core.Parsing.CommandMacro do
  @moduledoc """
  Macro for defining commands with reduced boilerplate.
  """

  defmacro defcommand(name, opts, do: block) do
    description = Keyword.get(opts, :description, "")
    usage = Keyword.get(opts, :usage, name)
    meta = Keyword.get(opts, :meta, [:builtin])

    quote do
      @behaviour Kodo.Ports.Command

      @impl true
      def name, do: unquote(name)

      @impl true
      def description, do: unquote(description)

      @impl true
      def usage, do: unquote(usage)

      @impl true
      def meta, do: unquote(meta)

      @impl true
      unquote(block)
    end
  end

  defmacro __using__(_opts) do
    quote do
      import Kodo.Core.Parsing.CommandMacro
    end
  end
end
