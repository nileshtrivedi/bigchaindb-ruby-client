require 'test/unit'
require_relative '../lib/bigchaindb'

class BigchainDBTest < Test::Unit::TestCase
  self.test_order = :alphabetic
  def setup
    @ipdb = {"url" => "https://test.ipdb.io/api/v1", "app_id" => ENV["IPDB_APP_ID"], "app_key" => ENV["IPDB_APP_KEY"]}
    # Dummy asset, safe to store keys in git
    @genesis = {"public" => "A1C3vzrCY5nrrohHRxQwBbWw1AfGkRB3S4zwPTZCcdoz", "private" => "EXVK9zvEQRRybGcfdGnqmhSPiCKocWbXN9uAhvJDwpbu"}
    @asset = "d4940533c0fa02ce6e17a29189d03785b79f06dc98cdb881dde1fbca0ee3e55e" # BdbTest
    @user1 = {"public"=>"HoFUXgDMhHiB6TigmLMoPTHQDDryDS6KbKi4p1GFjhfe", "private"=>"FbcfxNpLCkJoMkQfW5pwAvpFKTfwdk3AB8DFu3GQwJKd"}
    @user2 = {"public"=>"ApgPa5eDH11cAo6GwnYZAq1623U8hxXA79EggV671619", "private"=>"EprfDNjPoUMpPCix4M1KMNnD1fNzYg8h7NwEK8aDozp3"}
  end

  def test_a_generate_keypair
    account = Bdb.generate_keys
    assert account.has_key?("public")
    assert account.has_key?("private")
    assert_match(Bdb::ADDRESS_REGEXP, account["public"])
    assert_match(Bdb::ADDRESS_REGEXP, account["private"])
  end

  def test_b_create
    # Uncomment only when needed, otherwise it creates a new asset on IPDB every time it runs
    # genesis = Bdb.generate_keys
    # obj = Bdb.create_asset(@ipdb, genesis["public"], genesis["private"], asset_data = {"name": "dummyasset"}, 100, metadata = {"ts": Time.now.to_i})
    # assert_equal(false, obj.nil? || !obj.is_a?(Hash))
    # @asset = obj["txn"]["id"]
  end

  def test_c_check_balance
    bal = Bdb.balance_asset(@ipdb, @genesis["public"], @asset)
    assert(bal.is_a?(Integer) && bal > 0)
  end

  def test_d_transfer
    gen_bal = Bdb.balance_asset(@ipdb, @genesis["public"], @asset)
    u1_bal = Bdb.balance_asset(@ipdb, @user1["public"], @asset)
    u2_bal = Bdb.balance_asset(@ipdb, @user2["public"], @asset)
    bals = {:gen_bal => gen_bal, :u1_bal => u1_bal, :u2_bal => u2_bal}
    puts "bals = #{bals.inspect}"

    receiver_pubkeys_amounts = [{:pubkey => @user1["public"], :amount => 5}, {:pubkey => @user2["public"], :amount => 5}]
    txn, message = Bdb.transfer_asset(@ipdb, receiver_pubkeys_amounts, @genesis["public"], @genesis["private"], inputs = nil, @asset, metadata = {"ts"=> Time.now.to_i})
    puts message
    assert txn
    assert_equal(gen_bal - 10, Bdb.balance_asset(@ipdb, @genesis["public"], @asset))
    assert_equal(u1_bal + 5, Bdb.balance_asset(@ipdb, @user1["public"], @asset))
    assert_equal(u2_bal + 5, Bdb.balance_asset(@ipdb, @user2["public"], @asset))
  end
end