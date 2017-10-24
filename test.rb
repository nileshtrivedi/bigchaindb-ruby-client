require 'test/unit/ui/console/testrunner'
require_relative 'test/bigchaindb_test'

class BigchainDBTestSuite
  def self.suite
    suite = Test::Unit::TestSuite.new
    suite << BigchainDBTest.suite
    return suite
  end
end

Test::Unit::UI::Console::TestRunner.run(BigchainDBTestSuite)