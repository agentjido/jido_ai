defmodule Jido.AI.SourceLayoutTest do
  use ExUnit.Case, async: true

  test "AI source files follow their module namespaces" do
    for path <- Path.wildcard("lib/jido_ai/**/*.ex") do
      modules = Regex.scan(~r/^defmodule (Jido\.AI\.[\w.]+) do$/m, File.read!(path))
      assert modules != [], "No AI module found in #{path}"

      for [_, module] <- modules do
        expected =
          module
          |> String.replace_prefix("Jido.AI.", "")
          |> String.replace("ReAct", "React")
          |> Macro.underscore()
          |> then(&"lib/jido_ai/#{&1}.ex")

        # Keep the small, related error values with their error class.
        grouped_error? =
          (path == "lib/jido_ai/error.ex" and String.starts_with?(module, "Jido.AI.Error.")) or
            (path == "lib/jido_ai/skill/error.ex" and String.starts_with?(module, "Jido.AI.Skill.Error."))

        assert path == expected or grouped_error?, "#{module} belongs in #{expected}, found in #{path}"
      end
    end
  end
end
