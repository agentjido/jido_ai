defmodule Jido.AI.Reasoning.ReAct.PublicApiTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.{Config, Runner, State, Token}

  setup :set_mimic_from_context

  setup do
    Mimic.copy(Runner)
    Mimic.copy(Token)
    :ok
  end

  describe "build_config/1" do
    test "builds config from map and passes through config struct" do
      built = ReAct.build_config(%{model: :fast})
      assert %Config{} = built
      assert built.model == Jido.AI.resolve_model(:fast)

      passthrough = ReAct.build_config(built)
      assert passthrough == built
    end
  end

  describe "stream APIs" do
    test "stream/3 delegates to runner with normalized config" do
      Mimic.stub(Runner, :stream, fn query, config, opts ->
        assert query == "hello"
        assert %Config{} = config
        assert config.model == Jido.AI.resolve_model(:fast)
        assert opts[:request_id] == "req_1"
        [%{kind: :request_started}]
      end)

      events = ReAct.stream("hello", %{model: :fast}, request_id: "req_1") |> Enum.to_list()
      assert [%{kind: :request_started}] = events
    end

    test "stream_from_state/3 delegates to runner with provided state" do
      state = State.new("hello", nil, request_id: "req_state", run_id: "run_state")

      Mimic.stub(Runner, :stream_from_state, fn given_state, config, opts ->
        assert given_state == state
        assert %Config{} = config
        assert opts[:request_id] == "req_2"
        [%{kind: :checkpoint}]
      end)

      events = ReAct.stream_from_state(state, %{model: :fast}, request_id: "req_2") |> Enum.to_list()
      assert [%{kind: :checkpoint}] = events
    end
  end

  describe "run/start/continue/collect/cancel" do
    test "run/3 reduces stream into final aggregated payload" do
      Mimic.stub(Runner, :stream, fn _query, _config, _opts ->
        [
          %{kind: :request_started, data: %{}},
          %{
            kind: :request_completed,
            data: %{result: "done", termination_reason: :final_answer, usage: %{total_tokens: 2}}
          },
          %{kind: :checkpoint, data: %{token: "tok_1"}}
        ]
      end)

      result = ReAct.run("hello", %{model: :fast})
      assert result.result == "done"
      assert result.termination_reason == :final_answer
      assert result.usage == %{total_tokens: 2}
      assert result.final_token == "tok_1"
      assert length(result.trace) == 3
    end

    test "start/3 returns run metadata and event stream" do
      Mimic.stub(Runner, :stream, fn _query, _config, opts ->
        assert opts[:request_id] == "req_start"
        assert opts[:run_id] == "run_start"
        [:event_1, :event_2]
      end)

      assert {:ok, %{request_id: "req_start", run_id: "run_start", events: events, checkpoint_token: nil}} =
               ReAct.start("hello", %{model: :fast}, request_id: "req_start", run_id: "run_start")

      assert Enum.to_list(events) == [:event_1, :event_2]
    end

    test "continue/3 resumes from checkpoint token" do
      state = State.new("hello", nil, request_id: "req_continue", run_id: "run_continue")

      Mimic.stub(Token, :decode_state, fn token, config ->
        assert token == "checkpoint_token"
        assert %Config{} = config
        {:ok, state, %{raw: true}}
      end)

      Mimic.stub(Runner, :stream_from_state, fn given_state, _config, opts ->
        assert given_state == state
        assert opts[:request_id] == "req_override"
        [:continued]
      end)

      assert {:ok,
              %{
                request_id: "req_continue",
                run_id: "run_continue",
                events: events,
                checkpoint_token: "checkpoint_token"
              }} =
               ReAct.continue("checkpoint_token", %{model: :fast}, request_id: "req_override")

      assert Enum.to_list(events) == [:continued]
    end

    test "collect/3 from checkpoint with run_until_terminal? false returns decoded payload" do
      state =
        State.new("hello", nil, request_id: "req_collect", run_id: "run_collect")
        |> State.put_status(:completed)
        |> State.put_result("answer")
        |> State.merge_usage(%{total_tokens: 9})

      Mimic.stub(Token, :decode_state, fn token, _config ->
        assert token == "checkpoint_token"
        {:ok, state, %{decoded: true}}
      end)

      assert {:ok, payload} =
               ReAct.collect("checkpoint_token", %{model: :fast}, run_until_terminal?: false)

      assert payload.result == "answer"
      assert payload.termination_reason == :completed
      assert payload.usage == %{total_tokens: 9}
      assert payload.final_token == "checkpoint_token"
      assert payload.token_payload == %{decoded: true}
    end

    test "collect/3 from checkpoint with run_until_terminal? true resumes and reduces stream" do
      state = State.new("hello", nil, request_id: "req_collect", run_id: "run_collect")

      Mimic.stub(Token, :decode_state, fn _token, _config -> {:ok, state, %{decoded: true}} end)

      Mimic.stub(Runner, :stream_from_state, fn _state, _config, _opts ->
        [
          %{
            kind: :request_completed,
            data: %{result: "terminal", termination_reason: :final_answer, usage: %{total_tokens: 3}}
          },
          %{kind: :checkpoint, data: %{token: "final_tok"}}
        ]
      end)

      assert {:ok, payload} = ReAct.collect("checkpoint_token", %{model: :fast}, run_until_terminal?: true)
      assert payload.result == "terminal"
      assert payload.termination_reason == :final_answer
      assert payload.final_token == "final_tok"
    end

    test "collect/3 from events enumerable delegates to collect_stream" do
      events = [%{kind: :request_cancelled, data: %{}}, %{kind: :checkpoint, data: %{token: "cancel_tok"}}]

      assert {:ok, payload} = ReAct.collect(events, %{model: :fast}, [])
      assert payload.termination_reason == :cancelled
      assert payload.final_token == "cancel_tok"
    end

    test "cancel/3 delegates to token mark_cancelled" do
      Mimic.stub(Token, :mark_cancelled, fn token, config, reason ->
        assert token == "checkpoint_token"
        assert %Config{} = config
        assert reason == :user_cancelled
        {:ok, "new_token"}
      end)

      assert {:ok, "new_token"} = ReAct.cancel("checkpoint_token", %{model: :fast}, :user_cancelled)
    end
  end

  describe "collect_stream/1 edge cases" do
    test "handles failed request terminal event" do
      payload =
        ReAct.collect_stream([
          %{kind: :request_failed, data: %{error: :boom}},
          %{kind: :checkpoint, data: %{token: "tok_failed"}}
        ])

      assert payload.result == :boom
      assert payload.termination_reason == :failed
      assert payload.final_token == "tok_failed"
    end
  end
end
