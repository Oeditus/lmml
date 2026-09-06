defmodule Lmml.Narrative.Renderer do
  @moduledoc """
  Turns a `Lmml.Narrative.Resolver.t()` into the list of typed content
  parts a multimodal LLM chat completion API expects for a message's
  `content` field -- the same `%{"type" => ...}` shape already built by
  hand elsewhere in this workspace for vision models (see `dsh`'s
  `DeepSeekHarness.CLI.ContextExpander`/`Brain.Session`, which construct
  `%{"type" => "image_url", "image_url" => %{"url" => data_uri}}` and
  `%{"type" => "text", "text" => text}` parts).

  ## Scope

  The narrative's raw text becomes a single verbatim `"text"` part,
  included as-is rather than rewritten to strip or splice around embed
  occurrences. This is a deliberate difference from `ContextExpander`
  (which *does* rewrite free-form chat text, replacing an `@ref` with a
  `"[Image: label]"` placeholder): an `lmml` narrative's embed syntax
  (`@name.ext` / `@@@name.ext ... @@@`) is always clearly delimited and
  meaningful Markdown-superset text on its own, so a model reading the
  raw narrative already sees exactly where each embed occurs -- no
  destructive rewriting is needed to convey position, and every resolved
  embed's part is simply appended after the text part, in first-occurrence
  order.

  Each resolved embed becomes one further content part, typed by mapping
  its name's file extension to a MIME type: image extensions become
  `"image_url"` parts (a base64 data URI, exactly like `ContextExpander`);
  everything else becomes an `"attachment"` part carrying the resolved
  content directly (`%{"type" => "attachment", "name" => ..., "mime" =>
  ..., "content" => ...}`).
  """

  alias Lmml.Embed
  alias Lmml.Narrative.Resolver

  @extension_mime_types %{
    # Images (rendered as `image_url` data URIs)
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".bmp" => "image/bmp",
    ".svg" => "image/svg+xml",
    ".avif" => "image/avif",
    ".tif" => "image/tiff",
    ".tiff" => "image/tiff",
    ".ico" => "image/x-icon",
    # Structured / data text
    ".json" => "application/json",
    ".yaml" => "application/yaml",
    ".yml" => "application/yaml",
    ".toml" => "application/toml",
    ".xml" => "application/xml",
    ".csv" => "text/csv",
    ".html" => "text/html",
    ".htm" => "text/html",
    # Plain text & code-ish embeds
    ".txt" => "text/plain",
    ".md" => "text/markdown",
    ".log" => "text/plain",
    ".diff" => "text/x-diff",
    ".patch" => "text/x-diff",
    ".py" => "text/x-python",
    ".rb" => "text/x-ruby",
    ".ex" => "text/x-elixir",
    ".exs" => "text/x-elixir",
    ".sh" => "text/x-shellscript",
    ".sql" => "text/x-sql",
    # Documents
    ".pdf" => "application/pdf",
    ".doc" => "application/msword",
    ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    # Audio / video
    ".mp3" => "audio/mpeg",
    ".wav" => "audio/wav",
    ".ogg" => "audio/ogg",
    ".m4a" => "audio/mp4",
    ".mp4" => "video/mp4",
    ".webm" => "video/webm"
  }
  @default_mime "application/octet-stream"

  @type content_part :: %{required(String.t()) => String.t() | map()}

  @typedoc "Options for `render/2`."
  @type opts :: [max_embed_bytes: non_neg_integer()]

  @doc """
  Renders a resolved narrative into an ordered list of content parts, text
  first. Equivalent to `render/2` with no options.
  """
  @spec render(Resolver.t()) :: [content_part()]
  def render(resolved), do: render(resolved, [])

  @doc """
  Renders a resolved narrative into an ordered list of content parts, text
  first, honoring `opts`.

  Options:

    - `:max_embed_bytes` -- a per-embed byte budget. Any resolved embed
      whose content exceeds this size is *omitted* from the result (it is
      not truncated, since a partial image or config is worse than none).
      This is a safety valve for sending a narrative to an API with a
      payload/token budget: set it to the largest single asset you are
      willing to transmit and oversized embeds quietly drop out rather
      than blowing the request. Defaults to no limit (all embeds kept).

  The narrative's raw text always becomes the first, verbatim `"text"`
  part regardless of `opts`.
  """
  @spec render(Resolver.t(), opts()) :: [content_part()]
  def render(%Resolver{narrative: narrative, embeds: resolved}, opts) do
    max_bytes = Keyword.get(opts, :max_embed_bytes)

    kept =
      case max_bytes do
        nil -> resolved
        limit -> Enum.filter(resolved, &(byte_size(&1.content) <= limit))
      end

    [%{"type" => "text", "text" => narrative} | Enum.map(kept, &render_embed/1)]
  end

  @doc """
  The total byte size of all resolved embed content in `resolved` (the sum
  of every embed's resolved bytes, not counting the narrative text). Useful
  for gauging a narrative's payload against a budget before rendering.
  """
  @spec total_embed_bytes(Resolver.t()) :: non_neg_integer()
  def total_embed_bytes(%Resolver{embeds: resolved}) do
    Enum.reduce(resolved, 0, fn %{content: content}, acc -> acc + byte_size(content) end)
  end

  @doc "The MIME type inferred for `name` by its file extension, defaulting to `#{@default_mime}` when unrecognized."
  @spec mime_type(String.t()) :: String.t()
  def mime_type(name) do
    name
    |> Path.extname()
    |> String.downcase()
    |> then(&Map.get(@extension_mime_types, &1, @default_mime))
  end

  @doc "True when `name`'s inferred MIME type is an image type."
  @spec image?(String.t()) :: boolean()
  def image?(name), do: String.starts_with?(mime_type(name), "image/")

  @doc """
  Exports a narrative to standard, human-readable Markdown by replacing
  embed syntax (`@name.ext` and `@@@name.ext ... @@@`) with clean text
  placeholders (e.g. `[Image: logo.png]` or `[Attachment: config.yaml]`).
  """
  @spec to_md(Resolver.t() | Lmml.Bundle.t(), keyword()) :: String.t()
  def to_md(target, opts \\ [])

  def to_md(%Resolver{narrative: narrative, embeds: resolved}, _opts) do
    text_without_fences = Enum.reduce(resolved, narrative, &replace_inline_fence/2)
    Enum.reduce(resolved, text_without_fences, &replace_external_sigil/2)
  end

  def to_md(%Lmml.Bundle{} = bundle, opts) do
    case Resolver.resolve(bundle) do
      {:ok, resolved} ->
        to_md(resolved, opts)

      {:error, _} ->
        narrative = Lmml.Bundle.narrative(bundle)
        Enum.reduce(Lmml.Bundle.embeds(bundle), narrative, &convert_unresolved_embed/2)
    end
  end

  defp replace_inline_fence(%{embed: embed}, acc) do
    if Embed.inline?(embed) do
      fence = "@@@" <> embed.name <> "\n" <> Embed.content(embed) <> "@@@"
      String.replace(acc, fence, placeholder_for(embed.name))
    else
      acc
    end
  end

  defp replace_external_sigil(%{embed: embed}, acc) do
    if Embed.external?(embed) do
      name = embed.name
      pattern = ~r/@#{Regex.escape(name)}(?!\w)/u
      Regex.replace(pattern, acc, placeholder_for(name))
    else
      acc
    end
  end

  defp convert_unresolved_embed(embed, acc) do
    if Embed.inline?(embed) do
      fence = "@@@" <> embed.name <> "\n" <> Embed.content(embed) <> "@@@"
      String.replace(acc, fence, placeholder_for(embed.name))
    else
      pattern = ~r/@#{Regex.escape(embed.name)}(?!\w)/u
      Regex.replace(pattern, acc, placeholder_for(embed.name))
    end
  end

  defp placeholder_for(name) do
    if image?(name), do: "[Image: #{name}]", else: "[Attachment: #{name}]"
  end

  defp render_embed(%{embed: %Embed{name: name}, content: content}) do
    if image?(name) do
      %{"type" => "image_url", "image_url" => %{"url" => data_uri(name, content)}}
    else
      %{"type" => "attachment", "name" => name, "mime" => mime_type(name), "content" => content}
    end
  end

  defp data_uri(name, content), do: "data:#{mime_type(name)};base64,#{Base.encode64(content)}"
end
