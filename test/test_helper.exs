ExUnit.start()

# Ensure our application is started for tests
Application.ensure_all_started(:jido_ai)

if Code.loaded?(Mimic) do
  Mimic.copy(Req)
  Mimic.copy(System)
  Mimic.copy(Instructor)
  Mimic.copy(Instructor.Adapters.Anthropic)
  Mimic.copy(Dotenvy)
  Mimic.copy(Jido.AI.Keyring)
  Mimic.copy(Jido.Agent)
end
