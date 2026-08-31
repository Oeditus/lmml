# LMML Language Reference

<p align="center">
  <img src="https://raw.githubusercontent.com/Oeditus/lmml/v0.1.0/stuff/img/logo-500.png" alt="Lmml" width="160">
</p>

This document is the authoritative syntax and semantics reference for
`lmml`, a Markdown-superset markup language for LLM conversations. It
has been expanded incrementally as each implementation phase landed.

## 1. File forms

Every `lmml` document -- called a *narrative* -- is written in the same
Markdown-superset text syntax (section 3). It can be stored in one of two
container forms, chosen only by how you need to distribute it:

- `.lmml` -- a bare, self-contained text file. It is the narrative itself,
  nothing more. There is nowhere for an external file to live alongside
  it, so every embed it uses must be inline (section 3.3).
- `.lmmlz` -- a zip archive. Its canonical narrative entry is named by
  stripping the trailing `z` from the archive's own filename: a file
  named `convo.lmmlz` contains an entry named `convo.lmml`. Every other
  entry in the archive is a file the narrative can reference by name
  (section 3.2).

Both forms are opened through the same API and expose the same narrative
and embed model -- see `Lmml.Bundle`. Detection of which form a file is
happens by sniffing its content (the zip local-file-header magic bytes),
not by trusting the extension: a zip archive named `.lmml` still opens as
a zip, and a bare text file named `.lmmlz` produces a clean error rather
than being misinterpreted.

## 2. The embed model

An *embed* is a named piece of content a narrative mentions. Every embed
has exactly one of two forms of content:

- **inline** -- the content is written directly into the narrative text,
  as an `@@@name ... @@@` fenced block (section 3.3). Inline embeds
  resolve in every bundle kind, since their bytes travel with the text.
- **external** -- the content lives elsewhere: a real entry inside a
  `.lmmlz` archive, referenced from the narrative by `@name.ext`
  (section 3.2). External references only resolve inside a `.lmmlz`; in a
  bare `.lmml`, an external-style reference is a dangling reference by
  definition, since there is no archive for it to point into.

