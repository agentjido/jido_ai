Code.require_file(Path.expand("../../../examples/scripts/shared/bootstrap.exs", __DIR__))

defmodule Jido.AI.Examples.NativeCallbackMigrationTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Jido.AI.Examples.TaskListAgent
  alias Jido.AI.Examples.Weather.LiveContext
  alias Jido.AI.Test.MockLLM

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido)), do: start_supervised!({Jido, name: Jido})
    Mimic.copy(Jido.Exec)
    :ok
  end

  test "task tools commit state that later tool calls and requests can read" do
    mock =
      start_supervised!(
        {MockLLM,
         script: [
           %{reply: {:tools, [%{id: "add", name: "tasklist_add_tasks", arguments: %{tasks: [%{title: "Review"}]}}]}},
           %{
             reply:
               {:from_request,
                fn request ->
                  added = tool_output(request, "add")
                  id = hd(added["created_tasks"])["id"]
                  {:tools, [%{id: "start", name: "tasklist_start_task", arguments: %{task_id: id}}]}
                end}
           },
           %{
             reply:
               {:from_request,
                fn request ->
                  started = tool_output(request, "start")
                  assert started["task"]["status"] == "in_progress"

                  {:tools,
                   [
                     %{
                       id: "finish",
                       name: "tasklist_complete_task",
                       arguments: %{task_id: started["task"]["id"], result: "Reviewed"}
                     }
                   ]}
                end}
           },
           %{reply: {:text, "Review complete"}},
           %{reply: {:tools, [%{id: "state", name: "tasklist_get_state", arguments: %{}}]}},
           %{
             reply:
               {:from_request,
                fn request ->
                  tasks = tool_output(request, "state")["tasks"]
                  assert [%{"title" => "Review", "status" => "done", "result" => "Reviewed"}] = tasks
                  {:text, "One completed task"}
                end}
           }
         ]}
      )

    server = start_supervised!({Jido.AgentServer, agent: TaskListAgent})
    opts = [model: MockLLM.model(), llm_opts: MockLLM.options(mock)]
    assert {:ok, "Review complete"} = TaskListAgent.execute(server, "Review", opts)
    assert {:ok, "One completed task"} = TaskListAgent.status(server, opts)
    agent = Jido.AgentServer.agent(server)
    assert [%{"title" => "Review", "status" => "done"}] = agent.state.tasks
    assert agent.state.last_answer == "One completed task"
    assert %{remaining: [], unexpected: []} = MockLLM.report(mock)
  end

  test "weather context is reused within a request and fetched for a new request" do
    expect(Jido.Exec, :run, 6, fn
      Jido.Tools.Weather.Geocode, %{location: "Seattle"}, %{}, _ ->
        {:ok, %{coordinates: "47.6,-122.3"}}

      Jido.Tools.Weather.LocationToGrid, _, %{}, _ ->
        {:ok, %{city: "Seattle", urls: %{forecast: "https://weather.test/forecast"}}}

      Jido.Tools.Weather.Forecast, _, %{}, _ ->
        {:ok, %{periods: [%{name: "Tonight", temperature: 60}]}}
    end)

    request = %{messages: [%{role: :user, content: "Seattle weather"}]}
    context = %{query: "Seattle weather", request_id: "first"}
    assert {:ok, %{messages: messages}} = LiveContext.transform_request(request, nil, nil, context)
    assert List.last(messages).content =~ "Tonight"
    assert {:ok, %{}} = LiveContext.transform_request(%{messages: messages}, nil, nil, context)

    assert {:ok, %{messages: next}} =
             LiveContext.transform_request(%{messages: messages}, nil, nil, %{context | request_id: "second"})

    assert List.last(next).content =~ "LIVE_WEATHER_REQUEST: second"
  end

  test "weather source errors stop the request transformer" do
    expect(Jido.Exec, :run, fn _, _, _, _ -> {:error, :offline} end)

    assert {:error, message} =
             LiveContext.transform_request(%{messages: []}, nil, nil, %{query: "Seattle", request_id: "failed"})

    assert message =~ "Live weather fetch failed"
    assert message =~ "offline"
  end

  defp tool_output(request, call_id) do
    message = Enum.find(request["messages"], &(&1["role"] == "tool" and &1["tool_call_id"] == call_id))
    Jason.decode!(message["content"])["result"]
  end
end
