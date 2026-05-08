defmodule RockSolid.Schemas.VocabularyTest do
  use ExUnit.Case

  alias RockSolid.Schemas.Vocabulary

  describe "vocabulary/1" do
    test "returns corresponding atom for the URI" do
      assert Vocabulary.vocabulary("https://json-schema.org/draft/2020-12/schema") ==
               :draft2020_12

      assert Vocabulary.vocabulary("https://json-schema.org/draft/2019-09/schema") ==
               :draft2019_09

      assert Vocabulary.vocabulary("http://json-schema.org/draft-07/schema#") == :draft07
      assert Vocabulary.vocabulary("http://json-schema.org/draft-06/schema#") == :draft06
      assert Vocabulary.vocabulary("http://json-schema.org/draft-04/schema#") == :draft04
    end

    test "normalizes vocabulary" do
      assert Vocabulary.vocabulary("http://json-schema.org/draft-07/schema") == :draft07
    end

    test "raises for invalid vocabulary" do
      invalid_vocabulary = "https://json-schema.org/custom-vocabulary/schema#"

      assert_raise Vocabulary.InvalidVocabulary, ~r/Invalid vocabulary .*/, fn ->
        Vocabulary.vocabulary(invalid_vocabulary)
      end
    end
  end

  test "returns URI for vocabulary atom" do
    assert Vocabulary.draft2020_12() == "https://json-schema.org/draft/2020-12/schema"
    assert Vocabulary.draft2019_09() == "https://json-schema.org/draft/2019-09/schema"
    assert Vocabulary.draft07() == "http://json-schema.org/draft-07/schema#"
    assert Vocabulary.draft06() == "http://json-schema.org/draft-06/schema#"
    assert Vocabulary.draft04() == "http://json-schema.org/draft-04/schema#"
  end
end
