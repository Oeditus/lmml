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
  alias Lmml.Manifest
  alias Lmml.Settings

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

  # Zip archive magic bytes: local file header ("PK\x03\x04"), empty archive
  # end-of-central-directory ("PK\x05\x06"), and spanned archive ("PK\x07\x08").
  @zip_magics [
    <<0x50, 0x4B, 0x03, 0x04>>,
    <<0x50, 0x4B, 0x05, 0x06>>,
    <<0x50, 0x4B, 0x07, 0x08>>
  ]

  @reserved_settings_names ["settings.yaml", "settings.yml", "settings.json"]

  # ---------------------------------------------------------------------
  # Opening from disk
  # ---------------------------------------------------------------------

  @doc """
  Opens a `lmml` entity from disk, auto-detecting whether `path` is a bare
  text narrative or a zip archive by sniffing its content.

  Validates the resulting bundle by default (`validate: true`), rejecting any
  non-100%-valid LMML input with `{:error, {:invalid_bundle, issues}}` or a
  more specific parse/container error. Pass `validate: false` only when
  explicitly inspecting or diagnosing a malformed bundle.
  """
  @spec open(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def open(path, opts \\ [])

  def open(path, opts) when is_binary(path) and is_list(opts) do
    validate? = Keyword.get(opts, :validate, true)

    with {:ok, content} <- File.read(path),
         {:ok, bundle} <- decode_content(path, content) do
      maybe_validate(bundle, validate?)
    end
  end

  def open(_invalid, _opts), do: {:error, :invalid_input}

  @doc "Same as `open/2`, but raises on failure."
  @spec open!(Path.t(), keyword()) :: t()
  def open!(path, opts \\ []) do
    case open(path, opts) do
      {:ok, bundle} -> bundle
      {:error, reason} -> raise "Failed to open lmml bundle at #{path}: #{inspect(reason)}"
    end
  end

  defp decode_content(path, content) do
    name = path |> Path.basename() |> narrative_name_for()

    cond do
      zip_content?(content) ->
        open_zip(name, content)

      String.ends_with?(String.downcase(path), ".lmmlz") ->
        {:error, {:invalid_zip, :not_a_zip_archive}}

      true ->
        open_text(name, content)
    end
  end

  @spec zip_content?(binary()) :: boolean()
  defp zip_content?(<<magic::binary-size(4), _rest::binary>>), do: magic in @zip_magics
  defp zip_content?(_content), do: false

  defp open_text(name, content) do
    with {:ok, document} <- Document.parse(content, validate: false) do
      {:ok,
       %__MODULE__{kind: :text, name: name, narrative: content, document: document, entries: %{}}}
    end
  end

  defp open_zip(name, content) do
    with :ok <- validate_zip_table(content),
         {:ok, raw_entries} <- unzip(content),
         :ok <- validate_entry_names(Map.keys(raw_entries)),
         {:ok, narrative} <- fetch_narrative(raw_entries, name),
         {:ok, document} <- Document.parse(narrative, validate: false) do
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

  # Inspects the archive's central-directory entry names *before* any
  # in-memory extraction happens, so a hostile archive that tries to
  # escape the bundle root (an absolute path, a `..` segment, or a
  # backslash) is rejected with a clean `{:error, {:unsafe_entry, ...}}`
  # rather than being silently sanitized down to a bare basename by
  # `:zip.unzip/2` (which does collapse such names, but only with a
  # side-channel warning log the caller never sees). This is the same
  # defense `validate_entry_names/1` provides for entries that never go
  # through `:zip` at all (see `new_zip/3`); here it runs against the
  # archive's own table *before* extraction.
  defp validate_zip_table(content) do
    case :zip.table(content) do
      {:ok, table} ->
        names = table |> Enum.map(&entry_name/1) |> Enum.reject(&is_nil/1)
        validate_entry_names(names)

      {:error, reason} ->
        {:error, {:invalid_zip, reason}}
    end
  end

  # `:zip.table/1` returns a list whose elements are `{:zip_file, name,
  # info, comment, offset, csize}` tuples (one per entry) plus a leading
  # `{:zip_comment, comment}` tuple. We keep only the real file entries and
  # take each one's filename (element 2).
  defp entry_name({:zip_file, name, _info, _comment, _offset, _csize}), do: to_string(name)
  defp entry_name(_non_file_entry), do: nil

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

  Validates the resulting bundle by default (`validate: true`). Pass
  `validate: false` only when explicitly constructing a bundle for
  validation/diagnostic inspection.
  """
  @spec new_text(String.t(), binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def new_text(name, narrative, opts \\ [])

  def new_text(name, narrative, opts)
      when is_binary(name) and is_binary(narrative) and is_list(opts) do
    validate? = Keyword.get(opts, :validate, true)
    normalized = narrative_name_for(name)

    with :ok <- validate_bundle_name(name, normalized),
         {:ok, document} <- Document.parse(narrative, validate: false) do
      bundle = %__MODULE__{
        kind: :text,
        name: normalized,
        narrative: narrative,
        document: document,
        entries: %{}
      }

      maybe_validate(bundle, validate?)
    end
  end

  def new_text(_name, _narrative, _opts), do: {:error, :invalid_input}

  @doc """
  Builds a zip-backed bundle directly from narrative text plus a map of
  external entries (`%{"image.png" => <<bytes>>}`), without touching disk.
  Every entry name is path-safety validated the same way `open/1` validates
  entries read from a real archive.

  Validates the resulting bundle by default (`validate: true`). Pass
  `validate: false` only when explicitly constructing a bundle for
  validation/diagnostic inspection.
  """
  @spec new_zip(String.t(), binary(), %{optional(String.t()) => binary()}, keyword()) ::
          {:ok, t()} | {:error, term()}
  def new_zip(name, narrative, entries \\ %{}, opts \\ [])

  def new_zip(name, narrative, entries, opts)
      when is_binary(name) and is_binary(narrative) and is_map(entries) and is_list(opts) do
    validate? = Keyword.get(opts, :validate, true)
    normalized = narrative_name_for(name)

    with :ok <- validate_bundle_name(name, normalized),
         :ok <- validate_entries_map(entries),
         :ok <- validate_entry_names(Map.keys(entries)),
         {:ok, document} <- Document.parse(narrative, validate: false) do
      bundle = %__MODULE__{
        kind: :zip,
        name: normalized,
        narrative: narrative,
        document: document,
        entries: entries
      }

      maybe_validate(bundle, validate?)
    end
  end

  def new_zip(_name, _narrative, _entries, _opts), do: {:error, :invalid_input}

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

  Validates the bundle before writing (unless `validate: false` is passed) so
  malformed bundles are never persisted to disk by accident.
  """
  @spec write!(t(), Path.t(), keyword()) :: :ok
  def write!(bundle, path, opts \\ [])

  def write!(%__MODULE__{kind: :text, narrative: narrative} = bundle, path, opts) do
    ensure_writable!(bundle, opts)
    File.write!(path, narrative)
  end

  def write!(%__MODULE__{kind: :zip, narrative: narrative, entries: entries} = bundle, path, opts) do
    ensure_writable!(bundle, opts)
    name = path |> Path.basename() |> narrative_name_for()

    if Map.has_key?(entries, name) do
      raise "Failed to write .lmmlz archive to #{path}: entry #{inspect(name)} collides with narrative entry"
    end

    file_entries =
      [{String.to_charlist(name), narrative} | Enum.map(entries, &to_charlist_entry/1)]

    case :zip.create(String.to_charlist(path), file_entries) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "Failed to write .lmmlz archive to #{path}: #{inspect(reason)}"
    end
  end

  defp ensure_writable!(bundle, opts) do
    if Keyword.get(opts, :validate, true) do
      case validate(bundle) do
        :ok -> :ok
        {:error, issues} -> raise "Refusing to write invalid lmml bundle: #{inspect(issues)}"
      end
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
          | {:reserved_narrative_entry, String.t()}
          | {:invalid_narrative, term()}
          | {:invalid_manifest, term()}
          | {:invalid_settings, {String.t(), term()}}

  @doc """
  Cross-checks a bundle's narrative, entries, embed names, and reserved
  metadata embeds (`manifest.json`, `settings.yaml`/`.yml`/`.json`) for
  100% LMML conformance. Every issue found is returned at once, rather than
  stopping at the first:

    - `{:invalid_narrative, reason}` -- the narrative text itself is not
      syntactically valid LMML (e.g. invalid UTF-8 or unclosed `@@@` fence).
    - `{:missing_reference, name}` -- an `@name.ext` reference has no
      matching zip entry. For a `:text` bundle this fires for *every*
      external reference, since a bare `.lmml` has no entries at all to
      resolve one against.
    - `{:orphaned_entry, name}` -- a zip entry that no external embed in the
      narrative actually mentions.
    - `{:malformed_embed_name, name}` -- an embed or entry name that fails
      `Lmml.Embed.valid_name?/1`.
    - `{:conflicting_embed, name}` -- two or more embeds share a name but
      disagree on content (including disagreeing on inline-vs-external), or
      an inline embed shares a name with a zip entry.
    - `{:reserved_narrative_entry, name}` -- an embed or entry collides with
      the bundle's own canonical narrative entry name.
    - `{:invalid_manifest, reason}` -- a `manifest.json` embed is present but
      does not decode to a valid JSON object.
    - `{:invalid_settings, {name, reason}}` -- a `settings.yaml`/`.yml`/`.json`
      embed is present but fails decoding.

  Returns `:ok` when none of the above apply.
  """
  @spec validate(t()) :: :ok | {:error, [validation_issue()]}
  def validate(%__MODULE__{} = bundle) do
    issues =
      narrative_issues(bundle) ++
        missing_reference_issues(bundle) ++
        orphaned_entry_issues(bundle) ++
        malformed_name_issues(bundle) ++
        conflicting_embed_issues(bundle) ++
        reserved_narrative_entry_issues(bundle) ++
        reserved_metadata_issues(bundle)

    if issues == [], do: :ok, else: {:error, issues}
  end

  def validate(_invalid), do: {:error, [{:invalid_narrative, :invalid_input}]}

  defp maybe_validate(bundle, false), do: {:ok, bundle}

  defp maybe_validate(bundle, true) do
    case validate(bundle) do
      :ok -> {:ok, bundle}
      {:error, issues} -> {:error, {:invalid_bundle, issues}}
    end
  end

  defp narrative_issues(%__MODULE__{narrative: narrative}) do
    case Document.parse(narrative, validate: false) do
      {:ok, _doc} -> []
      {:error, reason} -> [{:invalid_narrative, reason}]
    end
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

  defp malformed_name_issues(%__MODULE__{document: document, entries: entries}) do
    names = Enum.uniq(Document.embed_names(document) ++ Map.keys(entries))

    names
    |> Enum.reject(&Embed.valid_name?/1)
    |> Enum.map(&{:malformed_embed_name, &1})
  end

  defp conflicting_embed_issues(%__MODULE__{document: document, entries: entries}) do
    in_narrative_conflicts =
      document.embeds
      |> Enum.group_by(& &1.name, & &1.content)
      |> Enum.filter(fn {_name, contents} -> contents |> Enum.uniq() |> length() > 1 end)
      |> Enum.map(fn {name, _contents} -> name end)

    inline_vs_entry_conflicts =
      document
      |> Document.inline_embeds()
      |> Enum.map(& &1.name)
      |> Enum.filter(&Map.has_key?(entries, &1))

    (in_narrative_conflicts ++ inline_vs_entry_conflicts)
    |> Enum.uniq()
    |> Enum.map(&{:conflicting_embed, &1})
  end

  defp reserved_narrative_entry_issues(%__MODULE__{
         name: name,
         document: document,
         entries: entries
       }) do
    names = Enum.uniq(Document.embed_names(document) ++ Map.keys(entries))

    if name in names do
      [{:reserved_narrative_entry, name}]
    else
      []
    end
  end

  defp reserved_metadata_issues(%__MODULE__{} = bundle) do
    manifest_issue =
      case Manifest.load_raw(bundle) do
        {:ok, _} -> []
        {:error, {:invalid_manifest, reason}} -> [{:invalid_manifest, reason}]
        # Resolution errors (e.g. missing_reference) are already reported above.
        {:error, _other} -> []
      end

    settings_issues =
      Enum.flat_map(@reserved_settings_names, fn settings_name ->
        case Settings.load_raw(bundle, settings_name) do
          {:ok, _} -> []
          {:error, {:invalid_settings, reason}} -> [{:invalid_settings, {settings_name, reason}}]
          {:error, _other} -> []
        end
      end)

    manifest_issue ++ settings_issues
  end

  # ---------------------------------------------------------------------
  # Naming & path safety
  # ---------------------------------------------------------------------

  defp validate_bundle_name("", _normalized), do: {:error, {:malformed_bundle_name, ""}}

  defp validate_bundle_name(raw_name, normalized) do
    if Embed.valid_name?(normalized) do
      :ok
    else
      {:error, {:malformed_bundle_name, raw_name}}
    end
  end

  defp validate_entries_map(entries) do
    valid? = Enum.all?(entries, fn {k, v} -> is_binary(k) and is_binary(v) end)
    if valid?, do: :ok, else: {:error, :invalid_input}
  end

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
  Validates that none of `names` could escape the bundle root or violate
  `Lmml.Embed.valid_name?/1`: no absolute paths, no `..` path segments, no
  backslashes, no whitespace or control characters. Used both when opening a
  zip archive (every entry it contains) and when resolving a single reference
  at read time.
  """
  @spec validate_entry_names([String.t()]) :: :ok | {:error, {:unsafe_entry, String.t()}}
  def validate_entry_names(names) do
    case Enum.find(names, &(not safe_entry_name?(&1))) do
      nil -> :ok
      unsafe -> {:error, {:unsafe_entry, unsafe}}
    end
  end

  @spec safe_entry_name?(String.t()) :: boolean()
  defp safe_entry_name?(name), do: Embed.valid_name?(name)
end
