defmodule JidoAI.InstallTaskTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "does not change formatter imports when installing" do
    formatter = """
    # Used by "mix format"
    [
      import_deps: [:ecto, :phoenix],
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """

    igniter =
      test_project(
        files: %{
          ".formatter.exs" => formatter,
          "config/config.exs" => "import Config\n"
        }
      )
      |> Igniter.Mix.Task.configure_and_run(Mix.Tasks.JidoAi.Install, [])

    igniter
    |> assert_content_equals(".formatter.exs", formatter)
    |> assert_has_notice(fn notice -> String.contains?(notice, "Jido AI installed successfully!") end)

    config_content =
      igniter.rewrite
      |> Rewrite.source!("config/config.exs")
      |> Rewrite.Source.get(:content)

    assert config_content =~ "config :jido_ai"
    assert config_content =~ "model_aliases:"
    assert config_content =~ "fast: \"anthropic:claude-haiku-4-5\""
    assert config_content =~ "capable: \"anthropic:claude-sonnet-4-20250514\""
  end
end
