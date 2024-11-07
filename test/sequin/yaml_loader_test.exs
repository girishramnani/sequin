defmodule Sequin.YamlLoaderTest do
  use Sequin.DataCase

  alias Sequin.Accounts.Account
  alias Sequin.Consumers.HttpEndpoint
  alias Sequin.Databases.PostgresDatabase
  alias Sequin.Databases.Sequence
  alias Sequin.Replication.PostgresReplicationSlot
  alias Sequin.Test.Support.ReplicationSlots
  alias Sequin.Test.UnboxedRepo
  alias Sequin.YamlLoader

  @moduletag :unboxed

  @publication "characters_publication"

  def replication_slot, do: ReplicationSlots.slot_name(__MODULE__)

  setup do
    Application.put_env(:sequin, :self_hosted, true)

    # Fast-forward the replication slot to the current WAL position
    :ok = ReplicationSlots.reset_slot(UnboxedRepo, replication_slot())

    :ok
  end

  def playground_yml do
    """
    account:
      name: "Playground"

    users:
      - email: "admin@sequinstream.com"
        password: "sequinpassword!"

    databases:
      - name: "test-db"
        username: "postgres"
        password: "postgres"
        hostname: "localhost"
        database: "sequin_test"
        slot_name: "#{replication_slot()}"
        publication_name: "#{@publication}"

    sequences:
      - name: "characters"
        database: "test-db"
        table_schema: "public"
        table_name: "Characters"
        sort_column_name: "updated_at"
    """
  end

  describe "playground.yml" do
    test "creates database and sequence with no existing account" do
      assert :ok = YamlLoader.load_from_yml(playground_yml())

      assert [account] = Repo.all(Account)
      assert account.name == "Playground"

      assert [%PostgresDatabase{} = db] = Repo.all(PostgresDatabase)
      assert db.account_id == account.id
      assert db.name == "test-db"

      assert [%PostgresReplicationSlot{} = replication] = Repo.all(PostgresReplicationSlot)
      assert replication.postgres_database_id == db.id
      assert replication.slot_name == replication_slot()
      assert replication.publication_name == @publication

      assert [%Sequence{} = sequence] = Repo.all(Sequence)
      assert sequence.postgres_database_id == db.id
      assert sequence.table_name == "Characters"
      assert sequence.table_schema == "public"
      assert sequence.sort_column_name == "updated_at"
    end

    test "applying yml twice creates no duplicates" do
      assert :ok = YamlLoader.load_from_yml(playground_yml())
      assert :ok = YamlLoader.load_from_yml(playground_yml())

      assert [account] = Repo.all(Account)
      assert account.name == "Playground"

      assert [%PostgresDatabase{} = db] = Repo.all(PostgresDatabase)
      assert db.account_id == account.id
      assert db.name == "test-db"

      assert [%PostgresReplicationSlot{} = replication] = Repo.all(PostgresReplicationSlot)
      assert replication.postgres_database_id == db.id
      assert replication.slot_name == replication_slot()
      assert replication.publication_name == @publication

      assert [%Sequence{} = sequence] = Repo.all(Sequence)
      assert sequence.postgres_database_id == db.id
      assert sequence.table_name == "Characters"
    end
  end

  describe "databases" do
    test "creates a database" do
      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               databases:
                 - name: "test-db"
                   username: "postgres"
                   password: "postgres"
                   hostname: "localhost"
                   database: "sequin_test"
                   slot_name: "#{replication_slot()}"
                   publication_name: "#{@publication}"
               """)

      assert [account] = Repo.all(Account)
      assert account.name == "Configured by Sequin"

      assert [%PostgresDatabase{} = db] = Repo.all(PostgresDatabase)
      assert db.account_id == account.id
      assert db.name == "test-db"
    end

    test "updates a database" do
      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               databases:
                 - name: "test-db"
                   username: "postgres"
                   password: "postgres"
                   hostname: "localhost"
                   database: "sequin_test"
                   slot_name: "#{replication_slot()}"
                   publication_name: "#{@publication}"
               """)

      assert [%PostgresDatabase{} = db] = Repo.all(PostgresDatabase)
      assert db.pool_size == 3

      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               databases:
                 - name: "test-db"
                   username: "postgres"
                   password: "postgres"
                   hostname: "localhost"
                   database: "sequin_test"
                   pool_size: 5
                   slot_name: "#{replication_slot()}"
                   publication_name: "#{@publication}"
               """)

      assert [%PostgresDatabase{} = db] = Repo.all(PostgresDatabase)
      assert db.name == "test-db"
      assert db.pool_size == 5
    end
  end

  describe "http_endpoints" do
    test "creates webhook.site endpoint" do
      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               http_endpoints:
                 - name: "webhook-endpoint"
                   webhook.site: "true"
               """)

      assert [endpoint] = Repo.all(HttpEndpoint)
      assert endpoint.name == "webhook-endpoint"
      assert endpoint.scheme == :https
      assert endpoint.host == "webhook.site"
      assert "/" <> uuid = endpoint.path
      assert Sequin.String.is_uuid?(uuid)
    end

    test "creates local endpoint" do
      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               http_endpoints:
                 - name: "local-endpoint"
                   local: "true"
               """)

      assert [endpoint] = Repo.all(HttpEndpoint)
      assert endpoint.name == "local-endpoint"
      assert endpoint.use_local_tunnel == true
      refute endpoint.path
      assert endpoint.headers == %{}
      assert endpoint.encrypted_headers == %{}
    end

    test "creates local endpoint with options" do
      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               http_endpoints:
                 - name: "local-endpoint"
                   local: "true"
                   path: "/webhook"
                   headers:
                     - key: "X-Test"
                       value: "test-value"
                   encrypted_headers:
                     - key: "X-Secret"
                       value: "secret-value"
               """)

      assert [endpoint] = Repo.all(HttpEndpoint)
      assert endpoint.name == "local-endpoint"
      assert endpoint.use_local_tunnel == true
      assert endpoint.path == "/webhook"
      assert endpoint.headers == %{"X-Test" => "test-value"}
      assert endpoint.encrypted_headers == %{"X-Secret" => "secret-value"}
    end

    test "creates external endpoint" do
      assert :ok =
               YamlLoader.load_from_yml("""
               account:
                 name: "Configured by Sequin"

               http_endpoints:
                 - name: "external-endpoint"
                   url: "https://api.example.com:8443/webhooks?key=value#fragment"
                   headers:
                     - key: "Authorization"
                       value: "Bearer token"
                   encrypted_headers:
                     - key: "X-Secret"
                       value: "secret-value"
               """)

      assert [endpoint] = Repo.all(HttpEndpoint)
      assert endpoint.name == "external-endpoint"
      assert endpoint.scheme == :https
      assert endpoint.host == "api.example.com"
      assert endpoint.port == 8443
      assert endpoint.path == "/webhooks"
      assert endpoint.query == "key=value"
      assert endpoint.fragment == "fragment"
      assert endpoint.headers == %{"Authorization" => "Bearer token"}
      assert endpoint.encrypted_headers == %{"X-Secret" => "secret-value"}
    end

    test "applying yml twice creates no duplicates" do
      yaml = """
      account:
        name: "Configured by Sequin"

      http_endpoints:
        - name: "test-endpoint"
          url: "https://api.example.com/webhook"
      """

      assert :ok = YamlLoader.load_from_yml(yaml)
      assert :ok = YamlLoader.load_from_yml(yaml)

      assert [endpoint] = Repo.all(HttpEndpoint)
      assert endpoint.name == "test-endpoint"
    end

    test "validates required fields" do
      assert_raise RuntimeError, ~r/Invalid HTTP endpoint configuration/, fn ->
        YamlLoader.load_from_yml("""
        account:
          name: "Configured by Sequin"

        http_endpoints:
          - name: "invalid-endpoint"
        """)
      end
    end
  end
end
