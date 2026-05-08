defmodule RockSolid.Schemas.Vocabulary do
  @moduledoc false

  @vocabularies %{
    :draft2020_12 => "https://json-schema.org/draft/2020-12/schema",
    :draft2019_09 => "https://json-schema.org/draft/2019-09/schema",
    :draft07 => "http://json-schema.org/draft-07/schema#",
    :draft06 => "http://json-schema.org/draft-06/schema#",
    :draft04 => "http://json-schema.org/draft-04/schema#"
  }

  def supported_vocabularies, do: Map.values(@vocabularies)

  defmodule InvalidVocabulary do
    defexception [:vocabulary]

    alias RockSolid.Schemas.Vocabulary

    def message(%{vocabulary: vocabulary} = _exception) do
      known_vocabularies = Enum.join(Vocabulary.supported_vocabularies(), ", ")
      "Invalid vocabulary '#{vocabulary}'. Supported vocabularies are #{known_vocabularies}"
    end
  end

  @type t :: :draft04 | :draft05 | :draft06 | :draft07 | :draft2019_09 | :draft2020_12
  @doc """
  Returns the corresponding vocabulary for the URI
  """
  @spec vocabulary(String.t() | t()) :: t() | String.t()
  def vocabulary(vocabulary_uri)

  def vocabulary(vocabulary_uri) when is_binary(vocabulary_uri) do
    vocabulary_uri = normalize(vocabulary_uri)

    case Enum.find_value(@vocabularies, fn
           {vocabulary, ^vocabulary_uri} -> vocabulary
           _ -> nil
         end) do
      nil -> raise InvalidVocabulary, vocabulary: vocabulary_uri
      vocabulary when is_atom(vocabulary) -> vocabulary
    end
  end

  defp normalize("http://json-schema.org/draft-07/schema"),
    do: "http://json-schema.org/draft-07/schema#"

  defp normalize(v), do: v

  # Convenience to do `Vocabulary.draft2020_12()` and get the URI
  for {vocab_atom, uri} <- @vocabularies do
    def unquote(vocab_atom)(), do: unquote(uri)
  end
end
