defmodule Jido.AI.SignalMetadataTest do
  use ExUnit.Case, async: true

  test "all typed AI Signals expose their generated metadata" do
    modules = [
      Jido.AI.Signal.EmbedResult,
      Jido.AI.Signal.RequestCompleted,
      Jido.AI.Signal.RequestError,
      Jido.AI.Signal.RequestFailed,
      Jido.AI.Signal.RequestStarted,
      Jido.AI.Signal.ToolResult,
      Jido.AI.Signal.ToolStarted,
      Jido.AI.Signal.Usage
    ]

    for module <- modules do
      assert module.extension_policy() == %{}
      assert module.__signal_metadata__() == module.to_json()
      assert is_map(module.to_json())
    end
  end
end
