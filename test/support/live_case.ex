defmodule Jido.AI.Test.LiveCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  alias Jido.AI.Test.LiveTrace

  @default_options [max_tokens: 32, temperature: 0.0, receive_timeout: 30_000]

  using do
    quote do
      @moduletag :live
      @moduletag timeout: 60_000

      import Jido.AI.Test.LiveCase,
        only: [capture_live: 4, capture_live: 5, live_options: 0, live_options: 1]
    end
  end

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    aliases = Map.put(original || %{}, :fast, "openai:gpt-4o-mini")
    Application.put_env(:jido_ai, :model_aliases, aliases)

    on_exit(fn -> restore_aliases(original) end)
  end

  @doc false
  def live_options, do: @default_options

  @doc false
  def live_options(overrides), do: Keyword.merge(@default_options, overrides)

  @doc false
  def capture_live(agent, input, scenario, fun),
    do: capture_live(agent, input, scenario, @default_options, fun)

  @doc false
  def capture_live(agent, input, scenario, options, fun) do
    config = Jido.AI.Plugin.config(agent)
    {:ok, model} = Jido.AI.Models.resolve(config.model)

    request = %{
      scenario: scenario,
      model: model,
      instructions: config.instructions,
      input: input,
      options: options
    }

    {result, trace_path} = LiveTrace.capture(request, fun)
    IO.puts("Live trace: #{trace_path}")

    assert File.exists?(trace_path)

    trace = trace_path |> File.read!() |> Jason.decode!()

    assert trace["scenario"] == scenario
    assert trace["status"] == "ok"

    assert Enum.map(trace["events"], & &1["type"]) == [
             "ai.request.started",
             "ai.response.completed"
           ]

    {result, trace_path}
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
