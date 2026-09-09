defmodule Jido.AI.Authoring.Codec do
  @moduledoc """
  Imports source AI profiles through a trusted core Agent Registry.

  This format stores profile data before lowering. It is separate from the
  lowered Agent document. The profile body uses the core tagged-data format to
  retain keyword lists, known atoms and registered static values such as schemas
  and rich model records. It cannot import code or create atoms.

  Supply stable host Registry IDs for stored documents. Decoding calls the same
  `Jido.AI.Authoring.lower/2` boundary as direct authoring.
  """
  alias Jido.Agent.Codec.{Data, Registry}
  alias Jido.AI.Profile

  @doc "Encodes source profiles through a host-owned Registry."
  def encode(profiles, registry) do
    with {:ok, registry} <- Registry.new(registry),
         {:ok, profiles} <- Profile.traverse(profiles, &source/1),
         {:ok, profiles} <- Data.encode(profiles, registry),
         document = %{"type" => "jido.ai.profiles", "version" => 1, "profiles" => profiles},
         :ok <- Data.check_document(document),
         do: {:ok, document}
  end

  @doc "Decodes source profiles and lowers them into a neutral core Agent."
  def decode(agent, document, registry) do
    with :ok <- Data.check_document(document),
         :ok <- Data.object(document, ~w(type version profiles)),
         :ok <- Data.version(document, "jido.ai.profiles"),
         {:ok, registry} <- Registry.new(registry),
         {:ok, profiles} <- Data.decode(document["profiles"], registry),
         do: Jido.AI.Authoring.lower(agent, profiles)
  end

  defp source(value) do
    with {:ok, {profile, routes}} <- Profile.source(value) do
      data = profile |> Map.from_struct() |> Map.put(:routes, routes)

      data =
        if profile.tool_interceptor == nil, do: Map.delete(data, :tool_interceptor), else: data

      data = if profile.skills == nil, do: Map.delete(data, :skills), else: data
      data = if profile.tool_context == %{}, do: Map.delete(data, :tool_context), else: data

      {:ok, data}
    end
  end
end
