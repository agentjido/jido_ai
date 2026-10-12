defmodule Jido.AI.TestSupport.LiveStreamRelayTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Reasoning.ReAct.{Config, Runner}
  alias Jido.AI.TestSupport.{LiveStreamRelay, ReActTimeoutServer}

  for mode <- [:before_response, :mid_stream] do
    test "the relay holds upstream SSE at #{mode} and cancels on client closure" do
      config = provider(unquote(mode))
      task = Task.async(fn -> Runner.stream("Work", config) |> Enum.to_list() end)
      assert_receive {:relay_held, connection, held}, 2_000
      assert held.upstream_status == 200
      assert held.held_bytes > 0
      assert held.text_frames == if(unquote(mode) == :mid_stream, do: 1, else: 0)
      monitor = Process.monitor(connection)
      events = Task.await(task, 3_000)
      assert %{kind: :request_failed, data: %{error: :stream_timeout}} = List.last(events)
      assert_receive {:relay_closed, ^connection, %{reason: :client_closed, upstream_cancel_requested: true}}, 2_000
      assert_receive {:DOWN, ^monitor, :process, ^connection, :normal}, 2_000
    end
  end

  test "the relay forwards a complete upstream response" do
    config = provider(:pass)
    events = Runner.stream("Work", config) |> Enum.to_list()
    assert %{kind: :request_completed, data: %{result: "Done"}} = List.last(events)
    assert_receive {:relay_closed, _, %{reason: :completed, text_frames: 1}}, 2_000
  end

  test "release forwards the held original response bytes" do
    config = %{provider(:mid_stream) | stream_timeout_ms: 5_000}
    task = Task.async(fn -> Runner.stream("Work", config) |> Enum.to_list() end)
    assert_receive {:relay_held, connection, _}, 2_000
    send(connection, :release)
    events = Task.await(task, 3_000)
    assert %{kind: :request_completed, data: %{result: "Done"}} = List.last(events)
    assert_receive {:relay_closed, ^connection, %{reason: :completed}}, 2_000
  end

  defp provider(mode) do
    upstream = start_supervised!({ReActTimeoutServer, owner: self(), modes: [:success], wire: :responses})

    relay =
      start_supervised!(
        {LiveStreamRelay,
         owner: self(), modes: [mode], upstream: ReActTimeoutServer.url(upstream), api_key: "offline-test"}
      )

    Config.new(%{
      model: "openai:gpt-4.1-mini",
      tools: [],
      stream_timeout_ms: 500,
      llm_opts: [
        api_key: "local-relay-only",
        base_url: LiveStreamRelay.url(relay),
        receive_timeout: 5_000,
        req_http_options: [retry: false, receive_timeout: 5_000]
      ]
    })
  end
end
