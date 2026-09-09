# History review 20: runtime providers and binary resources

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes two more source reviews. The total is 97 of 126.
All v3 port evidence remains pending.

Read both complete merged diffs: 2,889 lines for `3e391971` and 632 lines for
`fc5bc143`. Read PRs 358 and 360 and issue 359. Those records contain no issue
comments, reviews or inline review comments in the captured data. Checked final
source and the existing Turn/runner transport. No runtime tests were run.

| Commit / PR | Retained behavior | Acceptance mapping |
| --- | --- | --- |
| `3e391971` / PR 358 | Host runtime Specs, function/MFA resource providers, fresh reads, opaque IDs, post-policy authorization, context forwarding and common validation. | HIST-16: runtime Specs, callbacks, provider listings/selectors, freshness, ownership and failures |
| `fc5bc143` / PR 360 | Explicit binary policy, common text/image/file results, MIME/filename/size checks and existing content-part transport. | HIST-16: binary classification, metadata and actual attachment delivery; RELEASE: public resource APIs |

## Retain the host use case and its simpler design

[PR 358](https://github.com/agentjido/jido_ai/pull/358) adds runtime skills whose
resources come from the host application. The example uses an `about-jaicool`
skill and a UUID resource ID. The guide uses a tenant policy store. These are
useful migration examples: the resource is current host data, not a file bundled
with Jido AI. Do not force such hosts to build temporary filesystem skills.

[Issue 359](https://github.com/agentjido/jido_ai/issues/359) then reports that
text-only loading cannot serve images, PDFs or other assets. Its proposed
simplification is retained in [PR 360](https://github.com/agentjido/jido_ai/pull/360):
one normalized resource map, one shared validator, an explicit binary option,
and the existing `Turn`/`Context` content-part path. There is no need for another
resource execution engine, attachment transport or activation metadata model.

The issue's suggestion of a generic MIME dependency was optional. The merged
code uses a small explicit signature/extension table and adds no dependency.

## Runtime Specs and catalog preparation

Agent Skills accepts `specs:` containing `%Spec{}` values with `source: nil`
and valid UTF-8 inline bodies. An empty inline body is valid. Runtime Specs
retain their supplied fields and have no filesystem root. Their nonempty list
selects no default discovery roots unless `paths:` is supplied. Explicit mixed
paths still require trust. Duplicate runtime names return an error with both
indexes. Runtime entries win over discovered entries with a warning.

`Spec.validate_manifest/1` checks name, description, license, compatibility,
string metadata and allowed-tool strings. The Loader now also calls it after
its own parsing/repair stages. `validate_runtime/2` adds source and inline-body
checks and wraps errors with the runtime index. It does not validate every native
field, such as `tags`, `actions`, `plugins`, version or prior diagnostics. Treat
this as a manifest boundary, not proof that all possible Spec values are safe
for every later operation. Preserve native module capabilities separately.

Agent preparation validates the provider form but does not list resources.
`LoadSkill` supplies a provider binding only for source-less Specs. First
activation calls `:list`, saves the resulting catalog/policy/provider binding,
and records `resource_backend` plus the selected IDs. Repeated activation in
the same session reuses this context. A runtime skill without a provider gets
an empty complete resource list.

Direct `Activation.activate` can receive a provider binding independently of
Agent preparation. Its public trust contract is broader than the prepared
runtime-Spec path. Map this distinction explicitly in the v3 API migration.

## Provider contract and authorization

Providers can be two-argument functions, `{Module, :function}` or an MFA with
extra arguments. Validation loads the module and checks the final arity.
Callbacks receive a canonical request with `operation`, `skill` and `policy`;
loads also receive `resource_id`. Context retains host values such as tenant and
Agent IDs. The three reserved skill keys are removed in both atom and string
form. This is a shallow removal, not a general recursive context filter.

Top-level listing responses use `%{resources: list, complete: boolean}`.
Entries accept atom or string keys and require an ID, display name and declared
size. Optional type, modification time, MIME and metadata are normalized.
Missing modification time becomes the epoch; absent metadata becomes `%{}`.
Duplicate IDs and malformed fields fail. Type strings/atoms select the three
compatibility groups without removing entries from the aggregate list.

IDs remain in supplied order and are preserved byte-for-byte. They are not
paths. URL-like text, slashes, Unicode and surrounding whitespace must survive
unchanged. IDs must be nonempty valid UTF-8 and at most 1,024 bytes. The current
validator does not trim whitespace-only IDs or reject NUL separately. Test the
documented byte contract through actual JSON tool calls before changing it.

Provider listing policy takes an ordered prefix. The first count, declared-file
size or encoded-listing limit excludes that entry and all later entries.
`complete: false` also adds `:provider_incomplete`. IDs are authorized only from
the resulting selected list, even when it is incomplete. Clearing and activating
again refreshes that list. A path selector cannot substitute for a provider ID;
filesystem resources use `relative_path` or the legacy `path` alias. Exactly one
selector is required, with a useful root-level schema error.

The Action checks authorization before the callback. Unknown and cross-skill IDs
return resource-not-found and do not invoke the provider. The lower-level public
`ResourceProvider.load/5` validates an ID and response but has no activation
allowlist. Keep its use restricted to the documented trusted caller contract;
do not describe it as equivalent to the scoped Action.

Each authorized load invokes the saved provider again. The response must return
the requested ID and a size equal to actual bytes. Its size may differ from the
earlier listing size, since content is fresh. Reapply the saved resource policy
to current bytes. Existing tool results can remain in conversation history;
fresh reads do not mean that previous results disappear.

Provider errors, raises, throws, exits and malformed callback return shapes are
converted to explicit errors by the invocation boundary. Listing failure prevents
successful activation; load failure retains selector details. The provider call
is synchronous. Resource policy checks the returned content; it does not itself
limit callback execution time or memory before the result arrives. Use ordinary
Action/Flow deadlines and cancellation for live work.

## Ownership and bound checks before the port

The saved binding includes its original context, but `LoadResource` invokes the
saved provider with the current call's public context. Therefore, the activation
ID set can come from one tenant context while a later load receives another.
The current tests use a stable tenant; they do not prove tenant-change behavior.
Bind trusted tenant/catalog identity to the runtime session and define which
request fields can change. Keep fresh non-identity context where required.

Provider closures, MFA arguments, original context and MapSets are runtime data.
Do not serialize them unchanged as portable Agent state. Restore through a
trusted provider reference and explicit catalog/policy identity, then rebuild or
revalidate authorization. Ordinary imported fields cannot grant a provider or ID.

Listing normalization currently visits all returned entries before applying
limits. A malformed or duplicate entry beyond the selected prefix can fail the
whole listing. JSON encoding is checked during prefix selection, so an unencodable
metadata value beyond a reached limit may not be inspected. Test both cases;
one broad claim that all tail entries are ignored or validated would be false.
The host already returned the full list, so accepted output bounds are not proof
of bounded provider allocation. Keep total model-result bounds separate from
the general-list byte limit described in [review 19](19-trusted-catalog-and-resource-bounds.md).

## Binary results use the existing transport

The generic result adds a derived `kind: :text | :image | :file`, while retaining
content bytes, byte size, MIME type, filename and a path/ID selector. Both sources
use `Resources.validate_loaded_resource/2`. Actual and declared size must match.
The file limit applies to every kind; the text limit applies only to text.
Text-only APIs retain their return contract and force binary rejection.

Classification recognizes PNG, JPEG, both GIF headers, WebP and PDF signatures.
Known MIME types and known filename extensions must agree with the signature.
MIME values are normalized to lowercase. Valid UTF-8 without NUL is text unless
a recognized binary signature applies. Other bytes become a file. Filesystem
unknown binary formats receive `application/octet-stream`; a provider must supply
valid MIME and filename data for binary output. A supplied `kind` does not replace
classification. Metadata and filename checks are format identification, not a
full image/PDF decoder or proof of model support.

The default policy rejects binary output. Explicit `binary: :allow` permits it
within file limits. Binary filenames must be valid UTF-8, nonempty, at most
1,024 bytes and free from path separators/NUL or `.`/`..` values. MIME syntax and
length are checked. Keep old provider text responses valid without filenames.

`LoadResource` returns binary metadata plus `__content_parts__`, using the
existing image/file constructors. It omits raw `content` from the metadata map.
`Turn` removes the reserved content field from JSON and carries actual parts
beside it; `Context` preserves them for ReqLLM. Text Action outputs retain their
old fields. Provider errors use `resource_id`; filesystem errors use `path`.

The added transport test reaches `LoadResource -> Turn -> Context` with short
signature fixtures. It does not start an Agent, send the next HTTP request or
prove that a selected provider accepts valid attachments. Extend it through the
shared mock with complete image/PDF fixtures, real tool calls, history restore
and provider error handling. Reuse the earlier media cases instead of creating
another binary transport.

## Required acceptance cases

These extend HIST-16 and catalog 12, with existing media/recovery families where
needed. Every case remains pending.

| Variant | Required evidence |
| --- | --- |
| `HIST-16/runtime-specs` | Compare DSL, Builder and trusted data configuration with module, file and runtime Specs. Preserve inline bodies/native fields, validate manifest/source/body boundaries, duplicate indexes and runtime-over-file precedence. Runtime-only preparation performs no filesystem discovery or provider listing. |
| `HIST-16/provider-callbacks` | Run function, module/function and MFA forms through real Actions. Verify arity/load failures, canonical list/load requests and atom/string reserved-key removal. Host context reaches the provider; internal bindings do not become model data. |
| `HIST-16/provider-listing` | Cover ordered IDs, string-keyed entries, group views, defaults, duplicate/malformed data and complete/incomplete results. Exercise count, declared-size and encoded-byte boundaries, malformed/duplicate versus unencodable tail entries, and unauthorized IDs after truncation. |
| `HIST-16/provider-selectors` | Use the UUID consumer example, URL-like IDs, Unicode, whitespace and byte limits. Prove exact round trips, selector schema errors and backend-specific rules through direct Exec and model calls. Unknown/cross-skill IDs cause no callback. Document direct provider API trust separately. |
| `HIST-16/provider-freshness` | List once, then load the same authorized ID twice with changed host content and valid changed sizes. Both real outputs reach subsequent model requests. Clear/reactivate refreshes authorization; repeated activation alone does not refresh the list. |
| `HIST-16/provider-owner` | Test two tenants/sessions with identical skill names and IDs, changed request context, provider replacement, worker changes, cancellation and owner exit. Restore using approved references and fresh authorization; do not replay serialized closures, runtime context or forged IDs. |
| `HIST-16/provider-failures` | Fail listing and loading by error, exception, throw, exit, malformed shape, ID/size mismatch and timeout. Prove no failed activation, no rejected content in model input, stable structured errors and worker cleanup. Test callback deadlines with barriers, not elapsed sleeps. |
| `HIST-16/binary-classification` | Compare filesystem/provider text, scripts, PNG/JPEG/GIF/WebP/PDF and generic files. Cover default rejection, explicit allow, text-only wrappers, derived kind, empty/NUL/invalid-UTF-8 content and exact file/text byte limits. |
| `HIST-16/binary-metadata` | Test MIME case, known signature/extension conflicts, missing/invalid/oversized MIME and filenames, size mismatch and opaque ID mismatch. Keep provider text compatibility. Rejected metadata cannot create an attachment. |
| `HIST-16/binary-transport` | Have the shared mock request a real skill and image/PDF resource, then inspect the next encoded request. Preserve bytes, filename, MIME, selector, call/result pairing and JSON-safe metadata. Repeat for both sources, streamed tool calls, compaction/restore and unsupported provider/model results. |
| `RELEASE/skill-api-package` | Extend the existing consumer/package case with runtime Specs, provider callback forms, resource APIs, selector migration and binary policy. Verify the native demo and documentation against v3; historical test totals are not package evidence. |

## Refinement decisions

Keep one AI profile, one prepared catalog and one normalized resource contract.
Host resource callbacks are adapters used by normal Actions. They do not create
another Flow or runtime owner. Data authoring selects trusted provider references;
it cannot supply arbitrary executable callbacks.

Before runtime implementation, settle session/tenant identity, saved versus
current context, authorization refresh and portable restore. At the feature
gate, connect provider freshness and binary delivery to actual Agent transcripts.
At the package gate, preserve public text APIs and explicit selector/policy
conversion. These two commits complete the skill source sequence; the remaining
29 source reviews concern release dependencies and maintenance.

Source: [integration](../../../lib/jido_ai/skill/agent_integration.ex),
[Spec validation](../../../lib/jido_ai/skill/spec.ex),
[loader](../../../lib/jido_ai/skill/loader.ex),
[activation](../../../lib/jido_ai/skill/activation.ex),
[provider](../../../lib/jido_ai/skill/resource_provider.ex),
[resources](../../../lib/jido_ai/skill/resources.ex),
[resource Action](../../../lib/jido_ai/actions/skill/load_resource.ex),
[Turn](../../../lib/jido_ai/shared/turn.ex), and
[runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex).
Tests: [provider](../../../test/jido_ai/skill/resource_provider_test.exs),
[resource Action](../../../test/jido_ai/skills/skill/actions/load_resource_test.exs),
[runtime Spec](../../../test/jido_ai/skill/spec_test.exs), and
[binary resources](../../../test/jido_ai/skill/binary_resources_test.exs).


## Native runtime evidence: 2026-09-07

[18_01](../../../examples/18_skills/18_01_skill_runtime/README.md) connects real
activation, resource access, callback approval, committed context, compaction
and later HTTP requests in 27 integration cases. The linked ledger entries
are partial evidence for the feature boundaries in this review. A separate
v3 command passes 293 retained skill/resource checks. Automatic Agent Skills
authoring, packaged resources/CLI, standalone continuation, complete recovery
and release gates remain open. These results do not close the history rows.


## Automatic authoring evidence: 2026-09-07

[18_02](../../../examples/18_skills/18_02_skill_authoring/README.md) adds 21 cases
for public/native authoring and static format parity. The live Session prepares
one selected catalogue for prompt disclosure and loading. Cases cover runtime
roots, trust, source precedence, current-file activation, profile isolation,
restore and live tool/prompt changes. Pure construction performs no discovery.
Static providers and trust callbacks use MFA references. Installed resources,
CLI, standalone continuation, complete recovery and package gates remain open.
This evidence does not close a history row.
