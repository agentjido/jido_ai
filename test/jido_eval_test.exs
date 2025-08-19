defmodule JidoEvalTest do
  use ExUnit.Case, async: true

  doctest Jido.Eval

  describe "application startup" do
    test "can start the application" do
      # The application should already be running from the test helper
      assert Application.started_applications()
             |> Enum.any?(fn {app, _, _} -> app == :jido_eval end)
    end
  end
end
