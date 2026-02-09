defmodule JidoAITest.Actions.RLM.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.Workspace.{Note, GetSummary}
  alias Jido.AI.RLM.WorkspaceStore

  setup do
    {:ok, workspace_ref} = WorkspaceStore.init("test-#{System.unique_integer()}")
    %{workspace_ref: workspace_ref}
  end

  describe "Note" do
    test "records a finding note and returns summary", %{workspace_ref: ref} do
      params = %{text: "Found relevant data in chunk 3", kind: "finding"}
      context = %{workspace_ref: ref}

      assert {:ok, result} = Note.run(params, context)
      assert result.recorded == true
      assert is_binary(result.workspace_summary)

      workspace = WorkspaceStore.get(ref)
      assert [note] = workspace.notes
      assert note.kind == "finding"
      assert note.text == "Found relevant data in chunk 3"
      assert %DateTime{} = note.at
    end

    test "records a hypothesis note", %{workspace_ref: ref} do
      params = %{text: "Magic number is in the middle", kind: "hypothesis"}
      context = %{workspace_ref: ref}

      assert {:ok, _result} = Note.run(params, context)

      workspace = WorkspaceStore.get(ref)
      assert [note] = workspace.notes
      assert note.kind == "hypothesis"
    end

    test "defaults kind to finding", %{workspace_ref: ref} do
      params = %{text: "Some observation"}
      context = %{workspace_ref: ref}

      assert {:ok, _result} = Note.run(params, context)

      workspace = WorkspaceStore.get(ref)
      assert [note] = workspace.notes
      assert note.kind == "finding"
    end

    test "multiple notes accumulate", %{workspace_ref: ref} do
      context = %{workspace_ref: ref}

      assert {:ok, _} = Note.run(%{text: "First", kind: "hypothesis"}, context)
      assert {:ok, _} = Note.run(%{text: "Second", kind: "finding"}, context)
      assert {:ok, result} = Note.run(%{text: "Third", kind: "plan"}, context)

      workspace = WorkspaceStore.get(ref)
      assert length(workspace.notes) == 3
      assert is_binary(result.workspace_summary)
    end
  end

  describe "GetSummary" do
    test "returns empty summary for fresh workspace", %{workspace_ref: ref} do
      context = %{workspace_ref: ref}

      assert {:ok, result} = GetSummary.run(%{}, context)
      assert is_binary(result.summary)
    end

    test "returns summary after notes are added", %{workspace_ref: ref} do
      context = %{workspace_ref: ref}

      Note.run(%{text: "A hypothesis", kind: "hypothesis"}, context)
      Note.run(%{text: "A finding", kind: "finding"}, context)

      assert {:ok, result} = GetSummary.run(%{}, context)
      assert result.summary =~ "Notes:"
    end

    test "respects max_chars truncation", %{workspace_ref: ref} do
      context = %{workspace_ref: ref}

      for i <- 1..50 do
        Note.run(%{text: "Note number #{i} with some extra text to make it longer", kind: "finding"}, context)
      end

      assert {:ok, result} = GetSummary.run(%{max_chars: 50}, context)
      assert byte_size(result.summary) <= 50
    end

    test "defaults max_chars to 2000", %{workspace_ref: ref} do
      context = %{workspace_ref: ref}

      assert {:ok, result} = GetSummary.run(%{}, context)
      assert byte_size(result.summary) <= 2000
    end
  end
end
