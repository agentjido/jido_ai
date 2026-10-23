defmodule Jido.AI.Agent do
  @moduledoc """
  Defines a Jido Agent with the AI Plugin included.

  Use the normal `Jido.Agent` options and declare the AI configuration in an `ai`
  block:

      defmodule MyApp.Assistant do
        use Jido.AI.Agent, name: "assistant"

        ai do
          model "openai:gpt-4o-mini"
          instructions "Reply in one short sentence."
        end
      end

  Other Agent extensions can still be supplied with the `:extensions` option.

  The `ai` block is a top-level Plugin section. Keep core Agent data in the
  optional `agent` block.
  """

  @doc false
  defmacro __using__(opts) do
    opts = Jido.Agent.options!(opts, __CALLER__)

    extensions =
      opts
      |> Keyword.get(:extensions, [])
      |> Enum.reject(&(&1 == Jido.AI.Plugin))

    opts = Keyword.put(opts, :extensions, [Jido.AI.Plugin | extensions])

    quote do
      use Jido.Agent, unquote(Macro.escape(opts))

      @doc "Generates one response with this Agent's AI configuration."
      @spec generate(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
      def generate(input, opts \\ []), do: Jido.AI.generate(__MODULE__, input, opts)

      @doc "Runs one reasoning Flow and returns output, usage, and a sanitized trace."
      @spec reason(String.t(), keyword()) ::
              {:ok, Jido.AI.reasoning_result()}
              | {:ok, Jido.AI.reasoning_result(), Jido.Action.effects()}
              | {:error, term()}
      def reason(input, opts \\ []), do: Jido.AI.reason(__MODULE__, input, opts)

      @doc "Starts one streaming response with this Agent's AI configuration."
      @spec stream(String.t(), keyword()) ::
              {:ok, ReqLLM.StreamResponse.t()} | {:error, term()}
      def stream(input, opts \\ []), do: Jido.AI.stream(__MODULE__, input, opts)
    end
  end
end
