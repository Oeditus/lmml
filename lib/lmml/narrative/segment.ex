defmodule Lmml.Narrative.Segment do
  @moduledoc """
  Splits a resolved `lmml` narrative into an ordered list of role-labeled
  *turns* (messages), each renderable to the same typed content-part shape
  `Lmml.Narrative.Renderer` already produces.

  A bare `lmml` narrative is a single blob of prose plus embeds, rendered
  as one message. But a narrative frequently represents a *multi-turn*
  conversation -- the `examples/` narrative uses headings like
  `## Turn 1 -- user` / `## Turn 2 -- assistant`. `Segment` turns that
  structural convention into an actual list of messages, so a whole
  conversation carried in one `.lmml`/`.lmmlz` can be sent to a chat
  completion API as a sequence of `{role, content}` messages rather than
  a single prompt.

  ## Turn delimiters

  A *role delimiter* splits the narrative and opens a new turn. Two spellings
  are recognized, both case-insensitive:

    - A Markdown heading whose text names a role, e.g. `## Turn 1 -- user`,
      `# assistant`, `### system`. The role is the first whole-word role
      token in the heading's text.
    - An HTML comment containing only a role, e.g. `<!-- user -->`,
      `<!-- assistant -->`.

  The supported roles are `:user`, `:assistant`, `:system`, and `:tool`
  (see `roles/0`). The delimiter line itself is a structural marker and is
  *not* included in the turn it opens.

  ## Preamble and consecutive roles

  Narrative text before the first delimiter is a *preamble* and becomes a
  `:context` turn (so nothing the author wrote is ever dropped). Consecutive
  delimiters with the *same* role still open separate turns -- `## Turn 1 --
  user` followed by `## Turn 2 -- user` yields two distinct `:user` messages,
  since consecutive user messages are legitimately distinct in a transcript.

  ## Which embeds belong to which turn

  Each embed's marker is located by byte offset in the full narrative, and
  the embed is assigned to the turn whose text region contains that offset.
  Inline `@@@name ... @@@` fences and in-prose `@name` references are both
  handled; an embed opened inside one turn belongs to that turn even if its
  fence were to span a boundary. Because a resolved narrative lists each
  distinct embed name once (first occurrence), only first occurrences are
  located.

  ## Rendering

  `render_turns/2` maps each turn through `Lmml.Narrative.Renderer` (by
  building a per-turn `Lmml.Narrative.Resolver`), yielding
  `[%{role: role, content: [content_part, ...]}]` ready to hand to an API's
  `messages` field.
  """

  alias Lmml.Embed
  alias Lmml.Narrative.Renderer
  alias Lmml.Narrative.Resolver

  @roles [:context, :user, :assistant, :system, :tool]
  @message_roles [:user, :assistant, :system, :tool]

  @enforce_keys [:role, :narrative, :embeds]
  defstruct [:role, :narrative, :embeds]

  @type role :: :context | :user | :assistant | :system | :tool

  @type t :: %__MODULE__{
          role: role(),
          narrative: binary(),
          embeds: [Resolver.resolved_embed()]
        }

  @doc "Every role `Segment` recognizes, including the synthetic `:context` preamble role."
  @spec roles() :: [role()]
  def roles, do: @roles

  @doc "The roles that map onto real message roles (`:context` is excluded)."
  @spec message_roles() :: [role()]
  def message_roles, do: @message_roles

  @doc """
  Splits a resolved narrative into an ordered list of `t()` turns.

  Segmentation of an *already-resolved* narrative is pure text processing
  and cannot fail, so this returns the turn list directly (like
  `Lmml.Narrative.Renderer.render/1`), not a tagged tuple.

  See the moduledoc for the delimiter convention, preamble handling, and
  embed-to-turn assignment. `opts` currently accepts no options (reserved
  for future use) but is part of the public signature for forward
  compatibility.
  """
  @spec segment(Resolver.t(), keyword()) :: [t()]
  def segment(%Resolver{} = resolved, _opts \\ []) do
    do_segment(resolved)
  end

  @doc """
  Segments `resolved` and renders each turn through `Lmml.Narrative.Renderer`,
  returning `[%{role: role, content: [content_part, ...]}]` -- the shape a
  chat completion API's `messages` field expects.

  `opts` are forwarded to `Lmml.Narrative.Renderer.render/2` (see its
  `:max_embed_bytes`), so a per-message payload budget applies uniformly.
  """
  @spec render_turns(Resolver.t(), keyword()) :: [%{role: role(), content: [map()]}]
  def render_turns(%Resolver{} = resolved, opts \\ []) do
    resolved
    |> segment()
    |> Enum.map(fn turn ->
      per_turn = %Resolver{narrative: turn.narrative, embeds: turn.embeds}
      %{role: turn.role, content: Renderer.render(per_turn, opts)}
    end)
  end

  # ---------------------------------------------------------------------
  # Segmentation
  # ---------------------------------------------------------------------

  defp do_segment(%Resolver{narrative: narrative, embeds: embeds}) do
    delimiters = find_delimiters(narrative)

    regions =
      case delimiters do
        [] ->
          [{:context, 0, byte_size(narrative)}]

        _ ->
          build_regions(narrative, delimiters)
      end

    embed_offsets = locate_embeds(narrative, embeds)

    Enum.map(regions, fn {role, from, to} ->
      turn_embeds =
        embeds
        |> Enum.with_index()
        |> Enum.filter(fn {_embed, index} ->
          embed_in_region?(index, embed_offsets, from, to)
        end)
        |> Enum.map(fn {embed, _index} -> embed end)

      text = binary_part(narrative, from, to - from)

      %__MODULE__{role: role, narrative: text, embeds: turn_embeds}
    end)
  end

  defp embed_in_region?(index, embed_offsets, from, to) do
    case Map.fetch(embed_offsets, index) do
      {:ok, offset} -> offset >= from and offset < to
      :error -> false
    end
  end

  # Builds the text regions between role delimiters. `delimiters` is a list
  # of `{role, delim_start, delim_end}` where `delim_end` is the byte offset
  # just past the delimiter line (including its newline). Region boundaries:
  #   - any preamble before the first delimiter becomes a `:context` region;
  #   - each delimiter opens a region of its `role` running from just after
  #     the delimiter to the next delimiter's start (or the text's end).
  defp build_regions(narrative, delimiters) do
    total = byte_size(narrative)

    # A preamble region, unless the very first delimiter starts at byte 0.
    preamble =
      case delimiters do
        [{_role, 0, _dend} | _] -> []
        [{_role, dstart, _dend} | _] -> [{:context, 0, dstart}]
      end

    # For each consecutive delimiter pair, the earlier delimiter's region runs
    # from its own end to the next delimiter's start.
    middle =
      delimiters
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{role, _ds, dend}, {_nr, nstart, _nend}] -> {role, dend, nstart} end)

    # The final delimiter's region runs to the very end of the narrative.
    {last_role, _ds, last_dend} = List.last(delimiters)
    final = {last_role, last_dend, total}

    preamble ++ middle ++ [final]
  end

  # ---------------------------------------------------------------------
  # Delimiter detection
  # ---------------------------------------------------------------------

  # Scans the narrative line by line (tracking byte offsets) and returns the
  # role delimiters in order: `[{role, line_start, line_end}]` where
  # `line_end` is just past the delimiter's own trailing newline.
  defp find_delimiters(narrative) do
    narrative
    |> lines_with_offsets()
    |> Enum.flat_map(fn {line, start, after_newline} ->
      case role_of_line(line) do
        nil -> []
        role -> [{role, start, after_newline}]
      end
    end)
  end

  # Yields `{line_content_without_newline, byte_start, byte_after_newline}`
  # for each line of `text`.
  defp lines_with_offsets(text) do
    do_lines(text, 0, [])
    |> Enum.reverse()
  end

  defp do_lines(text, offset, acc) do
    case :binary.match(text, "\n") do
      :nomatch ->
        if byte_size(text) == 0 do
          acc
        else
          [{text, offset, offset + byte_size(text)} | acc]
        end

      {idx, 1} ->
        line = binary_part(text, 0, idx)
        rest = binary_part(text, idx + 1, byte_size(text) - idx - 1)
        do_lines(rest, offset + idx + 1, [{line, offset, offset + idx + 1} | acc])
    end
  end

  # Returns the role a single line names, or `nil` if it isn't a delimiter.
  defp role_of_line(line) do
    trimmed = String.trim(line)

    cond do
      heading?(trimmed) ->
        heading_role(trimmed)

      comment?(trimmed) ->
        comment_role(trimmed)

      true ->
        nil
    end
  end

  defp heading?(line) do
    Regex.match?(~r/^\#{1,6}[ \t]+/, line)
  end

  defp heading_role(line) do
    inner = Regex.replace(~r/^\#{1,6}[ \t]+/, line, "")
    role_token(inner)
  end

  defp comment?(line) do
    String.starts_with?(line, "<!--") and String.ends_with?(line, "-->")
  end

  defp comment_role(line) do
    inner =
      line
      |> String.replace_prefix("<!--", "")
      |> String.replace_suffix("-->", "")
      |> String.trim()

    role_token(inner)
  end

  # Finds the first whole-word role token in `text`.
  defp role_token(text) do
    role_strings = Enum.map(@message_roles, &Atom.to_string/1)

    text
    |> String.downcase()
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.find(&(&1 in role_strings))
    |> case do
      nil -> nil
      token -> String.to_existing_atom(token)
    end
  end

  # ---------------------------------------------------------------------
  # Embed locating
  # ---------------------------------------------------------------------

  # Locates the byte offset of each resolved embed's marker in the narrative,
  # returning a map `index => offset`. Inline embeds are located by their full
  # reconstructed fence; external embeds by their `@name` reference, skipping
  # anything inside an inline fence's content. `embeds` is the list of
  # resolved-embed maps (`%{embed: Embed, content: binary}`) straight from a
  # `Lmml.Narrative.Resolver`.
  defp locate_embeds(narrative, embeds) do
    inline_offsets = locate_inline_embeds(narrative, embeds)
    external_offsets = locate_external_embeds(narrative, embeds, inline_offsets)
    Map.merge(inline_offsets, external_offsets)
  end

  defp locate_inline_embeds(narrative, embeds) do
    embeds
    |> Enum.with_index()
    |> Enum.filter(fn {%{embed: embed}, _i} -> Embed.inline?(embed) end)
    |> Enum.reduce({%{}, 0}, fn {%{embed: embed}, index}, {acc, search_from} ->
      fence = inline_fence(embed)

      case :binary.match(narrative, fence,
             scope: {search_from, byte_size(narrative) - search_from}
           ) do
        {start, len} -> {Map.put(acc, index, start), start + len}
        :nomatch -> {acc, search_from}
      end
    end)
    |> elem(0)
  end

  defp locate_external_embeds(narrative, embeds, inline_offsets) do
    ext_markers =
      embeds
      |> Enum.with_index()
      |> Enum.filter(fn {%{embed: embed}, i} ->
        Embed.external?(embed) and not Map.has_key?(inline_offsets, i)
      end)
      |> Enum.map(fn {%{embed: embed}, index} -> {index, "@" <> embed.name} end)
      |> Enum.sort_by(fn {_index, marker} -> -byte_size(marker) end)

    # Spans inside inline fences that the external scan must skip.
    skip_spans = inline_fence_spans(embeds, inline_offsets)

    do_locate_external(narrative, 0, ext_markers, skip_spans, %{})
  end

  # Walks the narrative left to right, matching the longest external marker at
  # each position, skipping over any inline-fence span it crosses.
  defp do_locate_external(narrative, pos, markers, skip_spans, acc) do
    total = byte_size(narrative)

    cond do
      pos >= total ->
        acc

      # Skip over an inline fence span starting at pos.
      match_span_at(skip_spans, pos) != nil ->
        {_start, span_end} = match_span_at(skip_spans, pos)
        do_locate_external(narrative, span_end, markers, skip_spans, acc)

      true ->
        case match_marker_at(narrative, pos, markers) do
          nil ->
            do_locate_external(narrative, pos + 1, markers, skip_spans, acc)

          {index, marker_len} ->
            acc = Map.put_new(acc, index, pos)
            do_locate_external(narrative, pos + marker_len, markers, skip_spans, acc)
        end
    end
  end

  defp match_span_at([], _pos), do: nil
  defp match_span_at([{start, _end} = span | _], pos) when start == pos, do: span
  defp match_span_at([_ | rest], pos), do: match_span_at(rest, pos)

  defp match_marker_at(_narrative, _pos, []), do: nil

  # Returns `{index, marker_len}` for the longest marker whose literal bytes
  # appear at `pos`, or nil.
  defp match_marker_at(narrative, pos, [{index, marker} | rest]) do
    marker_len = byte_size(marker)

    if pos + marker_len <= byte_size(narrative) and
         binary_part(narrative, pos, marker_len) == marker do
      {index, marker_len}
    else
      match_marker_at(narrative, pos, rest)
    end
  end

  defp inline_fence(%Embed{name: name, content: {:inline, content}}) do
    "@@@" <> name <> "\n" <> content <> "@@@"
  end

  # Returns the sorted list of `{start, end}` byte spans occupied by inline
  # fences, so the external-reference scan can skip their content.
  defp inline_fence_spans(embeds, inline_offsets) do
    embeds
    |> Enum.with_index()
    |> Enum.flat_map(fn {%{embed: embed}, index} ->
      case {Embed.inline?(embed), Map.fetch(inline_offsets, index)} do
        {true, {:ok, start}} ->
          len = byte_size(inline_fence(embed))
          [{start, start + len}]

        _ ->
          []
      end
    end)
    |> Enum.sort()
  end
end
