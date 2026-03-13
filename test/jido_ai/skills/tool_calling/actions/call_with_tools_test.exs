defmodule Jido.AI.Actions.ToolCalling.CallWithToolsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.ToolCalling.CallWithTools
  alias Jido.AI.TestSupport.FakeReqLLM
  alias Jido.AI.Turn

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "Test calculator",
      schema:
        Zoi.object(%{
          operation: Zoi.string(),
          a: Zoi.integer(),
          b: Zoi.integer()
        })

    def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, %{result: a + b}}
    def run(_params, _context), do: {:error, :unsupported_operation}
  end

  defmodule OffsetCalculator do
    use Jido.Action,
      name: "calculator",
      description: "Fallback calculator that offsets result",
      schema:
        Zoi.object(%{
          operation: Zoi.string(),
          a: Zoi.integer(),
          b: Zoi.integer()
        })

    def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, %{result: a + b + 100}}
    def run(_params, _context), do: {:error, :unsupported_operation}
  end

  @moduletag :unit
  @moduletag :capture_log

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  defp tool_message_content(messages) when is_list(messages) do
    messages
    |> Enum.find_value(fn
      %ReqLLM.Message{role: :tool, content: content} -> Turn.extract_from_content(content)
      %{role: role, content: content} when role in [:tool, "tool"] -> normalize_message_content(content)
      _ -> nil
    end)
  end

  defp normalize_message_content(content) when is_list(content), do: Turn.extract_from_content(content)
  defp normalize_message_content(content), do: content

  describe "schema" do
    test "has required fields" do
      assert CallWithTools.schema().fields[:prompt].meta.required == true
      refute CallWithTools.schema().fields[:model].meta.required
      refute CallWithTools.schema().fields[:tools].meta.required
    end

    test "has default values" do
      assert CallWithTools.schema().fields[:max_tokens].value == 4096
      assert CallWithTools.schema().fields[:temperature].value == 0.7
      assert CallWithTools.schema().fields[:auto_execute].value == false
      assert CallWithTools.schema().fields[:max_turns].value == 10
    end
  end

  describe "run/2" do
    test "returns error when prompt is missing" do
      assert {:error, _} = CallWithTools.run(%{}, %{})
    end

    test "returns error when prompt is empty string" do
      assert {:error, _} = CallWithTools.run(%{prompt: ""}, %{})
    end

    test "returns error for invalid max_turns format" do
      assert {:error, :invalid_max_turns} =
               CallWithTools.run(%{prompt: "hello", max_turns: "many"}, %{})
    end

    test "returns result with valid prompt" do
      params = %{
        prompt: "What is 2 + 2?"
      }

      assert {:ok, result} = CallWithTools.run(params, %{})
      assert Map.has_key?(result, :type)
      assert Map.has_key?(result, :model)
    end

    test "includes tools in LLM call" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"]
      }

      context = %{
        tools: %{TestCalculator.name() => TestCalculator}
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert Map.has_key?(result, :type)
    end

    test "uses plugin-state defaults for auto_execute and tool registry" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"]
      }

      context = %{
        plugin_state: %{
          chat: %{
            auto_execute: true,
            max_turns: 3,
            tools: %{TestCalculator.name() => TestCalculator}
          }
        }
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :final_answer
      assert result.text =~ "Tool execution complete"
      assert tool_message_content(result.messages) =~ "\"result\":8"
    end

    test "uses state.chat tools fallback for auto execution" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"],
        auto_execute: true
      }

      context = %{
        state: %{
          chat: %{
            tools: %{TestCalculator.name() => TestCalculator}
          }
        }
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :final_answer
      assert tool_message_content(result.messages) =~ "\"result\":8"
    end

    test "prefers top-level tools over plugin_state chat tools" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"],
        auto_execute: true
      }

      context = %{
        tools: %{TestCalculator.name() => TestCalculator},
        plugin_state: %{
          chat: %{
            tools: %{OffsetCalculator.name() => OffsetCalculator}
          }
        }
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :final_answer
      assert tool_message_content(result.messages) =~ "\"result\":8"
      refute tool_message_content(result.messages) =~ "\"result\":108"
    end

    test "explicit auto_execute=false overrides plugin-state default" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"],
        auto_execute: false
      }

      context = %{
        plugin_state: %{
          chat: %{
            auto_execute: true,
            tools: %{TestCalculator.name() => TestCalculator}
          }
        }
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :tool_calls
      assert is_list(result.tool_calls)
    end

    test "preserves generation opts across multi-turn auto_execute" do
      params = %{
        prompt: "Calculate 5 + 3",
        tools: ["calculator"],
        auto_execute: true,
        max_tokens: 123,
        temperature: 0.2
      }

      context = %{
        tools: %{TestCalculator.name() => TestCalculator}
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :final_answer
      assert result.text =~ "max_tokens=123"
      assert result.text =~ "temperature=0.2"
      assert result.turns >= 1
      assert is_map(result.usage)
      assert result.usage.total_tokens > 0
    end

    test "preserves OpenAI Responses response_id across auto_execute turns" do
      test_pid = self()

      expect(ReqLLM.Generation, :generate_text, 2, fn model, messages, opts ->
        send(test_pid, {:generate_text, messages, opts})

        if Enum.any?(messages, &match?(%ReqLLM.Message{role: :tool}, &1)) do
          assistant_message =
            Enum.find(messages, fn
              %ReqLLM.Message{role: :assistant, tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] ->
                true

              _ ->
                false
            end)

          assert assistant_message.metadata[:response_id] == "resp_tool_round_1"

          {:ok,
           %{
             message: %{
               content: "Tool execution complete",
               tool_calls: nil,
               metadata: %{response_id: "resp_tool_round_2"}
             },
             finish_reason: :stop,
             usage: %{input_tokens: 12, output_tokens: 24},
             model: model
           }}
        else
          assert model == "openai:gpt-4o-mini"
          assert opts[:tools] != []

          {:ok,
           %{
             message: %{
               content: nil,
               tool_calls: [
                 %{
                   id: "tc_1",
                   name: "calculator",
                   arguments: %{"operation" => "add", "a" => 5, "b" => 3}
                 }
               ],
               metadata: %{response_id: "resp_tool_round_1"}
             },
             finish_reason: :tool_calls,
             usage: %{input_tokens: 10, output_tokens: 8},
             model: model
           }}
        end
      end)

      params = %{
        prompt: "Calculate 5 + 3",
        model: "openai:gpt-4o-mini",
        tools: ["calculator"],
        auto_execute: true
      }

      context = %{
        tools: %{TestCalculator.name() => TestCalculator}
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.type == :final_answer
      assert result.text == "Tool execution complete"
    end

    test "enforces max_turns and returns deterministic terminal shape" do
      params = %{
        prompt: "loop tool execution",
        tools: ["calculator"],
        auto_execute: true,
        max_turns: 1
      }

      context = %{
        tools: %{TestCalculator.name() => TestCalculator}
      }

      assert {:ok, result} = CallWithTools.run(params, context)
      assert result.reason == :max_turns_reached
      assert result.turns == 1
      assert is_map(result.usage)
      assert Map.has_key?(result.usage, :total_tokens)
    end
  end

  describe "model resolution" do
    test "accepts atom model alias" do
      params = %{
        prompt: "Test",
        model: :capable
      }

      assert params[:model] == :capable
    end

    test "accepts string model spec" do
      params = %{
        prompt: "Test",
        model: "anthropic:claude-sonnet-4-20250514"
      }

      assert params[:model] == "anthropic:claude-sonnet-4-20250514"
    end
  end
end
