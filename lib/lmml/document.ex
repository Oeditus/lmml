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

  Validates that the input is valid UTF-8, that all `@@@` inline embed fences
  are balanced and well-formed, that the parser consumes the entire input with
  no malformed `:lmml_embed` or `:lmml_ref` AST nodes, and (unless
  `validate: false` is passed) that every embed name satisfies
  `Lmml.Embed.valid_name?/1`.

  The `@@@name ... @@@` block is declared with `escape: false` in
  `Lmml.Narrative.Syntax` (`Md` >= 0.12.2), so an `:lmml_embed` node's
  content already matches the literal bytes written between the fences
  verbatim -- no post-processing needed here.
  """
  @spec parse(binary(), keyword()) :: {:ok, t()} | {:error, term()}
  def parse(narrative, opts \\ [])

  def parse(narrative, opts) when is_binary(narrative) and is_list(opts) do
    validate_names? = Keyword.get(opts, :validate, true)

    with :ok <- ensure_utf8(narrative),
         :ok <- validate_fences(narrative),
         {:ok, ast} <- run_parser(narrative),
         {:ok, embeds} <- collect_embeds(ast, validate_names?) do
      {:ok, %__MODULE__{ast: ast, embeds: embeds}}
    end
  end

  def parse(_non_binary, _opts), do: {:error, :invalid_input}

  @doc "Same as `parse/2`, but raises on failure."
  @spec parse!(binary(), keyword()) :: t()
  def parse!(narrative, opts \\ []) do
    case parse(narrative, opts) do
      {:ok, document} -> document
      {:error, reason} -> raise "Failed to parse lmml narrative: #{inspect(reason)}"
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
  # Parsing & structural validation
  # ---------------------------------------------------------------------

  defp ensure_utf8(narrative) do
    if String.valid?(narrative), do: :ok, else: {:error, :invalid_utf8}
  end

  defp run_parser(narrative) do
    case Parser.parse(narrative) do
      {"", state} -> {:ok, state.ast}
      {rest, _state} -> {:error, {:unparsed_input, rest}}
    end
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  # Scans lines to ensure every `@@@` inline embed fence outside standard
  # Markdown code fences (``` / ~~~) is properly opened with a name and closed.
  defp validate_fences(narrative) do
    narrative
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce_while(:prose, &check_fence_line/2)
    |> case do
      :prose -> :ok
      {:code_fence, _char, _len} -> :ok
      {:embed_fence, name, line_num} -> {:error, {:unclosed_embed, name, line_num}}
      {:error, _reason} = error -> error
    end
  end

  defp check_fence_line({raw_line, line_num}, :prose) do
    line = String.trim_trailing(raw_line, "\r")

    cond do
      match?({:code_fence, _, _}, opening_code_fence(line)) ->
        {:cont, opening_code_fence(line)}

      String.starts_with?(line, "@@@@") ->
        {:halt, {:error, {:malformed_embed_fence, line_num, :invalid_delimiter}}}

      String.starts_with?(line, "@@@") ->
        name = String.trim_leading(binary_part(line, 3, byte_size(line) - 3))

        if name == "" do
          {:halt, {:error, {:malformed_embed_fence, line_num, :missing_name}}}
        else
          {:cont, {:embed_fence, name, line_num}}
        end

      true ->
        {:cont, :prose}
    end
  end

  defp check_fence_line({raw_line, _line_num}, {:code_fence, char, len} = state) do
    line = raw_line |> String.trim_trailing("\r") |> String.trim()

    if closing_code_fence?(line, char, len) do
      {:cont, :prose}
    else
      {:cont, state}
    end
  end

  defp check_fence_line({raw_line, _line_num}, {:embed_fence, _name, _start_line} = state) do
    line = String.trim_trailing(raw_line, "\r")

    if String.ends_with?(line, "@@@") and not String.ends_with?(line, "@@@@") do
      {:cont, :prose}
    else
      {:cont, state}
    end
  end

  defp opening_code_fence(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, "```") ->
        {:code_fence, "`", leading_run_length(trimmed, ?`)}

      String.starts_with?(trimmed, "~~~") ->
        {:code_fence, "~", leading_run_length(trimmed, ?~)}

      true ->
        nil
    end
  end

  defp closing_code_fence?(trimmed, char, min_len) do
    byte = :binary.first(char)
    run = leading_run_length(trimmed, byte)
    run >= min_len and run == byte_size(trimmed)
  end

  defp leading_run_length(<<c, rest::binary>>, c), do: 1 + leading_run_length(rest, c)
  defp leading_run_length(_other, _c), do: 0

  # ---------------------------------------------------------------------
  # AST walking
  # ---------------------------------------------------------------------

  @spec collect_embeds(ast(), boolean()) :: {:ok, [Embed.t()]} | {:error, term()}
  defp collect_embeds(nodes, validate_names?) do
    case do_collect_embeds(nodes, validate_names?, []) do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end

  defp do_collect_embeds([], _validate_names?, acc), do: {:ok, acc}

  defp do_collect_embeds([node | rest], validate_names?, acc) do
    with {:ok, acc} <- collect_node(node, validate_names?, acc) do
      do_collect_embeds(rest, validate_names?, acc)
    end
  end

  defp collect_node({:lmml_ref, %{name: name}, []}, validate_names?, acc) when is_binary(name) do
    if not validate_names? or Embed.valid_name?(name) do
      {:ok, [Embed.external(name) | acc]}
    else
      {:error, {:malformed_embed_name, name}}
    end
  end

  defp collect_node({:lmml_ref, attrs, _children}, _validate_names?, _acc) do
    {:error, {:malformed_embed, attrs}}
  end

  defp collect_node({:lmml_embed, %{name: name}, [content]}, validate_names?, acc)
       when is_binary(name) and is_binary(content) do
    if not validate_names? or Embed.valid_name?(name) do
      {:ok, [Embed.inline(name, content) | acc]}
    else
      {:error, {:malformed_embed_name, name}}
    end
  end

  defp collect_node({:lmml_embed, %{name: name}, []}, validate_names?, acc)
       when is_binary(name) do
    if not validate_names? or Embed.valid_name?(name) do
      {:ok, [Embed.inline(name, "") | acc]}
    else
      {:error, {:malformed_embed_name, name}}
    end
  end

  defp collect_node({:lmml_embed, attrs, _children}, _validate_names?, _acc) do
    {:error, {:malformed_embed, attrs}}
  end

  defp collect_node({_tag, _attrs, children}, validate_names?, acc) when is_list(children) do
    do_collect_embeds(children, validate_names?, acc)
  end

  defp collect_node(_leaf_or_unrecognized, _validate_names?, acc), do: {:ok, acc}
end
