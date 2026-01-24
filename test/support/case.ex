defmodule Jido.AI.TestCase do
  @moduledoc """
  Base test case for Jido.AI tests.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Jido.AI.TestCase
    end
  end

  setup _tags do
    :ok
  end
end
