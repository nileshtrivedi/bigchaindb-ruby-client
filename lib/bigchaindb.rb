require 'json'
require 'shellwords'
require 'httparty'

module Bdb
  def self.generate_keys
    JSON.parse(`bdb generate_keys`)
    # {"public"=> "x", "private"=> "y"} #Base58 256-bit numbers
  end

  def self.generate_output(owner_after, amount = 1)
    # owner_after = who can consume this output? Can be a single pubkey or a m-of-n ThresholdSha256 condition
    JSON.parse(`bdb generate_output --amount #{[amount,owner_after].shelljoin}`)
  end

  def self.create_txn(owner_before, output, asset_data, metadata)
    # owner_before is the issuer of the asset
    args = [
      "--asset-data", asset_data.to_json,
      "--metadata", metadata.to_json,
      owner_before,
      output.to_json
    ]
    command = "bdb create #{args.shelljoin}"
    JSON.parse(`#{command}`)
  end

  def self.transfer_txn(inputs, outputs, asset, metadata = nil)
    if metadata
      args = [inputs.to_json, outputs.to_json, asset.to_json, metadata.to_json]
    else
      args = [inputs.to_json, outputs.to_json, asset.to_json]
    end
    JSON.parse(`bdb transfer #{args.shelljoin}`)
  end

  def self.get_asset(txn)
    args = [txn.to_json]
    JSON.parse(`bdb get_asset #{args.shelljoin}`)
  end

  def self.sign(txn,privkey)
    args = [txn.to_json, privkey]
    JSON.parse(`bdb sign #{args.shelljoin}`)
  end

  def self.spend(txn, output_ids = [])
    # Convert outputs in txn to signable/spendable inputs.
    if output_ids.any?
      args = [txn.to_json]
    else
      args = [txn.to_json, output_ids.to_json]
    end
    JSON.parse(`bdb spend #{args.shelljoin}`)
  end

  def self.unspent_outputs(ipdb, pubkey)
    resp = self.get_outputs_by_pubkey(ipdb, pubkey, spent = :both)
    JSON.parse(resp.body)
  end

  def self.transfer_asset(ipdb, receiver_pubkey, sender_pubkey, sender_privkey, inputs, amount, asset_id, metadata = {"ts"=> Time.now.to_s})
    asset = { "id" => asset_id}
    input_amount = inputs["outputs"].inject(0) { |sum,out| sum + out["amount"].to_i }
    if amount > input_amount
      puts "input_amount < amount"
      return nil
    end
    outputs = [Bdb.generate_output(receiver_pubkey,amount)]
    if amount < input_amount
      # left-over amount should be transferred back to sender
      outputs.push(Bdb.generate_output(sender_pubkey,input_amount - amount))
    end
    input = Bdb.spend(inputs)
    transfer = Bdb.transfer_txn(input, outputs, asset, metadata)
    signed_transfer = Bdb.sign(transfer, sender_privkey)
    resp = post_transaction(ipdb, signed_transfer)
    if resp.code == 202
      puts "Transaction posted. Now checking status..."
      sleep(5)
      txn = JSON.parse(resp.body)
      status_resp = get_transaction_status(ipdb, txn["id"])
      if (status_resp.code == 200) && JSON.parse(status_resp.body)["status"] == "valid"
        return {"transfer" => transfer, "txn" => txn}
      else
        puts "Trying again: #{status_resp.code} #{status_resp.body}"
        sleep(5)
        status_resp = get_transaction_status(ipdb, txn["id"])
        if (status_resp.code == 200) && JSON.parse(status_resp.body)["status"] == "valid"
          return {"transfer" => transfer, "txn" => txn}
        else
          puts "Tried twice but failed. #{status_resp.code} #{status_resp.body}"
          return nil
        end
      end
    else
      puts "Error in transfer_asset: #{resp.code} #{resp.body}"
      return nil
    end
  end

  def self.create_asset(ipdb, public_key, private_key, asset_data, amount = 1, metadata = {"x"=> "y"})
    output = Bdb.generate_output(public_key, amount)
    create = Bdb.create_txn(public_key, output, asset_data, metadata)
    signed_create = Bdb.sign(create, private_key)
    resp = post_transaction(ipdb, signed_create)
    if resp.code == 202
      puts "Transaction posted. Now checking status..."
      sleep(5)
      txn = JSON.parse(resp.body)
      status_resp = get_transaction_status(ipdb, txn["id"])
      if (status_resp.code == 200) && JSON.parse(status_resp.body)["status"] == "valid"
        return {"create" => create, "txn" => txn}
      else
        puts "Trying again: #{status_resp.code} #{status_resp.body}"
        sleep(5)
        status_resp = get_transaction_status(ipdb, txn["id"])
        if (status_resp.code == 200) && JSON.parse(status_resp.body)["status"] == "valid"
          return {"create" => create, "txn" => txn}
        else
          puts "Tried twice but failed. #{status_resp.code} #{status_resp.body}"
          return nil
        end
      end
    else
      puts "Error in create_asset: #{resp.code} #{resp.body}"
      return nil
    end
  end

  def self.test
    # Generate key-pairs
    alice = Bdb.generate_keys
    puts "alice = #{alice.to_json}\n\n"
    bob = Bdb.generate_keys
    puts "bob = #{bob.to_json}\n\n"

    # Define the metadata for an asset, null should work too
    asset_data = { "name" => "mycoin", "symbol" => "MC" }
    puts "asset = #{asset_data.to_json}\n\n"

    # To create a CREATE txn, we need output and asset. metadata is optional
    # Let's generate the output first: we'll need receiver and amount
    output = Bdb.generate_output(alice["public"],100)
    puts "output = #{output.to_json}\n\n"

    metadata = {"msg" => "creating mycoin asset"}
    create = Bdb.create_txn(alice["public"], output, asset_data, metadata)
    puts "create = #{create.to_json}\n\n"

    signed_create = Bdb.sign(create, alice["private"])
    puts "signed_create = #{signed_create.to_json}\n\n"

    # This signed CREATE txn can be sent to BigChainDB over HTTP api
    ipdb = { "url" => ENV["IPDB_URL"], "app_id" => ENV["IPDB_APP_ID"], "app_key" => ENV["IPDB_APP_KEY"]}
    resp = post_transaction(ipdb, signed_create)
    puts "resp = #{resp.code} #{resp.body}"

    # Now let's create a TRANSFER txn and transfer 10 coins to bob
    # we'll need: inputs, outputs, asset and metadata
    # asset for transfer is just { "id": "id of the create txn"}
    asset = { "id" => signed_create["id"]}
    output = Bdb.generate_output(bob["public"],10)
    input = Bdb.spend(create)
    puts "input = #{input.to_json}\n\n"

    transfer = Bdb.transfer_txn(input, output, asset, {"msg" => "txferring"})
    puts "transfer = #{transfer.to_json}\n\n"

    signed_transfer = Bdb.sign(transfer, alice["private"])
    puts "signed_transfer = #{signed_transfer.to_json}\n\n"
    # Now send this to server
    resp = post_transaction(ipdb, signed_transfer)
    puts "resp = #{resp.code} #{resp.body}"

    # Get all txns for this asset
    txns = JSON.parse(get_transactions_by_asset(root_url, asset["id"]).body)

    # txfr status
    puts get_transaction_status(ipdb, txns.first["id"]).body
    puts get_transaction_status(ipdb, txns.last["id"]).body
  end

  def self.post_transaction(ipdb, txn)
    HTTParty.post(ipdb["url"] + "/transactions/", {:body => txn.to_json, :headers => {"Content-Type" => "application/json", "app_id" => ipdb["app_id"], "app_key" => ipdb["app_key"]}})
  end

  def self.get_transaction_by_id(ipdb, txn_id)
    HTTParty.get(ipdb["url"] + "/transactions/#{txn_id}")
  end

  def self.get_transactions_by_asset(ipdb, asset_id)
    HTTParty.get(ipdb["url"] + "/transactions?asset_id=#{asset_id}")
  end

  def self.get_outputs_by_pubkey(ipdb, pubkey, spent = :both)
    return HTTParty.get(ipdb["url"] + "/outputs?public_key=#{pubkey}") if spent == :both
    return HTTParty.get(ipdb["url"] + "/outputs?public_key=#{pubkey}&spent=#{spent}") # true or false
  end

  def self.get_transaction_status(ipdb, txn_id)
    HTTParty.get(ipdb["url"] + "/statuses?transaction_id=#{txn_id}")
  end

  def self.get_assets(ipdb, query)
    HTTParty.get(ipdb["url"] + "/assets?search=#{query}")
  end
end