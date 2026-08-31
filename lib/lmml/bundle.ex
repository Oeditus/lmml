defmodule Lmml.Bundle do
  @moduledoc """
  A loaded `lmml` entity, regardless of which of the two on-disk forms it
  came from:

    - `.lmml` -- a bare, self-contained Markdown-superset text file. There
      is nowhere for an external reference to point to, so every embed it
      mentions must be inline.
    - `.lmmlz` -- a zip archive whose canonical narrative entry is named
      by stripping the trailing `z` from the archive's own filename
      (`foo.lmmlz` contains `foo.lmml`), plus whatever other entries its
      `@name.ext` references point at.

  `open/1` detects which form a file is by sniffing its content (the zip
  local-file-header magic bytes), not by trusting its extension, and
  either way returns a `Bundle` exposing the exact same API: `narrative/1`,
  `embeds/1`, `embed/2`, `entries/1`.
  """

  alias Lmml.Document
  alias Lmml.Embed

  @enforce_keys [:kind, :name, :narrative, :document, :entries]
  defstruct [:kind, :name, :narrative, :document, :entries]

  @typedoc "Which on-disk form this bundle was loaded from (or is destined for)."
  @type kind :: :text | :zip

  @type t :: %__MODULE__{
          kind: kind(),
          name: String.t(),
          narrative: binary(),
          document: Document.t(),
          entries: %{optional(String.t()) => binary()}
        }

  # Local file header signature ("PK\x03\x04"), the byte sequence every
  # non-empty zip archive starts with. Sniffing this (rather than trusting
  # the `.lmml`/`.lmmlz` extension) is what lets `open/1` treat a
  # misnamed or extensionless file correctly, and is the same technique
  # `.docx`/`.epub`-style "zip wearing a different extension" formats rely on.
  @zip_magic <<0x50, 0x4B, 0x03, 0x04>>

  # ---------------------------------------------------------------------
  # Opening from disk
  # ---------------------------------------------------------------------

  @doc """
  Opens a `lmml` entity from disk, auto-detecting whether `path` is a bare
  text narrative or a zip archive by sniffing its content.
  """
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(path) do
    with {:ok, content} <- File.read(path) do
      name = path |> Path.basename() |> narrative_name_for()

      if zip_content?(content), do: open_zip(name, content), else: open_text(name, content)
    end
  end

  @doc "Same as `open/1`, but raises on failure."
  @spec open!(Path.t()) :: t()
  def open!(path) do
    case open(path) do
      {:ok, bundle} -> bundle
      {:error, reason} -> raise "Failed to open lmml bundle at #{path}: #{inspect(reason)}"
    end
  end

  @spec zip_content?(binary()) :: boolean()
  defp zip_content?(content) when is_binary(content) do
    byte_size(content) >= byte_size(@zip_magic) and
      binary_part(content, 0, byte_size(@zip_magic)) == @zip_magic
  end

  defp open_text(name, content) do
    with {:ok, document} <- Document.parse(content) do
      {:ok,
       %__MODULE__{kind: :text, name: name, narrative: content, document: document, entries: %{}}}
    end
  end

  defp open_zip(name, content) do
    with {:ok, raw_entries} <- unzip(content),
         :ok <- validate_entry_names(Map.keys(raw_entries)),
         {:ok, narrative} <- fetch_narrative(raw_entries, name),
         {:ok, document} <- Document.parse(narrative) do
      entries = Map.delete(raw_entries, name)

      {:ok,
       %__MODULE__{
         kind: :zip,
         name: name,
         narrative: narrative,
         document: document,
         entries: entries
       }}
    end
  end

  defp unzip(content) do
    case :zip.unzip(content, [:memory]) do
      {:ok, files} ->
        {:ok, Map.new(files, fn {filename, data} -> {to_string(filename), data} end)}

      {:error, reason} ->
        {:error, {:invalid_zip, reason}}
    end
  end

  defp fetch_narrative(entries, name) do
    case Map.fetch(entries, name) do
      {:ok, narrative} -> {:ok, narrative}
      :error -> {:error, {:missing_narrative_entry, name}}
    end
  end

  # ---------------------------------------------------------------------
  # Building in memory
  # ---------------------------------------------------------------------

  @doc """
  Builds a bare-text bundle directly from narrative text, without touching
  disk. `name` is normalized to always end in `.lmml` (the logical
  narrative name is the same regardless of file form).
  """
  @spec new_text(String.t(), binary()) :: {:ok, t()} | {:error, term()}
  def new_text(name, narrative) when is_binary(name) and is_binary(narrative) do
    with {:ok, document} <- Document.parse(narrative) do
      {:ok,
       %__MODULE__{
         kind: :text,
         name: narrative_name_for(name),
         narrative: narrative,
         document: document,
         entries: %{}
       }}
    end
  end

  @doc """
  Builds a zip-backed bundle directly from narrative text plus a map of
  external entries (`%{"image.png" => <<bytes>>}`), without touching disk.
  Every entry name is path-safety validated the same way `open/1` validates
  entries read from a real archive.
  """
  @spec new_zip(String.t(), binary(), %{optional(String.t()) => binary()}) ::
          {:ok, t()} | {:error, term()}
  def new_zip(name, narrative, entries \\ %{})
      when is_binary(name) and is_binary(narrative) and is_map(entries) do
    with :ok <- validate_entry_names(Map.keys(entries)),
         {:ok, document} <- Document.parse(narrative) do
      {:ok,
       %__MODULE__{
         kind: :zip,
         name: narrative_name_for(name),
         narrative: narrative,
         document: document,
         entries: entries
       }}
    end
  end

  # ---------------------------------------------------------------------
  # Writing to disk
  # ---------------------------------------------------------------------

  @doc """
  Persists a bundle to disk in its *current* form (text stays text, zip
  stays zip) -- this does not convert between forms; see `Lmml.Pack` for
  that. For a `:zip` bundle, the internal narrative entry name is always
  freshly derived from `path`'s own basename (not from whatever name the
  bundle was constructed/opened with), so whatever you write is always
  internally self-consistent with its own filename.
  """
  @spec write!(t(), Path.t()) :: :ok
  def write!(%__MODULE__{kind: :text, narrative: narrative}, path) do
    File.write!(path, narrative)
  end

  def write!(%__MODULE__{kind: :zip, narrative: narrative, entries: entries}, path) do
    name = path |> Path.basename() |> narrative_name_for()

    file_entries =
      [{String.to_charlist(name), narrative} | Enum.map(entries, &to_charlist_entry/1)]

    case :zip.create(String.to_charlist(path), file_entries) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to write .lmmlz archive to #{path}: #{inspect(reason)}"
    end
  end

  defp to_charlist_entry({entry_name, data}), do: {String.to_charlist(entry_name), data}

  # ---------------------------------------------------------------------
  # Uniform accessors
  # ---------------------------------------------------------------------

  @doc "The bundle's own logical name (always ending in `.lmml`, regardless of bundle kind)."
  @spec name(t()) :: String.t()
  def name(%__MODULE__{name: name}), do: name

  @doc "The bundle's raw narrative text."
  @spec narrative(t()) :: binary()
  def narrative(%__MODULE__{narrative: narrative}), do: narrative

  @doc "Every embed mentioned in the narrative (see `Lmml.Document`'s `embeds` field)."
  @spec embeds(t()) :: [Embed.t()]
  def embeds(%__MODULE__{document: document}), do: document.embeds

  @doc "Names of the zip entries this bundle carries, excluding the narrative itself. Always `[]` for a `:text` bundle."
  @spec entries(t()) :: [String.t()]
  def entries(%__MODULE__{entries: entries}), do: Map.keys(entries)

  @doc "True for a bundle backed by a bare text narrative (no external files possible)."
  @spec text?(t()) :: boolean()
  def text?(%__MODULE__{kind: :text}), do: true
  def text?(%__MODULE__{}), do: false

  @doc "True for a bundle backed by a zip archive."
  @spec zip?(t()) :: boolean()
  def zip?(%__MODULE__{kind: :zip}), do: true
  def zip?(%__MODULE__{}), do: false

  @doc """
  Resolves a named embed's actual content: inline embeds return their
  own captured text directly (working for any bundle kind); external
  references are looked up among the zip's entries, which only exists
  for a `:zip` bundle.
  """
  @spec embed(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def embed(%__MODULE__{document: document} = bundle, name) do
    with {:ok, embed} <- Document.embed(document, name) do
      resolve(bundle, embed)
    end
  end

  defp resolve(_bundle, %Embed{content: {:inline, content}}), do: {:ok, content}

  defp resolve(%__MODULE__{kind: :text}, %Embed{content: {:external, entry_name}}) do
    {:error, {:unresolvable_reference, entry_name}}
  end

  defp resolve(%__MODULE__{kind: :zip, entries: entries}, %Embed{content: {:external, entry_name}}) do
    with :ok <- validate_entry_names([entry_name]) do
      case Map.fetch(entries, entry_name) do
        {:ok, data} -> {:ok, data}
        :error -> {:error, {:missing_entry, entry_name}}
      end
    end
  end

  # ---------------------------------------------------------------------
  # Cross-bundle validation
  # ---------------------------------------------------------------------

  @typedoc "A single issue found by `validate/1`."
  @type validation_issue ::
          {:missing_reference, String.t()}
          | {:orphaned_entry, String.t()}
          | {:malformed_embed_name, String.t()}
          | {:conflicting_embed, String.t()}

  @doc """
  Cross-checks a bundle's narrative against its own entries and its own
  internal consistency. This is a distinct, opt-in step from `open/1` or
  `new_zip/3` (which only ever reject an entry name that is outright
  *unsafe* -- see `validate_entry_names/1`): `validate/1` instead catches
  authoring mistakes that are still perfectly well-formed as far as
  parsing and path-safety go. Every issue found is returned at once,
  rather than stopping at the first:

    - `{:missing_reference, name}` -- an `@name.ext` reference has no
      matching zip entry. For a `:text` bundle this fires for *every*
      external reference, since a bare `.lmml` has no entries at all to
      resolve one against.
    - `{:orphaned_entry, name}` -- a zip entry that no embed in the
      narrative actually mentions.
    - `{:malformed_embed_name, name}` -- an embed name (inline or
      external) that could not safely become a zip entry name (see
      `validate_entry_names/1`). This applies to every embed, not only
      inline ones, since `Lmml.Pack.pack/2` (planned) can turn any inline
      embed into a real zip entry later.
    - `{:conflicting_embed, name}` -- two or more embeds share a name but
      disagree on content (including disagreeing on inline-vs-external),
      which is an authoring mistake: a name is meant to identify one
      entity consistently throughout a narrative.

  Returns `:ok` when none of the above apply.
  """
  @spec validate(t()) :: :ok | {:error, [validation_issue()]}
  def validate(%__MODULE__{} = bundle) do
    issues =
      missing_reference_issues(bundle) ++
        orphaned_entry_issues(bundle) ++
        malformed_name_issues(bundle) ++
        conflicting_embed_issues(bundle)

    if issues == [], do: :ok, else: {:error, issues}
  end

  defp missing_reference_issues(%__MODULE__{document: document, entries: entries}) do
    document
    |> Document.external_embeds()
    |> Enum.uniq_by(& &1.name)
    |> Enum.reject(fn %Embed{content: {:external, entry_name}} ->
      Map.has_key?(entries, entry_name)
    end)
    |> Enum.map(fn %Embed{name: name} -> {:missing_reference, name} end)
  end

  defp orphaned_entry_issues(%__MODULE__{document: document, entries: entries}) do
    referenced =
      document
      |> Document.external_embeds()
      |> MapSet.new(fn %Embed{content: {:external, entry_name}} -> entry_name end)

    entries
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(referenced, &1))
    |> Enum.map(&{:orphaned_entry, &1})
  end

  defp malformed_name_issues(%__MODULE__{document: document}) do
    document
    |> Document.embed_names()
    |> Enum.reject(&(validate_entry_names([&1]) == :ok))
    |> Enum.map(&{:malformed_embed_name, &1})
  end

  defp conflicting_embed_issues(%__MODULE__{document: document}) do
    document.embeds
    |> Enum.group_by(& &1.name, & &1.content)
    |> Enum.filter(fn {_name, contents} -> contents |> Enum.uniq() |> length() > 1 end)
    |> Enum.map(fn {name, _contents} -> {:conflicting_embed, name} end)
  end

  # ---------------------------------------------------------------------
  # Naming & path safety
  # ---------------------------------------------------------------------

  # `foo.lmmlz` -> `foo.lmml` (strip exactly one trailing `z`); any other
  # basename (including one that's already `.lmml`, or has no recognized
  # lmml extension at all) is used as-is unless it lacks a `.lmml` suffix
  # entirely, in which case one is appended -- the logical narrative name
  # is always `<basename>.lmml`.
  @spec narrative_name_for(String.t()) :: String.t()
  defp narrative_name_for(basename) do
    cond do
      String.ends_with?(basename, ".lmmlz") -> String.trim_trailing(basename, "z")
      String.ends_with?(basename, ".lmml") -> basename
      true -> basename <> ".lmml"
    end
  end

  @doc """
  Validates that none of `names` could escape the bundle root when
  resolved: no absolute paths, no `..` path segments. Used both when
  opening a zip archive (every entry it contains) and when resolving a
  single reference at read time.

  Note: for archives that actually went through `:zip.unzip/2` (i.e. every
  entry reaching this check via `open/1`), Erlang's own zip implementation
  has *already* sanitized traversal/absolute entry names down to a bare
  basename (logging a warning as it does so) by the time this runs -- so
  in practice this check rarely has anything to catch on that path. It
  remains meaningful as the *only* line of defense for entries that never
  go through `:zip` at all, i.e. those supplied directly to `new_zip/3`.
  """
  @spec validate_entry_names([String.t()]) :: :ok | {:error, {:unsafe_entry, String.t()}}
  def validate_entry_names(names) do
    case Enum.find(names, &(not safe_entry_name?(&1))) do
      nil -> :ok
      unsafe -> {:error, {:unsafe_entry, unsafe}}
    end
  end

  @spec safe_entry_name?(String.t()) :: boolean()
  defp safe_entry_name?(name) do
    not String.starts_with?(name, "/") and
      not String.contains?(name, "\\") and
      not Enum.any?(Path.split(name), &(&1 == ".."))
  end
end
