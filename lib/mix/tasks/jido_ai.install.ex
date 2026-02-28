defmodule Mix.Tasks.JidoAi.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Install and configure Jido AI for use in an application."
  end

  @spec example() :: String.t()
  def example do
    "mix igniter.install jido_ai"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    ## Example

    ```sh
    #{example()}
    ```

    ## What this task does

    1. Adds `:jido_ai` formatter configuration
    2. Configures default model aliases in `config/config.exs`
    3. Reminds you to set up LLM provider API keys
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.JidoAi.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :jido_ai,
        adds_deps: [],
        installs: [{:jido, "~> 2.0"}],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: [],
        schema: [],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:jido_ai)
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :jido_ai,
        [:model_aliases],
        %{
          fast: "anthropic:claude-haiku-4-5",
          capable: "anthropic:claude-sonnet-4-20250514"
        }
      )
      |> Igniter.add_notice("""
      Jido AI installed successfully!

      Next steps:
        1. Configure your LLM provider API keys:

           # config/runtime.exs
           config :req_llm,
             anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
             openai_api_key: System.get_env("OPENAI_API_KEY")

        2. Check out the getting started guide:
           https://hexdocs.pm/jido_ai/readme.html
      """)
    end
  end
else
  defmodule Mix.Tasks.JidoAi.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'jido_ai.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
