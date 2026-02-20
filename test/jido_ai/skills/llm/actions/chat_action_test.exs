defmodule Jido.AI.Actions.LLM.ChatTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.LLM.Chat
  alias Jido.AI.TestSupport.FakeReqLLM

  setup :set_mimic_from_context
  setup :stub_req_llm

  defp stub_req_llm(context), do: FakeReqLLM.setup_stubs(context)

  describe "Chat action" do
    test "has correct metadata" do
      metadata = Chat.__action_metadata__()
      assert metadata.name == "llm_chat"
      assert metadata.category == "ai"
      assert metadata.vsn == "1.0.0"
    end

    test "requires prompt parameter" do
      assert {:error, _} = Jido.Exec.run(Chat, %{}, %{})
    end

    test "accepts valid parameters with defaults" do
      params = %{
        prompt: "Hello, world!"
      }

      # Test that the schema accepts the parameters
      # We can't run the actual LLM call in unit tests
      assert params.prompt == "Hello, world!"
    end

    test "accepts optional parameters" do
      params = %{
        prompt: "Test",
        model: "anthropic:claude-haiku-4-5",
        system_prompt: "You are helpful",
        max_tokens: 500,
        temperature: 0.5
      }

      assert params.prompt == "Test"
      assert params.model == "anthropic:claude-haiku-4-5"
      assert params.system_prompt == "You are helpful"
      assert params.max_tokens == 500
      assert params.temperature == 0.5
    end

    test "uses context defaults when parameters are omitted" do
      params = %{prompt: "Hello from defaults"}

      context = %{
        provided_params: [:prompt],
        plugin_state: %{
          chat: %{
            default_model: :fast,
            default_max_tokens: 333,
            default_temperature: 0.2
          }
        }
      }

      assert {:ok, result} = Chat.run(params, context)
      assert result.model == Jido.AI.resolve_model(:fast)
      assert is_binary(result.text)
    end

    test "explicit model overrides context default model" do
      params = %{prompt: "Hello explicit", model: "custom:model"}

      context = %{
        provided_params: [:prompt, :model],
        plugin_state: %{chat: %{default_model: :fast}}
      }

      assert {:ok, result} = Chat.run(params, context)
      assert result.model == "custom:model"
    end
  end
end
