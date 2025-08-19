defmodule Jido.InstructionTest do
  use JidoTest.ActionCase, async: true

  alias Jido.Instruction
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.NoSchema

  @moduletag :capture_log

  describe "normalize/3" do
    test "normalizes single instruction struct" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      assert {:ok, [normalized]} = Instruction.normalize(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "normalizes bare action module" do
      assert {:ok, [instruction]} = Instruction.normalize(BasicAction)
      assert instruction.action == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with map params" do
      assert {:ok, [instruction]} = Instruction.normalize({BasicAction, %{value: 42}})
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with keyword list params" do
      assert {:ok, [instruction]} =
               Instruction.normalize({BasicAction, [value: 42, name: "test"]})

      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42, name: "test"}
      assert instruction.context == %{}
    end

    test "returns error for invalid params list format" do
      assert {:error, %_{} = error} =
               Instruction.normalize({BasicAction, ["not", "a", "keyword", "list"]})

      assert is_exception(error)
    end

    test "normalizes list of mixed formats with different param types" do
      input = [
        BasicAction,
        {NoSchema, %{data: "test"}},
        {BasicAction, [value: 42]},
        %Instruction{action: BasicAction, context: %{local: true}}
      ]

      assert {:ok, [first, second, third, fourth]} =
               Instruction.normalize(input, %{request_id: "123"})

      assert first.action == BasicAction
      assert first.params == %{}
      assert first.context == %{request_id: "123"}

      assert second.action == NoSchema
      assert second.params == %{data: "test"}
      assert second.context == %{request_id: "123"}

      assert third.action == BasicAction
      assert third.params == %{value: 42}
      assert third.context == %{request_id: "123"}

      assert fourth.action == BasicAction
      assert fourth.params == %{}
      assert fourth.context == %{local: true, request_id: "123"}
    end

    test "returns error for invalid params format" do
      assert {:error, %_{} = error} = Instruction.normalize({BasicAction, "invalid"})
      assert is_exception(error)
    end

    test "returns error for invalid instruction format" do
      assert {:error, %_{} = error} = Instruction.normalize(123)
      assert is_exception(error)
    end

    test "merges options from input" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        opts: [timeout: 20_000]
      }

      assert {:ok, [normalized]} = Instruction.normalize(instruction, %{}, retry: true)
      assert normalized.opts == [timeout: 20_000, retry: true]
    end

    test "uses provided options when instruction has none" do
      assert {:ok, [normalized]} = Instruction.normalize(BasicAction, %{}, retry: true)
      assert normalized.opts == [retry: true]
    end

    test "returns error for nested lists" do
      nested_input = [
        BasicAction,
        [NoSchema, {BasicAction, %{value: 1}}]
      ]

      assert {:error, %_{} = error} = Instruction.normalize(nested_input)
      assert is_exception(error)
    end

    test "handles nil context gracefully" do
      assert {:ok, [instruction]} = Instruction.normalize(BasicAction, nil)
      assert instruction.context == %{}
    end

    test "handles empty list" do
      assert {:ok, []} = Instruction.normalize([])
    end

    test "stops on first error in list processing" do
      input = [
        BasicAction,
        # This will cause an error
        123,
        # This shouldn't be processed
        NoSchema
      ]

      assert {:error, %_{} = error} = Instruction.normalize(input)
      assert is_exception(error)
    end
  end

  describe "normalize!/3" do
    test "returns normalized instructions directly" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      [normalized] = Instruction.normalize!(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "raises error for invalid input" do
      assert_raise Jido.Action.Error.ExecutionFailureError, fn ->
        Instruction.normalize!(123)
      end
    end
  end

  describe "validate_allowed_actions/2" do
    test "returns ok when all actions are allowed" do
      instructions = [
        %Instruction{action: BasicAction},
        %Instruction{action: NoSchema}
      ]

      assert :ok = Instruction.validate_allowed_actions(instructions, [BasicAction, NoSchema])
    end

    test "returns error when actions are not allowed" do
      instructions = [
        %Instruction{action: BasicAction},
        %Instruction{action: NoSchema}
      ]

      assert {:error, %_{} = error} =
               Instruction.validate_allowed_actions(instructions, [BasicAction])

      assert is_exception(error)
    end

    test "validates single instruction" do
      instruction = %Instruction{action: BasicAction}
      assert :ok = Instruction.validate_allowed_actions(instruction, [BasicAction])

      assert {:error, %_{} = error} =
               Instruction.validate_allowed_actions(instruction, [NoSchema])

      assert is_exception(error)
    end
  end

  describe "new/2" do
    test "creates instruction with valid action" do
      assert {:ok, instruction} = Instruction.new(%{action: BasicAction})
      assert instruction.action == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
      assert instruction.opts == []
      assert is_binary(instruction.id)
    end

    test "creates instruction with all fields" do
      attrs = %{
        id: "custom-id",
        action: BasicAction,
        params: %{value: 42},
        context: %{user_id: "123"},
        opts: [retry: true]
      }

      assert {:ok, instruction} = Instruction.new(attrs)
      assert instruction.id == "custom-id"
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{user_id: "123"}
      assert instruction.opts == [retry: true]
    end

    test "creates instruction from keyword list" do
      assert {:ok, instruction} = Instruction.new(action: BasicAction, params: %{value: 1})
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 1}
    end

    test "returns error for missing action" do
      assert {:error, :missing_action} = Instruction.new(%{params: %{value: 1}})
    end

    test "returns error for invalid action" do
      assert {:error, :invalid_action} = Instruction.new(%{action: "not_a_module"})
    end

    test "returns error for non-atom action" do
      assert {:error, :invalid_action} = Instruction.new(%{action: 123})
    end
  end

  describe "new!/2" do
    test "creates instruction successfully" do
      instruction = Instruction.new!(%{action: BasicAction, params: %{value: 42}})
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
    end

    test "returns error tuple for missing action" do
      assert {:error, %_{} = error} = Instruction.new!(%{params: %{value: 1}})
      assert is_exception(error)
    end

    test "returns error tuple for invalid action" do
      assert {:error, %_{} = error} = Instruction.new!(%{action: "not_a_module"})
      assert is_exception(error)
    end
  end

  describe "normalize_single/3" do
    test "normalizes instruction struct" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        context: %{local: true}
      }

      assert {:ok, normalized} = Instruction.normalize_single(instruction, %{request_id: "123"})
      assert normalized.action == BasicAction
      assert normalized.params == %{value: 1}
      assert normalized.context == %{local: true, request_id: "123"}
    end

    test "normalizes bare action module" do
      assert {:ok, instruction} = Instruction.normalize_single(BasicAction)
      assert instruction.action == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with map params" do
      assert {:ok, instruction} = Instruction.normalize_single({BasicAction, %{value: 42}})
      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with keyword list params" do
      assert {:ok, instruction} =
               Instruction.normalize_single({BasicAction, [value: 42, name: "test"]})

      assert instruction.action == BasicAction
      assert instruction.params == %{value: 42, name: "test"}
      assert instruction.context == %{}
    end

    test "normalizes action tuple with nil params" do
      assert {:ok, instruction} = Instruction.normalize_single({BasicAction, nil})
      assert instruction.action == BasicAction
      assert instruction.params == %{}
      assert instruction.context == %{}
    end

    test "returns error for invalid params format" do
      assert {:error, %_{} = error} =
               Instruction.normalize_single({BasicAction, "invalid"})

      assert is_exception(error)
    end

    test "returns error for non-keyword list params" do
      assert {:error, %_{} = error} =
               Instruction.normalize_single({BasicAction, ["not", "keyword", "list"]})

      assert is_exception(error)
    end

    test "returns error for invalid instruction format" do
      assert {:error, %_{} = error} = Instruction.normalize_single(123)
      assert is_exception(error)
    end

    test "returns error for list input" do
      assert {:error, %_{} = error} = Instruction.normalize_single([BasicAction])
      assert is_exception(error)
    end

    test "handles nil context in normalize_single" do
      assert {:ok, instruction} = Instruction.normalize_single(BasicAction, nil)
      assert instruction.context == %{}
    end

    test "handles non-atom action in tuple" do
      assert {:error, %_{} = error} = Instruction.normalize_single({"not_atom", %{}})
      assert is_exception(error)
    end

    test "merges options from input" do
      instruction = %Instruction{
        action: BasicAction,
        params: %{value: 1},
        opts: [timeout: 20_000]
      }

      assert {:ok, normalized} = Instruction.normalize_single(instruction, %{}, retry: true)
      assert normalized.opts == [timeout: 20_000, retry: true]
    end

    test "uses provided options when instruction has none" do
      assert {:ok, normalized} = Instruction.normalize_single(BasicAction, %{}, retry: true)
      assert normalized.opts == [retry: true]
    end
  end
end
