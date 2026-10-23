defmodule Jido.AI.Test.ReqLLMCase do
  @moduledoc """
  Shared setup for tests that mock the ReqLLM boundary.

  The case uses global Mimic mode because Jido Flows and AgentServer can call
  ReqLLM from child processes. Tests that use this case must stay synchronous.
  """

  use ExUnit.CaseTemplate

  import Mimic

  using do
    quote do
      import Mimic
      import Jido.AI.Test.ReqLLMMock
    end
  end

  setup :set_mimic_global
  setup :verify_on_exit!
end
