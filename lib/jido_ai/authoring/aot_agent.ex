defmodule Jido.AI.AoTAgent do
  @moduledoc "AoT explore helpers over the shared v3 Agent and Flow implementation."

  defmacro __using__(opts) do
    keys = [:profile, :search_style, :examples, :require_explicit_answer]

    options =
      opts
      |> Keyword.take(keys)
      |> Keyword.update(:examples, [], fn value ->
        value = Jido.AI.Agent.Definition.expand_and_eval_literal_option(value, __CALLER__)
        Jido.AI.Reasoning.AlgorithmOfThoughts.Machine.new(examples: value).examples
      end)

    temperature =
      Jido.AI.Agent.Definition.expand_and_eval_literal_option(
        Keyword.get(opts, :temperature, 0.0),
        __CALLER__
      )

    temperature =
      Jido.AI.Reasoning.AlgorithmOfThoughts.Machine.new(temperature: temperature).temperature

    opts =
      opts
      |> Keyword.drop(keys)
      |> Keyword.put(:reasoning, :algorithm_of_thoughts)
      |> Keyword.put(:reasoning_options, options)
      |> Keyword.put(:temperature, temperature)
      |> Keyword.put_new(:max_tokens, 2048)

    quote do
      use Jido.AI.Agent, unquote(opts)

      def explore(server, prompt, opts \\ []) when is_binary(prompt) or is_list(prompt),
        do: ask(server, prompt, opts)

      def explore_sync(server, prompt, opts \\ []) when is_binary(prompt) or is_list(prompt),
        do: ask_sync(server, prompt, opts)

      @doc "Returns legacy method settings for inspection; the AI profile owns execution policy."
      def strategy_opts do
        {:ok, options} =
          Jido.AI.Reasoning.options(:algorithm_of_thoughts, @jido_ai_options[:reasoning_options])

        [
          model: Keyword.get(@jido_ai_options, :model, :fast),
          temperature: @jido_ai_options[:temperature],
          max_tokens: @jido_ai_options[:max_tokens]
        ] ++ Enum.to_list(options)
      end

      @doc "Extracts the final answer, including a declared typed answer."
      def answer(%{answer: answer}), do: answer
      def answer(_), do: nil

      defoverridable explore: 3, explore_sync: 3
    end
  end
end
