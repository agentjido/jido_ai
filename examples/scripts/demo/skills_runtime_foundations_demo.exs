Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.Paths
alias Jido.AI.Skill
alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
alias Jido.AI.Skill.{AgentIntegration, Loader, Prompt, Registry, Spec}

Bootstrap.init!()
Bootstrap.print_banner("Skills Runtime Foundations Demo")

skill_root = Paths.repo_path("priv/skills")
code_review_skill = Path.join(skill_root, "code-review/SKILL.md")

Bootstrap.assert!(File.exists?(code_review_skill), "Missing #{code_review_skill}")

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
{:ok, runtime_manifest} = Loader.load(code_review_skill)

:ok = Registry.ensure_started()
Registry.register(calc_manifest)
{:ok, _count} = Registry.load_from_paths([skill_root])

{:ok, _} = Registry.lookup("calculator")
{:ok, _} = Skill.resolve("calculator")

rendered = Prompt.render([SkillsRuntimeFoundationsDemo.Calculator], include_body: false)

runtime_spec = %Spec{
  name: "about-jaicool",
  description: "Loads JAICool overview resources supplied by the host.",
  source: nil,
  body_ref: {:inline, "# About JAICool\n\nLoad the provider resource before answering."},
  metadata: %{"owner" => "demo"},
  tags: ["runtime"]
}

resource_id = "b7754895-90f8-4594-b6be-c80fd0859545"

provider = fn
  %{operation: :list}, %{tenant_id: _tenant_id} ->
    {:ok,
     %{
       resources: [%{id: resource_id, name: "about-jaicool.md", type: :reference, size: 13}],
       complete: true
     }}

  %{operation: :load, resource_id: loaded_resource_id}, %{tenant_id: _tenant_id} ->
    content = "About JAICool"
    {:ok, %{content: content, resource_id: loaded_resource_id, size: byte_size(content)}}
end

{:ok, integration} = AgentIntegration.prepare(specs: [runtime_spec], resource_provider: provider)
context = Map.merge(integration.tool_context, %{agent_id: "skills-runtime-demo", tenant_id: "acme"})

{:ok, loaded_runtime} = LoadSkill.run(%{name: "about-jaicool"}, context)
listed_resource_id = hd(loaded_runtime.resources.resources).id
{:ok, runtime_resource} = LoadResource.run(%{name: "about-jaicool", resource_id: listed_resource_id}, context)

Bootstrap.assert!(calc_manifest.name == "calculator", "Module skill manifest name mismatch.")

Bootstrap.assert!(
  is_binary(runtime_manifest.name) and runtime_manifest.name != "",
  "Runtime skill manifest failed to load."
)

Bootstrap.assert!(
  String.contains?(String.downcase(rendered), "calculator"),
  "Rendered prompt missing calculator skill content."
)

Bootstrap.assert!(
  loaded_runtime.instructions =~ "About JAICool" and runtime_resource.content == "About JAICool" and
    listed_resource_id == resource_id and hd(loaded_runtime.resources.references).id == resource_id,
  "Runtime provider-backed skill failed to load."
)

IO.puts("✓ Module and runtime skills loaded")
IO.puts("✓ Registry and prompt rendering validated")
IO.puts("✓ Runtime spec provider resources validated")
