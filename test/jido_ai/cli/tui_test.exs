defmodule Jido.AI.CLI.TUITest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.TUI

  describe "TUI module" do
    test "module is loaded and exports run/1" do
      assert {:module, TUI} = Code.ensure_loaded(TUI)
      assert {:run, 1} in TUI.__info__(:functions)
    end
  end
end
