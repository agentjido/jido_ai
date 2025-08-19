# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
### Changed
### Deprecated
### Removed
### Fixed
### Security

## [1.0.0] - 2025-02-03

### Added
- Initial release of Jido Signal
- Signal processing and event handling framework
- Bus-based pub/sub system with adapters
- Signal routing with pattern matching
- Multiple dispatch adapters: `:pid`, `:pubsub`, `:http`, `:bus`, `:named`, `:console`, `:logger`, `:noop`
- In-memory persistence via ETS
- Middleware pipeline support
- Comprehensive test suite with 80%+ coverage
- Documentation with guides and examples
- OTP supervision tree architecture

[Unreleased]: https://github.com/agentjido/jido_signal/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/agentjido/jido_signal/releases/tag/v1.0.0
