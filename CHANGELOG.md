# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Top-level façade** (`Lmml`) -- Added convenience delegators (`Lmml.open/1`, `open!/1`, `resolve/1`, `resolve!/1`, `render/2`, `to_md/2`, `validate/1`, `pack/2`, `pack!/2`, `inline/2`, `inline!/2`, `segment/2`, `render_turns/2`, `settings/2`, `manifest/1`, `embeds/1`, `narrative/1`).
- **Turn-level / multi-message segmentation** (`Lmml.Narrative.Segment`) -- Splits a narrative into role-labeled messages (`:user`, `:assistant`, `:system`, `:tool`, `:context`), assigning embeds to their respective turns and mapping to API message structures.
- **Typed project settings** (`Lmml.Settings`) -- Structured helper for loading `settings.yaml` / `settings.json` embeds, featuring a built-in YAML-subset parser.
- **`Manifest.fetch/2` and `Settings.fetch/2`** -- Exposes key fetching distinguishing missing keys (`:error`) from explicit `null` values (`{:ok, nil}`).
- **Embed helper accessors** (`Lmml.Embed.content/1`, `Lmml.Embed.entry_name/1`).
- **CLI Mix Tasks** -- Added `mix lmml.render SOURCE` for rendering LLM-ready content parts (with optional `--json` and `--max-embed-bytes`), and `mix lmml.to_md SOURCE [DEST]` for lossy-but-readable Markdown export.
- **Markdown export tooling** (`Lmml.to_md/2`, `Lmml.Narrative.Renderer.to_md/2`) -- Converts embed syntax into clean human-readable placeholders (`[Image: name]`, `[Attachment: name]`).
- **MIME & budget controls** -- Expanded MIME coverage (audio, video, diff, pdf, csv, log, svg) and added per-embed payload budgeting via `max_embed_bytes` in `Renderer.render/2`.

### Fixed & Hardened

- **Pack name collisions** (`Lmml.Pack.pack/2`) -- Added defensive check rejecting inline embed names that collide with external references or existing zip entries, preventing silent data loss.
- **Stable inlining order** (`Lmml.Pack.inline/2`) -- Appends inlined `@@@name ... @@@` blocks in first-occurrence narrative order while maintaining prefix-safe substitution.
- **Archive path traversal protection** (`Lmml.Bundle`) -- Validates raw archive central directory tables via `:zip.table/1` up front, returning clean `{:error, {:unsafe_entry, name}}` error tuples.
- **Comprehensive test coverage** -- Added test suites for `Lmml.Narrative.Segment`, `Lmml.Settings`, `LmmlTest`, new Mix tasks, end-to-end zip archive roundtrips, invalid UTF-8 parse handling, 4-kind aggregate validation reporting, and failure ordering.

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
