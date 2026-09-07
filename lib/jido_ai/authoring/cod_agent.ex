defmodule Jido.AI.CoDAgent do
  @moduledoc """
  CoD request helpers over the shared v3 Agent and Flow implementation.

  `draft/3` sends `ai.cod.query` and returns a handle after admission commits.
  `await/2` reads the committed result. `draft_sync/3` combines both operations.
  The shared session owns model work, cancellation, and worker cleanup.

  A busy call returns `{:error, :busy}`. With `stream_to`, the caller also gets
  a `:request_failed` event with the rejected request ID. Active work is kept.
  `state.requests` stores the full result or error; `last_result` is printable.
  CoD uses its default prompt and parses the final answer after `####`.
  """
  defmacro __using__(opts) do
    opts = Keyword.put(opts, :reasoning, :chain_of_draft)

    quote do
      use Jido.AI.Agent, unquote(opts)

      def draft(server, prompt, opts \\ []) when is_binary(prompt) or is_list(prompt),
        do: ask(server, prompt, opts)

      def draft_sync(server, prompt, opts \\ []) when is_binary(prompt) or is_list(prompt),
        do: ask_sync(server, prompt, opts)

      @doc "Legacy model and prompt inspection. Execution uses the Agent's AI profile."
      def strategy_opts do
        opts =
          Keyword.take(@jido_ai_options, [:model, :system_prompt])
          |> Keyword.put_new(:model, :fast)

        case opts[:system_prompt] do
          nil ->
            Keyword.put(
              opts,
              :system_prompt,
              Jido.AI.Reasoning.Linear.default_prompt(:chain_of_draft)
            )

          _ ->
            opts
        end
      end

      defoverridable draft: 3, draft_sync: 3
    end
  end
end
