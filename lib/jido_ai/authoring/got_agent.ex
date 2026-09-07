defmodule Jido.AI.GoTAgent do
  @moduledoc "Graph search helpers over the shared v3 Agent and Flow implementation."

  @method_keys ~w(max_nodes max_depth aggregation_strategy min_nodes_for_aggregation generation_prompt connection_prompt aggregation_prompt)a

  defmacro __using__(opts) do
    options =
      opts
      |> Keyword.take(@method_keys)
      |> Jido.AI.Agent.expand_and_eval_literal_option(__CALLER__)

    normalized =
      case Jido.AI.Reasoning.options(:graph_of_thoughts, options) do
        {:ok, value} -> value
        {:error, error} -> raise error
      end

    opts =
      opts
      |> Keyword.drop(@method_keys)
      |> Keyword.put(:reasoning, :graph_of_thoughts)
      |> Keyword.put(:reasoning_options, options)
      |> Keyword.put_new(:description, "GoT agent #{Keyword.fetch!(opts, :name)}")
      |> Keyword.put_new(
        :max_iterations,
        Jido.AI.Reasoning.model_call_limit(:graph_of_thoughts, normalized)
      )
      |> Keyword.put_new(:max_tokens, 1024)
      |> Keyword.put_new(:temperature, 0.2)

    quote do
      use Jido.AI.Agent, unquote(opts)

      def explore(server, prompt, opts \\ []) when is_binary(prompt),
        do: ask(server, prompt, opts)

      def explore_sync(server, prompt, opts \\ []) when is_binary(prompt),
        do: ask_sync(server, prompt, opts)

      @doc "Reads declared method settings. The AI profile owns execution policy."
      def strategy_opts do
        {:ok, options} =
          Jido.AI.Reasoning.options(:graph_of_thoughts, @jido_ai_options[:reasoning_options])

        [model: Keyword.get(@jido_ai_options, :model, :fast)] ++
          (options |> Enum.reject(fn {_, value} -> is_nil(value) end))
      end

      defoverridable explore: 3, explore_sync: 3
    end
  end
end
