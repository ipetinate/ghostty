# Grammar fixtures

Third-party TextMate grammars, used by `GrammarTokenizerTests` to prove the
engine colours a language the binary knows nothing about.

| File | Scope | Origin | Licence |
| --- | --- | --- | --- |
| `elixir.tmLanguage.json` | `source.elixir` | [elixir-lsp/vscode-elixir-ls](https://github.com/elixir-lsp/vscode-elixir-ls) `syntaxes/elixir.json` | MIT, see `LICENSE-elixir` |
| `eex.tmLanguage.json` | `text.elixir` | [elixir-lsp/vscode-elixir-ls](https://github.com/elixir-lsp/vscode-elixir-ls) `syntaxes/eex.json` | MIT, see `LICENSE-elixir` |

Both files are unmodified copies, renamed to the `.tmLanguage.json` extension
the store publishes. `LICENSE-elixir` is that project's own licence file, kept
next to them so the attribution travels with the grammars.
