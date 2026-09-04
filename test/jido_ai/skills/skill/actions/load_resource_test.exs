defmodule Jido.AI.Actions.Skill.LoadResourceTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.Skill.{Activation, AgentIntegration, Registry, Resources, Spec}

  @moduletag :tmp_dir

  setup do
    start_supervised!(Registry)
    :ok
  end

  describe "schema" do
    test "accepts exactly one resource selector" do
      assert {:ok, %{name: "resource-skill", resource_id: "opaque-id"}} =
               Zoi.parse(LoadResource.schema(), %{name: "resource-skill", resource_id: "opaque-id"})

      assert {:ok, %{name: "resource-skill", relative_path: "references/guide.md"}} =
               Zoi.parse(LoadResource.schema(), %{
                 name: "resource-skill",
                 relative_path: "references/guide.md"
               })

      assert {:ok, %{name: "resource-skill", path: "references/guide.md"}} =
               Zoi.parse(LoadResource.schema(), %{name: "resource-skill", path: "references/guide.md"})
    end

    test "rejects missing resource selector with a useful selector error" do
      assert {:error, errors} = Zoi.parse(LoadResource.schema(), %{name: "resource-skill"})

      assert selector_error?(errors)
      refute error_message?(errors, "name")
      assert Enum.all?(errors, &(&1.path == []))
    end

    test "rejects multiple resource selectors" do
      selector_sets = [
        %{resource_id: "opaque-id", relative_path: "references/guide.md"},
        %{resource_id: "opaque-id", path: "references/guide.md"},
        %{relative_path: "references/guide.md", path: "references/guide.md"},
        %{resource_id: "opaque-id", relative_path: "references/guide.md", path: "references/guide.md"}
      ]

      for selectors <- selector_sets do
        assert {:error, errors} =
                 LoadResource.schema()
                 |> Zoi.parse(Map.put(selectors, :name, "resource-skill"))

        assert selector_error?(errors)
      end
    end
  end

  describe "run/2" do
    test "loads text only from an activated skill in the same session", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "resource-skill", "agent-a")
      File.mkdir_p!(Path.join(tmp_dir, "references"))
      File.write!(Path.join(tmp_dir, "references/guide.md"), "Guide text")

      assert {:ok, result} =
               LoadResource.run(
                 %{name: "resource-skill", relative_path: "references/guide.md"},
                 %{agent_id: "agent-a"}
               )

      assert result == %{
               skill: "resource-skill",
               path: "references/guide.md",
               content: "Guide text",
               size: 10
             }

      assert {:error, %{type: :skill_not_activated}} =
               LoadResource.run(
                 %{name: "resource-skill", path: "references/guide.md"},
                 %{agent_id: "agent-b"}
               )
    end

    test "requires prior skill activation", %{tmp_dir: _tmp_dir} do
      assert {:error, error} =
               LoadResource.run(%{name: "inactive", path: "guide.md"}, %{agent_id: "agent-a"})

      assert error.type == :skill_not_activated
      assert error.skill == "inactive"
    end

    test "returns structured invalid and missing path errors", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "safe-skill", "safe-agent")
      context = %{agent_id: "safe-agent"}

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "safe-skill", path: "../outside.txt"}, context)

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "safe-skill", path: "SKILL.md"}, context)

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "safe-skill", path: "./SKILL.md"}, context)

      assert {:error, %{type: :resource_not_found}} =
               LoadResource.run(%{name: "safe-skill", path: "missing.txt"}, context)
    end

    test "returns structured oversized and binary errors", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "bounded-skill", "bounded-agent", max_text_bytes: 4)
      File.write!(Path.join(tmp_dir, "large.txt"), "12345")
      File.write!(Path.join(tmp_dir, "binary.bin"), <<0xFF, 0xFE>>)
      File.write!(Path.join(tmp_dir, "nul.bin"), <<0, 0, 0>>)
      context = %{agent_id: "bounded-agent"}

      assert {:error, oversized} =
               LoadResource.run(%{name: "bounded-skill", path: "large.txt"}, context)

      assert oversized.type == :resource_too_large
      assert oversized.limit_kind == :text
      assert oversized.size == 5
      assert oversized.limit == 4

      assert {:error, %{type: :binary_resource}} =
               LoadResource.run(%{name: "bounded-skill", path: "binary.bin"}, context)

      assert {:error, %{type: :binary_resource}} =
               LoadResource.run(%{name: "bounded-skill", path: "nul.bin"}, context)
    end

    test "uses the agent integration policy after load_skill activation", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "integrated-skill")
      File.mkdir_p!(Path.join(skill_dir, "custom"))

      File.write!(
        Path.join(skill_dir, "SKILL.md"),
        "---\nname: integrated-skill\ndescription: Integrated skill.\n---\nInstructions.\n"
      )

      File.write!(Path.join(skill_dir, "custom/data.txt"), "12345")

      assert {:ok, integration} =
               AgentIntegration.prepare(
                 paths: [tmp_dir],
                 trust: true,
                 resource_policy: [max_text_bytes: 4]
               )

      context = Map.put(integration.tool_context, :agent_id, "integrated-agent")
      assert {:ok, loaded} = LoadSkill.run(%{name: "integrated-skill"}, context)
      assert Enum.map(loaded.resources.resources, & &1.relative_path) == ["custom/data.txt"]

      assert {:error, %{type: :resource_too_large, limit: 4}} =
               LoadResource.run(%{name: "integrated-skill", path: "custom/data.txt"}, context)
    end

    test "loads runtime spec resources through the provider with fresh reads and forwarded context" do
      parent = self()
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      spec = %Spec{
        name: "runtime-resource",
        description: "Runtime resource skill.",
        body_ref: {:inline, "Runtime instructions."}
      }

      provider = fn
        %{operation: :list}, context ->
          send(parent, {:provider_context, :list, context})

          {:ok,
           %{resources: [%{id: "s3-object:01J/guide", name: "guide.md", type: :reference, size: 1}], complete: true}}

        %{operation: :load, resource_id: "s3-object:01J/guide"}, context ->
          send(parent, {:provider_context, :load, context})
          value = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
          content = "fresh-#{value}"
          {:ok, %{content: content, resource_id: "s3-object:01J/guide", size: byte_size(content)}}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      context = Map.merge(integration.tool_context, %{agent_id: "runtime-agent", tenant: "acme"})

      assert {:ok, loaded} = LoadSkill.run(%{name: "runtime-resource"}, context)
      assert loaded.instructions == "Runtime instructions."
      assert loaded.root_dir == nil
      assert Enum.map(loaded.resources.resources, & &1.id) == ["s3-object:01J/guide"]

      assert {:ok, first} = LoadResource.run(%{name: "runtime-resource", resource_id: "s3-object:01J/guide"}, context)
      assert {:ok, second} = LoadResource.run(%{name: "runtime-resource", resource_id: "s3-object:01J/guide"}, context)
      assert first.content == "fresh-1"
      assert second.content == "fresh-2"
      assert first.resource_id == "s3-object:01J/guide"

      assert_receive {:provider_context, :list, %{tenant: "acme", agent_id: "runtime-agent"} = list_context}
      assert_receive {:provider_context, :load, %{tenant: "acme", agent_id: "runtime-agent"} = load_context}
      refute Enum.any?(Map.keys(list_context), &(to_string(&1) =~ "__jido_ai"))
      refute Enum.any?(Map.keys(load_context), &(to_string(&1) =~ "__jido_ai"))
    end

    test "returns structured provider and malformed response errors for runtime resources" do
      spec = %Spec{name: "runtime-error", description: "Runtime error.", body_ref: {:inline, "Body."}}

      failing_provider = fn
        %{operation: :list}, _context ->
          {:ok, %{resources: [%{id: "guide-id", name: "guide.md", size: 1}], complete: true}}

        %{operation: :load}, _context ->
          {:error, :boom}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: failing_provider)
      context = Map.put(integration.tool_context, :agent_id, "provider-error-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-error"}, context)

      assert {:error, provider_error} = LoadResource.run(%{name: "runtime-error", resource_id: "guide-id"}, context)
      assert provider_error.type == :resource_load_failed
      assert provider_error.reason == {:resource_provider_failed, :boom}
      assert provider_error.resource_id == "guide-id"
      refute Map.has_key?(provider_error, :path)

      malformed_provider = fn
        %{operation: :list}, _context ->
          {:ok, %{resources: [%{id: "guide-id", name: "guide.md", size: 1}], complete: true}}

        %{operation: :load}, _context ->
          {:ok, %{content: "x", resource_id: "guide-id", size: 2}}
      end

      spec = %{spec | name: "runtime-malformed"}
      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: malformed_provider)
      context = Map.put(integration.tool_context, :agent_id, "provider-malformed-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-malformed"}, context)

      assert {:error, malformed_error} =
               LoadResource.run(%{name: "runtime-malformed", resource_id: "guide-id"}, context)

      assert malformed_error.type == :resource_load_failed
      assert malformed_error.reason == :resource_size_mismatch
      assert malformed_error.resource_id == "guide-id"
      refute Map.has_key?(malformed_error, :path)
    end

    test "uses resource_id in provider-specific resource errors" do
      cases = [
        {"too-large", "12345", {:resource_too_large, :text, 5, 4}, :resource_too_large},
        {"binary", <<0xFF>>, :binary_resource, :binary_resource}
      ]

      for {suffix, content, expected_reason, expected_type} <- cases do
        name = "runtime-#{suffix}"
        spec = %Spec{name: name, description: "Runtime #{suffix}.", body_ref: {:inline, "Body."}}

        provider = fn
          %{operation: :list}, _context ->
            {:ok, %{resources: [%{id: "guide-id", name: "guide.md", size: byte_size(content)}], complete: true}}

          %{operation: :load}, _context ->
            {:ok, %{content: content, resource_id: "guide-id", size: byte_size(content)}}
        end

        assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
        context = Map.put(integration.tool_context, :agent_id, "provider-#{suffix}-agent")

        context =
          if suffix == "too-large" do
            Map.put(context, Resources.context_policy_key(), %{max_text_bytes: 4})
          else
            context
          end

        assert {:ok, _loaded} = LoadSkill.run(%{name: name}, context)

        assert {:error, error} = LoadResource.run(%{name: name, resource_id: "guide-id"}, context)
        assert error.type == expected_type
        assert error.resource_id == "guide-id"
        refute Map.has_key?(error, :path)

        if expected_type == :resource_load_failed do
          assert error.reason == expected_reason
        end
      end
    end

    test "rejects unknown provider IDs without invoking the provider" do
      parent = self()
      spec = %Spec{name: "runtime-unknown", description: "Runtime unknown.", body_ref: {:inline, "Body."}}

      provider = fn
        %{operation: :list}, _context ->
          {:ok, %{resources: [%{id: "known-id", name: "guide.md", size: 5}], complete: false}}

        %{operation: :load}, _context ->
          send(parent, :provider_load_invoked)
          {:error, :boom}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      context = Map.put(integration.tool_context, :agent_id, "runtime-unknown-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-unknown"}, context)

      assert {:error, unknown_error} =
               LoadResource.run(%{name: "runtime-unknown", resource_id: "missing-id"}, context)

      assert unknown_error.type == :resource_not_found
      assert unknown_error.resource_id == "missing-id"
      refute Map.has_key?(unknown_error, :path)

      refute_received :provider_load_invoked
    end

    test "rejects provider IDs listed for a different runtime skill" do
      parent = self()

      specs = [
        %Spec{name: "runtime-alpha", description: "Runtime alpha.", body_ref: {:inline, "Alpha."}},
        %Spec{name: "runtime-beta", description: "Runtime beta.", body_ref: {:inline, "Beta."}}
      ]

      provider = fn
        %{operation: :list, skill: %{name: "runtime-alpha"}}, _context ->
          {:ok, %{resources: [%{id: "alpha-id", name: "alpha.md", size: 5}], complete: true}}

        %{operation: :list, skill: %{name: "runtime-beta"}}, _context ->
          {:ok, %{resources: [%{id: "beta-id", name: "beta.md", size: 4}], complete: true}}

        %{operation: :load}, _context ->
          send(parent, :provider_load_invoked)
          {:error, :boom}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: specs, resource_provider: provider)
      context = Map.put(integration.tool_context, :agent_id, "runtime-cross-skill-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-alpha"}, context)
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-beta"}, context)

      assert {:error, cross_skill_error} =
               LoadResource.run(%{name: "runtime-beta", resource_id: "alpha-id"}, context)

      assert cross_skill_error.type == :resource_not_found
      assert cross_skill_error.resource_id == "alpha-id"
      refute Map.has_key?(cross_skill_error, :path)

      refute_received :provider_load_invoked
    end

    test "rejects provider selectors that use filesystem paths" do
      spec = %Spec{name: "runtime-selector", description: "Runtime selector.", body_ref: {:inline, "Body."}}
      provider = fn %{operation: :list}, _context -> {:ok, %{resources: [], complete: true}} end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      context = Map.put(integration.tool_context, :agent_id, "runtime-selector-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-selector"}, context)

      assert {:error, %{type: :invalid_resource_id, reason: :invalid_provider_selector}} =
               LoadResource.run(%{name: "runtime-selector", relative_path: "guide.md"}, context)
    end

    test "rejects resource_id selectors for filesystem-backed skills", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "filesystem-selector", "filesystem-selector-agent")

      assert {:error, %{type: :invalid_resource_path, reason: :invalid_filesystem_selector}} =
               LoadResource.run(%{name: "filesystem-selector", resource_id: "opaque-id"}, %{
                 agent_id: "filesystem-selector-agent"
               })
    end

    test "loads provider resources through action execution with string-keyed arguments" do
      parent = self()
      resource_id = "b7754895-90f8-4594-b6be-c80fd0859545"
      spec = %Spec{name: "about-jaicool", description: "About JAICool.", body_ref: {:inline, "Body."}}

      provider = fn
        %{operation: :list}, _context ->
          {:ok, %{resources: [%{id: resource_id, name: "about.md", size: 13}], complete: true}}

        %{operation: :load, resource_id: ^resource_id}, _context ->
          send(parent, {:provider_resource_id, resource_id})
          {:ok, %{content: "About JAICool", resource_id: resource_id, size: 13}}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      context = Map.put(integration.tool_context, :agent_id, "tool-provider-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "about-jaicool"}, context)

      assert {:ok, payload} =
               Jido.Action.Tool.execute_action(
                 LoadResource,
                 %{"name" => "about-jaicool", "resource_id" => resource_id},
                 context
               )

      assert {:ok, result} = Jason.decode(payload)
      assert result["skill"] == "about-jaicool"
      assert result["resource_id"] == resource_id
      assert result["content"] == "About JAICool"
      assert_receive {:provider_resource_id, ^resource_id}
    end

    test "loads filesystem resources through action execution with relative_path and legacy path", %{tmp_dir: tmp_dir} do
      activate_skill(tmp_dir, "tool-filesystem", "tool-filesystem-agent")
      File.mkdir_p!(Path.join(tmp_dir, "references"))
      File.write!(Path.join(tmp_dir, "references/guide.md"), "Guide text")
      File.write!(Path.join(tmp_dir, "legacy.txt"), "Legacy text")
      context = %{agent_id: "tool-filesystem-agent"}

      assert {:ok, relative_payload} =
               Jido.Action.Tool.execute_action(
                 LoadResource,
                 %{"name" => "tool-filesystem", "relative_path" => "references/guide.md"},
                 context
               )

      assert {:ok, relative_result} = Jason.decode(relative_payload)
      assert relative_result["skill"] == "tool-filesystem"
      assert relative_result["path"] == "references/guide.md"
      assert relative_result["content"] == "Guide text"

      assert {:ok, path_payload} =
               Jido.Action.Tool.execute_action(
                 LoadResource,
                 %{"name" => "tool-filesystem", "path" => "legacy.txt"},
                 context
               )

      assert {:ok, path_result} = Jason.decode(path_payload)
      assert path_result["skill"] == "tool-filesystem"
      assert path_result["path"] == "legacy.txt"
      assert path_result["content"] == "Legacy text"
    end

    test "surfaces provider listing failures through load_skill" do
      spec = %Spec{name: "runtime-list-fail", description: "Runtime list fail.", body_ref: {:inline, "Body."}}
      provider = fn %{operation: :list}, _context -> {:error, :listing_failed} end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      context = Map.put(integration.tool_context, :agent_id, "runtime-list-fail-agent")

      assert {:error, %{type: :skill_activation_failed, reason: {:resource_provider_failed, :listing_failed}}} =
               LoadSkill.run(%{name: "runtime-list-fail"}, context)
    end

    test "provider-backed resources remain scoped by agent session" do
      spec = %Spec{name: "runtime-scoped", description: "Runtime scoped.", body_ref: {:inline, "Body."}}

      provider = fn
        %{operation: :list}, _context ->
          {:ok, %{resources: [%{id: "guide-id", name: "guide.md", size: 5}], complete: true}}

        %{operation: :load}, _context ->
          {:ok, %{content: "Guide", resource_id: "guide-id", size: 5}}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      agent_a_context = Map.put(integration.tool_context, :agent_id, "runtime-agent-a")
      agent_b_context = Map.put(integration.tool_context, :agent_id, "runtime-agent-b")

      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-scoped"}, agent_a_context)

      assert {:ok, %{content: "Guide"}} =
               LoadResource.run(%{name: "runtime-scoped", resource_id: "guide-id"}, agent_a_context)

      assert {:error, %{type: :skill_not_activated}} =
               LoadResource.run(%{name: "runtime-scoped", resource_id: "guide-id"}, agent_b_context)
    end

    test "rejects provider path selectors before invocation" do
      parent = self()
      spec = %Spec{name: "runtime-safe", description: "Runtime safe.", body_ref: {:inline, "Body."}}

      provider = fn
        %{operation: :list}, _context ->
          {:ok, %{resources: [], complete: true}}

        %{operation: :load}, _context ->
          send(parent, :load_invoked)
          {:error, :boom}
      end

      assert {:ok, integration} = AgentIntegration.prepare(specs: [spec], resource_provider: provider)
      context = Map.put(integration.tool_context, :agent_id, "runtime-safe-agent")
      assert {:ok, _loaded} = LoadSkill.run(%{name: "runtime-safe"}, context)

      assert {:error, %{type: :invalid_resource_id, reason: :invalid_provider_selector}} =
               LoadResource.run(%{name: "runtime-safe", path: "../secret.txt"}, context)

      refute_received :load_invoked
    end

    test "rejects invalid parameters", %{tmp_dir: tmp_dir} do
      assert {:error, %{type: :invalid_params}} = LoadResource.run([], %{})
      assert {:error, %{type: :invalid_skill_name}} = LoadResource.run(%{path: "file.txt"}, %{})

      activate_skill(tmp_dir, "valid-name", "invalid-param-agent")

      assert {:error, %{type: :invalid_resource_path}} =
               LoadResource.run(%{name: "valid-name", path: ""}, %{agent_id: "invalid-param-agent"})
    end
  end

  defp activate_skill(root, name, session_id, policy_opts \\ []) do
    skill_path = Path.join(root, "SKILL.md")
    File.write!(skill_path, "instructions")

    spec = %Spec{
      name: name,
      description: "Resource test skill.",
      body_ref: {:inline, "instructions"},
      source: {:file, skill_path}
    }

    assert {:ok, _activation} =
             Activation.activate(spec, session_id: session_id, resource_policy: policy_opts)
  end

  defp selector_error?(errors) do
    error_message?(errors, "exactly one of resource_id, relative_path, or path is required")
  end

  defp error_message?(errors, message) do
    Enum.any?(List.wrap(errors), fn error ->
      error
      |> Map.get(:message, "")
      |> String.contains?(message)
    end)
  end
end
