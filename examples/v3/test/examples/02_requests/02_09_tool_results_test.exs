defmodule JidoAI.Examples.ToolResultsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.ToolResults.{Agent, NativeAgent}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  defp events(request),
    do: request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()

  defp saved(server, request), do: Server.agent(server).state.requests[request.id]

  defp native_ask(server, context),
    do:
      Request.create_and_send(server, "Run",
        signal_type: "ai.ask",
        source: "/examples/tools",
        context: context,
        stream_to: self()
      )

  defp tool_messages(mock) do
    MockLLM.report(mock).requests
    |> List.last()
    |> Map.fetch!(:body)
    |> Map.fetch!("messages")
    |> Enum.filter(&(&1["role"] == "tool"))
  end

  @tag :tmp_dir
  @tag history_case: "HIST-14/tool-failure"
  test "a real directory failure reaches the model as a canonical error without crashing the Agent",
       %{jido: jido, tmp_dir: dir} do
    missing = Path.join(dir, "missing")
    call = %{id: "read", name: "inspect_directory", arguments: %{path: missing}}

    {mock, context} =
      mock([%{reply: {:tools, [call]}}, %{reply: {:text, "The directory does not exist"}}])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Read", context: context, stream_to: self())
    assert {:ok, "The directory does not exist"} = Agent.await(request)
    assert_receive {:directory_read, ^missing, _}
    refute_receive {:directory_read, _, _}, 20
    assert [message] = tool_messages(mock)
    assert message["tool_call_id"] == "read"
    payload = Jason.decode!(message["content"])
    assert payload["ok"] == false
    assert payload["error"]["type"] == "execution_error"
    assert payload["error"]["details"]["reason"] == "enoent"
    assert payload["error"]["details"]["tool_name"] == "inspect_directory"
    assert payload["error"]["details"]["tool_call_id"] == "read"
    assert payload["error"]["retryable?"] == false

    assert [%{id: "read", status: :error, attempts: 1, result: {:error, error, []}}] =
             saved(server, request).meta.tool_results

    assert error.details.reason == :enoent
    complete = Enum.find(events(request), &(&1.kind == :tool_completed))
    assert complete.data.result == {:error, error, []}
    assert_script_done(mock)
  end

  for {kind, expected} <- [
        {"text", "Tool text"},
        {"number", 7},
        {"map", %{"value" => 7}},
        {"triple", %{"value" => 8}}
      ] do
    @tag history_case: "HIST-14/canonical-tool-result"
    test "#{kind} tool results use the success envelope and retain the actual value", %{
      jido: jido
    } do
      call = %{id: "value", name: "fixture_value", arguments: %{kind: unquote(kind)}}
      {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Done"}}])
      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = Agent.ask(server, "Read", context: context)
      assert {:ok, "Done"} = Agent.await(request)
      assert [message] = tool_messages(mock)

      assert Jason.decode!(message["content"]) == %{
               "ok" => true,
               "result" => unquote(Macro.escape(expected))
             }

      assert [%{result: {:ok, value, []}, status: :ok, id: "value"}] =
               saved(server, request).meta.tool_results

      assert Jason.decode!(Jason.encode!(value)) == unquote(Macro.escape(expected))
      assert_script_done(mock)
    end
  end

  for kind <- ["invalid", "raise"] do
    test "a tool #{kind} result becomes an error that the model can handle", %{jido: jido} do
      call = %{id: "bad", name: "fixture_value", arguments: %{kind: unquote(kind)}}
      {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Tool failed"}}])
      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = Agent.ask(server, "Run", context: context)
      assert {:ok, "Tool failed"} = Agent.await(request)
      assert [message] = tool_messages(mock)

      assert %{
               "ok" => false,
               "error" => %{"message" => text, "details" => details, "retryable?" => false}
             } = Jason.decode!(message["content"])

      assert text != ""
      assert details["tool_call_id"] == "bad"
      assert [%{status: :error, attempts: 1}] = saved(server, request).meta.tool_results
      assert_script_done(mock)
    end
  end

  test "nonportable tool values have bounded model and stored inspection forms", %{jido: jido} do
    call = %{id: "unsafe", name: "fixture_value", arguments: %{kind: "unsafe"}}
    {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Done"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Run", context: context)
    assert {:ok, "Done"} = Agent.await(request)
    assert [message] = tool_messages(mock)

    assert %{
             "ok" => true,
             "result" => %{
               "owner" => %{"type" => "pid"},
               "nested" => %{"secret_key" => "[REDACTED]"}
             }
           } = Jason.decode!(message["content"])

    assert [%{result_storage: :transport, result: {:ok, value, []}}] =
             saved(server, request).meta.tool_results

    assert value.owner.type == :pid
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "content-part tool results retain the canonical JSON and separate content", %{jido: jido} do
    call = %{id: "parts", name: "fixture_value", arguments: %{kind: "parts"}}
    {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Done"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Read", context: context)
    assert {:ok, "Done"} = Agent.await(request)
    assert [message] = tool_messages(mock)

    assert [%{"type" => "text", "text" => json}, %{"type" => "text", "text" => "Tool part"}] =
             message["content"]

    assert %{
             "ok" => true,
             "result" => %{
               "output" => %{"read" => true},
               "content" => [%{"type" => "text", "text" => "Tool part"}]
             }
           } = Jason.decode!(json)

    assert [%{result: {:ok, %ReqLLM.ToolResult{}, []}}] = saved(server, request).meta.tool_results
    assert_script_done(mock)
  end

  for kind <- ["file_result", "file_map", "file_list"] do
    @tag history_case: "HIST-03/binary-tool-results"
    test "#{kind} keeps invalid UTF-8 file bytes outside the JSON envelope", %{jido: jido} do
      call = %{id: "file", name: "fixture_value", arguments: %{kind: unquote(kind)}}
      {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Read file"}}])
      server = start_agent(jido, Agent.new!())
      assert {:ok, request} = Agent.ask(server, "Read", context: context)
      assert {:ok, "Read file"} = Agent.await(request)
      assert [message] = tool_messages(mock)
      # ReqLLM owns the provider encoding. Its chat encoder uses a data URI.
      assert [
               %{"type" => "text", "text" => json},
               %{"type" => "image_url", "image_url" => %{"url" => uri}}
             ] = message["content"]

      assert %{"ok" => true, "result" => result} = Jason.decode!(json)
      assert result == if(unquote(kind) == "file_list", do: nil, else: %{"read" => true})
      assert "data:image/png;base64," <> encoded = uri
      assert Base.decode64!(encoded) == <<0xE2, 0x28, 0xA1>>
      assert [%{result: {:ok, stored, []}}] = saved(server, request).meta.tool_results

      assert [
               %ReqLLM.Message.ContentPart{},
               %ReqLLM.Message.ContentPart{
                 type: :file,
                 data: bytes,
                 filename: "fixture.png",
                 media_type: "image/png"
               }
             ] = Jido.AI.ToolResult.content({:ok, stored, []})

      assert bytes == <<0xE2, 0x28, 0xA1>>
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end
  end

  @tag history_case: "HIST-03/binary-tool-results"
  test "unsupported uploaded file references retain their media type and metadata on provider rejection",
       %{jido: jido} do
    call = %{id: "file", name: "fixture_value", arguments: %{kind: "file_reference"}}
    {mock, context} = mock([%{reply: {:tools, [call]}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Read", context: context)
    assert {:error, %ReqLLM.Error.Invalid.Parameter{parameter: message}} = Agent.await(request)
    assert message =~ "text/plain"
    assert [%{result: {:ok, stored, []}}] = saved(server, request).meta.tool_results

    assert [
             %ReqLLM.Message.ContentPart{text: json},
             %ReqLLM.Message.ContentPart{
               type: :file,
               file_id: "file_notes",
               filename: "notes.txt",
               media_type: "text/plain",
               metadata: %{"label" => "fixture"}
             }
           ] = Jido.AI.ToolResult.content({:ok, stored, []})

    assert %{"ok" => true, "result" => nil} = Jason.decode!(json)
    assert length(MockLLM.report(mock).requests) == 1
    assert_script_done(mock)
  end

  @tag history_case: "HIST-03/binary-tool-results"
  test "unsupported PDF content retains the raw bytes after provider rejection", %{jido: jido} do
    call = %{id: "pdf", name: "fixture_value", arguments: %{kind: "pdf"}}
    {mock, context} = mock([%{reply: {:tools, [call]}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Read", context: context)
    assert {:error, %ReqLLM.Error.Invalid.Parameter{parameter: message}} = Agent.await(request)
    assert message =~ "application/pdf"
    assert [%{result: {:ok, stored, []}}] = saved(server, request).meta.tool_results

    assert [
             %ReqLLM.Message.ContentPart{text: json},
             %ReqLLM.Message.ContentPart{
               type: :file,
               data: bytes,
               filename: "fixture.pdf",
               media_type: "application/pdf"
             }
           ] = Jido.AI.ToolResult.content({:ok, stored, []})

    assert bytes == <<0xE2, 0x28, 0xA1>>
    assert %{"ok" => true, "result" => %{"read" => true}} = Jason.decode!(json)
    assert length(MockLLM.report(mock).requests) == 1
    assert_script_done(mock)
  end

  test "a nested Flow failure keeps its supported error type in the model envelope", %{jido: jido} do
    call = %{id: "flow", name: "broken_flow", arguments: %{n: 9}}
    {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Flow failed"}}])
    server = start_agent(jido, NativeAgent.new!())
    assert {:ok, request} = native_ask(server, context)
    assert {:ok, "Flow failed"} = Request.await(request)
    assert [message] = tool_messages(mock)

    assert %{
             "ok" => false,
             "error" => %{
               "type" => "flow_execution_error",
               "details" => details,
               "retryable?" => false
             }
           } = Jason.decode!(message["content"])

    assert details["value"] == 9
    assert details["reason"] == "unavailable"

    assert [%{status: :error, result: {:error, error, []}}] =
             saved(server, request).meta.tool_results

    assert error.type == :flow_execution_error
    assert_script_done(mock)
  end

  test "reversed parallel completion retains call order in model messages and stored results", %{
    jido: jido
  } do
    calls = for n <- 1..2, do: %{id: "call-#{n}", name: "wait", arguments: %{n: n}}
    {mock, context} = mock([%{reply: {:tools, calls}}, %{reply: {:text, "Done"}}])
    server = start_agent(jido, NativeAgent.new!())
    assert {:ok, request} = native_ask(server, context)
    assert_receive {:tool_waiting, first, 1}, 2_000
    assert_receive {:tool_waiting, second, 2}, 2_000
    send(second, :release)

    assert_receive {:jido_ai_request_event, %{kind: :tool_completed, tool_call_id: "call-2"}},
                   2_000

    send(first, :release)
    assert {:ok, "Done"} = Request.await(request)
    assert Enum.map(tool_messages(mock), & &1["tool_call_id"]) == ["call-1", "call-2"]
    assert Enum.map(saved(server, request).meta.tool_results, & &1.id) == ["call-1", "call-2"]

    assert Enum.map(saved(server, request).meta.tool_results, & &1.result) == [
             {:ok, %{value: 1}, []},
             {:ok, %{value: 2}, []}
           ]

    assert_script_done(mock)
  end

  test "cancellation retains a completed tool while stopping the remaining parallel work", %{
    jido: jido
  } do
    calls = for n <- 1..2, do: %{id: "call-#{n}", name: "wait", arguments: %{n: n}}
    {mock, context} = mock([%{reply: {:tools, calls}}])
    server = start_agent(jido, NativeAgent.new!())
    assert {:ok, request} = native_ask(server, context)
    assert_receive {:tool_waiting, first, 1}, 2_000
    assert_receive {:tool_waiting, second, 2}, 2_000
    ref = Process.monitor(second)
    send(first, :release)

    assert_receive {:jido_ai_request_event, %{kind: :tool_completed, tool_call_id: "call-1"}},
                   2_000

    assert :ok = Session.cancel(request)
    assert {:error, :cancelled} = Request.await(request)
    assert_receive {:DOWN, ^ref, :process, ^second, _}, 2_000

    assert [%{id: "call-1", result: {:ok, %{value: 1}, []}}] =
             saved(server, request).meta.tool_results

    assert Server.agent(server).state.reply == ""
    assert_script_done(mock)
  end

  test "a later provider failure retains completed tool outputs", %{jido: jido} do
    call = %{id: "value", name: "fixture_value", arguments: %{kind: "number"}}
    {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:error, 503, "Later failure"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Run", context: context, stream_to: self())
    assert {:error, _} = Agent.await(request)

    assert [%{id: "value", status: :ok, result: {:ok, 7, []}}] =
             saved(server, request).meta.tool_results

    assert List.last(events(request)).data.meta.tool_results ==
             saved(server, request).meta.tool_results

    assert_script_done(mock)
  end

  @tag :tmp_dir
  @tag history_case: "HIST-14/completed-tools"
  test "completed tools retain IDs and results across event replay and a later request", %{
    jido: jido,
    tmp_dir: dir
  } do
    File.write!(Path.join(dir, "example.txt"), "Fixture")

    calls = [
      %{id: "files", name: "inspect_directory", arguments: %{path: dir}},
      %{id: "value", name: "fixture_value", arguments: %{kind: "number"}}
    ]

    {mock, context} =
      mock([
        %{reply: {:tools, calls}},
        %{reply: {:wait, :final, {:text, "Done"}}},
        %{reply: {:text, "Next"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, request} = Agent.ask(server, "Run", context: context, stream_to: self())
    assert_receive {:directory_read, ^dir, tool_context}, 2_000
    assert_receive {:mock_llm_waiting, ^mock, :final, _}, 2_000

    assert_receive {:jido_ai_request_event,
                    %{kind: :tool_completed, data: %{tool_call_id: "files"} = data}},
                   2_000

    assert :ok = Session.emit(tool_context, :tool_completed, data)
    assert :ok = MockLLM.release(mock, :final)
    assert {:ok, "Done"} = Agent.await(request)
    results = saved(server, request).meta.tool_results
    assert Enum.map(results, & &1.id) == ["files", "value"]
    assert Enum.map(results, & &1.result) == [{:ok, ["example.txt"], []}, {:ok, 7, []}]
    assert Enum.map(tool_messages(mock), & &1["tool_call_id"]) == ["files", "value"]
    refute_receive {:directory_read, _, _}, 20
    assert {:ok, next} = Agent.ask(server, "Next", context: context)
    assert {:ok, "Next"} = Agent.await(next)
    assert Map.get(saved(server, next).meta, :tool_results, []) == []
    assert saved(server, request).meta.tool_results == results
    assert_script_done(mock)
  end
end
