alias JidoAI.Examples.ThreadSessionValues, as: Example

session =
  Example.open_case("case-42", "What changed in this release?")
  |> Example.record_answer("The request and history APIs now use portable values.")

IO.inspect(Example.messages(session), label: "messages")
IO.inspect(Example.export(session), label: "portable session")
