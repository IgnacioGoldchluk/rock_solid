defmodule RockSolid.Schemas.ObjectTest do
  use ExUnit.Case, async: true

  alias RockSolid.Schemas.Object

  describe "new/1" do
    test "propertyNames and patternProperties intersect each other" do
      schema = %{
        "patternProperties" => %{".*" => %{"type" => "string"}},
        "propertyNames" => %{"pattern" => "^[A-Za-z0-9_.-]+$"},
        "type" => "object"
      }

      expected = %{
        "additionalProperties" => false,
        "patternProperties" => %{
          "^[A-Za-z0-9_.-]+$" => %{"type" => "string"}
        },
        "propertyNames" => %{"pattern" => "^[A-Za-z0-9_.-]+$", "type" => "string"},
        "type" => "object"
      }

      assert {:ok, expected} == Object.new(schema)
    end

    test "minProperties > maxProperties is invalid" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Object.new(%{
                 "properties" => %{"name" => %{"type" => "string"}},
                 "minProperties" => 5,
                 "maxProperties" => 3
               })

      assert msg == "minProperties > maxProperties"
    end

    test "required property matches property name" do
      assert {:ok, schema} =
               Object.new(%{
                 "required" => ["name"],
                 "additionalProperties" => %{"type" => "string"},
                 "propertyNames" => %{"minLength" => 3}
               })

      assert schema["properties"]["name"] == %{"type" => "string"}
    end

    test "required property matches propertyPatterns" do
      assert {:ok, schema} =
               Object.new(%{
                 "required" => ["ENV_SYSTEM"],
                 "patternProperties" => %{
                   "^ENV_" => %{"type" => "number"}
                 }
               })

      assert schema["properties"]["ENV_SYSTEM"] == %{"type" => "number"}
    end

    test "required property with no other specifications" do
      schema = %{"required" => ["foo"]}

      assert {:ok, %{"type" => "object", "properties" => %{"foo" => true}, "required" => ["foo"]}} ==
               Object.new(schema)
    end

    test "empty required is discarded" do
      schema = %{
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => []
      }

      expected = %{"properties" => %{"name" => %{"type" => "string"}}, "type" => "object"}
      assert {:ok, expected} == Object.new(schema)
    end

    test "required property dos not match anything" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Object.new(%{
                 "required" => ["name"],
                 "patternProperties" => %{
                   "^ENV_" => %{"type" => "number"}
                 },
                 "additionalProperties" => false
               })

      assert msg == "name missing from properties"
    end

    test "maxProperties < required" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Object.new(%{
                 "required" => ["name", "firstName", "lastName"],
                 "maxProperties" => 2,
                 "properties" => %{
                   "name" => %{"type" => "string"},
                   "firstName" => %{"type" => "string"},
                   "lastName" => %{"type" => "string"}
                 }
               })

      assert msg == "required > maxProperties"
    end

    test "properties are intersected with matching patternProperties" do
      schema = %{
        "type" => "object",
        "properties" => %{"ENV_ASD" => %{"type" => "string"}, "other" => %{"type" => "number"}},
        "patternProperties" => %{
          "^ENV_" => %{"pattern" => "^[A-Za-z]$", "type" => "string"}
        }
      }

      expected = %{
        "patternProperties" => %{
          "^ENV_" => %{"pattern" => "^[A-Za-z]$", "type" => "string"}
        },
        "properties" => %{
          "ENV_ASD" => %{"pattern" => "^[A-Za-z]$", "type" => "string"},
          "other" => %{"type" => "number"}
        },
        "type" => "object"
      }

      assert {:ok, expected} == Object.new(schema)
    end

    test "non-matching property overlapped with patternProperties is set to false" do
      schema = %{
        "type" => "object",
        "properties" => %{"password" => %{"type" => "string", "minLength" => 10}},
        "patternProperties" => %{
          "^[a-z]+" => %{"type" => "string", "maxLength" => 8}
        }
      }

      expected = %{
        "patternProperties" => %{"^[a-z]+" => %{"maxLength" => 8, "type" => "string"}},
        "properties" => %{"password" => false},
        "type" => "object"
      }

      assert {:ok, expected} == Object.new(schema)
    end

    test "minProperties smaller than required is discarded" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        },
        "required" => ["name", "age"],
        "minProperties" => 1
      }

      assert {:ok, obj} = Object.new(schema)
      assert obj == Map.delete(schema, "minProperties")
    end

    # Decide what to do with this later
    # test "patternProperties + propertyNames is invalid" do
    #   schema = %{
    #     "type" => "object",
    #     "properties" => %{"name" => %{"type" => "string"}},
    #     "patternProperties" => %{".*" => true},
    #     "propertyNames" => %{"type" => "string"}
    #   }

    #   assert {:error, [%Zoi.Error{message: msg}]} = Object.new(schema)
    #   assert msg == "patternProperties + propertyNames not supported"
    # end

    test "required property non-matching is invalid" do
      schema = %{
        "type" => "object",
        "required" => ["ENV_NAME"],
        "additionalProperties" => false,
        "patternProperties" => %{"[a-z]+" => true}
      }

      assert {:error, [%Zoi.Error{message: msg}]} = Object.new(schema)

      assert msg == "ENV_NAME missing from properties"
    end

    test "overlapping patternProperties raises" do
      schema = %{
        "type" => "object",
        "patternProperties" => %{
          "[a-z]+" => %{"type" => "string", "minLength" => 1},
          "[A-Za-z]+" => %{"type" => "string"}
        }
      }

      assert {:error, [%Zoi.Error{message: msg}]} = Object.new(schema)
      assert String.starts_with?(msg, "overlapping patternProperties")
    end
  end
end
