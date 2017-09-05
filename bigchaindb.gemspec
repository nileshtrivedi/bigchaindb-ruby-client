Gem::Specification.new do |s|
  s.name        = 'bigchaindb'
  s.version     = '0.0.4'
  s.date        = '2017-09-05'
  s.summary     = "BigchainDB / IPDB client"
  s.description = "Library for preparing/signing transactions and submitting them or querying a BigchainDB/IPDB node"
  s.authors     = ["Nilesh Trivedi"]
  s.email       = 'github@nileshtrivedi.com'
  s.files       = ["lib/bigchaindb.rb"]
  s.add_runtime_dependency 'httparty'
  s.homepage    =
    'https://github.com/nileshtrivedi/bigchaindb-ruby-client'
  s.license       = 'MIT'
end
