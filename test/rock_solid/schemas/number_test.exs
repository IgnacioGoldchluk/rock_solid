defmodule RockSolid.Schemas.NumberTest do
  use ExUnit.Case, async: true

  alias RockSolid.Schemas.Number

  describe "new/1" do
    test "invalid type fails" do
      assert {:error, [%Zoi.Error{path: ["type"]}]} = Number.new(%{"type" => "string"})
    end

    test "multipleOf 0 fails" do
      assert {:error, [%Zoi.Error{path: ["multipleOf"]}]} = Number.new(%{"multipleOf" => 0})
    end

    test "integer and multipleOf float fails" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"type" => "integer", "multipleOf" => 0.1})

      assert msg == "integer specified but multipleOf is not integer: 0.1"
    end

    test "invalid maximum and exclusive maximum" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"maximum" => 1, "exclusiveMaximum" => 1})

      assert msg =~ "provide maximum OR exclusiveMaximum"
    end

    test "invalid minimum and exclusiveMinimum" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"minimum" => 1, "exclusiveMinimum" => 1})

      assert msg =~ "provide minimum OR exclusiveMinimum"
    end

    test "invalid minimum greater than maximum" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"minimum" => 1, "maximum" => 0})

      assert msg =~ "minimum > maximum"
    end

    test "invalid minimum equal to exclusiveMaximum" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"minimum" => 1, "exclusiveMaximum" => 1})

      assert msg == "minimum = maximum with exclusive range: 1"
    end

    test "invalid exclusiveMinimum equal to maximum" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"minimum" => 1, "exclusiveMaximum" => 1})

      assert msg == "minimum = maximum with exclusive range: 1"
    end

    test "minimum equal to maximum with valid multipleOf" do
      schema = %{"multipleOf" => 2, "minimum" => 2, "maximum" => 2}

      assert {:ok, %{"enum" => [2]}} == Number.new(schema)
    end

    test "same minimum and maximum returns the number itself" do
      schema = %{"minimum" => 1, "maximum" => 1, "type" => "integer"}

      assert {:ok, %{"enum" => [1]}} == Number.new(schema)
    end

    test "valid numbers pass" do
      assert {:ok, _} = Number.new(%{"maximum" => 10, "exclusiveMinimum" => 0})
      assert {:ok, _} = Number.new(%{"minimum" => 0, "multipleOf" => 2})
    end

    test "no number in range" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Number.new(%{"minimum" => 6, "maximum" => 9, "multipleOf" => 5})

      assert msg =~ "no multipleOf in range"
    end

    test "rounds integer ranges" do
      assert {:ok, %{"minimum" => 4, "maximum" => 6}} =
               Number.new(%{"type" => "integer", "minimum" => 3.3, "maximum" => 6.9})
    end
  end
end
