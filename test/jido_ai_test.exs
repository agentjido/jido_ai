defmodule Jido.AITest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI
  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct

  doctest Jido.AI

  defp create_react_agent(opts) do
    %Jido.Agent{id: "jido-ai-test-agent", name: "jido-ai-test-agent", state: %{}}
    |> then(fn agent ->
      {agent, []} = ReAct.init(agent, %{strategy_opts: Keyword.merge([tools: []], opts)})
      agent
    end)
  end

  describe "model_aliases/0 and resolve_model/1" do
    test "loads built-in defaults" do
      assert is_binary(AI.resolve_model(:fast))
    end

    test "merges configured aliases over defaults" do
      original = Application.get_env(:jido_ai, :model_aliases)

      Application.put_env(:jido_ai, :model_aliases, %{
        fast: "test:fast",
        custom: "test:custom"
      })

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:jido_ai, :model_aliases)
        else
          Application.put_env(:jido_ai, :model_aliases, original)
        end
      end)

      assert AI.resolve_model(:fast) == "test:fast"
      assert AI.resolve_model(:custom) == "test:custom"
    end
  end

  describe "llm_defaults/0 and llm_defaults/1" do
    test "returns built-in defaults for text/object/stream" do
      defaults = AI.llm_defaults()

      assert defaults[:text][:model] == :fast
      assert defaults[:object][:model] == :thinking
      assert defaults[:stream][:model] == :fast
      assert defaults[:text][:timeout] == 30_000
    end

    test "merges configured defaults with built-ins" do
      original = Application.get_env(:jido_ai, :llm_defaults)

      Application.put_env(:jido_ai, :llm_defaults, %{
        text: %{model: :capable, temperature: 0.7},
        stream: %{max_tokens: 2048}
      })

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:jido_ai, :llm_defaults)
        else
          Application.put_env(:jido_ai, :llm_defaults, original)
        end
      end)

      assert AI.llm_defaults(:text)[:model] == :capable
      assert AI.llm_defaults(:text)[:temperature] == 0.7
      assert AI.llm_defaults(:text)[:timeout] == 30_000
      assert AI.llm_defaults(:stream)[:max_tokens] == 2048
      assert AI.llm_defaults(:stream)[:model] == :fast
    end

    test "raises for unknown default kind" do
      assert_raise ArgumentError, fn ->
        AI.llm_defaults(:unknown_kind)
      end
    end
  end

  describe "struct-level strategy helpers" do
    test "get_strategy_context prefers run_context while a request is active" do
      agent = create_react_agent(system_prompt: "Prompt")

      base_context =
        Context.new(system_prompt: "Prompt")
        |> Context.append_user("old")

      run_context = Context.append_user(base_context, "new")

      agent =
        agent
        |> StratState.get(%{})
        |> Map.put(:context, base_context)
        |> Map.put(:run_context, run_context)
        |> then(&StratState.put(agent, &1))

      assert AI.get_strategy_context(agent) == run_context
    end

    test "update_context_entries only updates run_context while active" do
      agent = create_react_agent(system_prompt: "Prompt")

      base_context =
        Context.new(system_prompt: "Prompt")
        |> Context.append_user("old")

      run_context = Context.append_user(base_context, "new")
      active_entries = [hd(run_context.entries)]

      agent =
        agent
        |> StratState.get(%{})
        |> Map.put(:context, base_context)
        |> Map.put(:run_context, run_context)
        |> then(&StratState.put(agent, &1))

      agent = AI.update_context_entries(agent, active_entries)
      state = StratState.get(agent, %{})

      assert state.run_context.entries == active_entries
      assert state.context.entries == base_context.entries
    end

    test "update_context_entries updates materialized context when idle" do
      agent = create_react_agent(system_prompt: "Prompt")

      context =
        Context.new(system_prompt: "Prompt")
        |> Context.append_user("old")
        |> Context.append_assistant("reply")

      kept_entries = [hd(context.entries)]

      agent =
        agent
        |> StratState.get(%{})
        |> Map.put(:context, context)
        |> Map.put(:run_context, nil)
        |> then(&StratState.put(agent, &1))

      agent = AI.update_context_entries(agent, kept_entries)
      state = StratState.get(agent, %{})

      assert state.context.entries == kept_entries
      assert state.run_context == nil
    end
  end
end
