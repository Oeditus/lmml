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
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".bmp" => "image/bmp",
    ".json" => "application/json",
    ".yaml" => "application/yaml",
    ".yml" => "application/yaml",
    ".txt" => "text/plain",
    ".md" => "text/markdown"
  }
  @default_mime "application/octet-stream"

  @type content_part :: %{required(String.t()) => String.t() | map()}

  @doc "Renders a resolved narrative into an ordered list of content parts, text first."
  @spec render(Resolver.t()) :: [content_part()]
  def render(%Resolver{narrative: narrative, embeds: resolved}) do
    [%{"type" => "text", "text" => narrative} | Enum.map(resolved, &render_embed/1)]
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

  defp render_embed(%{embed: %Embed{name: name}, content: content}) do
    if image?(name) do
      %{"type" => "image_url", "image_url" => %{"url" => data_uri(name, content)}}
    else
      %{"type" => "attachment", "name" => name, "mime" => mime_type(name), "content" => content}
    end
  end

  defp data_uri(name, content), do: "data:#{mime_type(name)};base64,#{Base.encode64(content)}"
end
