defmodule Jido.AI.Profile.ModelInputTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Error.Validation.Invalid
  alias Jido.AI.Profile

  test "invalid scalar models return the Profile validation error" do
    for model <- [nil, true, false, 0, 1, -1, 1.5] do
      assert {:error, %Invalid{field: "models", message: "models: Invalid ReqLLM model input"}} =
               Profile.new(%{id: :assistant, model: model, result: %{into: :answer}})
    end
  end

  test "invalid named models fail before reasoning and limit validation" do
    assert {:error, %Invalid{field: "models"}} =
             Profile.new(%{
               id: :assistant,
               models: %{answer: %{model: false}},
               reasoning: %{method: :invalid},
               controls: %{timeout: 0},
               result: %{into: :answer}
             })
  end

  test "callable reasoning returns the same tagged model error" do
    profile =
      Profile.new!(%{id: :review, reasoning: :chain_of_thought, result: %{into: :answer}})

    profile = put_in(profile.models.default.model, false)

    assert {:error, %Invalid{field: "models"}} =
             Jido.AI.Actions.Reasoning.RunStrategy.run(%{prompt: "Explain"}, %{jido_ai_callable_profile: profile})
  end

  test "native model specifications remain unchanged in a validated Profile" do
    for model <- [
          "openai:gpt-4.1",
          {:openai, "gpt-4.1", [reasoning_effort: :medium]},
          {:openai, [id: "gpt-4.1"]},
          %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"},
          LLMDB.Model.new!(%{provider: :openai, id: "gpt-4.1"})
        ] do
      assert {:ok, profile} = Profile.new(%{id: :assistant, model: model, result: %{into: :answer}})
      assert profile.models.default.model == model
    end
  end

  test "atom aliases stay inert and registered string aliases normalize" do
    for model <- [:fast, :reasoning, :host_defined_alias] do
      assert {:ok, profile} = Profile.new(%{id: :assistant, model: model, result: %{into: :answer}})
      assert profile.models.default.model == model
    end

    assert {:ok, profile} = Profile.new(%{id: :assistant, model: "fast", result: %{into: :answer}})
    assert profile.models.default.model == :fast
  end
end
