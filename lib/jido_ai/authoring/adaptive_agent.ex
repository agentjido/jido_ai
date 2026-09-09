defmodule Jido.AI.AdaptiveAgent do
  @moduledoc "Adaptive method selection over the shared v3 Agent and Flow implementation."

  @method_keys ~w(available_strategies complexity_thresholds strategy_override method_options)a

  defmacro __using__(opts) do
    options =
      opts
      |> Keyword.take(@method_keys)
      |> Jido.AI.Agent.expand_and_eval_literal_option(__CALLER__)

    case Jido.AI.Reasoning.options(:adaptive, options) do
      {:ok, _} -> :ok
      {:error, error} -> raise error
    end

    # The old selector stored this option but did not use it for selection.
    default =
      opts
      |> Keyword.get(:default_strategy, :react)
      |> Jido.AI.Agent.expand_and_eval_literal_option(__CALLER__)

    opts =
      opts
      |> Keyword.drop([:default_strategy | @method_keys])
      |> Keyword.put(:reasoning, :adaptive)
      |> Keyword.put(:reasoning_options, Macro.escape(options))
      |> Keyword.put_new(:description, "Adaptive agent #{Keyword.fetch!(opts, :name)}")

    quote do
      use Jido.AI.Agent, unquote(opts)

      def ask(server, prompt, opts) when is_binary(prompt), do: super(server, prompt, opts)
      def ask_sync(server, prompt, opts) when is_binary(prompt), do: super(server, prompt, opts)

      @doc "Reads declared settings. default_strategy is retained as an unused compatibility option."
      def strategy_opts do
        options = @jido_ai_options[:reasoning_options]

        [
          model: Keyword.get(@jido_ai_options, :model, :fast),
          default_strategy: unquote(Macro.escape(default)),
          available_strategies: Keyword.get(options, :available_strategies, [:cod, :cot, :react, :tot, :got, :trm])
        ] ++
          Keyword.take(options, [:complexity_thresholds, :strategy_override, :method_options]) ++
          Keyword.take(@jido_ai_options, [:tools])
      end

      defoverridable ask: 3, ask_sync: 3
    end
  end
end
