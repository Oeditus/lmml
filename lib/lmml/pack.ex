defmodule Lmml.Pack do
  @moduledoc """
  Converts between `lmml`'s two on-disk forms by moving each embed
  between being carried inline in the narrative text (`@@@name ...
  @@@`) and being carried as a real zip entry (`@name`) -- the
  mechanical operation the `.lmml` <-> `.lmmlz` conversion boils down to,
  per the "Embed is the one abstraction" design decision (see
  `docs/LANGUAGE_REFERENCE.md`).

  ## How the narrative text is rewritten

  `Md` is a parser with no matching generator, so neither direction
  re-serializes the whole AST back into Markdown from scratch; both
  instead perform targeted substring surgery on the exact fence/reference
  occurrences already known from the parsed `Lmml.Document`, which is
  sufficient since embeds are the only `lmml`-specific syntax either
  direction ever touches:

    - `pack/2` replaces each inline embed's *entire, exact* fence
      substring (`"@@@name\\ncontent@@@"`) with its reference form
      (`"@name"`). A fence's distinctive three-`@` marker makes an
      accidental collision with unrelated prose implausible in practice
      (the only way to get a false match is for some *other* embed's own
      content to literally quote this whole fence, name and content
      both, byte for byte -- a pathological case treated as an accepted,
      documented limitation rather than something guarded against).
    - `inline/2` cannot simply substitute `"@@@name\ncontent@@@"` in
      place of `"@name"`: a fence's *opening* `@@@` is only valid at the
      start of the document or immediately after a blank line (the same
      block-level rule every fenced construct in this language follows),
      so a reference used mid-sentence -- the common case -- would
      produce an unparseable result if replaced in place. Instead,
      `inline/2` strips the bare `@` sigil from every in-prose reference
      occurrence (`"@notes.txt"` becomes plain `"notes.txt"`, no longer
      special syntax) and appends one proper, blank-line-separated
      `"@@@name ... @@@"` block per resolved reference at the end of the
      narrative. Substitutions only ever happen within segments outside
      any *existing* inline embed's own fence (never inside one), and use
      a word-boundary-aware regex so a short reference name is never
      matched as a prefix of a longer, unrelated token (e.g. stripping
      `@a.png` never touches an unrelated `@a.png.bak` reference).

  Neither direction touches embeds it isn't converting: `pack/2` leaves
  any already-external `@name` reference exactly as it is (there is
  nothing to move for it, though its bytes -- if resolvable -- are still
  carried forward into the result's entries, so packing an already-`:zip`
  bundle correctly merges its existing entries rather than losing them);
  `inline/2` leaves any already-inline `@@@name ... @@@` block exactly as
  it is.

  ## Only text can be inlined

  `inline/2` fails with `{:error, {name, :not_utf8}}` for any external
  reference whose resolved content isn't valid UTF-8. A narrative is
  itself UTF-8 text, re-parsed as `lmml`/Markdown from scratch every time
  it's opened, so splicing genuinely binary content (a real image, say)
  into it isn't just ugly -- it actively crashes `Md`'s parser, which
  matches one UTF-8 codepoint at a time and has no defined behavior for
  an invalid byte sequence appearing mid-text. A binary asset should stay
  external via `@name.ext`, which is exactly what `.lmmlz` archives are
  for; only text-like embeds (settings, notes, diffs, JSON, ...) are ever
  valid candidates for inlining.
  """

  alias Lmml.Bundle
  alias Lmml.Embed

  @doc """
  Externalizes every inline embed in `bundle` into a real zip entry,
  returning a new `:zip` bundle. `name` overrides the resulting bundle's
  logical name; defaults to `bundle`'s own name.

  An already-external reference is carried forward as-is in the
  narrative text, with its bytes resolved against `bundle` itself and
  copied into the result's entries when possible -- this is what makes
  packing an already-`:zip` bundle a safe, idempotent merge rather than
  a lossy re-creation. A reference that isn't resolvable in the source
  bundle (a dangling `@name.ext` in a bare `.lmml`) is left dangling in
  the result too, since there is nothing to carry forward for it.
  """
  @spec pack(Bundle.t(), String.t() | nil) :: {:ok, Bundle.t()} | {:error, term()}
  def pack(%Bundle{} = bundle, name \\ nil) do
    inline_embeds =
      bundle |> Bundle.embeds() |> Enum.filter(&Embed.inline?/1) |> Enum.uniq_by(& &1.name)

    narrative =
      Enum.reduce(inline_embeds, Bundle.narrative(bundle), fn embed, text ->
        String.replace(text, fence_text(embed), "@" <> embed.name)
      end)

    Bundle.new_zip(name || Bundle.name(bundle), narrative, collect_entries(bundle))
  end

  @doc "Same as `pack/2`, but raises on failure."
  @spec pack!(Bundle.t(), String.t() | nil) :: Bundle.t()
  def pack!(bundle, name \\ nil) do
    case pack(bundle, name) do
      {:ok, packed} -> packed
      {:error, reason} -> raise "Failed to pack lmml bundle: #{inspect(reason)}"
    end
  end

  @doc """
  Inlines every external reference in `bundle` into a `@@@name ... @@@`
  block, returning a new `:text` bundle. `name` overrides the resulting
  bundle's logical name; defaults to `bundle`'s own name.

  Unlike `pack/2`, every external reference must actually resolve --
  there is no such thing as a partially-inlined result, since a `:text`
  bundle has nowhere left to point a dangling reference at. A zip entry
  that no embed in the narrative mentions at all (see
  `Lmml.Bundle.validate/1`'s `{:orphaned_entry, ...}`) is necessarily
  dropped, since it was never part of the document model to begin with
  and a `:text` bundle cannot carry an unreferenced entry.
  """
  @spec inline(Bundle.t(), String.t() | nil) :: {:ok, Bundle.t()} | {:error, term()}
  def inline(%Bundle{} = bundle, name \\ nil) do
    with {:ok, resolved} <- resolve_external(bundle) do
      narrative = substitute_references(Bundle.narrative(bundle), bundle, resolved)
      Bundle.new_text(name || Bundle.name(bundle), narrative)
    end
  end

  @doc "Same as `inline/2`, but raises on failure."
  @spec inline!(Bundle.t(), String.t() | nil) :: Bundle.t()
  def inline!(bundle, name \\ nil) do
    case inline(bundle, name) do
      {:ok, inlined} -> inlined
      {:error, reason} -> raise "Failed to inline lmml bundle: #{inspect(reason)}"
    end
  end

  # ---------------------------------------------------------------------
  # pack/2 helpers
  # ---------------------------------------------------------------------

  defp fence_text(%Embed{name: name, content: {:inline, content}}) do
    "@@@" <> name <> "\n" <> content <> "@@@"
  end

  defp collect_entries(bundle) do
    bundle
    |> Bundle.embeds()
    |> Enum.uniq_by(& &1.name)
    |> Enum.reduce(%{}, fn embed, acc ->
      case Bundle.embed(bundle, embed.name) do
        {:ok, content} -> Map.put(acc, embed.name, content)
        {:error, _reason} -> acc
      end
    end)
  end

  # ---------------------------------------------------------------------
  # inline/2 helpers
  # ---------------------------------------------------------------------

  defp resolve_external(bundle) do
    bundle
    |> Bundle.embeds()
    |> Enum.filter(&Embed.external?/1)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(&(-byte_size(&1.name)))
    |> Enum.reduce_while({:ok, []}, fn embed, {:ok, acc} ->
      with {:ok, content} <- Bundle.embed(bundle, embed.name),
           :ok <- ensure_inlinable(content) do
        {:cont, {:ok, [{embed.name, content} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, {embed.name, reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end

  # Only valid UTF-8 text can be carried inline: the narrative it's
  # spliced into is itself UTF-8 text, re-parsed as `lmml`/Markdown from
  # scratch every time it's opened. Genuinely binary content (a real
  # image, for instance) isn't just "ugly" inlined -- it's actively
  # unsafe, since `Md`'s parser matches its input one UTF-8 codepoint at
  # a time and has no defined behavior for an invalid byte sequence
  # embedded in otherwise-valid text (verified empirically: it crashes
  # with a raw "no function clause matching" error rather than failing
  # cleanly). Failing here with a clear reason keeps that crash from
  # ever happening; a binary asset should stay external, referenced by
  # `@name.ext`, which is exactly what `.lmmlz` archives are for.
  defp ensure_inlinable(content) do
    if String.valid?(content), do: :ok, else: {:error, :not_utf8}
  end

  defp substitute_references(narrative, bundle, resolved) do
    body =
      bundle
      |> Bundle.embeds()
      |> Enum.filter(&Embed.inline?/1)
      |> Enum.uniq_by(& &1.name)
      |> Enum.reduce([{:prose, narrative}], fn embed, segments ->
        fence = fence_text(embed)

        Enum.flat_map(segments, fn
          {:fence, _} = segment -> [segment]
          {:prose, text} -> split_on_fence(text, fence)
        end)
      end)
      |> Enum.map_join("", fn
        {:fence, text} -> text
        {:prose, text} -> drop_reference_sigils(text, resolved)
      end)

    case appended_blocks(resolved) do
      "" -> body
      blocks -> body <> "\n\n" <> blocks
    end
  end

  defp split_on_fence(text, fence) do
    case :binary.match(text, fence) do
      :nomatch ->
        [{:prose, text}]

      {start, len} ->
        before = binary_part(text, 0, start)
        rest = binary_part(text, start + len, byte_size(text) - start - len)
        [{:prose, before}, {:fence, fence} | split_on_fence(rest, fence)]
    end
  end

  # Turns a reference occurrence back into plain, non-magic text (its
  # actual content is supplied instead via `appended_blocks/1`, since a
  # fence can't safely be opened at this position -- see the moduledoc).
  defp drop_reference_sigils(text, resolved) do
    Enum.reduce(resolved, text, fn {name, _content}, acc ->
      pattern = ~r/@#{Regex.escape(name)}(?![\w.\/-])/u
      Regex.replace(pattern, acc, fn _whole -> name end)
    end)
  end

  # One proper, blank-line-separated `@@@name ... @@@` block per resolved
  # reference, in the same (substitution-safe, descending-name-length)
  # order they were resolved in -- not necessarily their original
  # narrative order.
  defp appended_blocks(resolved) do
    Enum.map_join(resolved, "\n\n", fn {name, content} ->
      "@@@" <> name <> "\n" <> content <> "@@@"
    end)
  end
end
