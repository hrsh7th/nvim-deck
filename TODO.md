# TODO

## git.branch

- improve `git.branch.rebase_onto` old-base selection using a switch source
  (branch picker vs log picker) (depends on: implement switch source)

## Core features

- implement source options as first-class: sources declare their options
  (name/type/default), ctx.get_option() reads them, and a generic `edit_option`
  action lets users change options at runtime and re-execute the source
- implement switch source: a meta-source that shows switcher items at the top
  and replaces its items when a mode is selected

## LSP

### LSP API

- implement `lsp.document_symbols` source
  - `client:request('textDocument/documentSymbol', params, handler)`
  - live update: `LspNotify` (textDocument/didChange) → refresh
- implement `lsp.references` source
  - `client:request('textDocument/references', params, handler)`
- implement `lsp.call_hierarchy` source
  - incoming / outgoing calls: `callHierarchy/incomingCalls`,
    `callHierarchy/outgoingCalls`
- implement `lsp.type_hierarchy` source
  - `typeHierarchy/supertypes`, `typeHierarchy/subtypes`
  - 同様に `textDocument/prepareTypeHierarchy` → supertypes/subtypes
- implement `lsp.goto` actions
  - definition / declaration / type_definition / implementation
- implement `lsp.code_actions` source / action
