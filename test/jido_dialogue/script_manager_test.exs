defmodule Jido.Dialogue.ScriptManagerTest do
  use ExUnit.Case
  alias Jido.Dialogue.{ScriptManager, TestHelper}

  setup do
    TestHelper.start_supervised_app()
    on_exit(fn -> TestHelper.stop_supervised_app() end)
    :ok
  end

  test "load_script/2 loads and validates a script" do
    conversation_id = "test-convo-" <> UUID.uuid4()

    script = %{
      name: "Test Script",
      scenes: [
        %{
          name: "Introduction",
          beats: [
            %{
              name: "Greeting",
              character: "TechnicalGuide",
              content: "Hello! I am the Technical Guide."
            }
          ]
        }
      ]
    }

    assert {:ok, ^script} = ScriptManager.load_script(conversation_id, script)
  end

  test "load_script/2 returns error for invalid script format" do
    conversation_id = "test-convo-" <> UUID.uuid4()

    invalid_script = %{
      scenes: [%{invalid: "format"}]
    }

    assert {:error, :invalid_script} = ScriptManager.load_script(conversation_id, invalid_script)
  end

  describe "current scene management" do
    setup do
      conversation_id = "test-convo-" <> UUID.uuid4()

      script = %{
        name: "Test Script",
        scenes: [
          %{
            name: "Introduction",
            beats: [
              %{
                name: "Greeting",
                character: "TechnicalGuide",
                content: "Hello! I am the Technical Guide."
              }
            ]
          }
        ]
      }

      {:ok, _} = ScriptManager.load_script(conversation_id, script)
      {:ok, conversation_id: conversation_id}
    end

    test "get_current_scene/1 returns the current scene and beat", %{
      conversation_id: conversation_id
    } do
      assert {:ok,
              %{name: "Introduction", current_beat: "Greeting", scene_index: 0, beat_index: 0}} =
               ScriptManager.get_current_scene(conversation_id)
    end

    test "get_current_scene/1 returns error for non-existent conversation" do
      assert {:error, :not_found} = ScriptManager.get_current_scene("non-existent")
    end
  end

  describe "script advancement" do
    setup do
      conversation_id = "test-convo-" <> UUID.uuid4()

      script = %{
        name: "Test Script",
        scenes: [
          %{
            name: "Introduction",
            beats: [
              %{
                name: "Greeting",
                character: "TechnicalGuide",
                content: "Hello! I am the Technical Guide."
              },
              %{
                name: "Ask Name",
                character: "TechnicalGuide",
                content: "What is your name?"
              }
            ]
          },
          %{
            name: "Conversation",
            beats: [
              %{
                name: "Response",
                character: "TechnicalGuide",
                content: "Nice to meet you!"
              }
            ]
          }
        ]
      }

      {:ok, _} = ScriptManager.load_script(conversation_id, script)
      {:ok, conversation_id: conversation_id}
    end

    test "advance_script/2 advances to the next beat or scene", %{
      conversation_id: conversation_id
    } do
      assert :ok = ScriptManager.advance_script(conversation_id)

      assert {:ok,
              %{name: "Introduction", current_beat: "Ask Name", scene_index: 0, beat_index: 1}} =
               ScriptManager.get_current_scene(conversation_id)

      assert :ok = ScriptManager.advance_script(conversation_id)

      assert {:ok,
              %{name: "Conversation", current_beat: "Response", scene_index: 1, beat_index: 0}} =
               ScriptManager.get_current_scene(conversation_id)
    end

    test "advance_script/2 returns error when at end of script", %{
      conversation_id: conversation_id
    } do
      assert :ok = ScriptManager.advance_script(conversation_id)
      assert :ok = ScriptManager.advance_script(conversation_id)
      assert {:error, :end_of_script} = ScriptManager.advance_script(conversation_id)
    end
  end
end
