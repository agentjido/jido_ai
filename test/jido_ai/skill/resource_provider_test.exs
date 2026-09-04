defmodule Jido.AI.Skill.ResourceProviderTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Skill.LoadSkill
  alias Jido.AI.Skill.{ResourcePolicy, ResourceProvider, Resources, Spec}

  defmodule CallbackProvider do
    def list(request, context) do
      {:ok,
       %{
         resources: [
           %{id: "s3-object:01J/guide", name: "guide.md", type: :reference, size: 5},
           %{id: "tool://script/run", name: "run.sh", type: :script, size: 3}
         ],
         complete: Map.get(context, :complete?, request.operation == :list)
       }}
    end

    def load(%{resource_id: resource_id}, _context),
      do: {:ok, %{content: "Guide", resource_id: resource_id, size: 5, mime_type: "text/markdown"}}

    def load_with_suffix(%{resource_id: resource_id}, _context, suffix) do
      content = "Guide" <> suffix
      {:ok, %{content: content, resource_id: resource_id, size: byte_size(content)}}
    end
  end

  @runtime_spec %Spec{name: "runtime-skill", description: "Runtime skill.", body_ref: {:inline, "Body."}}

  describe "validate/1" do
    test "accepts function, module/function, and MFA forms" do
      assert {:ok, fun} =
               ResourceProvider.validate(fn _request, _context -> {:ok, %{resources: [], complete: true}} end)

      assert is_function(fun, 2)
      assert {:ok, {CallbackProvider, :list, []}} = ResourceProvider.validate({CallbackProvider, :list})

      assert {:ok, {CallbackProvider, :load_with_suffix, ["!"]}} =
               ResourceProvider.validate({CallbackProvider, :load_with_suffix, ["!"]})
    end

    test "rejects malformed provider forms" do
      assert {:error, {:invalid_resource_provider, :invalid_form}} = ResourceProvider.validate(:not_a_provider)

      assert {:error, {:invalid_resource_provider, :undefined_function}} =
               ResourceProvider.validate({CallbackProvider, :missing})
    end
  end

  describe "list/4" do
    test "normalizes listing entries, forwards public context, and applies policy" do
      parent = self()

      provider = fn request, context ->
        send(parent, {:provider_context, request.operation, context})

        {:ok,
         %{
           resources: [
             %{id: "z://1", name: "z.txt", size: 1},
             %{"id" => "s3-object:01J/guide", "name" => "guide.md", "type" => "reference", "size" => 5},
             %{id: "unicode:λ/文", name: "unicode.md", type: :reference, size: 1}
           ],
           complete: false
         }}
      end

      context = %{
        LoadSkill.context_skills_key() => %{},
        Resources.context_policy_key() => Resources.default_policy(),
        ResourceProvider.context_provider_key() => provider,
        tenant: "acme"
      }

      assert {:ok, listing} = ResourceProvider.list(provider, @runtime_spec, %ResourcePolicy{max_resources: 2}, context)
      assert Enum.map(listing.resources, & &1.id) == ["z://1", "s3-object:01J/guide"]
      assert listing.references |> Enum.map(& &1.id) == ["s3-object:01J/guide"]
      assert Enum.any?(listing.resources, &(&1.id == "s3-object:01J/guide"))
      refute listing.complete
      assert :max_resources in listing.truncation_reasons
      assert :provider_incomplete in listing.truncation_reasons
      assert_receive {:provider_context, :list, %{tenant: "acme"} = forwarded}
      refute Map.has_key?(forwarded, LoadSkill.context_skills_key())
      refute Map.has_key?(forwarded, Resources.context_policy_key())
      refute Map.has_key?(forwarded, ResourceProvider.context_provider_key())
    end

    test "rejects malformed listing results and unsafe entries" do
      assert {:error, :malformed_resource_listing} =
               ResourceProvider.list(
                 fn _, _ -> {:ok, %{resources: []}} end,
                 @runtime_spec,
                 Resources.default_policy(),
                 %{}
               )

      for entry <- [
            %{id: "", name: "empty.md", size: 1},
            %{id: <<0xFF>>, name: "binary.md", size: 1},
            %{id: String.duplicate("a", 1_025), name: "long.md", size: 1},
            %{id: "bad", name: "bad.txt", size: -1},
            %{id: "bad", name: "", size: 1},
            %{id: "bad", name: "bad.txt", type: :unknown, size: 1},
            %{id: "bad", name: "bad.txt", size: 1, modified: false},
            %{id: "bad", name: "bad.txt", size: 1, metadata: false},
            "bad"
          ] do
        provider = fn _, _ -> {:ok, %{resources: [entry], complete: true}} end
        assert {:error, _reason} = ResourceProvider.list(provider, @runtime_spec, Resources.default_policy(), %{})
      end
    end

    test "rejects duplicate provider IDs" do
      provider = fn _, _ ->
        {:ok,
         %{
           resources: [
             %{id: "same-id", name: "one.md", size: 1},
             %{id: "same-id", name: "two.md", size: 2}
           ],
           complete: true
         }}
      end

      assert {:error, :duplicate_resource_id} =
               ResourceProvider.list(provider, @runtime_spec, Resources.default_policy(), %{})
    end

    test "rejects non-encodable listing metadata without raising" do
      provider = fn _, _ ->
        {:ok,
         %{
           resources: [%{id: "bad-metadata", name: "bad.md", size: 1, metadata: %{pid: self()}}],
           complete: true
         }}
      end

      assert {:error, :malformed_resource_listing} =
               ResourceProvider.list(provider, @runtime_spec, Resources.default_policy(), %{})
    end

    test "preserves opaque IDs byte-for-byte without path interpretation" do
      ids = ["s3-object:01J/guide", "https://example.test/a/../b?q=1", " unicode id ", "λ/文"]
      entries = Enum.map(ids, &%{id: &1, name: "guide.md", size: 1})
      provider = fn _, _ -> {:ok, %{resources: entries, complete: true}} end

      assert {:ok, listing} = ResourceProvider.list(provider, @runtime_spec, Resources.default_policy(), %{})
      assert Enum.map(listing.resources, & &1.id) == ids
    end

    test "returns an empty complete listing" do
      provider = fn _, _ -> {:ok, %{resources: [], complete: true}} end
      assert {:ok, listing} = ResourceProvider.list(provider, @runtime_spec, Resources.default_policy(), %{})
      assert listing.resources == []
      assert listing.complete
      refute listing.truncated
    end

    test "applies declared-size and encoded-listing policy with ordered truncation" do
      provider = fn _, _ ->
        {:ok,
         %{
           resources: [
             %{id: "first", name: "first.md", size: 1},
             %{id: "oversized", name: "large.md", size: 6},
             %{id: "small", name: "small.md", size: 1}
           ],
           complete: true
         }}
      end

      assert {:ok, listing} = ResourceProvider.list(provider, @runtime_spec, %ResourcePolicy{max_file_bytes: 5}, %{})
      assert Enum.map(listing.resources, & &1.id) == ["first"]
      assert :max_file_bytes in listing.truncation_reasons

      provider = fn _, _ -> {:ok, %{resources: [%{id: "long-id", name: "long.md", size: 1}], complete: true}} end
      assert {:ok, listing} = ResourceProvider.list(provider, @runtime_spec, %ResourcePolicy{max_listing_bytes: 2}, %{})
      assert listing.resources == []
      assert :max_listing_bytes in listing.truncation_reasons
    end
  end

  describe "load/5" do
    test "loads through function, module/function, and MFA providers" do
      assert {:ok, %{content: "Guide"}} =
               ResourceProvider.load(
                 fn request, context -> CallbackProvider.load(request, context) end,
                 @runtime_spec,
                 "s3-object:01J/guide",
                 Resources.default_policy(),
                 %{}
               )

      assert {:ok, %{content: "Guide"}} =
               ResourceProvider.load(
                 {CallbackProvider, :load},
                 @runtime_spec,
                 "s3-object:01J/guide",
                 Resources.default_policy(),
                 %{}
               )

      assert {:ok, %{content: "Guide!"}} =
               ResourceProvider.load(
                 {CallbackProvider, :load_with_suffix, ["!"]},
                 @runtime_spec,
                 "s3-object:01J/guide",
                 Resources.default_policy(),
                 %{}
               )
    end

    test "round-trips opaque IDs without normalization" do
      parent = self()
      id = " https://bucket.test/a/../b?x=λ "

      provider = fn %{resource_id: resource_id}, _context ->
        send(parent, {:requested_id, resource_id})
        {:ok, %{content: "Guide", resource_id: resource_id, size: 5}}
      end

      assert {:ok, resource} = ResourceProvider.load(provider, @runtime_spec, id, Resources.default_policy(), %{})
      assert resource.resource_id == id
      assert_receive {:requested_id, ^id}
    end

    test "rejects invalid IDs before invoking the provider" do
      provider = fn _, _ -> flunk("provider should not be invoked") end

      assert {:error, :invalid_resource_id} =
               ResourceProvider.load(provider, @runtime_spec, "", Resources.default_policy(), %{})
    end

    test "rejects malformed, oversized, binary, mismatched ID, and mismatched size responses" do
      cases = [
        {fn _, _ -> {:ok, %{content: "Guide", resource_id: "other-id", size: 5}} end, :resource_id_mismatch},
        {fn _, _ -> {:ok, %{content: "Guide", resource_id: "s3-object:01J/guide", size: 4}} end,
         :resource_size_mismatch},
        {fn _, _ -> {:ok, %{content: <<0xFF>>, resource_id: "s3-object:01J/guide", size: 1}} end, :binary_resource},
        {fn _, _ -> {:ok, %{content: "Guide", resource_id: "s3-object:01J/guide"}} end, :malformed_resource},
        {fn _, _ -> {:error, :boom} end, {:resource_provider_failed, :boom}}
      ]

      for {provider, reason} <- cases do
        assert {:error, ^reason} =
                 ResourceProvider.load(provider, @runtime_spec, "s3-object:01J/guide", Resources.default_policy(), %{})
      end

      provider = fn _, _ -> {:ok, %{content: "12345", resource_id: "s3-object:01J/guide", size: 5}} end

      assert {:error, {:resource_too_large, :text, 5, 4}} =
               ResourceProvider.load(
                 provider,
                 @runtime_spec,
                 "s3-object:01J/guide",
                 %ResourcePolicy{max_text_bytes: 4},
                 %{}
               )
    end
  end
end
