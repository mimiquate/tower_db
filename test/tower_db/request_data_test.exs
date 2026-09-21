defmodule TowerDB.RequestDataTest do
  use ExUnit.Case, async: true

  alias TowerDB.RequestData

  describe "build/1" do
    test "extracts url without query string, method, and user_ip" do
      conn =
        Plug.Test.conn(:get, "http://example.com/users/1?foo=bar")
        |> Map.put(:remote_ip, {127, 0, 0, 1})

      request_data = RequestData.build(conn)

      assert request_data["url"] == "http://example.com:80/users/1"
      assert request_data["method"] == "GET"
      assert request_data["user_ip"] == "127.0.0.1"
    end

    test "returns fetched params merged from query and body" do
      conn =
        Plug.Test.conn(:get, "/users?foo=bar")
        |> Plug.Conn.fetch_query_params()

      request_data = RequestData.build(conn)

      assert request_data["params"] == %{"foo" => "bar"}
    end

    test "returns \"unfetched\" when params were never fetched" do
      conn = Plug.Test.conn(:get, "/users?foo=bar")

      request_data = RequestData.build(conn)

      assert request_data["params"] == "unfetched"
    end

    test "only includes allowlisted headers" do
      conn =
        Plug.Test.conn(:get, "/users")
        |> Plug.Conn.put_req_header("user-agent", "ExampleBrowser/1.0")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("x-request-id", "req-123")

      request_data = RequestData.build(conn)

      assert request_data["headers"] == %{
               "user-agent" => "ExampleBrowser/1.0",
               "content-type" => "application/json"
             }
    end

    test "filters denylisted params (exact, substring, nested) and headers, case-insensitively" do
      conn =
        Plug.Test.conn(:post, "/login", %{
          "email" => "user@example.com",
          "PASSWORD" => "hunter2",
          "token" => "abc123",
          "user_password" => "hunter3",
          "old_password" => "hunter4",
          "user" => %{"name" => "Jane", "password" => "hunter5"}
        })
        |> Plug.Conn.fetch_query_params()
        |> Plug.Conn.put_req_header("user-agent", "ExampleBrowser/1.0")
        |> Plug.Conn.put_req_header("cookie", "session=abc123")

      request_data = RequestData.build(conn)

      assert request_data["params"] == %{
               "email" => "user@example.com",
               "PASSWORD" => "[FILTERED]",
               "token" => "[FILTERED]",
               "user_password" => "[FILTERED]",
               "old_password" => "[FILTERED]",
               "user" => %{"name" => "Jane", "password" => "[FILTERED]"}
             }

      assert request_data["headers"] == %{
               "content-type" => "multipart/mixed; boundary=plug_conn_test",
               "user-agent" => "ExampleBrowser/1.0",
               "cookie" => "[FILTERED]"
             }
    end
  end
end
