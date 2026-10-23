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
  optional `state` block.

  Jido AI uses the core Agent instance-state boundary. Use the core
  `c:Jido.Agent.initialize/2` callback to create a new `Jido.Session` or
  `Jido.Thread` for each Agent instance. Core Jido merges static
  `initial_state` with explicit caller `state:` before it calls the initializer.
  The initializer returns the complete candidate state for schema validation.
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

      @doc "Prepares one request without running controls, tools, or a model."
      @spec preflight(String.t(), keyword()) ::
              {:ok, Jido.AI.Request.t()} | {:error, term()}
      def preflight(input, opts \\ []), do: Jido.AI.preflight(__MODULE__, input, opts)

      @doc "Runs one request and returns an explicit completed or failed result."
      @spec run(String.t(), keyword()) ::
              {:ok, Jido.AI.Result.t()}
              | {:ok, Jido.AI.Result.t(), Jido.Action.effects()}
              | {:error, Jido.AI.Result.t() | term()}
      def run(input, opts \\ []), do: Jido.AI.run(__MODULE__, input, opts)

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
