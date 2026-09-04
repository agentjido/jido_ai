defmodule Jido.AI.Skill.BinaryResourcesTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.Skill.{LoadResource, LoadSkill}
  alias Jido.AI.{Context, Turn}
  alias Jido.AI.Skill.{Activation, AgentIntegration, Registry, ResourcePolicy, ResourceProvider, Resources, Spec}
  alias ReqLLM.Message.ContentPart

  @moduletag :tmp_dir
  @png <<137, "PNG", 13, 10, 26, 10, 0, 255>>
  @pdf "%PDF-1.7\nA small PDF fixture."
  @specimen %Spec{name: "binary-skill", description: "Binary resource test", body_ref: {:inline, "Instructions"}}

  setup do
    start_supervised!(Registry)
    :ok
  end

  test "text and scripts use the text limit, while images and files use the file limit" do
    policy = %ResourcePolicy{binary: :allow, max_text_bytes: 4}

    assert {:error, {:resource_too_large, :text, 5, 4}} =
             Resources.validate_loaded_resource(resource("hello", "script.ex", nil), policy)

    for {bytes, name, mime, kind} <- [
          {@png, "plot.png", "image/png", :image},
          {<<255, 216, 255, 0>>, "plot.jpg", "image/jpeg", :image},
          {"GIF89a", "plot.gif", "image/gif", :image},
          {<<"RIFF", 0, 0, 0, 0, "WEBP">>, "plot.webp", "image/webp", :image},
          {@pdf, "report.pdf", "application/pdf", :file},
          {<<0, 255, 1>>, "program.bin", "application/octet-stream", :file}
        ] do
      input = resource(bytes, name, mime)
      assert {:ok, %{kind: ^kind, content: ^bytes}} = Resources.validate_loaded_resource(input, policy)
      assert {:error, :binary_resource} = Resources.validate_loaded_resource(input, ResourcePolicy.default())

      assert {:error, {:resource_too_large, :file, _, 1}} =
               Resources.validate_loaded_resource(input, %{policy | max_file_bytes: 1})
    end
  end

  test "text wrappers remain text-only under an allow policy" do
    policy = %ResourcePolicy{binary: :allow}
    assert :ok = Resources.validate_loaded_text(resource("x = 1", "code.ex", nil), policy)

    assert {:error, :binary_resource} =
             Resources.validate_loaded_text(resource(@pdf, "doc.pdf", "application/pdf"), policy)
  end

  test "shared validation rejects inconsistent size, MIME and filename metadata" do
    policy = %ResourcePolicy{binary: :allow}
    valid = resource(@png, "plot.png", "image/png")

    assert {:ok, %{mime_type: "image/png"}} =
             Resources.validate_loaded_resource(%{valid | mime_type: "IMAGE/PNG"}, policy)

    assert {:error, :resource_size_mismatch} = Resources.validate_loaded_resource(%{valid | size: 0}, policy)

    assert {:error, :resource_mime_mismatch} =
             Resources.validate_loaded_resource(%{valid | mime_type: "image/jpeg"}, policy)

    assert {:error, :resource_mime_mismatch} =
             Resources.validate_loaded_resource(%{valid | filename: "doc.pdf"}, policy)

    assert {:error, :resource_mime_mismatch} =
             Resources.validate_loaded_resource(resource("plain text", "plot.png", "image/png"), policy)

    assert {:error, :invalid_resource_mime_type} = Resources.validate_loaded_resource(%{valid | mime_type: nil}, policy)

    for name <- [nil, "", "../plot.png", "bad\0.png", false] do
      assert {:error, :invalid_resource_filename} =
               Resources.validate_loaded_resource(%{valid | filename: name}, policy)
    end
  end

  test "filesystem and provider resources use the same content contract", %{tmp_dir: root} do
    policy = %ResourcePolicy{binary: :allow, max_text_bytes: 1}
    File.write!(Path.join(root, "report.pdf"), @pdf)
    assert {:ok, from_file} = Resources.load(root, "report.pdf", policy)
    provider = fn _, _ -> {:ok, Map.put(resource(@pdf, "report.pdf", "application/pdf"), :resource_id, "opaque")} end
    assert {:ok, from_provider} = ResourceProvider.load(provider, @specimen, "opaque", policy, %{})

    for key <- [:kind, :content, :size, :mime_type, :filename] do
      assert from_file[key] == from_provider[key]
    end

    assert from_file.selector == {:path, "report.pdf"}
    assert from_provider.selector == {:resource_id, "opaque"}
  end

  test "filesystem loader rejects mismatched names, symlinks and traversal", %{tmp_dir: root} do
    File.write!(Path.join(root, "wrong.png"), @pdf)
    File.write!(Path.join(root, "program.bin"), <<0, 255>>)
    File.ln_s!("program.bin", Path.join(root, "link.bin"))
    assert {:error, :resource_mime_mismatch} = Resources.load(root, "wrong.png", binary: :allow)
    assert {:error, _} = Resources.load(root, "link.bin", binary: :allow)
    assert {:error, _} = Resources.load(root, "../outside", binary: :allow)

    assert {:ok, %{kind: :file, mime_type: "application/octet-stream"}} =
             Resources.load(root, "program.bin", binary: :allow)
  end

  test "existing provider text responses need no filename" do
    provider = fn _, _ -> {:ok, %{resource_id: "text", content: "Guide", size: 5}} end

    assert {:ok, %{kind: :text, content: "Guide", filename: nil}} =
             ResourceProvider.load(provider, @specimen, "text", ResourcePolicy.default(), %{})
  end

  test "binary provider responses retain ID and size checks" do
    policy = %ResourcePolicy{binary: :allow}
    input = Map.put(resource(@png, "plot.png", "image/png"), :resource_id, "id")
    provider = fn _, _ -> {:ok, %{input | size: 1}} end
    assert {:error, :resource_size_mismatch} = ResourceProvider.load(provider, @specimen, "id", policy, %{})
    provider = fn _, _ -> {:ok, input} end
    assert {:error, :resource_id_mismatch} = ResourceProvider.load(provider, @specimen, "other", policy, %{})
  end

  test "images and PDFs pass from LoadResource through Turn into Context without bytes in JSON", %{tmp_dir: root} do
    File.write!(Path.join(root, "SKILL.md"), "instructions")
    spec = %{@specimen | source: {:file, Path.join(root, "SKILL.md")}}
    assert {:ok, _} = Activation.activate(spec, session_id: "binary-session", resource_policy: [binary: :allow])

    for {bytes, name, kind} <- [{@png, "plot.png", :image}, {@pdf, "report.pdf", :file}] do
      File.write!(Path.join(root, name), bytes)

      assert {:ok, output, []} =
               Turn.execute_module(LoadResource, %{name: spec.name, path: name}, %{agent_id: "binary-session"})

      refute Map.has_key?(output, :content)
      assert [%ContentPart{type: ^kind, data: ^bytes}] = output.__content_parts__

      assert [%ContentPart{type: :text, text: json}, %ContentPart{type: ^kind, data: ^bytes}] =
               parts = Turn.format_tool_result_content({:ok, output})

      assert {:ok, _} = Jason.decode(json)
      refute String.contains?(json, bytes)
      thread = Context.append_tool_result(Context.new(), "call-1", LoadResource.name(), parts)
      assert [%{content: ^parts}] = Context.to_messages(thread)
    end
  end

  test "provider-backed actions emit attachments only for authorized IDs" do
    parent = self()
    input = Map.put(resource(@png, "plot.png", "image/png"), :resource_id, "allowed")

    provider = fn
      %{operation: :list}, _ ->
        {:ok, %{resources: [%{id: "allowed", name: "plot.png", size: byte_size(@png)}], complete: true}}

      %{operation: :load}, _ ->
        send(parent, :loaded)
        {:ok, input}
    end

    assert {:ok, integration} =
             AgentIntegration.prepare(
               specs: [@specimen],
               resource_provider: provider,
               resource_policy: [binary: :allow]
             )

    context = Map.put(integration.tool_context, :agent_id, "provider-binary-session")
    assert {:ok, _} = LoadSkill.run(%{name: @specimen.name}, context)

    assert {:error, %{type: :resource_not_found}} =
             LoadResource.run(%{name: @specimen.name, resource_id: "denied"}, context)

    refute_received :loaded

    assert {:ok, %{resource_id: "allowed", filename: "plot.png", __content_parts__: [%ContentPart{type: :image}]}} =
             LoadResource.run(%{name: @specimen.name, resource_id: "allowed"}, context)

    assert_received :loaded
  end

  defp resource(content, filename, mime_type),
    do: %{content: content, size: byte_size(content), filename: filename, mime_type: mime_type}
end
