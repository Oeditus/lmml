defmodule Lmml.Document do
  @moduledoc """
  A parsed `lmml` narrative: the `Md`-produced AST plus the flat list of
  `Lmml.Embed`s discovered anywhere within it (however deeply nested --
  inside a list item, a blockquote, an emphasis span, and so on).

  This is the file-form-independent half of the data model: a `Document`
  knows exactly what embeds a narrative *mentions*, but nothing about
  where an external one's bytes actually live -- that's `Lmml.Bundle`'s
  job, since only the bundle knows whether it's backed by a bare `.lmml`
  text file (nothing to resolve `@ref`s against) or a `.lmmlz` zip
  archive (which has real entries to look up).
  """

  alias Lmml.Embed
  alias Lmml.Narrative.Parser

  @enforce_keys [:ast, :embeds]
  defstruct [:ast, :embeds]

  @type ast :: [Md.Listener.branch()]
  @type t :: %__MODULE__{ast: ast(), embeds: [Embed.t()]}

  @doc """
  Parses raw narrative text into a `Document`, extracting every `@name.ext`
  reference and `@@@name.ext ... @@@` inline embed found anywhere in the
  resulting AST.

  Never fails on malformed/unexpected input in the way a strict grammar
  might: `lmml` is a superset of Markdown, so anything `Md.Parser.Default`
  itself can parse, this parses too (see `Lmml.Narrative.Parser`).

  The `@@@name ... @@@` block is declared with `escape: false` in
  `Lmml.Narrative.Syntax` (`Md` >= 0.12.2), so an `:lmml_embed` node's
  content already matches the literal bytes written between the fences
  verbatim -- no post-processing needed here.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, term()}
  def parse(narrative) when is_binary(narrative) do
    {"", state} = Parser.parse(narrative)
    {:ok, %__MODULE__{ast: state.ast, embeds: collect_embeds(state.ast)}}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Same as `parse/1`, but raises on failure."
  @spec parse!(binary()) :: t()
  def parse!(narrative) do
    case parse(narrative) do
      {:ok, document} -> document
      {:error, reason} -> raise "Failed to parse lmml narrative: #{reason}"
    end
  end

  @doc """
  Looks up the first embed named `name`.

  A narrative may legitimately mention the same *external* reference more
  than once (e.g. `@image.png` appearing twice just means "this image,
  again"); this always returns the first occurrence. Detecting *inline*
  embeds that share a name but disagree on content is `Lmml.Bundle.validate/1`'s
  job, not this function's.
  """
  @spec embed(t(), String.t()) :: {:ok, Embed.t()} | {:error, :not_found}
  def embed(%__MODULE__{embeds: embeds}, name) do
    case Enum.find(embeds, &(&1.name == name)) do
      nil -> {:error, :not_found}
      embed -> {:ok, embed}
    end
  end

  @doc "Names of every embed mentioned in the document, in first-seen order, deduplicated."
  @spec embed_names(t()) :: [String.t()]
  def embed_names(%__MODULE__{embeds: embeds}) do
    embeds |> Enum.map(& &1.name) |> Enum.uniq()
  end

  @doc "Embeds whose content is external (a `@name.ext` reference needing a zip entry to resolve)."
  @spec external_embeds(t()) :: [Embed.t()]
  def external_embeds(%__MODULE__{embeds: embeds}), do: Enum.filter(embeds, &Embed.external?/1)

  @doc "Embeds whose content is carried inline (a `@@@name.ext ... @@@` block)."
  @spec inline_embeds(t()) :: [Embed.t()]
  def inline_embeds(%__MODULE__{embeds: embeds}), do: Enum.filter(embeds, &Embed.inline?/1)

  # ---------------------------------------------------------------------
  # AST walking
  # ---------------------------------------------------------------------

  @spec collect_embeds(ast() | Md.Listener.branch() | term()) :: [Embed.t()]
  defp collect_embeds(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &collect_embeds/1)

  defp collect_embeds({:lmml_ref, %{name: name}, []}) when is_binary(name) do
    [Embed.external(name)]
  end

  defp collect_embeds({:lmml_embed, %{name: name}, [content]})
       when is_binary(name) and is_binary(content) do
    [Embed.inline(name, content)]
  end

  defp collect_embeds({:lmml_embed, %{name: name}, []}) when is_binary(name) do
    [Embed.inline(name, "")]
  end

  defp collect_embeds({_tag, _attrs, children}) when is_list(children) do
    collect_embeds(children)
  end

  defp collect_embeds(_leaf_or_unrecognized), do: []
end
