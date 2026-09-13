defmodule Jido.AI.Examples.Tools.AgentGuildVerifyPassport do
  @moduledoc """
  Requests verification of a supplied public Agent Guild passport.

  Expected issuer and subject must be independently known by the caller, not copied
  from the passport to establish trust. The complete validated original JSON text is
  sent to the fixed Guild verifier; verification attempts are logged by the service.
  No identity is registered, passport fetched, or payment made by this action.
  """

  use Jido.Action,
    name: "agent_guild_verify_passport",
    description:
      "Verify a supplied public passport against separately expected DIDs and a fixed freshness policy. Signature integrity is not safety.",
    schema:
      Zoi.object(%{
        credential_json:
          Zoi.string(
            description:
              "Complete shareable AgentGuildPassport JSON object, including proof; transmitted unchanged after validation."
          ),
        expected_issuer:
          Zoi.string(description: "Independently selected trusted issuer did:key, not trust on first use."),
        expected_subject: Zoi.string(description: "Independently known intended counterparty did:key.")
      })

  @doc "Returns verifier flags with bindings, or fixed unavailable output; never returns raw claims."
  @impl Jido.Action
  def run(params, _context), do: Jido.AI.Examples.Tools.AgentGuild.verify_passport(params)
end
