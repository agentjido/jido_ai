defmodule Jido.AI.ReqLLMLiveTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Test.LiveTrace

  @moduletag :live
  @moduletag timeout: 60_000

  defmodule Assistant do
    use Jido.Agent, name: "live_assistant", extensions: [Jido.AI.Plugin]

    ai do
      model "openai:gpt-4o-mini"
      instructions "Reply with one short sentence."
    end
  end

  test "the configured model returns text through ReqLLM" do
    config = Jido.AI.Plugin.response(Assistant)

    options = [
      max_tokens: 16,
      temperature: 0.0,
      receive_timeout: 30_000
    ]

    request = %{
      scenario: "basic_response",
      model: config.model,
      instructions: config.instructions,
      input: "Reply with the word pong.",
      options: options
    }

    context =
      ReqLLM.Context.new([
        ReqLLM.Context.system(request.instructions),
        ReqLLM.Context.user(request.input)
      ])

    {result, trace_path} =
      LiveTrace.capture(request, fn ->
        ReqLLM.generate_text(config.model, context, options)
      end)

    IO.puts("Live trace: #{trace_path}")

    assert {:ok, response} = result

    assert response |> ReqLLM.Response.text() |> String.trim() != ""

    assert File.exists?(trace_path)

    trace = trace_path |> File.read!() |> Jason.decode!()

    assert trace["scenario"] == "basic_response"
    assert trace["status"] == "ok"

    assert Enum.map(trace["events"], & &1["type"]) == [
             "ai.request.started",
             "ai.response.completed"
           ]
  end
end
