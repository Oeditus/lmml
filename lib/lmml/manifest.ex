defmodule Lmml.Manifest do
  @moduledoc """
  Optional `manifest.json` metadata for a `Lmml.Bundle`.

  `manifest.json` is not a distinct front-matter mechanism -- it is simply
  an embed literally named `"manifest.json"`, exactly like any other
  embed: `@@@manifest.json ... @@@` inline, or `@manifest.json`
  referencing a zip entry inside a `.lmmlz`. This module looks that embed
  up, decodes it with OTP's built-in `:json` (not `Jason`), and exposes
  its top-level fields as a plain map.

  A bundle mentioning no `manifest.json` embed at all has no manifest --
  that is a normal, fully-supported, non-error state (`load/1` returns
  `{:ok, nil}`), not something to special-case at every call site.
  """

  alias Lmml.Bundle

  @manifest_name "manifest.json"

  @enforce_keys [:data]
  defstruct [:data]

  @type t :: %__MODULE__{data: map()}

  @doc "The reserved embed name a bundle's manifest is looked up by, if present."
  @spec name() :: String.t()
  def name, do: @manifest_name

  @doc """
  Loads and decodes `bundle`'s `manifest.json` embed, if any.

  Returns:
    - `{:ok, %Lmml.Manifest{}}` -- a `manifest.json` embed exists and
      decodes to a JSON object.
    - `{:ok, nil}` -- no `manifest.json` embed is mentioned anywhere in
      the narrative. This is the common case for a manifest-less bundle,
      not an error.
    - `{:error, reason}` -- a `manifest.json` embed *is* mentioned, but
      either its content is unresolvable (e.g. an `@manifest.json`
      reference in a bare `.lmml`, or a dangling reference into a
      `.lmmlz`'s entries -- see `Lmml.Bundle.embed/2`), or its resolved
      content is not valid JSON, or it decodes to something other than a
      JSON object (`{:invalid_manifest, reason}`).
  """
  @spec load(Bundle.t()) :: {:ok, t() | nil} | {:error, term()}
  def load(%Bundle{} = bundle) do
    case Bundle.embed(bundle, @manifest_name) do
      {:error, :not_found} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
      {:ok, content} -> decode(content)
    end
  end

  @doc "Same as `load/1`, but raises on failure. A manifest-less bundle still returns `nil`, not an exception."
  @spec load!(Bundle.t()) :: t() | nil
  def load!(bundle) do
    case load(bundle) do
      {:ok, manifest} -> manifest
      {:error, reason} -> raise "Failed to load lmml manifest: #{inspect(reason)}"
    end
  end

  @doc "Fetches a top-level key from the manifest's decoded data, or `nil` if absent."
  @spec get(t(), String.t()) :: term() | nil
  def get(%__MODULE__{data: data}, key) when is_binary(key), do: Map.get(data, key)

  defp decode(content) do
    case :json.decode(content) do
      data when is_map(data) -> {:ok, %__MODULE__{data: data}}
      other -> {:error, {:invalid_manifest, {:not_an_object, other}}}
    end
  rescue
    e -> {:error, {:invalid_manifest, Exception.message(e)}}
  catch
    _, reason -> {:error, {:invalid_manifest, inspect(reason)}}
  end
end
