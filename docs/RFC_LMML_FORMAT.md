# RFC 0000: Language Model Markup Language (LMML) and Archive Bundle Specification (LMMLZ)

- **Document Version**: 1.0.0
- **Status**: Informational / Specification
- **Authors**: Oeditus Team
- **Date**: September 2026

---

## 1. Abstract

This specification defines **Language Model Markup Language (LMML)**, a Markdown-superset markup format for representing structured, multi-turn artificial intelligence (AI) and Large Language Model (LLM) interaction sessions. It also specifies **LMMLZ**, a portable, single-file zip archive format for packaging an LMML narrative alongside external binary and textual assets.

---

## 2. Terminology and Conformance

The key words "**MUST**", "**MUST NOT**", "**REQUIRED**", "**SHALL**", "**SHALL NOT**", "**SHOULD**", "**SHOULD NOT**", "**RECOMMENDED**", "**MAY**", and "**OPTIONAL**" in this document are to be interpreted as described in [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119) and [RFC 8174](https://datatracker.ietf.org/doc/html/rfc8174).

- **Narrative**: The underlying UTF-8 text containing human prose, Markdown formatting, and embedded asset references.
- **Embed**: A named entity (inline or external) contained or referenced within a narrative.
- **Bundle**: A container abstraction representing an LMML entity, regardless of whether it is stored as a bare text file (`.lmml`) or an archive bundle (`.lmmlz`).

---

## 3. On-Disk Formats

An LMML document **MUST** be stored in one of two canonical forms:

### 3.1 Plain Text Form (`.lmml`)
A single UTF-8 encoded text file bearing the `.lmml` extension.
- **Constraint**: Because a bare text file carries no secondary file payload streams, every embed referenced within a `.lmml` narrative **MUST** either be inline (`@@@name.ext ... @@@`) or be resolved against an external environment. Unresolved external references (`@name.ext`) in a bare `.lmml` document **MUST** evaluate to an unresolvable reference error upon asset resolution.

### 3.2 Zip Archive Form (`.lmmlz`)
A standard PKZIP archive (magic bytes `0x50 0x4B 0x03 0x04`) bearing the `.lmmlz` extension.
- **Canonical Entry Naming**: An `.lmmlz` archive **MUST** contain exactly one primary narrative entry whose filename is derived by stripping the trailing `z` from the archive file's basename (e.g. archive `session.lmmlz` **MUST** contain primary narrative entry `session.lmml`).
- **Asset Entries**: Any additional file stored within the archive represents a named external asset accessible to `@name.ext` references.

---

## 4. Narrative Syntax Specification

LMML is designed as a strict superset of standard Markdown (CommonMark/GFM). Any valid Markdown document **MUST** parse as a valid LMML narrative with zero embeds.

### 4.1 External Embed References (`@name.ext`)
- **Syntax**: An `@` symbol followed immediately by an asset identifier matching `[a-zA-Z0-9_.-]+`.
- **Parsing Rules**:
  - The identifier **MUST** begin with an alphanumeric character.
  - Punctuation immediately trailing the identifier (such as periods `.`, commas `,`, or closing parentheses `)`) **MUST NOT** be captured as part of the asset name if it constitutes standard sentence punctuation.
  - References nested inside inline spans (code spans `` `...` ``) or block constructs (fenced code blocks ```` ```...``` ````) **MUST NOT** be interpreted as LMML references.

### 4.2 Inline Embed Blocks (`@@@name.ext ... @@@`)
- **Syntax**:
  ```markdown
  @@@name.ext
  <content>
  @@@
  ```
- **Parsing Rules**:
  - The opening fence line **MUST** start with three `@` symbols (`@@@`), followed immediately by the embed name.
  - The content between the opening and closing `@@@` lines **MUST** be captured verbatim (byte-for-byte), without HTML entity escaping or Markdown modification.
  - The closing fence **MUST** be `@@@` on a line by itself.

---

## 5. Reserved Embeds and Metadata Conventions

LMML defines standard conventions for structural metadata embeds. Implementations **MUST** recognize these reserved names when requested by callers:

### 5.1 `manifest.json`
An embed named `manifest.json` (inline or external) carries global session metadata.
- **Format**: JSON Object (`{ ... }`).
- **Semantics**: Exposes key-value parameters such as schema versions, model IDs, or session UUIDs.

### 5.2 `settings.yaml` / `settings.json`
An embed named `settings.yaml` or `settings.json` carries execution configurations (such as model sampling parameters like `temperature`, `top_p`, or custom agent instructions).

---

## 6. Multi-Turn Segmentation Protocol

An LMML narrative **MAY** represent a multi-turn conversation comprising multiple message roles.

### 6.1 Role Delimiters
Implementations **MUST** recognize two delimiter syntaxes for demarcating turn boundaries (case-insensitive):

1. **Markdown Headings**:
   - `## Turn N -- <role>`
   - `# <role>`
   - `### <role>`
   Where `<role>` is one of `:user`, `:assistant`, `:system`, or `:tool`.

2. **HTML Comments**:
   - `<!-- <role> -->`

### 6.2 Turn Structure and Preamble
- Text preceding the first role delimiter **MUST** be assigned to a synthetic `:context` preamble turn.
- Text following a delimiter belongs to that turn until the next delimiter or end-of-file.
- Embeds occurring within a turn's character offset span **MUST** be bound exclusively to that turn.

---

## 7. Extension-Based Asset Handlers and Semantic Resolution

LMML separates asset containment from asset consumption:

1. **Resolution Phase**: An implementation **MUST** resolve every embed name to its underlying raw bytes (`{:inline, binary}` or `{:external, filename}`).
2. **Rendering / Handler Phase**: Resolved assets **MUST** be mapped to typed application structures based on file extension (or manifest metadata):
   - Image extensions (`.png`, `.jpg`, `.jpeg`, `.webp`, `.svg`, `.gif`) **SHOULD** map to `image_url` data URIs.
   - Text and document extensions (`.json`, `.yaml`, `.pdf`, `.csv`, `.log`, `.diff`) **SHOULD** map to structured attachment parts.
   - Implementations **MAY** register custom handlers per extension (e.g. invoking an audio transcriber for `.mp3` or code interpreter for `.py`).

---

## 8. Conformance & Cross-Validation Requirements

An implementation's validator **MUST** report all of the following authoring defects when cross-checking a bundle (`Bundle.validate/1`):

1. `missing_reference`: An external reference `@name` with no corresponding archive entry.
2. `orphaned_entry`: An archive entry not referenced anywhere in the narrative.
3. `malformed_embed_name`: An embed name violating safe filename path boundaries.
4. `conflicting_embed`: Embeds sharing the same name but carrying conflicting content.

---

## 9. Security Considerations

Implementations **MUST** enforce the following security rules:
- **Path Traversal Immunization**: Entry names containing absolute paths (`/`), backslashes (`\`), or parent directory segments (`..`) **MUST** be rejected up front with `{:error, {:unsafe_entry, name}}`.
- **Zip Central Directory Inspection**: In zip archives (`.lmmlz`), implementations **MUST** validate archive central-directory tables (e.g. via `:zip.table/1`) *prior* to extracting file bytes into memory or disk.
