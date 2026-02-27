defmodule Jido.AI.Directive.ExecRuntimeTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Directive.{LLMEmbed, LLMGenerate, LLMStream, ToolExec}
  alias Jido.AI.TestSupport.DirectiveExec, as: DirectiveSupport
  alias Jido.AgentServer.DirectiveExec

  defmodule DummyAction do
  end

  setup :set_mimic_from_context

  setup do
    Mimic.copy(Jido.AI.Turn)
    :ok
  end

  describe "LLMGenerate DirectiveExec" do
    test "emits usage and llm response signals on success" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == Jido.AI.resolve_model(:fast)
        assert [%{role: :system, content: "Keep it brief"}, %{role: :user, content: "hello"}] = messages
        assert opts[:receive_timeout] == 321

        {:ok,
         %{
           message: %{content: "hello world", tool_calls: nil},
           finish_reason: :stop,
           usage: %{input_tokens: 2, output_tokens: 3}
         }}
      end)

      directive =
        LLMGenerate.new!(%{
          id: "llm_gen_ok",
          model_alias: :fast,
          system_prompt: "Keep it brief",
          context: [%{role: :user, content: "hello"}],
          timeout: 321
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      usage_signal = DirectiveSupport.assert_signal_cast("ai.usage")
      assert usage_signal.data.call_id == "llm_gen_ok"
      assert usage_signal.data.total_tokens == 5

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert response_signal.data.call_id == "llm_gen_ok"
      assert {:ok, %Jido.AI.Turn{text: "hello world"}} = response_signal.data.result
    end

    test "returns sync ok with supervisor error envelope when task cannot start" do
      Mimic.copy(Task.Supervisor)

      Mimic.stub(Task.Supervisor, :start_child, fn _task_supervisor, _fun ->
        {:error, :cannot_start_task}
      end)

      state = DirectiveSupport.state_with_supervisor(self())

      directive =
        LLMGenerate.new!(%{
          id: "llm_gen_supervisor_error",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hi"}]
        })

      assert {:ok, ^state} = DirectiveExec.exec(directive, nil, state)

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:error, %{type: :supervisor}} = response_signal.data.result
    end

    test "converts generate_text exceptions into error envelopes" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
        raise "boom"
      end)

      directive =
        LLMGenerate.new!(%{
          id: "llm_gen_raise",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hello"}]
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")

      assert {:error, %{exception: "boom", type: RuntimeError, error_type: :unknown}} =
               response_signal.data.result
    end
  end

  describe "LLMEmbed DirectiveExec" do
    test "emits embed result on success" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(ReqLLM.Embedding, :embed, fn model, texts, opts ->
        assert model == "openai:text-embedding-3-small"
        assert texts == ["a", "b"]
        assert opts[:dimensions] == 3
        assert opts[:receive_timeout] == 250
        {:ok, [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]}
      end)

      directive =
        LLMEmbed.new!(%{
          id: "embed_ok",
          model: "openai:text-embedding-3-small",
          texts: ["a", "b"],
          dimensions: 3,
          timeout: 250
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      embed_signal = DirectiveSupport.assert_signal_cast("ai.embed.result")
      assert embed_signal.data.call_id == "embed_ok"
      assert {:ok, %{count: 2, embeddings: _embeddings}} = embed_signal.data.result
    end

    test "returns sync ok with supervisor error envelope when task cannot start" do
      Mimic.copy(Task.Supervisor)

      Mimic.stub(Task.Supervisor, :start_child, fn _task_supervisor, _fun ->
        {:error, :cannot_start_task}
      end)

      state = DirectiveSupport.state_with_supervisor(self())

      directive =
        LLMEmbed.new!(%{
          id: "embed_supervisor_error",
          model: "openai:text-embedding-3-small",
          texts: "hello"
        })

      assert {:ok, ^state} = DirectiveExec.exec(directive, nil, state)

      embed_signal = DirectiveSupport.assert_signal_cast("ai.embed.result")
      assert {:error, %{type: :supervisor}} = embed_signal.data.result
    end

    test "converts embed exceptions into error envelopes" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(ReqLLM.Embedding, :embed, fn _model, _texts, _opts ->
        raise "embed boom"
      end)

      directive =
        LLMEmbed.new!(%{
          id: "embed_raise",
          model: "openai:text-embedding-3-small",
          texts: "hello"
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      embed_signal = DirectiveSupport.assert_signal_cast("ai.embed.result")

      assert {:error, %{exception: "embed boom", type: RuntimeError, error_type: :unknown}} =
               embed_signal.data.result
    end
  end

  describe "LLMStream DirectiveExec" do
    test "emits deltas, usage, and final response on successful stream processing" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.copy(ReqLLM.StreamResponse)

      Mimic.stub(ReqLLM, :stream_text, fn model, messages, opts ->
        assert model == Jido.AI.resolve_model(:fast)
        assert [%{role: :system, content: "Keep it brief"}, %{role: :user, content: "hello"}] = messages
        assert opts[:receive_timeout] == 321
        {:ok, :stream_response}
      end)

      Mimic.stub(ReqLLM.StreamResponse, :process_stream, fn :stream_response, callbacks ->
        callbacks[:on_thinking].("thinking chunk")
        callbacks[:on_result].("content chunk")
        {:ok, %{message: %{content: "hello world"}, usage: %{input_tokens: 2, output_tokens: 3}}}
      end)

      Mimic.stub(Jido.AI.Turn, :from_response, fn response, model: model ->
        assert model == Jido.AI.resolve_model(:fast)
        %Jido.AI.Turn{text: response.message.content, usage: response.usage}
      end)

      directive =
        LLMStream.new!(%{
          id: "llm_stream_ok",
          model_alias: :fast,
          system_prompt: "Keep it brief",
          context: [%{role: :user, content: "hello"}],
          timeout: 321
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      signal_1 = DirectiveSupport.assert_signal_cast("ai.llm.delta")
      signal_2 = DirectiveSupport.assert_signal_cast("ai.llm.delta")

      assert Enum.sort([signal_1.data.chunk_type, signal_2.data.chunk_type]) == [:content, :thinking]

      usage_signal = DirectiveSupport.assert_signal_cast("ai.usage")
      assert usage_signal.data.call_id == "llm_stream_ok"
      assert usage_signal.data.total_tokens == 5

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:ok, %Jido.AI.Turn{text: "hello world"}} = response_signal.data.result
    end

    test "does not emit usage signal when stream usage is nil" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.copy(ReqLLM.StreamResponse)

      Mimic.stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
        {:ok, :stream_response}
      end)

      Mimic.stub(ReqLLM.StreamResponse, :process_stream, fn :stream_response, callbacks ->
        callbacks[:on_result].("content chunk")
        {:ok, %{message: %{content: "no usage"}}}
      end)

      Mimic.stub(Jido.AI.Turn, :from_response, fn response, _opts ->
        %Jido.AI.Turn{text: response.message.content, usage: nil}
      end)

      directive =
        LLMStream.new!(%{
          id: "llm_stream_no_usage",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hello"}]
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      assert DirectiveSupport.assert_signal_cast("ai.llm.delta").data.chunk_type == :content
      refute_receive {:"$gen_cast", {:signal, %Jido.Signal{type: "ai.usage"}}}, 100

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:ok, %Jido.AI.Turn{text: "no usage"}} = response_signal.data.result
    end

    test "returns error envelope when stream processing returns error" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.copy(ReqLLM.StreamResponse)

      Mimic.stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
        {:ok, :stream_response}
      end)

      Mimic.stub(ReqLLM.StreamResponse, :process_stream, fn :stream_response, _callbacks ->
        {:error, :bad_stream}
      end)

      directive =
        LLMStream.new!(%{
          id: "llm_stream_process_error",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hello"}]
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:error, :bad_stream} = response_signal.data.result
    end

    test "returns error envelope when stream_text fails" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
        {:error, :network}
      end)

      directive =
        LLMStream.new!(%{
          id: "llm_stream_start_error",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hello"}]
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:error, :network} = response_signal.data.result
    end

    test "converts thrown values into catch error envelopes" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(ReqLLM, :stream_text, fn _model, _messages, _opts ->
        throw(:boom)
      end)

      directive =
        LLMStream.new!(%{
          id: "llm_stream_throw",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hello"}]
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:error, %{caught: :throw, error_type: :unknown}} = response_signal.data.result
    end

    test "returns sync ok with supervisor error envelope when task cannot start" do
      Mimic.copy(Task.Supervisor)

      Mimic.stub(Task.Supervisor, :start_child, fn _task_supervisor, _fun ->
        {:error, :cannot_start_task}
      end)

      state = DirectiveSupport.state_with_supervisor(self())

      directive =
        LLMStream.new!(%{
          id: "llm_stream_supervisor_error",
          model: "openai:gpt-4o-mini",
          context: [%{role: :user, content: "hello"}]
        })

      assert {:ok, ^state} = DirectiveExec.exec(directive, nil, state)

      response_signal = DirectiveSupport.assert_signal_cast("ai.llm.response")
      assert {:error, %{type: :supervisor}} = response_signal.data.result
    end
  end

  describe "ToolExec DirectiveExec" do
    test "emits successful tool_result for direct module execution" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(Jido.AI.Turn, :execute_module, fn module, params, context ->
        assert module == DummyAction
        assert params == %{"value" => 7}
        assert context == %{origin: :test}
        {:ok, %{value: 8}}
      end)

      directive =
        ToolExec.new!(%{
          id: "tool_ok",
          tool_name: "dummy",
          action_module: DummyAction,
          arguments: %{"value" => 7},
          context: %{origin: :test}
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      signal = DirectiveSupport.assert_signal_cast("ai.tool.result")
      assert signal.data.call_id == "tool_ok"
      assert signal.data.tool_name == "dummy"
      assert signal.data.result == {:ok, %{value: 8}, []}
    end

    test "emits timeout error when execution exceeds timeout_ms" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.stub(Jido.AI.Turn, :execute_module, fn _module, _params, _context ->
        Process.sleep(50)
        {:ok, %{slow: true}}
      end)

      directive =
        ToolExec.new!(%{
          id: "tool_timeout",
          tool_name: "dummy",
          action_module: DummyAction,
          timeout_ms: 5
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      signal = DirectiveSupport.assert_signal_cast("ai.tool.result")
      assert {:error, %{type: :timeout, retryable?: true}, []} = signal.data.result
    end

    test "retries retryable errors and succeeds on a later attempt" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      key = {__MODULE__, :retryable_attempts}
      :persistent_term.put(key, 0)
      on_exit(fn -> :persistent_term.erase(key) end)

      Mimic.stub(Jido.AI.Turn, :execute, fn _tool_name, _params, _context, _opts ->
        attempt = :persistent_term.get(key, 0) + 1
        :persistent_term.put(key, attempt)

        if attempt == 1 do
          {:error, %{type: :timeout, message: "timeout", retryable?: true, details: %{}}, []}
        else
          {:ok, %{attempt: attempt}}
        end
      end)

      directive =
        ToolExec.new!(%{
          id: "tool_retry",
          tool_name: "dummy",
          max_retries: 1,
          retry_backoff_ms: 0
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      signal = DirectiveSupport.assert_signal_cast("ai.tool.result")
      assert signal.data.result == {:ok, %{attempt: 2}, []}
      assert :persistent_term.get(key) == 2
    end

    test "does not retry non-retryable errors" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      key = {__MODULE__, :non_retryable_attempts}
      :persistent_term.put(key, 0)
      on_exit(fn -> :persistent_term.erase(key) end)

      Mimic.stub(Jido.AI.Turn, :execute, fn _tool_name, _params, _context, _opts ->
        attempt = :persistent_term.get(key, 0) + 1
        :persistent_term.put(key, attempt)

        {:error, %{type: :validation, message: "bad args", retryable?: false, details: %{}}, []}
      end)

      directive =
        ToolExec.new!(%{
          id: "tool_no_retry",
          tool_name: "dummy",
          max_retries: 3,
          retry_backoff_ms: 0
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      signal = DirectiveSupport.assert_signal_cast("ai.tool.result")
      assert {:error, %{type: :validation}, []} = signal.data.result
      assert :persistent_term.get(key) == 1
    end

    test "returns sync ok with supervisor error envelope when task cannot start" do
      Mimic.copy(Task.Supervisor)

      Mimic.stub(Task.Supervisor, :start_child, fn _task_supervisor, _fun ->
        {:error, :cannot_start_task}
      end)

      state = DirectiveSupport.state_with_supervisor(self())

      directive =
        ToolExec.new!(%{
          id: "tool_supervisor_error",
          tool_name: "dummy"
        })

      assert {:ok, ^state} = DirectiveExec.exec(directive, nil, state)

      signal = DirectiveSupport.assert_signal_cast("ai.tool.result")
      assert {:error, %{type: :supervisor}, []} = signal.data.result
    end

    test "falls back to internal_error signal when tool result signal construction fails" do
      supervisor = DirectiveSupport.start_task_supervisor!()
      on_exit(fn -> DirectiveSupport.stop_task_supervisor(supervisor) end)

      Mimic.copy(Jido.AI.Signal.ToolResult)

      Mimic.stub(Jido.AI.Signal.ToolResult, :new!, fn attrs ->
        case Process.get(:tool_result_build_attempt, 0) do
          0 ->
            Process.put(:tool_result_build_attempt, 1)
            raise "signal build failed"

          _ ->
            Jido.Signal.new!("ai.tool.result", attrs, source: "/ai/strategy")
        end
      end)

      Mimic.stub(Jido.AI.Turn, :execute_module, fn _module, _params, _context ->
        {:ok, %{value: :ok}}
      end)

      directive =
        ToolExec.new!(%{
          id: "tool_signal_fallback",
          tool_name: "dummy",
          action_module: DummyAction
        })

      state = DirectiveSupport.state_with_supervisor(supervisor)
      assert {:async, nil, ^state} = DirectiveExec.exec(directive, nil, state)

      signal = DirectiveSupport.assert_signal_cast("ai.tool.result")
      assert {:error, %{type: :internal_error}, []} = signal.data.result
    end
  end
end
