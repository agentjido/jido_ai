defmodule Jido.AI.CoTAgent do
  @moduledoc """
  CoT request helpers over the shared v3 Agent and Flow implementation.

  Request Lifecycle Contract: `think/3` sends `ai.cot.query` and returns a
  request handle after admission commits. `await/2` reads the committed result.
  `think_sync/3` combines these operations. The shared session owns model work.

  Default request policy is `:reject`. A busy call returns `{:error, :busy}`.
  If `stream_to` is set, its caller also receives a `:request_failed` event
  with the rejected request ID. The active request is kept. Rejections use
  this request stream in place of the old `ai.request.error` Strategy hook.

  Successful results and provider errors are stored in `state.requests`.
  `last_result` is a printable view; the request record keeps the full value.
  Cancellation and worker failure close the request and release its resources.
  """
  defmacro __using__(opts) do
    opts = Keyword.put(opts, :reasoning, :chain_of_thought)

    quote do
      use Jido.AI.Agent, unquote(opts)

      def think(server, prompt, opts \\ []) when is_binary(prompt) or is_list(prompt),
        do: ask(server, prompt, opts)

      def think_sync(server, prompt, opts \\ []) when is_binary(prompt) or is_list(prompt),
        do: ask_sync(server, prompt, opts)

      @doc "Legacy model and prompt inspection. Execution uses the Agent's AI profile."
      def strategy_opts do
        opts =
          Keyword.take(@jido_ai_options, [:model, :system_prompt])
          |> Keyword.put_new(:model, :fast)

        case opts[:system_prompt] do
          nil -> Keyword.delete(opts, :system_prompt)
          _ -> opts
        end
      end

      defoverridable think: 3, think_sync: 3
    end
  end
end
