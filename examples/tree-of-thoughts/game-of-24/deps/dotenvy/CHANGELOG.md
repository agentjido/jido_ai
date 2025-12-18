# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.1

- Fixes compiler warnings in Elixir 1.19
- Bumps deps to latest

## v1.1.0

- Adds support for `Dotenvy.Parser.parse/3` options `:sys_cmd_fn` and `:sys_cmd_opts` to
  allow for greater control over how (or if) any system commands (designated via `$()`)
  are executed during parsing.
- Updates dependencies to latest
- Docs cleanup around `RELEASE_ROOT` so the examples tolerate cases where the path
  includes or omits a trailing slash. This is important because a bad path there causes
  all kinds of frustration in a release.

## v1.0.1

- Minor docs cleanup re Markdown syntax.
- Added link for Sponsor

## v1.0.0

- Adds support for shell commands via the `$()` syntax
- new documentation pages added to introduce generators and more examples
- Deletes deprecated `Dotenvy.env/3` function
- Updates dependencies to latest
- Better error messages for unset variables
- Better error messages for `:require_files` errors
- Updated Logo

## v0.9.0

- Removes fallback to `System.fetch_env/1` and instead requires explicit sourcing of system envs. See [Issue 21](https://github.com/fireproofsocks/dotenvy/issues/21)
- Bumps Elixir version specified for local development in `.tool-versions`
- Updates dependencies to latest

## v0.8.0

- Enables exception rescuing to report on problems with custom callback functions
- Moves `Dotenvy.Transformer.Error` to `Dotenvy.Error` to offer a simpler interface
  for devs who want to raise errors from custom transformer functions
- Improved documentation and examples for usage in umbrella apps
- Updates all internal options in the parser to use `%Opts{}` struct
- Improves test coverage
- Bumps Elixir version specified for local development in `.tool-versions`
- Updates dependencies to latest

## v0.7.0

- Formally defines a type for all supported conversions to improve documentation and specs
- Updates dependencies to latest
- Specifies Elixir 1.13 as required (simply because I can't get anything older to compile)

## v0.6.0

- Does away with the confusing `:overwrite?` and `vars` options in favor of a simple declarative/explicit inputs. `source/2` now accepts ad-hoc maps as inputs.
- Updates dependencies including `:ex_doc` to take advantage of admonishment blocks.
- Various documentation cleanups/clarifications.

## v0.5.0

- Shifts storage of system environment variables to the application process dictionary and alters the reading of this data to help improve the security posture and avoid leaking env values. `:side_effect` option for `source/2` and `source!/2` function changed.

## v0.4.1

- Makes error messages more informative when unable to convert strings to integers or floats

## v0.4.0

- Adds support for custom transformer types by allowing an arity 1 function as the second argument to Dotenvy.Transformer.to/2. See [Issue 2](https://github.com/fireproofsocks/dotenvy/issues/2)

## v0.3.0

- Renames Dotenvy.Transformer.to/2 to `Dotenvy.Transformer.to!/2` to better communicate that it may raise an error.
- Returns key name in errors for easier troubleshooting.
- Tracks an error if the `:require_files` option lists a file not included in the `files` input (for sanity).
- Introduces `Dotenvy.env!/3` (which is the same as `Dotenvy.env/3` but with no defaults provided). This better communicates that it may raise an error (because internally it relies on `Dotenvy.Transformer.to!/2`)
- Deprecates `Dotenvy.env/3` in favor of `Dotenvy.env!/3`

## v0.2.0

Adds support for default `type` of `:string` to the `Dotenvy.env!/2` and `Dotenvy.env/3` functions.

## v0.1.0

Initial release.
