defmodule JidoAI.Examples.Controls.MemberOnly do
  @moduledoc "Allows requests from members."

  use Jido.Action,
    name: "member_only",
    description: "Allow requests from members",
    schema: Zoi.object(%{input: Zoi.string()})

  @impl Jido.Action
  def run(_params, %{role: :member}), do: {:ok, %{allowed: true}}
  def run(_params, _context), do: {:error, :access_denied}
end

defmodule JidoAI.Examples.Controls.Agent do
  @moduledoc "A response with checks before and after the model call."

  use Jido.AI.Agent, name: "controls_example"

  ai do
    model :fast
    instructions "Answer with a source marker."

    controls do
      timeout 5_000
      max_iterations 1
      max_model_calls 1
      max_tool_calls 1
      input JidoAI.Examples.Controls.MemberOnly

      output_action %{output: output},
        name: "require_source",
        description: "Require a source marker in generated text",
        schema: Zoi.object(%{output: Zoi.string()}) do
        if String.contains?(output, "[source]"),
          do: {:ok, %{accepted: true}},
          else: {:error, :source_required}
      end
    end
  end
end
