Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Actions.LLM.{Chat, Complete, GenerateObject}
alias Jido.AI.Examples.Scripts.Bootstrap

Bootstrap.init!(required_env: ["ANTHROPIC_API_KEY"])
Bootstrap.print_banner("Actions LLM Runtime Demo")

{:ok, chat} = Jido.Exec.run(Chat, %{prompt: "Summarize Elixir in one sentence."})
chat_text = Map.get(chat, :text, "")
Bootstrap.assert!(is_binary(chat_text) and String.length(chat_text) > 10, "Chat action returned empty text.")

{:ok, complete} = Jido.Exec.run(Complete, %{prompt: "The key feature of OTP is"})
complete_text = Map.get(complete, :text, "")

Bootstrap.assert!(
  is_binary(complete_text) and String.length(complete_text) > 10,
  "Complete action returned empty text."
)

schema = Zoi.object(%{title: Zoi.string(), confidence: Zoi.float()})

{:ok, generated} =
  Jido.Exec.run(GenerateObject, %{prompt: "Return title/confidence for note: Jido AI roadmap", object_schema: schema})

Bootstrap.assert!(is_map(generated), "GenerateObject action did not return a map payload.")

IO.puts("✓ LLM actions chat/complete/generate_object passed")
