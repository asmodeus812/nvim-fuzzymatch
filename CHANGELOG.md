## [Unreleased]

### Added

### Fixed

## [1.0.0] - 2026-03-06

### Breaking
- refactor(api)!: change the contract format for decorators and highlighters
- refactor(api)!: move interactive and map away from context map

### Added
- Match: a fuzzy matcher module which is used to fuzzy match a query within a list of provided user items
- Select: user interface providing an interactive set of components to input, display and preview items within a user defined list
- Stream: async stream component which can start system utilities or stream from in-memory sources in a non-blocking interactive way
- Picker: a component which combines the core Select, Match and Stream and provides a rich extensible interface to create dynamic user pickers.
- feat(texthl): allow highlighting the display line in the list
- feat(decor): new decorators and fixing and adjusting the old ones
- feat(pickers): add several new options and fixups for vim pickers
- feat(tick): add generic tick to context and directory state watcher
- feat(bench): add bench testing for the pickers stages
- feat(bench): add bench testing for the pickers stages
- feat(doc): add vimdoc and improve the manpages
- feat(diagnostic): clean up diagnostic warnings and issues
- feat(document): the existing picker modules options
- feat(ci): addci integration and improve the documentation
- feat(tests): add initial test specs for the picker
- feat(pickers): add the base for new pickers
- feat(async): make the stream async as well when flushing
- feat(render): experimental viewport culled and limited rendering
- feat(visitor): add visitors and stateful converter modules

### Fixed
- fix(test): fix failing tests and introduce more robust extmark cleanup
- fix(picker): several picker fixes and more passes on naming fixes.
- fix(naming): ensure naming is consistent across pickers
- fix(robustness): ensure that the select fallback buffer is rendered correctly
- fix(robustness): ensure that the select fallback buffer is rendered correctly
- fix(content): check & evaluate dynamic content
- fix(state): ensure contents and args reflects mutable state change
- fix(input): ensure the tests use unified input query methods
- fix(pickers): add workaround for major matchfuzzy bug
- fix(docs): ensure documentation is clear and consice
- fix(select): add asserts and upstream issue related to matchfuzzy
- fix(cursor): enable clamping and cursor range assertions
- fix(various): ensure correctness of pickers and consistent and efficient api usage
- fix(picker): various small fixes onto select and picker modules.
- fix(opts): remove unused reuse options for pickers
- fix(sizes): optimize the resize and fill steps for the pool tables
- fix(stream): make the streaming more robust and performant.
- fix(misc): combined some minor misc changes and fixes
- fix(cleanup): ensure more aggressive cleanup on a buf deletion
- fix(cleanup): ensure more aggressive cleanup on a buf deletion

### Misc
- chore(fmt): formatting and minor docs adjustment
- test(pickers): add more tests and fix existing ones
- test(togggle): add standalone test for toggle and actions
- chore(docs): sync docs and add more detailed explainations
- perf(misc): various performance and general robustness fixes
- chore(diag): fix some false positive diagnostics reports
- test(init): add more comprehensive init testing
- test(pickers): add more comprehensive and complete test for pickers
- chore(cleanup): general clean up and api improvement
- format(tests): ensure consistent formatting across the code base
- chore(docs): misc docs changes and improvements
- fix(misc): combined some minor misc changes and fixes
- feat(async): make the stream async as well when flushing
- feat(render): experimental viewport culled and limited rendering
- feat(visitor): add visitors and stateful converter modules
- fix(cleanup): ensure more aggressive cleanup on a buf deletion
- fix(cleanup): ensure more aggressive cleanup on a buf deletion

## [0.0.1] - 2025-09-19

### Added

- Initial release of the `picker` library.

### Fixed

- Fixing various bugs and issues found during initial testing.
