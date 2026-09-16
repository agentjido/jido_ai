defmodule JidoAI.Examples.IncompleteResponse.DesignRequirementsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Request
  alias JidoAI.Examples.IncompleteResponse.Agent
  @moduletag :design_requirement

  for destination <- [:stream, :storage] do
    requirement = %{stream: "OBS-REQ-032", storage: "OBS-REQ-033"}[destination]
    @tag requirements: [requirement]
    test "#{requirement} default #{destination} excludes media bytes", %{jido: jido} do
      bytes = "SYNTHETIC_IMAGE_BYTES"
      encoded = Base.encode64(bytes)
      delta = %{images: [%{type: "image_url", image_url: %{url: "data:image/png;base64,#{encoded}"}}]}
      {mock, context} = native_mock([%{reply: {:stream, [delta], "stop"}}])
      server = start_agent(jido, Agent.new!())
      {:ok, %{request: request, events: events}} = Agent.ask_stream(server, "Draw", context: context)
      # Await reads committed state, not a second private result store.
      assert {:ok, [%ReqLLM.Message.ContentPart{type: :text, text: "[Content not retained]"}]} = Request.await(request)
      events = Enum.to_list(events)
      assert_script_done(mock)

      projection = if unquote(destination) == :stream, do: events, else: Server.agent(server).state
      serialized = :erlang.term_to_binary(projection)
      assert :binary.match(serialized, bytes) == :nomatch
      assert :binary.match(serialized, encoded) == :nomatch
    end
  end

  @tag requirements: ["MDL-REQ-015"]
  test "MDL-REQ-015 nonempty truncated output is not a completed result", %{jido: jido} do
    {mock, context} = native_mock([%{reply: {:stream, [%{content: "Truncated answer"}], "length"}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Answer", context: context)
    outcome = Request.await(request)
    assert_script_done(mock)
    assert {:error, _} = outcome
    assert Server.agent(server).state.reply == "untouched"
  end

  for destination <- [:stream, :storage, :diagnostics] do
    requirement = %{stream: "OBS-REQ-034", storage: "OBS-REQ-035", diagnostics: "OBS-REQ-036"}[destination]
    @tag requirements: [requirement, "OBS-REQ-023"]
    test "#{requirement} default #{destination} excludes synthetic reasoning content", %{jido: jido} do
      {mock, context} =
        native_mock([
          %{reply: {:stream, [%{reasoning_content: "PRIVATE_SYNTHETIC_MARKER"}, %{content: "Visible answer"}]}}
        ])

      server = start_agent(jido, Agent.new!())
      {:ok, %{request: request, events: events}} = Agent.ask_stream(server, "Answer", context: context)
      assert {:ok, "Visible answer"} = Request.await(request)
      events = Enum.to_list(events)
      assert_script_done(mock)

      projection =
        case unquote(destination) do
          :stream ->
            events

          :storage ->
            Server.agent(server).state

          :diagnostics ->
            {:ok, view} = Jido.AI.Orchestration.snapshot(server, request_id: request.id)
            view.details
        end

      refute inspect(projection, limit: :infinity, printable_limit: :infinity) =~ "PRIVATE_SYNTHETIC_MARKER"
    end
  end
end
