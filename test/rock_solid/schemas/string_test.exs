defmodule RockSolid.Schemas.StringTest do
  use ExUnit.Case, async: true
  alias RockSolid.Schemas

  describe "new/1" do
    test "errors invalid length" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Schemas.String.new(%{"minLength" => 5, "maxLength" => 3})

      assert msg =~ "minLength > maxLength"
    end

    test "valid length" do
      assert {:ok, string} = Schemas.String.new(%{"minLength" => 10})
      assert string["type"] == "string"
      assert string["minLength"] == 10
    end

    test "valid regex pattern" do
      assert {:ok, %{"pattern" => "[A-Z]+", "type" => "string"}} =
               Schemas.String.new(%{"pattern" => "[A-Z]+"})
    end

    test "invalid regex pattern" do
      assert {:error, [%Zoi.Error{message: msg}]} = Schemas.String.new(%{"pattern" => "1)"})

      assert String.starts_with?(msg, "invalid regex")
    end
  end
end