`@name.ext` (by reference) and `@@@name.ext ... @@@` (by value) are two
*renderings* of the exact same idea -- "this document contains a named
embedded entity" -- not two different concepts. Converting between them
(externalizing an inline embed into a real zip entry, or inlining a zip
entry's content back into the narrative text) is a lossless, mechanical
operation; see `Lmml.Pack` (section 7).

## 3. Narrative syntax

A narrative is valid Markdown (CommonMark, as implemented by the
[`md`](https://hexdocs.pm/md) library's `Md.Parser.Syntax`'s `Default`
syntax module) plus two additions. Every plain `.md` file with no `lmml`-specific syntax at
all is already a valid, trivial, embed-less `lmml` narrative -- this
superset property is deliberate and tested (see
`test/lmml/narrative/parser_test.exs`, "lmml is a superset of vanilla
Markdown").

### 3.1 Standard Markdown

Headings, emphasis (`*bold*`, `_italic_`), links (`[text](url)`), images
(`![alt](src)`), lists, blockquotes, tables, plain fenced code blocks
(` ```lang `), and everything else `Md.Parser.Syntax`'s `Default` syntax
module supports work exactly as in standard Markdown, completely
unaffected by the additions below. Two of Default's own magnets are
notable and are kept as-is:

- `https://` / `http://` auto-linking -- plain URLs in prose become
  anchors, useful for narrative text that mentions external resources.
- The `✇` (YouTube) and `♫` (SoundCloud) magnets -- obscure Unicode
  trigger characters, harmless to leave in place since they cannot
  collide with ordinary prose or with `@`/`@@@` (disjoint prefixes).

### 3.2 References: `@name.ext`

A bare `@` immediately followed by a name (letters, digits, and any
characters that are not ASCII punctuation or whitespace) is an external
reference to an embed named `name.ext`:

```
Please review @diagram.png before the meeting.
```

The reference stops at the first ASCII punctuation character that
immediately precedes whitespace or end-of-input -- so `@image.png)`,
`@image.png,`, `@image.png.`, and `@image.png*` all correctly capture
just `image.png`, leaving the trailing punctuation as ordinary text (or,
for markdown-meaningful punctuation like `*`, as ordinary markdown). A
dot *inside* a name, like the one before `png`, is never mistaken for a
terminator, since only the single character immediately preceding a
whitespace/EOF boundary is ever checked.

A reference resolves by looking up `name.ext` among the bundle's zip
entries (`.lmmlz` only) or among the narrative's own inline embeds
(`@@@name.ext ... @@@`, any bundle kind) -- whichever exists. See
`Lmml.Bundle.embed/2` / `Lmml.Document.embed/2`.

### 3.3 Inline embeds: `@@@name.ext ... @@@`

A block starting with `@@@name.ext` on its own line, followed by content,
and closed by a line containing only `@@@`, is an inline embed: the named
entity's content, carried directly in the narrative text.

```
@@@settings.yaml
theme: dark
retries: 3
@@@
```

Like a standard ` ``` ` fenced code block, `@@@...@@@` is a *block-level*
construct: it must begin at the start of the document or immediately
after a blank line, and content inside it is captured verbatim (including
any blank lines within the fence) rather than being re-parsed as
Markdown. This is the same limitation an ordinary backtick fence has when
attempted mid-sentence, and matches the same user expectation: embeds are
used as their own block, never spliced into running prose.

Multiple inline embeds may appear in the same document, each producing
its own embed node.

`@@@` was chosen over an alternative like `$$$` specifically to avoid
colliding with the widely-used `$$`/`$$$` LaTeX/KaTeX math-block
convention in other Markdown flavors -- reusing that marker here would
silently corrupt how a bare `.lmml` renders in a generic Markdown viewer,
undermining the superset-of-Markdown guarantee. `@` has no meaning at all
in vanilla CommonMark, so an unrendered `@@@name` degrades to inert
paragraph text in a naive viewer, never to a misleading math block or a
broken fence.

### 3.4 The manifest convention

`manifest.json` is not a separate front-matter mechanism -- it is simply
an embed literally named `manifest.json` (inline via `@@@manifest.json
... @@@`, or external via `@manifest.json` in a `.lmmlz`). It is entirely
optional: a document with no such embed is still a perfectly valid,
manifest-less narrative. When present, `Lmml.Manifest.load/1` decodes it
(using OTP's built-in `:json`, not `Jason`) and exposes it as a plain
map; `Lmml.Manifest.load/1` returns `{:ok, nil}` when no `manifest.json`
embed is mentioned at all, which is the common case, not an error.

### 3.5 Content fidelity of inline embeds

An inline embed's content is guaranteed to match, byte for byte, exactly
what was written between its `@@@name ... @@@` fences. The underlying
`Md` parser's `block:` category (what the `@@@` fence is built on)
HTML-entity-escapes five characters -- `'`, `"`, `&`, `<`, `>` -- by
default while capturing a block's content, the same as Default's own
` ```lang ` code fence; the `@@@` entry in `Lmml.Narrative.Syntax` sets
`escape: false` (a `block:` property added in `Md` 0.12.2) so its content
is captured verbatim instead, which is why `manifest.json` (or any other
embed whose content happens to contain a quote, ampersand, or angle
bracket) round-trips correctly. This opt-out applies only to `lmml`'s own
`@@@` entry -- an ordinary code fence elsewhere in a narrative keeps
Default's escaping, since it isn't part of the embed model.

## 4. Path safety

Every zip entry name a `.lmmlz` bundle resolves is validated against path
traversal (`Lmml.Bundle.validate_entry_names/1`): no absolute paths, no
`..` path segments, no backslashes. This matters because a `.lmmlz` may
arrive from somewhere you didn't author.

Empirically, Erlang's own `:zip.unzip/2` already provides a first line of
defense here: given an entry name containing a path-traversal or absolute
component, it does not propagate that name as-is -- it logs a warning and
silently collapses the entry down to its bare basename before
`Lmml.Bundle` ever sees it. `validate_entry_names/1` is still real
defense-in-depth, and is the *only* line of defense for entries supplied
directly to the in-memory `Lmml.Bundle.new_zip/3` constructor, which never
goes through `:zip` and so receives none of that free sanitization.

## 5. Validation

`Lmml.Bundle.validate/1` is a distinct, opt-in cross-check beyond what
`open/1`/`new_zip/3` already enforce (path safety alone). It returns
`:ok`, or `{:error, issues}` collecting every issue found in one pass:

- `{:missing_reference, name}` -- an `@name.ext` reference has no
  matching zip entry (every external reference in a bare `.lmml`
  necessarily counts, since it has no entries at all).
- `{:orphaned_entry, name}` -- a zip entry nothing in the narrative
  mentions.
- `{:malformed_embed_name, name}` -- an embed name (inline or external)
  that could not safely become a zip entry name, relevant to every embed
  since `Lmml.Pack.pack/2` (section 7) can turn any inline embed into a
  real entry later.
- `{:conflicting_embed, name}` -- two or more embeds share a name but
  disagree on content, including disagreeing on inline-vs-external.

## 6. Rendering for an LLM call

`Lmml.Narrative.Resolver.resolve/1` resolves every distinct embed a
bundle's narrative mentions against the bundle itself (inline embeds
trivially, external references via the zip's entries), failing fast if
any one of them cannot be resolved rather than sending a partially
resolved narrative to an LLM.

`Lmml.Narrative.Renderer.render/1` turns that resolved structure into an
ordered list of typed content parts for a multimodal chat completion
API: the raw narrative text becomes one verbatim `"text"` part (its
`@name.ext`/`@@@name.ext ... @@@` syntax is left as-is, since it already
clearly marks where each embed occurs), followed by one part per
resolved embed -- an `"image_url"` part (base64 data URI) for image
extensions, or an `"attachment"` part carrying the content directly for
everything else, typed by an extension-to-MIME-type mapping with an
`"application/octet-stream"` fallback.

## 7. Packing and inlining

`Lmml.Pack.pack/2` converts a bundle into a `:zip` bundle: every inline
embed is externalized into a real zip entry and its `@@@name ... @@@`
occurrence rewritten to a plain `@name` reference (safe anywhere, since a
short reference is valid wherever prose is). Already-external references
are left as text but their bytes are still resolved and copied into the
result's entries when possible, so packing an already-`.lmmlz` bundle is
a safe, idempotent merge rather than a lossy re-creation.

`Lmml.Pack.inline/2` converts a bundle into a `:text` bundle: every
external reference must resolve (it fails outright rather than producing
a partial result), and a zip entry nothing references is necessarily
dropped, since a bare `.lmml` cannot carry an unreferenced entry.

Critically, `inline/2` does *not* substitute a fenced block in place of a
reference: a `@@@name ... @@@` fence's opening marker is only valid at
the start of the document or after a blank line (section 3.3), but a
reference is normally used mid-sentence (`"Please review @diagram.png
before the meeting."`), where substituting a fence in place would
produce unparseable output. Instead, `inline/2` strips the bare `@`
sigil from each in-prose occurrence (`"@notes.txt"` becomes plain
`"notes.txt"`) and appends one proper, blank-line-separated
`"@@@name ... @@@"` block per resolved reference at the end of the
narrative.

Both directions rewrite text via targeted substring surgery on exact
fence/reference occurrences already known from the parsed `Document`,
not by re-serializing the whole AST back into Markdown (`Md` has no
matching generator, and embeds are the only `lmml`-specific syntax
either direction touches). Packing then inlining (or vice versa) is a
lossless round trip in terms of every embed's resolvable content, though
not necessarily of the raw narrative text's exact prose wording around a
formerly-external reference (its `@` sigil is stripped) or of orphaned
zip entries (dropped by `inline/2`, since they were never part of the
document model to begin with).

Only valid UTF-8 content can ever be inlined. `inline/2` fails with
`{:error, {name, :not_utf8}}` for an external reference whose resolved
bytes aren't valid UTF-8 -- splicing genuinely binary content (a real
image, say) into the narrative's own UTF-8 text isn't just ugly, it
crashes the underlying parser outright, since it matches one UTF-8
codepoint at a time with no defined behavior for an invalid byte
sequence appearing mid-text. A binary asset should simply stay external
via `@name.ext`, which is exactly what `.lmmlz` archives are for.
