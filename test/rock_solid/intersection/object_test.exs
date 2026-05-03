defmodule RockSolid.Intersection.ObjectTest do
  use ExUnit.Case, async: true

  alias RockSolid.Intersection

  describe "intersection/2" do
    test "object returns itself" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "number", "minimum" => 18}
        }
      }

      assert {:ok, schema} == Intersection.intersection(schema, schema)
    end

    test "const property intesection" do
      s1 = %{"type" => "object", "properties" => %{"name" => %{"const" => "Alice"}}}
      s2 = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "properties" => %{"name" => %{"enum" => ["Alice"]}},
               "type" => "object"
             }
    end

    test "required properties intersect" do
      s1 = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "minLength" => 3},
          "age" => %{"type" => "integer"}
        },
        "required" => ["name", "age"]
      }

      s2 = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "number", "maximum" => 99}
        },
        "required" => ["age", "name"]
      }

      {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "properties" => %{
                 "age" => %{"maximum" => 99, "type" => "integer"},
                 "name" => %{"minLength" => 3, "type" => "string"}
               },
               "required" => ["name", "age"],
               "type" => "object"
             }
    end

    test "required property cannot match" do
      s1 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "maxLength" => 8}}
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "minLength" => 10}},
        "required" => ["name"]
      }

      assert {:error, "name cannot match"} == Intersection.intersection(s1, s2)
      assert {:error, "name cannot match"} == Intersection.intersection(s2, s1)
    end

    test "property matches propertyNames from another schema" do
      s1 = %{"type" => "object", "properties" => %{"ENV_SYSTEM" => %{"type" => "string"}}}
      s2 = %{"type" => "object", "patternProperties" => %{"^[a-z_]+$" => %{"type" => "number"}}}

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, schema2} = Intersection.intersection(s2, s1)
      assert schema == schema2

      assert schema == %{
               "properties" => %{"ENV_SYSTEM" => %{"type" => "string"}},
               "type" => "object",
               "patternProperties" => %{"^[a-z_]+$" => %{"type" => "number"}}
             }
    end

    test "property does not match propertyNames" do
      s1 = %{
        "type" => "object",
        "properties" => %{"ENV_SYSTEM" => %{"type" => "string"}},
        "required" => ["ENV_SYSTEM"]
      }

      s2 = %{"type" => "object", "propertyNames" => %{"type" => "string", "pattern" => "^[a-z]$"}}

      assert {:error, msg} = Intersection.intersection(s1, s2)
      assert {:error, ^msg} = Intersection.intersection(s2, s1)

      assert [%Zoi.Error{message: "ENV_SYSTEM missing" <> _}] = msg
    end

    test "impossible properties with minProperties retuns error" do
      s1 = %{
        "minProperties" => 1,
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "minLength" => 10}},
        "additionalProperties" => false
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "maxLength" => 9}},
        "additionalProperties" => false
      }

      assert {:error, [%Zoi.Error{message: msg}]} = Intersection.intersection(s1, s2)
      assert msg == "cannot generate minProperties 1 from schema"
    end

    test "property does not match patternProperties or additionalProperties" do
      # This is a bug because if one has patternProperties and the other one doesn't
      # then we have to match against additionalProperties!
      s1 = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

      s2 = %{
        "type" => "object",
        "patternProperties" => %{"^[A-Z]$" => %{"type" => "string"}},
        "additionalProperties" => false
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, ^schema} = Intersection.intersection(s2, s1)

      assert schema == %{
               "additionalProperties" => false,
               "type" => "object",
               "patternProperties" => %{"^[A-Z]$" => %{"type" => "string"}}
             }
    end

    test "unspecified object and object with required properties" do
      s1 = %{"type" => "object", "required" => ["foo"]}
      s2 = %{"type" => "object"}

      expected = %{
        "type" => "object",
        "required" => ["foo"],
        "properties" => %{
          "foo" => true
        }
      }

      assert {:ok, expected} == Intersection.intersection(s1, s2)
    end

    test "patternProperties does not match propertyNames" do
      s1 = %{"type" => "object", "patternProperties" => %{"$[a-z]+" => %{"type" => "string"}}}
      s2 = %{"type" => "object", "propertyNames" => %{"type" => "string", "pattern" => "$[A-Z]+"}}

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, ^schema} = Intersection.intersection(s2, s1)

      assert schema == %{
               "propertyNames" => %{"pattern" => "$[A-Z]+", "type" => "string"},
               "type" => "object"
             }
    end

    test "no matches with properties and no additionalProperties returns empty object" do
      s1 = %{
        "type" => "object",
        "properties" => %{"baz" => %{"type" => "number"}},
        "additionalProperties" => false
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"baz" => %{"type" => "string"}},
        "additionalProperties" => false
      }

      assert {:ok, %{"enum" => [%{}]}} == Intersection.intersection(s1, s2)
    end

    test "no matching on anything returns empty object" do
      s1 = %{
        "type" => "object",
        "propertyNames" => %{"enum" => ["name", "age"]},
        "additionalProperties" => %{"type" => "string"}
      }

      s2 = %{
        "type" => "object",
        "propertyNames" => %{"enum" => ["name", "other"]},
        "additionalProperties" => %{"type" => "number"}
      }

      assert {:ok, %{"enum" => [%{}]}} == Intersection.intersection(s1, s2)
    end

    test "false property is set to false" do
      s1 = %{"type" => "object", "properties" => %{"name" => false}}
      s2 = %{"type" => "object"}

      expected = %{"type" => "object", "properties" => %{"name" => false}}

      assert {:ok, expected} == Intersection.intersection(s1, s2)
    end

    test "not matching on anything with minProperties returns error" do
      s1 = %{
        "type" => "object",
        "properties" => %{"baz" => %{"type" => "number"}},
        "additionalProperties" => false
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"baz" => %{"type" => "string"}},
        "additionalProperties" => false,
        "minProperties" => 1
      }

      assert {:error, [%Zoi.Error{message: msg}]} = Intersection.intersection(s1, s2)
      assert msg == "cannot generate minProperties 1 from schema"
    end

    test "property matches patternProperty name but not value" do
      s1 = %{"type" => "object", "properties" => %{"ENV_CMD" => %{"type" => "string"}}}

      s2 = %{
        "type" => "object",
        "additionalProperties" => false,
        "patternProperties" => %{
          "^ENV_" => %{"type" => "number"}
        }
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "additionalProperties" => false,
               "patternProperties" => %{"^ENV_" => %{"type" => "number"}},
               "type" => "object"
             }
    end

    test "propertyNames in both schemas computes intersection" do
      s1 = %{"type" => "object", "propertyNames" => %{"enum" => ["name", "age"]}}
      s2 = %{"type" => "object", "propertyNames" => %{"enum" => ["name", "other"]}}

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert schema == %{"propertyNames" => %{"enum" => ["name"]}, "type" => "object"}
    end

    test "patternProperties in both schemas computes intersection" do
      s1 = %{
        "type" => "object",
        "patternProperties" => %{
          "^[a-z]$" => %{"type" => "number"},
          "^[A-Z]$" => %{"type" => "string"}
        }
      }

      s2 = %{
        "type" => "object",
        "patternProperties" => %{
          "^[a-z]" => %{"type" => "string"},
          "^[A-Z0-9]$" => %{"type" => "string"}
        }
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "patternProperties" => %{"^[A-Z]$" => %{"type" => "string"}},
               "type" => "object"
             }
    end

    test "patternProperties values does not match additionalProperties" do
      s1 = %{"type" => "object", "patternProperties" => %{"$[a-z]+" => %{"type" => "string"}}}

      s2 = %{
        "type" => "object",
        "propertyNames" => %{"type" => "string"},
        "additionalProperties" => %{"type" => "number"}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, ^schema} = Intersection.intersection(s2, s1)

      assert schema == %{
               "additionalProperties" => %{"type" => "number"},
               "type" => "object"
             }
    end

    test "property matches patternProperties from another schema" do
      s1 = %{"type" => "object", "properties" => %{"ENV_SYSTEM" => %{"type" => "string"}}}

      s2 = %{
        "type" => "object",
        "patternProperties" => %{"^ENV_" => %{"type" => "string", "maxLength" => 255}}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)
      assert {:ok, schema2} = Intersection.intersection(s2, s1)
      assert schema == schema2

      assert schema == %{
               "properties" => %{"ENV_SYSTEM" => %{"type" => "string", "maxLength" => 255}},
               "patternProperties" => %{"^ENV_" => %{"type" => "string", "maxLength" => 255}},
               "type" => "object"
             }
    end

    test "non-matching properties are set to false" do
      s1 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "maxLength" => 10}}
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "minLength" => 14}}
      }

      expected = %{"type" => "object", "properties" => %{"name" => false}}
      assert {:ok, expected} == Intersection.intersection(s1, s2)
    end

    test "non-matching properties when propertyNames exists" do
      s1 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "maxLength" => 10}},
        "propertyNames" => %{"type" => "string", "minLength" => 3}
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "minLength" => 14}},
        "propertyNames" => %{"not" => %{"const" => "reserved"}}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "properties" => %{"name" => false},
               "propertyNames" => %{
                 "minLength" => 3,
                 "not" => %{"const" => "reserved"},
                 "type" => "string"
               },
               "type" => "object"
             }
    end

    test "dependentRequired are accumulated" do
      s1 = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "firstName" => %{"type" => "string"},
          "lastName" => %{"type" => "string"}
        },
        "dependentRequired" => %{"name" => ["firstName", "lastName"], "firstName" => ["lastName"]}
      }

      s2 = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "string"}},
        "dependentRequired" => %{"name" => ["age"], "age" => ["name"]}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "firstName" => %{"type" => "string"},
                 "lastName" => %{"type" => "string"},
                 "age" => %{"type" => "string"}
               },
               "dependentRequired" => %{
                 "name" => ["firstName", "lastName", "age"],
                 "firstName" => ["lastName"],
                 "age" => ["name"]
               }
             }
    end
  end
end
