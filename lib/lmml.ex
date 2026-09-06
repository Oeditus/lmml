defmodule Lmml do
  @moduledoc """
  `lmml` is a markup format for talking to LLMs, designed as a strict
  superset of Markdown.

  A `.lmml` file is a self-contained narrative (Markdown-superset text).
  A `.lmmlz` file is the same narrative packed into a zip archive
  alongside the external files it references (its canonical narrative
  entry is named by stripping the trailing `z` from the archive's own
  filename, e.g. `foo.lmmlz` contains `foo.lmml`).

  Both forms express the same underlying model: an ordered narrative with
  zero or more named *embeds*, differing only in whether each embed's
  content is inline (`@@@name ... @@@`) or external (`@name`, resolved
  against the zip).

  This top-level module is a convenience façade delegating to the focused
  underlying modules: `Lmml.Bundle`, `Lmml.Pack`, `Lmml.Manifest`,
  `Lmml.Settings`, and `Lmml.Narrative.*`.

  ## Naming conventions for raising vs tagged tuple functions

  Across the entire surface of `lmml`:

    - **Constructors and loaders** (`open/1`, `resolve/1`, `pack/2`,
      `inline/2`, `manifest/1`, `settings/2`) return tagged tuples
      `{:ok, result}` or `{:error, reason}` by default.
    - Bang variants (`open!/1`, `resolve!/1`, `pack!/2`, `inline!/2`,
      `manifest!/1`, `settings!/2`) raise on failure.
    - **I/O Writers** (`Bundle.write!/2`) raise on failure.
  """

  alias Lmml.Bundle
  alias Lmml.Manifest
  alias Lmml.Narrative.Renderer
  alias Lmml.Narrative.Resolver
  alias Lmml.Narrative.Segment
  alias Lmml.Pack
  alias Lmml.Settings

  @doc "Opens a `.lmml`/`.lmmlz` entity from disk. Delegates to `Lmml.Bundle.open/1`."
  @spec open(Path.t()) :: {:ok, Bundle.t()} | {:error, term()}
  def open(path), do: Bundle.open(path)

  @doc "Same as `open/1`, but raises on failure. Delegates to `Lmml.Bundle.open!/1`."
  @spec open!(Path.t()) :: Bundle.t()
  def open!(path), do: Bundle.open!(path)

  @doc "Builds a bare-text bundle from narrative text. Delegates to `Lmml.Bundle.new_text/2`."
  @spec new_text(String.t(), binary()) :: {:ok, Bundle.t()} | {:error, term()}
  def new_text(name, narrative), do: Bundle.new_text(name, narrative)

  @doc "Builds a zip-backed bundle from narrative text plus external entries. Delegates to `Lmml.Bundle.new_zip/3`."
  @spec new_zip(String.t(), binary(), %{optional(String.t()) => binary()}) ::
          {:ok, Bundle.t()} | {:error, term()}
  def new_zip(name, narrative, entries \\ %{}), do: Bundle.new_zip(name, narrative, entries)

  @doc "Resolves every embed a bundle's narrative mentions. Delegates to `Lmml.Narrative.Resolver.resolve/1`."
  @spec resolve(Bundle.t()) :: {:ok, Resolver.t()} | {:error, term()}
  def resolve(bundle), do: Resolver.resolve(bundle)

  @doc "Same as `resolve/1`, but raises on failure. Delegates to `Lmml.Narrative.Resolver.resolve!/1`."
  @spec resolve!(Bundle.t()) :: Resolver.t()
  def resolve!(bundle), do: Resolver.resolve!(bundle)

  @doc "Renders a resolved narrative into typed content parts. Delegates to `Lmml.Narrative.Renderer.render/2`."
  @spec render(Resolver.t(), Renderer.opts()) :: [Renderer.content_part()]
  def render(resolved, opts \\ []), do: Renderer.render(resolved, opts)

  @doc "Exports a narrative or bundle to standard Markdown with text placeholders. Delegates to `Lmml.Narrative.Renderer.to_md/2`."
  @spec to_md(Resolver.t() | Bundle.t(), keyword()) :: String.t()
  def to_md(target, opts \\ []), do: Renderer.to_md(target, opts)

  @doc "Cross-checks a bundle's narrative against its own entries. Delegates to `Lmml.Bundle.validate/1`."
  @spec validate(Bundle.t()) :: :ok | {:error, [Bundle.validation_issue()]}
  def validate(bundle), do: Bundle.validate(bundle)

  @doc "Externalizes inline embeds into a zip-backed bundle. Delegates to `Lmml.Pack.pack/2`."
  @spec pack(Bundle.t(), String.t() | nil) :: {:ok, Bundle.t()} | {:error, term()}
  def pack(bundle, name \\ nil), do: Pack.pack(bundle, name)

  @doc "Same as `pack/2`, but raises on failure. Delegates to `Lmml.Pack.pack!/2`."
  @spec pack!(Bundle.t(), String.t() | nil) :: Bundle.t()
  def pack!(bundle, name \\ nil), do: Pack.pack!(bundle, name)

  @doc "Inlines zip entries into narrative fence blocks. Delegates to `Lmml.Pack.inline/2`."
  @spec inline(Bundle.t(), String.t() | nil) :: {:ok, Bundle.t()} | {:error, term()}
  def inline(bundle, name \\ nil), do: Pack.inline(bundle, name)

  @doc "Same as `inline/2`, but raises on failure. Delegates to `Lmml.Pack.inline!/2`."
  @spec inline!(Bundle.t(), String.t() | nil) :: Bundle.t()
  def inline!(bundle, name \\ nil), do: Pack.inline!(bundle, name)

  @doc "Splits a resolved narrative into ordered role turns. Delegates to `Lmml.Narrative.Segment.segment/2`."
  @spec segment(Resolver.t(), keyword()) :: [Segment.t()]
  def segment(resolved, opts \\ []), do: Segment.segment(resolved, opts)

  @doc "Segments and renders each turn into message objects. Delegates to `Lmml.Narrative.Segment.render_turns/2`."
  @spec render_turns(Resolver.t(), keyword()) :: [%{role: Segment.role(), content: [map()]}]
  def render_turns(resolved, opts \\ []), do: Segment.render_turns(resolved, opts)

  @doc "Loads settings from a bundle. Delegates to `Lmml.Settings.load/2`."
  @spec settings(Bundle.t(), String.t()) :: {:ok, Settings.t() | nil} | {:error, term()}
  def settings(bundle, name \\ Settings.name()), do: Settings.load(bundle, name)

  @doc "Same as `settings/2`, but raises on failure. Delegates to `Lmml.Settings.load!/2`."
  @spec settings!(Bundle.t(), String.t()) :: Settings.t() | nil
  def settings!(bundle, name \\ Settings.name()), do: Settings.load!(bundle, name)

  @doc "Loads manifest metadata from a bundle. Delegates to `Lmml.Manifest.load/1`."
  @spec manifest(Bundle.t()) :: {:ok, Manifest.t() | nil} | {:error, term()}
  def manifest(bundle), do: Manifest.load(bundle)

  @doc "Same as `manifest/1`, but raises on failure. Delegates to `Lmml.Manifest.load!/1`."
  @spec manifest!(Bundle.t()) :: Manifest.t() | nil
  def manifest!(bundle), do: Manifest.load!(bundle)

  @doc "Returns every embed mentioned in the bundle's narrative. Delegates to `Lmml.Bundle.embeds/1`."
  @spec embeds(Bundle.t()) :: [Lmml.Embed.t()]
  def embeds(bundle), do: Bundle.embeds(bundle)

  @doc "Returns the bundle's raw narrative text. Delegates to `Lmml.Bundle.narrative/1`."
  @spec narrative(Bundle.t()) :: binary()
  def narrative(bundle), do: Bundle.narrative(bundle)
end
