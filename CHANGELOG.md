# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-31

Initial release.

### Added

- **Narrative syntax** (`Lmml.Narrative.Parser`) -- a strict superset of
  Markdown built on [`md`](https://hexdocs.pm/md), adding `@name.ext`
  external references and `@@@name.ext ... @@@` inline embeds. Any bare
  `.md`/text file with none of this syntax is already a valid, trivial
  `lmml` narrative.
- **Core data model** -- `Lmml.Embed` (inline vs. external content),
  `Lmml.Document` (parsed AST plus every embed it mentions), and
  `Lmml.Bundle`, the uniform entry point over both on-disk forms:
  - `.lmml` -- a bare, self-contained text file.
  - `.lmmlz` -- a zip archive whose canonical narrative entry is named
    by stripping the trailing `z` from the archive's own filename,
    carrying whatever other files its narrative references.
- **`manifest.json` convention** (`Lmml.Manifest`) -- an optional embed
  literally named `manifest.json`, decoded with OTP's built-in `:json`.
- **Validation** (`Lmml.Bundle.validate/1`) -- cross-checks a bundle's
  references, zip entries, and embed names, reporting every issue found
  in one pass (missing references, orphaned entries, malformed embed
  names, conflicting embeds).
- **LLM payload rendering** (`Lmml.Narrative.Resolver`,
  `Lmml.Narrative.Renderer`) -- resolves every embed a bundle mentions
  and renders it into the typed content-part shape (`text`, `image_url`,
  `attachment`) a multimodal chat completion API expects.
- **Lossless packing** (`Lmml.Pack`) -- `pack/2` and `inline/2` convert a
  bundle between its `.lmml` and `.lmmlz` forms, preserving every
  resolvable embed's content.
- **Mix tasks** -- `mix lmml.new`, `mix lmml.pack`, `mix lmml.inline`,
  `mix lmml.validate` for command-line ergonomics without writing
  Elixir.
- **Documentation** -- a full language reference
  (`docs/LANGUAGE_REFERENCE.md`) and two worked examples under
  `examples/`.

### Notes

- Requires `md >= 0.12.2`, which fixes a `Md.Parser.Syntax.merge/2`
  crash on a custom `:settings` map and adds the `escape: false` `block:`
  property `lmml`'s `@@@` embed syntax relies on to carry content
  through verbatim.

[0.1.0]: https://github.com/Oeditus/lmml/releases/tag/v0.1.0
