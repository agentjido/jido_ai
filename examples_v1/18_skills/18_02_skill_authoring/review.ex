defmodule JidoAI.Examples.SkillAuthoring.Review do
  use Jido.AI.Skill,
    name: "review",
    description: "Review a document.",
    metadata: %{owner: :native_module},
    actions: [JidoAI.Examples.SkillAuthoring.Echo],
    body: "Module review instructions"
end
