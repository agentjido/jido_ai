defmodule Jido.AI.Reasoning.ReAct.Actions.RuntimeActionsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Actions.{Cancel, Collect, Continue, Start}
  alias Jido.AI.Reasoning.ReAct.Config

  setup :set_mimic_from_context

  setup do
    Mimic.copy(ReAct)
    :ok
  end

  describe "Start action" do
    test "starts runtime stream and returns metadata envelope" do
      Mimic.stub(ReAct, :stream, fn query, config, opts ->
        assert query == "hello"
        assert %Config{} = config
        assert opts[:request_id] == "req_start"
        assert opts[:run_id] == "run_start"
        [:event_1]
      end)

      params = %{query: "hello", request_id: "req_start", run_id: "run_start", model: :fast}

      assert {:ok, %{request_id: "req_start", run_id: "run_start", events: [:event_1], checkpoint_token: nil}} =
               Start.run(params, %{})
    end

    test "maps empty query validation to :query_required" do
      assert {:error, :query_required} = Start.run(%{query: ""}, %{})
    end
  end

  describe "Continue action" do
    test "continues runtime from checkpoint token and forwards query when provided" do
      Mimic.stub(ReAct, :continue, fn token, config, opts ->
        assert token == "token_1"
        assert %Config{} = config
        assert opts[:query] == "follow up"
        {:ok, %{events: [:continued]}}
      end)

      params = %{checkpoint_token: "token_1", query: "follow up", model: :fast}
      assert {:ok, %{events: [:continued]}} = Continue.run(params, %{})
    end
  end

  describe "Collect action" do
    test "collects directly from provided events" do
      Mimic.stub(ReAct, :collect, fn events, config, opts ->
        assert events == [:e1, :e2]
        assert %Config{} = config
        assert opts == []
        {:ok, %{result: "from_events"}}
      end)

      assert {:ok, %{result: "from_events"}} = Collect.run(%{events: [:e1, :e2], model: :fast}, %{})
    end

    test "collects from checkpoint token with options and resolved supervisor" do
      Mimic.stub(ReAct, :collect, fn token, config, opts ->
        assert token == "token_2"
        assert %Config{} = config
        assert opts[:run_until_terminal?] == false
        assert opts[:query] == "resume"
        assert opts[:task_supervisor] == self()
        {:ok, %{result: "from_checkpoint"}}
      end)

      params = %{checkpoint_token: "token_2", run_until_terminal?: false, query: "resume", model: :fast}
      context = %{task_supervisor: self()}

      assert {:ok, %{result: "from_checkpoint"}} = Collect.run(params, context)
    end

    test "returns error when neither events nor checkpoint token is present" do
      assert {:error, :events_or_checkpoint_token_required} = Collect.run(%{}, %{})
    end
  end

  describe "Cancel action" do
    test "cancels checkpoint token and returns wrapped result" do
      Mimic.stub(ReAct, :cancel, fn token, config, reason ->
        assert token == "token_3"
        assert %Config{} = config
        assert reason == :user_cancelled
        {:ok, "replacement_token"}
      end)

      params = %{checkpoint_token: "token_3", reason: :user_cancelled, model: :fast}

      assert {:ok, %{cancelled: true, token: "replacement_token"}} = Cancel.run(params, %{})
    end
  end
end
