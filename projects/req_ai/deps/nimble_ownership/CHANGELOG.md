# Changelog

## v1.0.1

  * Fix a potential bug that was caused by resolving lazy allowances too early. See [this issue](https://github.com/dashbitco/nimble_ownership/pull/8) for more context if needed.

## v1.0.0

  * Accept a list of PIDs from the function you pass to `NimbleOwnership.allow/5`.

## v0.3.2

  * Fix multiple allowances under the same key.

## v0.3.1

  * Fix small memory leak related to owner cleanup.

## v0.3.0

  * Fixes around transitive dependencies.
  * Add `NimbleOwnership.set_owner_to_manual_cleanup/2` and `NimbleOwnership.cleanup_owner/2`.

## v0.2.1

  * Fix spec for `NimbleOwnership.fetch_owner/3`.

## v0.2.0

This release contains mostly breaking changes, and a first sort-of-stable API. It also adds *shared mode*.
