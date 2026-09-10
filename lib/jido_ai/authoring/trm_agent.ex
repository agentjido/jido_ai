defmodule Jido.AI.TRMAgent do
  @moduledoc "Recursive reasoning helpers over the shared v3 Agent and Flow implementation."

  @method_keys ~w(max_supervision_steps act_threshold)a

  defmacro __using__(opts) do
    options =
      opts
      |> Keyword.take(@method_keys)
      |> Jido.AI.Agent.Definition.expand_and_eval_literal_option(__CALLER__)

    normalized =
      case Jido.AI.Reasoning.options(:trm, options) do
        {:ok, value} -> value
        {:error, error} -> raise error
      end

    opts =
      opts
      |> Keyword.drop(@method_keys)
      |> Keyword.put(:reasoning, :trm)
      |> Keyword.put(:reasoning_options, options)
      |> Keyword.put_new(:description, "TRM agent #{Keyword.fetch!(opts, :name)}")
      |> Keyword.put_new(:max_iterations, Jido.AI.Reasoning.model_call_limit(:trm, normalized))
      |> Keyword.put_new(:max_tokens, 1024)
      |> Keyword.put_new(:temperature, 0.2)

    quote do
      use Jido.AI.Agent, unquote(opts)

      def reason(server, prompt, opts \\ []) when is_binary(prompt),
        do: ask(server, prompt, opts)

      def reason_sync(server, prompt, opts \\ []) when is_binary(prompt),
        do: ask_sync(server, prompt, opts)

      @doc "Reads declared method settings. The AI profile owns execution policy."
      def strategy_opts do
        {:ok, options} =
          Jido.AI.Reasoning.options(:trm, @jido_ai_options[:reasoning_options])

        [model: Keyword.get(@jido_ai_options, :model, :fast)] ++
          Enum.to_list(options)
      end

      defoverridable reason: 3, reason_sync: 3
    end
  end
end
