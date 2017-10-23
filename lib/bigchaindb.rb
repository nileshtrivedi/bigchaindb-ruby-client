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
      args = [txn.to_json, output_ids.to_json]
    else
      args = [txn.to_json]
    end
    JSON.parse(`bdb spend #{args.shelljoin}`)
  end

  def self.unspent_outputs(ipdb, pubkey)
    resp = self.get_outputs_by_pubkey(ipdb, pubkey, spent = false)
    JSON.parse(resp.body)
  end

  def self.transfer_asset(ipdb, receiver_pubkeys_amounts, sender_pubkey, sender_privkey, inputs, asset_id, metadata = {"ts"=> Time.now.to_s})
    asset = { "id" => asset_id}
    new_inputs = []
    input_amount = 0

    if inputs.nil? || inputs.none?
      # ask IPDB for unspent outputs
      unspent = Bdb.unspent_outputs(ipdb, sender_pubkey)
      if unspent.none?
        return nil, "#{sender_pubkey} does not have any unspent outputs for asset #{asset_id}"
      end
      unspent.each do |u|
        txn = JSON.parse(Bdb.get_transaction_by_id(ipdb, u["transaction_id"]).body)
        next unless txn["asset"]["id"] == asset_id
        input_amount += txn["outputs"][u["output_index"]]["amount"].to_i
        new_inputs.push(Bdb.spend(txn, u["output_index"]))
      end
    else
      # assume that every output for sender_pubkey in given inputs is unspent and can be used as input
      inputs.each do |inp|
        input_amount += inp["outputs"].select { |o| o["condition"]["details"]["public_key"] == sender_pubkey }.inject(0) { |sum,out| sum + out["amount"].to_i }
        new_inputs += Bdb.spend(inp, inp["outputs"].each_with_index.select { |o,i| o["condition"]["details"]["public_key"] == sender_pubkey }.map(&:last))
      end
    end

    outgoing_amount = 0
    receiver_pubkeys_amounts.each do |pa|
      if pa[:amount] <= 0
        return nil, "Invalid amount (<=0) found for #{pa[:pubkey]}"
      end
      outgoing_amount += pa[:amount]
    end

    if outgoing_amount > input_amount
      return nil, "input_amount #{input_amount} < outgoing_amount #{outgoing_amount}"
    end
    outputs = receiver_pubkeys_amounts.collect { |pa| Bdb.generate_output(pa[:pubkey],pa[:amount]) }
    if outgoing_amount < input_amount
      # left-over amount should be transferred back to sender
      outputs.push(Bdb.generate_output(sender_pubkey,input_amount - outgoing_amount))
    end
    
    transfer = Bdb.transfer_txn(new_inputs, outputs, asset, metadata)
    signed_transfer = Bdb.sign(transfer, sender_privkey)
    resp = post_transaction(ipdb, signed_transfer)
    if resp.code == 202
      txn = JSON.parse(resp.body)
      puts "Transaction #{txn["id"]} posted. Now checking status..."
      sleep(5)
      status_resp = get_transaction_status(ipdb, txn["id"])
      if (status_resp.code == 200) && JSON.parse(status_resp.body)["status"] == "valid"
        return txn, "success"
      else
        puts "Trying again: #{status_resp.code} #{status_resp.body}"
        sleep(5)
        status_resp = get_transaction_status(ipdb, txn["id"])
        if (status_resp.code == 200) && JSON.parse(status_resp.body)["status"] == "valid"
          return txn, "success"
        else
          return nil, "Tried twice but failed. #{status_resp.code} #{status_resp.body}"
        end
      end
    else
      return nil, "Error in transfer_asset: #{resp.code} #{resp.body}"
    end
  end

  def self.balance_asset(ipdb, public_key, asset_id)
    unspent = Bdb.unspent_outputs(ipdb, public_key)
    balance = 0
    unspent.each do |u|
      txn = JSON.parse(Bdb.get_transaction_by_id(ipdb, u["transaction_id"]).body)
      next unless ((txn["operation"] == "CREATE") && (txn["id"] == asset_id)) || (txn["asset"]["id"] == asset_id)
      balance += txn["outputs"][u["output_index"]]["amount"].to_i
    end
    return balance
  end

  def self.create_asset(ipdb, public_key, private_key, asset_data, amount = 1, metadata = {"x"=> "y"})
    output = Bdb.generate_output(public_key, amount)
    create = Bdb.create_txn(public_key, output, asset_data, metadata)
    signed_create = Bdb.sign(create, private_key)
    resp = post_transaction(ipdb, signed_create)
    if resp.code == 202
      txn = JSON.parse(resp.body)
      puts "Transaction #{txn["id"]} posted. Now checking status..."
      sleep(5)
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