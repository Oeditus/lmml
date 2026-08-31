defmodule Lmml.Narrative.Resolver do
  @moduledoc """
  Resolves every embed a bundle's narrative mentions against the bundle
  itself, producing a fully-resolved intermediate structure that pairs
  each `Lmml.Embed` with its actual bytes -- trivially for an inline
  embed (its bytes are already its own content) and by zip-entry lookup
  for an external reference (`Lmml.Bundle.embed/2`).

  This is deliberately the *only* place bundle access happens on the way
  to an LLM-ready payload: `Lmml.Narrative.Renderer` consumes a
  `t:t/0` produced here and needs no further knowledge of `Lmml.Bundle`
  at all.
  """

  alias Lmml.Bundle
  alias Lmml.Embed

  @typedoc "One embed paired with its actually-resolved bytes."
  @type resolved_embed :: %{embed: Embed.t(), content: binary()}

  @enforce_keys [:narrative, :embeds]
  defstruct [:narrative, :embeds]

  @type t :: %__MODULE__{narrative: binary(), embeds: [resolved_embed()]}

  @doc """
  Resolves every embed `bundle`'s narrative mentions (each distinct name
  once, in first-occurrence order -- see `Lmml.Document.embed_names/1`).

  Fails on the first embed that cannot be resolved (a dangling
  `@name.ext` reference, or one pointing outside the bundle) rather than
  silently dropping it or returning a partial result: a narrative meant
  for an LLM call should either be fully resolved or not sent at all.
  """
  @spec resolve(Bundle.t()) :: {:ok, t()} | {:error, term()}
  def resolve(%Bundle{} = bundle) do
    with {:ok, resolved} <- resolve_embeds(bundle) do
      {:ok, %__MODULE__{narrative: Bundle.narrative(bundle), embeds: resolved}}
    end
  end

  @doc "Same as `resolve/1`, but raises on failure."
  @spec resolve!(Bundle.t()) :: t()
  def resolve!(bundle) do
    case resolve(bundle) do
      {:ok, resolved} -> resolved
      {:error, reason} -> raise "Failed to resolve lmml narrative: #{inspect(reason)}"
    end
  end

  defp resolve_embeds(bundle) do
    bundle
    |> Bundle.embeds()
    |> Enum.uniq_by(& &1.name)
    |> Enum.reduce_while({:ok, []}, fn embed, {:ok, acc} ->
      case Bundle.embed(bundle, embed.name) do
        {:ok, content} -> {:cont, {:ok, [%{embed: embed, content: content} | acc]}}
        {:error, reason} -> {:halt, {:error, {embed.name, reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end
end
