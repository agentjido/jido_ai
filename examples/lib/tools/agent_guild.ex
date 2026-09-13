defmodule Jido.AI.Examples.Tools.AgentGuild do
  @moduledoc false

  @origin "https://agent-guild-5d5r.onrender.com"
  @body_limit 65_536
  @deadline_ms 6_000
  @checks ~w(endpoint_reachable protocol_handshake agent_card_resolves agent_card_signed payment_claim_holds independent_evidence)
  @note "Advisory observation only. No safety, ownership, task quality, payment, or delegation authorization is established."

  def preflight(params) do
    with {:ok, %{target: target}} <- fields(params, [:target]),
         :ok <- target(target),
         {:ok, response} <- request(:get, "/preflight?" <> URI.encode_query(%{"url" => target}), ""),
         {:ok, result} <- project_preflight(response, target) do
      {:ok, result}
    else
      {:error, reason} -> unavailable(reason)
    end
  end

  def verify_passport(params) do
    with {:ok, inputs} <- fields(params, [:credential_json, :expected_issuer, :expected_subject]),
         :ok <- did(inputs.expected_issuer),
         :ok <- did(inputs.expected_subject),
         {:ok, credential} <- decode(inputs.credential_json),
         :ok <- passport(credential, inputs),
         {:ok, response} <- request(:post, "/credentials/verify", inputs.credential_json),
         :ok <- dates(credential),
         {:ok, result} <- project_passport(response, inputs) do
      {:ok, result}
    else
      {:error, reason} -> unavailable(reason)
    end
  end

  defp unavailable(reason),
    do: {:ok, %{status: :unavailable, reason: reason, note: @note}}

  defp fields(params, keys) when is_map(params) and not is_struct(params) do
    if map_size(params) == length(keys) and Enum.all?(keys, &Map.has_key?(params, &1)) do
      {:ok, params}
    else
      {:error, :invalid_parameters}
    end
  end

  defp fields(_, _), do: {:error, :invalid_parameters}

  defp target(value) when is_binary(value) and byte_size(value) in 1..2048 do
    with true <- String.valid?(value),
         false <- String.contains?(value, ["\\", "#"]),
         false <- Regex.match?(~r/[\s\x00-\x20\x7f]/u, value),
         {:ok, uri} <- URI.new(value),
         true <- uri.scheme in ["http", "https"] and is_binary(uri.host),
         true <- is_nil(uri.userinfo) and uri.port in 1..65_535,
         true <- public_host?(String.downcase(uri.host)) do
      :ok
    else
      _ -> {:error, :invalid_public_target}
    end
  end

  defp target(_), do: {:error, :invalid_public_target}

  defp public_host?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {a, b, c, _d}} ->
        a not in [0, 10, 127] and a < 224 and
          not (a == 100 and b in 64..127) and
          not (a == 169 and b == 254) and not (a == 172 and b in 16..31) and
          not (a == 192 and (b in [0, 168] or (b == 0 and c == 2))) and
          not (a == 198 and (b in [18, 19] or (b == 51 and c == 100))) and
          not (a == 203 and b == 0 and c == 113)

      {:ok, {a, b, _, _, _, _, _, _}} ->
        # Global unicast only; reject mapped IPv4, loopback, local and documentation ranges.
        a in 0x2000..0x3FFF and not (a == 0x2001 and (b == 0x0DB8 or b < 0x0200))

      {:error, _} ->
        String.contains?(host, ".") and byte_size(host) <= 253 and
          not Regex.match?(~r/^[0-9.]+$/, host) and
          not Regex.match?(~r/(^|\.)(localhost|local|internal|localdomain|invalid|test)\.?$/, host) and
          Enum.all?(String.split(host, "."), &Regex.match?(~r/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/, &1))
    end
  end

  defp did(value) when is_binary(value) and byte_size(value) <= 128 do
    if Regex.match?(~r/^did:key:z[1-9A-HJ-NP-Za-km-z]{46,60}$/, value),
      do: :ok,
      else: {:error, :invalid_expected_did}
  end

  defp did(_), do: {:error, :invalid_expected_did}

  defp decode(text) when is_binary(text) and byte_size(text) in 1..@body_limit do
    with true <- String.valid?(text),
         :ok <- depth(text, 0, false, false),
         {:ok, value} <- Jason.decode(text, objects: :ordered_objects),
         {:ok, result} <- unique(value),
         true <- is_map(result) do
      {:ok, result}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_json_object}
    end
  rescue
    _ -> {:error, :invalid_json_object}
  end

  defp decode(_), do: {:error, :invalid_json_size_or_type}

  # Bound nesting before the decoder allocates a recursive structure. Jason still validates syntax.
  defp depth(_, level, _, _) when level > 16, do: {:error, :json_too_deep}
  defp depth(<<>>, _, _, _), do: :ok
  defp depth(<<_c, rest::binary>>, level, true, true), do: depth(rest, level, true, false)
  defp depth(<<?\\, rest::binary>>, level, true, false), do: depth(rest, level, true, true)
  defp depth(<<?", rest::binary>>, level, quoted, false), do: depth(rest, level, not quoted, false)
  defp depth(<<c, rest::binary>>, level, false, _) when c in [?{, ?[], do: depth(rest, level + 1, false, false)
  defp depth(<<c, rest::binary>>, level, false, _) when c in [?}, ?]], do: depth(rest, level - 1, false, false)
  defp depth(<<_c, rest::binary>>, level, quoted, escaped), do: depth(rest, level, quoted, escaped)

  defp unique(%Jason.OrderedObject{values: pairs}) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with false <- Map.has_key?(acc, key), {:ok, item} <- unique(value) do
        {:cont, {:ok, Map.put(acc, key, item)}}
      else
        true -> {:halt, {:error, :duplicate_json_key}}
        error -> {:halt, error}
      end
    end)
  end

  defp unique(items) when is_list(items) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case unique(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp unique(value), do: {:ok, value}

  defp passport(vc, inputs) do
    proof = vc["proof"]
    subject = vc["credentialSubject"]
    issuer = inputs.expected_issuer

    with true <- vc["@context"] == ["https://www.w3.org/ns/credentials/v2"],
         true <- vc["type"] == ["VerifiableCredential", "AgentGuildPassport"],
         true <- vc["issuer"] == issuer,
         true <- is_map(subject) and subject["id"] == inputs.expected_subject,
         true <- is_map(proof) and proof["type"] == "DataIntegrityProof",
         true <- proof["cryptosuite"] == "eddsa-jcs-2022" and proof["proofPurpose"] == "assertionMethod",
         true <- proof["@context"] == vc["@context"],
         true <- proof["verificationMethod"] == issuer <> "#" <> String.replace_prefix(issuer, "did:key:", ""),
         true <-
           is_binary(proof["proofValue"]) and Regex.match?(~r/^z[1-9A-HJ-NP-Za-km-z]{80,100}$/, proof["proofValue"]),
         true <- proof["created"] == vc["validFrom"],
         :ok <- dates(vc) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :passport_binding_or_format}
    end
  end

  defp dates(vc) do
    now = DateTime.utc_now()

    with {:ok, issued, _} <- DateTime.from_iso8601(vc["validFrom"] || ""),
         comparison when comparison in [:eq, :gt] <- DateTime.compare(now, issued),
         age when age >= 0 and age <= 86_400 <- DateTime.diff(now, issued),
         :ok <- expiration(Map.get(vc, "validUntil", :absent), issued, now) do
      :ok
    else
      _ -> {:error, :passport_date_or_freshness}
    end
  rescue
    _ -> {:error, :passport_date_or_freshness}
  end

  defp expiration(:absent, _, _), do: :ok

  defp expiration(value, issued, now) when is_binary(value) do
    with {:ok, expires, _} <- DateTime.from_iso8601(value),
         :gt <- DateTime.compare(expires, issued),
         :gt <- DateTime.compare(expires, now) do
      :ok
    else
      _ -> {:error, :expired_passport}
    end
  end

  defp expiration(_, _, _), do: {:error, :invalid_expiration}

  defp project_preflight(response, target) do
    checks = response["checks"]

    with true <- response["target"] == target,
         true <- is_list(checks) and length(checks) == length(@checks),
         true <-
           Enum.all?(checks, &(is_map(&1) and &1["check"] in @checks and &1["status"] in ~w(proven failed unknown))),
         statuses = Map.new(checks, &{&1["check"], &1["status"]}),
         true <- map_size(statuses) == length(@checks),
         failed = Enum.filter(@checks, &(statuses[&1] == "failed")),
         unknowns = Enum.filter(@checks, &(statuses[&1] == "unknown")),
         scored = Enum.filter(@checks, &(statuses[&1] != "unknown")),
         true <- response["failed"] == failed and response["unknowns"] == unknowns and response["scored"] == scored,
         true <- response["verdict"] == verdict(failed) do
      {:ok,
       %{
         status: :observed,
         target: target,
         checks: statuses,
         failed: failed,
         unknowns: unknowns,
         scored: scored,
         service_verdict: verdict(failed),
         observed_at_local: DateTime.to_iso8601(DateTime.utc_now()),
         note: @note,
         signature_check: "Card signature presence only; no signature validity check.",
         evidence_limit:
           "Guild registry history is not independent endpoint ownership proof. Unknowns do not affect the service verdict."
       }}
    else
      _ -> {:error, :invalid_preflight_response}
    end
  end

  defp verdict(failed) do
    cond do
      Enum.any?(~w(endpoint_reachable protocol_handshake), &(&1 in failed)) -> "do_not_delegate"
      failed != [] -> "delegate_with_caution"
      true -> "no_failed_checks"
    end
  end

  defp project_passport(response, inputs) do
    with true <- is_boolean(response["valid"]) and is_boolean(response["guild_issued"]),
         true <- response["issuer"] == inputs.expected_issuer,
         true <- response["subject_did"] == inputs.expected_subject do
      {:ok,
       %{
         status: :observed,
         verified: response["valid"] and response["guild_issued"],
         signature_valid: response["valid"],
         guild_issued: response["guild_issued"],
         expected_issuer: inputs.expected_issuer,
         expected_subject: inputs.expected_subject,
         freshness_policy:
           "Signed validFrom/proof.created within 24 hours, no future date, unexpired if validUntil is present.",
         note: @note,
         verification_limit:
           "Guild reports signature verification. Origin and integrity do not bind this subject to any endpoint or prove current reputation."
       }}
    else
      _ -> {:error, :invalid_verifier_response}
    end
  end

  defp request(method, path, body) do
    task = Task.async(fn -> fetch(method, path, body) end)

    case Task.yield(task, @deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :deadline_exceeded}
    end
  end

  defp fetch(method, path, body) do
    request =
      Req.Request.new()
      |> Req.Steps.attach()
      |> Req.merge(
        method: method,
        url: @origin <> path,
        body: body,
        headers: [{"accept", "application/json"}, {"accept-encoding", "identity"}, {"content-type", "application/json"}],
        raw: true,
        retry: false,
        redirect: false,
        receive_timeout: 4_000,
        finch: [pool_timeout: 1_000],
        connect_options: [timeout: 2_000],
        into: &collect/2
      )

    with {:ok, response} <- Req.request(request),
         true <- response.status == 200,
         true <- response.private[:guild_error] == nil,
         true <- Map.get(response.headers, "content-encoding", []) in [[], ["identity"]],
         true <-
           Enum.any?(
             Map.get(response.headers, "content-type", []),
             &String.starts_with?(String.downcase(&1), "application/json")
           ),
         {:ok, object} <- decode(response.body) do
      {:ok, object}
    else
      _ -> {:error, :http_or_response_unavailable}
    end
  rescue
    _ -> {:error, :http_or_response_unavailable}
  catch
    _, _ -> {:error, :http_or_response_unavailable}
  end

  defp collect({:data, data}, {request, response}) do
    body = response.body || ""

    if response.status == 200 and byte_size(body) + byte_size(data) <= @body_limit do
      {:cont, {request, %{response | body: body <> data}}}
    else
      {:halt, {request, %{response | body: "", private: Map.put(response.private, :guild_error, :body_rejected)}}}
    end
  end
end
