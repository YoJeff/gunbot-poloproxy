require 'logger'

class PoloLogger
	#@logger = Logger.new(STDOUT)
	@logger = Logger.new('gunprox.log', 'daily')
	@logger.level = Logger::DEBUG
  @buy_history = []

  @console_logger = Logger.new($stdout)
  @console_logger.level = Logger::DEBUG


  def self.logger
  	@logger
  end

  def self.buy_log(result,reason,params)
    @buy_history << [result,reason,params]
    @logger.info('buy') { "Buy #{result} #{reason} #{params}"}    
  end

  def self.console_logger
    @console_logger
  end



end