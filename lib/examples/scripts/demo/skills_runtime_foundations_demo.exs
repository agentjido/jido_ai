Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Skill
alias Jido.AI.Skill.{Loader, Prompt, Registry}

Bootstrap.init!()
Bootstrap.print_banner("Skills Runtime Foundations Demo")

Bootstrap.assert!(File.exists?("priv/skills/code-review/SKILL.md"), "Missing priv/skills/code-review/SKILL.md")

defmodule SkillsRuntimeFoundationsDemo.Calculator do
  use Jido.AI.Skill,
    name: "calculator",
    description: "Performs arithmetic with tool-based execution.",
    license: "MIT",
    allowed_tools: ~w(add subtract multiply divide),
    tags: ["math", "utility"],
    body: """
    # Calculator Skill

    Use arithmetic tools for every operation.
    """
end

calc_manifest = Skill.manifest(SkillsRuntimeFoundationsDemo.Calculator)
{:ok, runtime_manifest} = Loader.load("priv/skills/code-review/SKILL.md")

:ok = Registry.ensure_started()
Registry.register(calc_manifest)
{:ok, _count} = Registry.load_from_paths(["priv/skills"])

{:ok, _} = Registry.lookup("calculator")
{:ok, _} = Skill.resolve("calculator")

rendered = Prompt.render([SkillsRuntimeFoundationsDemo.Calculator], include_body: false)

Bootstrap.assert!(calc_manifest.name == "calculator", "Module skill manifest name mismatch.")

Bootstrap.assert!(
  is_binary(runtime_manifest.name) and runtime_manifest.name != "",
  "Runtime skill manifest failed to load."
)

Bootstrap.assert!(
  String.contains?(String.downcase(rendered), "calculator"),
  "Rendered prompt missing calculator skill content."
)

IO.puts("✓ Module and runtime skills loaded")
IO.puts("✓ Registry and prompt rendering validated")
