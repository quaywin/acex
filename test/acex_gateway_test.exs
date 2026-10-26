defmodule AcexGatewayTest do
  use ExUnit.Case, async: true

  test "version returns valid semantic version" do
    assert AcexGateway.version() == "0.1.0"
  end
end
