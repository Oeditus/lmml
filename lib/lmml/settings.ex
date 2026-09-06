defmodule Lmml.Settings do
  @moduledoc """
  Optional project settings carried by a `Lmml.Bundle`.

  Settings are not a distinct mechanism -- they are simply an embed
  literally named `"settings.yaml"` (or `"settings.json"`), exactly like
  any other embed: `@@@settings.yaml ... @@@` inline, or
  `@settings.yaml` referencing a zip entry inside a `.lmmlz`. This module
  looks that embed up, decodes it, and exposes its top-level fields as a
  plain map -- mirroring `Lmml.Manifest`'s API shape.

  A bundle mentioning no settings embed at all has no settings -- that is
  a normal, fully-supported, non-error state (`load/1` returns `{:ok,
  nil}`), not something to special-case at every call site.

  ## Encoding support

  Which decoder is used depends on the settings embed's file extension:

    - `.json` -- decoded with OTP's built-in `:json` (this project has no
      `Jason` dependency).
    - `.yaml` / `.yml` -- decoded with a small, hand-rolled YAML-subset
      decoder (this project also has no YAML dependency). Support is
      deliberately limited to the common flat and lightly-nested shapes:

        * `key: value` mapping lines, where `value` is an integer, float,
          `true`/`false`, `null`, or a bare or quoted string;
        * nested maps written with indentation (`key:` followed by
          indented `child: value` lines); and
        * blank lines and full-line `#` comments.

      Anything outside that subset -- sequences/lists (`- item`),
      multi-line `|`/`>` block scalars, anchors/aliases, tags, etc. -- is
      rejected with `{:error, {:unsupported_yaml, line, reason}}` rather
      than silently mis-decoded. If a settings narrative needs richer
      YAML, name the embed `settings.json` instead.
  """

  alias Lmml.Bundle

  @settings_name "settings.yaml"

  @enforce_keys [:data]
  defstruct [:data]

  @type t :: %__MODULE__{data: map()}

  @doc "The reserved embed name a bundle's settings are looked up by by default."
  @spec name() :: String.t()
  def name, do: @settings_name

  @doc """
  Loads and decodes `bundle`'s settings embed, if any.

  Returns:
    - `{:ok, %Lmml.Settings{}}` -- a settings embed exists and decodes to
      a mapping.
    - `{:ok, nil}` -- no settings embed with `name` is mentioned anywhere
      in the narrative. This is the common case for a settings-less
      bundle, not an error.
    - `{:error, reason}` -- a settings embed *is* mentioned, but either
      its content is unresolvable (e.g. an `@settings.yaml` reference in
      a bare `.lmml`, or a dangling reference into a `.lmmlz`'s entries
      -- see `Lmml.Bundle.embed/2`), or its resolved content cannot be
      decoded (`{:invalid_settings, reason}`).
  """
  @spec load(Bundle.t(), String.t()) :: {:ok, t() | nil} | {:error, term()}
  def load(%Bundle{} = bundle, name \\ @settings_name) do
    case Bundle.embed(bundle, name) do
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
      {:ok, content} -> decode(name, content)
    end
  end

  @doc "Same as `load/2`, but raises on failure. A settings-less bundle still returns `nil`, not an exception."
  @spec load!(Bundle.t(), String.t()) :: t() | nil
  def load!(bundle, name \\ @settings_name) do
    case load(bundle, name) do
      {:ok, settings} -> settings
      {:error, reason} -> raise "Failed to load lmml settings: #{inspect(reason)}"
    end
  end

  @doc "Fetches a top-level key from the settings' decoded data, or `nil` if absent."
  @spec get(t(), String.t()) :: term() | nil
  def get(%__MODULE__{data: data}, key) when is_binary(key), do: Map.get(data, key)

  @doc "Fetches a top-level key from the settings' decoded data as `{:ok, term}`, or `:error` if absent."
  @spec fetch(t(), String.t()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{data: data}, key) when is_binary(key), do: Map.fetch(data, key)

  # ---------------------------------------------------------------------
  # Decoding
  # ---------------------------------------------------------------------

  @spec decode(String.t(), binary()) :: {:ok, t()} | {:error, term()}
  defp decode(name, content) do
    case Path.extname(name) |> String.downcase() do
      ".json" -> decode_json(content)
      ext when ext in [".yaml", ".yml"] -> decode_yaml(content)
      _ext -> {:error, {:invalid_settings, {:unsupported_extension, name}}}
    end
  end

  defp decode_json(content) do
    case :json.decode(content) do
      data when is_map(data) -> {:ok, %__MODULE__{data: data}}
      other -> {:error, {:invalid_settings, {:not_an_object, other}}}
    end
  rescue
    e -> {:error, {:invalid_settings, Exception.message(e)}}
  catch
    _, reason -> {:error, {:invalid_settings, inspect(reason)}}
  end

  defp decode_yaml(content) do
    case __MODULE__.YamlSubset.decode(content) do
      {:ok, map} when is_map(map) -> {:ok, %__MODULE__{data: map}}
      {:error, reason} -> {:error, {:invalid_settings, reason}}
    end
  end

  # ---------------------------------------------------------------------
  # Hand-rolled YAML-subset decoder (see module @moduledoc for the subset)
  # ---------------------------------------------------------------------

  defmodule YamlSubset do
    @moduledoc false

    # A minimal, documented-subset YAML decoder used by `Lmml.Settings`
    # when the settings embed is named `settings.yaml`/`.yml`. Supports
    # flat and indented-nested `key: value` mappings with scalar values
    # only. See `Lmml.Settings`'s moduledoc for exactly what is accepted.

    @spec decode(binary()) :: {:ok, map()} | {:error, term()}
    def decode(content) when is_binary(content) do
      lines =
        content
        |> String.split("\n")
        |> Enum.map(&strip_comment/1)
        |> Enum.reject(&(String.trim(&1) == ""))

      case parse_block(lines, 0) do
        {:ok, map, []} ->
          {:ok, map}

        {:ok, _map, [leftover | _]} ->
          {:error, {:unsupported_yaml, leftover, "unexpected indentation"}}

        {:error, _reason} = error ->
          error
      end
    end

    # Parses a block of sibling `key: value` lines all at indentation
    # `indent`. Sibling lines are consumed in order; a deeper-indented line
    # after a bare `key:` opens a nested child map which is parsed
    # recursively at the child's own (deeper) indentation. Returns
    # `{:ok, map, rest}` where `rest` holds any lines that belong to an
    # *outer* (less-indented) level.
    @spec parse_block([String.t()], non_neg_integer()) ::
            {:ok, map(), [String.t()]} | {:error, term()}
    defp parse_block([], _indent), do: {:ok, %{}, []}

    defp parse_block([line | _rest] = lines, indent) do
      case indent_of(line) do
        ^indent ->
          parse_siblings(lines, indent, %{})

        less when less < indent ->
          # The block being requested starts at a shallower indent than the
          # caller asked for -- hand the whole run back unchanged.
          {:ok, %{}, lines}

        _more ->
          {:error, {:unsupported_yaml, line, "unexpected indentation"}}
      end
    end

    # Consumes sibling `key: ...` lines all at `indent`, folding any nested
    # child maps, until the lines run out or a shallower-indented line is
    # reached. Returns `{:ok, map, rest}`.
    defp parse_siblings([], _indent, acc), do: {:ok, acc, []}

    defp parse_siblings([line | rest] = lines, indent, acc) do
      case indent_of(line) do
        ^indent ->
          case parse_entry(line, rest, indent) do
            {:ok, key, value, remaining} ->
              parse_siblings(remaining, indent, Map.put(acc, key, value))

            {:error, _reason} = error ->
              error
          end

        less when less < indent ->
          # Reached an outer level; hand the whole remaining run back up.
          {:ok, acc, lines}

        _more ->
          {:error, {:unsupported_yaml, line, "unexpected indentation"}}
      end
    end

    # Parses one `key: value` / `key:` line. When `key:` is followed by a
    # deeper-indented line, that opens a nested child map which is parsed
    # recursively at the child's own indentation. Returns
    # `{:ok, key, value, remaining}`.
    defp parse_entry(line, rest, indent) do
      case split_key_value(line) do
        {:error, _reason} = error -> error
        {key, raw_value} -> parse_value_or_child(key, raw_value, rest, indent)
      end
    end

    defp parse_value_or_child(key, raw_value, rest, indent) do
      case child_indent(rest, indent) do
        nil ->
          {:ok, key, decode_scalar(raw_value), rest}

        child_indent ->
          {child_lines, remaining} = collect_child_lines(rest, indent)
          parse_child_map(key, child_lines, child_indent, remaining)
      end
    end

    defp parse_child_map(key, child_lines, child_indent, remaining) do
      case parse_block(child_lines, child_indent) do
        {:ok, child_map, []} ->
          {:ok, key, child_map, remaining}

        {:ok, _child_map, leftover} ->
          {:error, {:unsupported_yaml, hd(leftover), "unexpected indentation"}}

        {:error, _reason} = error ->
          error
      end
    end

    # The indentation of the next line if it opens a deeper-indented child
    # block (a nested map), or `nil` if the next line is a sibling or there
    # is no next line. Kept out of a guard because it calls local functions.
    defp child_indent([next | _], indent) do
      next_indent = indent_of(next)
      if next_indent > indent, do: next_indent, else: nil
    end

    defp child_indent([], _indent), do: nil

    # Collects the consecutive lines that are more deeply indented than
    # `indent` (a child block), returning `{child_lines, remaining}`.
    defp collect_child_lines(lines, indent) do
      {child, rest} =
        Enum.split_while(lines, fn line ->
          indent_of(line) > indent
        end)

      {child, rest}
    end

    # Splits a `key: value` line into its trimmed key and value, or returns
    # `{:error, {:unsupported_yaml, line, reason}}` for a line that isn't a
    # `key: value` mapping (e.g. a list item `- item`, or a stray colon).
    defp split_key_value(line) do
      stripped = String.trim(line)

      case :binary.split(stripped, ":") do
        [key, value] -> {String.trim(key), String.trim(value)}
        _ -> {:error, {:unsupported_yaml, line, "expected 'key: value'"}}
      end
    end

    # Decodes a scalar value: typed numbers, booleans, null, or a string.
    defp decode_scalar(value) do
      cond do
        value == "" -> %{}
        value in ["null", "~"] -> nil
        value in ["true"] -> true
        value in ["false"] -> false
        quoted_string?(value) -> unwrap_quotes(value)
        true -> decode_number(value)
      end
    end

    defp quoted_string?(value) do
      (String.starts_with?(value, "\"") and String.ends_with?(value, "\"")) or
        (String.starts_with?(value, "'") and String.ends_with?(value, "'"))
    end

    defp unwrap_quotes(value), do: String.slice(value, 1, byte_size(value) - 2)

    defp decode_number(value) do
      case Integer.parse(value) do
        {int, ""} ->
          int

        _ ->
          case Float.parse(value) do
            {float, ""} -> float
            _ -> value
          end
      end
    end

    defp strip_comment(line) do
      case :binary.match(line, "#") do
        {idx, 1} ->
          before = binary_part(line, 0, idx)
          if String.trim(before) == "", do: "", else: before

        :nomatch ->
          line
      end
    end

    defp indent_of(line) do
      line
      |> String.trim_leading()
      |> then(fn trimmed ->
        byte_size(line) - byte_size(trimmed)
      end)
    end
  end
end
