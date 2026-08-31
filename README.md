<img src="https://raw.githubusercontent.com/Oeditus/lmml/v0.1.0/stuff/img/logo-128.png" alt="lmml" width="128" align="right">

# `lmml`

[![CI](https://github.com/Oeditus/lmml/actions/workflows/ci.yml/badge.svg)](https://github.com/Oeditus/lmml/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/lmml.svg)](https://hex.pm/packages/lmml)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/lmml)
[![License](https://img.shields.io/hexpm/l/lmml.svg)](LICENSE)

`lmml` is a pure-Elixir markup language for talking to LLMs, designed as
a strict superset of Markdown: any bare `.md`/text file already parses
and means something sensible as an `lmml` narrative.

A narrative can be stored in one of two forms:

- `.lmml` -- a bare, self-contained Markdown-superset text file. There is
  nowhere for an external file to live alongside it, so every embed it
  mentions must be carried inline.
- `.lmmlz` -- a zip archive whose canonical narrative entry is named by
  stripping the trailing `z` from the archive's own filename
  (`convo.lmmlz` contains `convo.lmml`), plus whatever other files its
  narrative references.

Both forms express the same underlying model -- an ordered narrative
with zero or more named *embeds* -- differing only in whether each
embed's content is carried inline (`@@@name ... @@@`) or externally
(`@name`, resolved against the zip). See
[`docs/LANGUAGE_REFERENCE.md`](docs/LANGUAGE_REFERENCE.md) for the full
syntax and semantics.

## Syntax at a glance

```markdown
# Project context

Please review @diagram.png before the meeting.

@@@settings.yaml
model: gpt-5
temperature: 0.2
@@@
```

`@diagram.png` is an external reference (resolved from a `.lmmlz`
archive's entries); `@@@settings.yaml ... @@@` is an inline embed
(carried directly in the text). Everything else is ordinary Markdown.

## Installation

Add `lmml` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lmml, "~> 0.1"}
  ]
end
```

## Usage

```elixir
{:ok, bundle} = Lmml.Bundle.open("convo.lmmlz")
{:ok, resolved} = Lmml.Narrative.Resolver.resolve(bundle)
content_parts = Lmml.Narrative.Renderer.render(resolved)
```

`content_parts` is a list of `%{"type" => ...}` maps ready to hand to a
multimodal chat completion API's `content` field (`"text"`,
`"image_url"`, or `"attachment"` parts) -- see
`Lmml.Narrative.Renderer`.

To build a bundle programmatically:

```elixir
{:ok, bundle} = Lmml.Bundle.new_zip("convo", "See @a.png.", %{"a.png" => image_bytes})
:ok = Lmml.Bundle.write!(bundle, "convo.lmmlz")
```

See the `examples/` directory in the repository for two complete worked
examples: a settings-only bare `.lmml` narrative, and a multi-turn
conversation with an embedded image packed as `.lmmlz`, resolved and
rendered end to end.

## Mix tasks

- `mix lmml.new PATH` -- creates a new, empty `.lmml` narrative file.
- `mix lmml.pack SOURCE [DEST]` -- externalizes every inline embed into a
  real zip entry, producing a `.lmmlz` archive.
- `mix lmml.inline SOURCE [DEST]` -- inlines every external reference
  back into a bare `.lmml` text file.
- `mix lmml.validate SOURCE` -- cross-checks a bundle's references,
  entries, and embed names, failing (non-zero exit) if any issue is
  found; suitable as a CI check.

## Documentation

Full API and syntax documentation can be generated locally with
[ExDoc](https://github.com/elixir-lang/ex_doc):

```sh
mix docs
```

or at [hexdocs](https://lmml.hexdocs.pm).

See [`docs/LANGUAGE_REFERENCE.md`](docs/LANGUAGE_REFERENCE.md) for the
complete language reference, including several non-obvious findings
about the underlying `Md` parser library that shaped the design (magnet
vs. block category ordering, an HTML-entity-escaping quirk in fenced
blocks, and Erlang's own zip path-traversal handling).

## Status and possible future directions

Phases 0 through 6 of the implementation plan are complete: the
narrative parser, the core `Embed`/`Document`/`Bundle` data model, an
optional `manifest.json` convention, bundle-level validation, an LLM
payload resolver/renderer, lossless `.lmml` <-> `.lmmlz` packing, and a
handful of `mix lmml.*` CLI tasks.

As a stretch idea (not implemented, and out of this project's own
scope): a tool like `dsh`'s `Brain.SessionStore` could optionally
persist and load its conversation sessions as `.lmml`/`.lmmlz` bundles
instead of (or alongside) its own session format, using
`Lmml.Narrative.Resolver`/`Renderer` directly to build the multimodal
message payloads it already sends to an LLM API.

