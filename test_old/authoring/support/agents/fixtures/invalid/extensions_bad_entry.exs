defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.ExtensionsBadEntry do
  use Jido.AI.Agent, name: "invalid_extension_entry", extensions: [42]
end
