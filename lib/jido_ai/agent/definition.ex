defmodule Jido.AI.Agent.Definition do
  @moduledoc false

  defmacro __using__(opts) do
    {max_state_size, opts} = Keyword.pop(opts, :max_state_size)
    extensions_ast = Keyword.get(opts, :extensions, [])

    extensions =
      case extensions_ast do
        {:@, _, _} ->
          raise CompileError,
            file: __CALLER__.file,
            line: __CALLER__.line,
            description: "extensions must be an inline compile-time list of modules"

        value ->
          value |> Code.eval_quoted([], __CALLER__) |> elem(0)
      end

    unless is_list(extensions) and Enum.all?(extensions, &is_atom/1) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "extensions must be a compile-time list of modules"
    end

    opts = Keyword.put(opts, :extensions, Enum.uniq([Jido.AI.DSL | extensions]))

    quote location: :keep do
      @jido_ai_max_state_size unquote(max_state_size)
      use Jido.Agent, unquote(opts)

      import Jido.AI.Agent, only: [tools_from_skills: 1]

      @doc "Runs one request with the selected AI profile."
      def ask(server, query, opts \\ []),
        do: Jido.AI.Agent.Interface.ask(__MODULE__, server, query, opts)

      @doc "Runs one request and waits for a completed result when needed."
      def ask_sync(server, query, opts \\ []),
        do: Jido.AI.Agent.Interface.ask_sync(__MODULE__, server, query, opts)

      @doc "Starts one AI request with provider streaming and runtime events."
      def ask_stream(server, query, opts \\ []),
        do: Jido.AI.Agent.Interface.ask_stream(__MODULE__, server, query, opts)

      @doc "Waits for one admitted session request."
      def await(request, opts \\ []), do: Jido.AI.Request.await(request, opts)

      @doc "Cancels one active session request."
      def cancel(server, opts \\ []), do: Jido.AI.Agent.Interface.cancel(server, opts)

      @doc "Queues visible input for an active session request."
      def steer(server, content, opts \\ []), do: Jido.AI.steer(server, content, opts)

      defoverridable ask: 3,
                     ask_sync: 3,
                     ask_stream: 3,
                     await: 2,
                     cancel: 2,
                     steer: 3
    end
  end
end
