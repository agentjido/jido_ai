ExUnit.start()

# Ensure our application is started for tests
Application.ensure_all_started(:jido_ai)

if Code.loaded?(Mimic) do
  Mimic.copy(Req)
  Mimic.copy(System)
  Mimic.copy(Instructor)
  Mimic.copy(Instructor.Adapters.Anthropic)
  Mimic.copy(LangChain.ChatModels.ChatOpenAI)
  Mimic.copy(LangChain.ChatModels.ChatAnthropic)
  Mimic.copy(LangChain.Chains.LLMChain)
  Mimic.copy(Finch)
  Mimic.copy(OpenaiEx)
  Mimic.copy(OpenaiEx.Chat.Completions)
  Mimic.copy(OpenaiEx.Embeddings)
  Mimic.copy(OpenaiEx.Images)
  Mimic.copy(Dotenvy)
  Mimic.copy(Jido.AI.Keyring)
  Mimic.copy(Jido.Workflow)
  Mimic.copy(Jido.AI.Actions.Instructor)
  Mimic.copy(Jido.AI.Actions.Langchain)
  Mimic.copy(Jido.AI.Actions.OpenaiEx)
end
