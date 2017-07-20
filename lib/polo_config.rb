require 'yaml'
require 'listen'


class PoloConfig
  DEFAULT_CACHE_SECONDS = 45
  @creds = Queue.new
  @cred_mutex = Mutex.new
  @config = {}

  def self.logger
    PoloLogger.logger
  end

  def self.relay
    PoloRelay
  end

  def self.config
    @config
  end

  def self.cache_periods
    @config['cache']['periods']
  end

  def self.global_expiry
    @config['cache']['global_expiry']
  end

  def self.ttl(command)
    if command == 'buy'
      @config['buy']['timeout'] || 30
    else
      @config['cache']['ttl'] ? @config['cache']['ttl'][command] || DEFAULT_CACHE_SECONDS : DEFAULT_CACHE_SECONDS
    end
  end

  def self.creds
    cred = nil
    throw "No creds!" if !@creds || @creds.length == 0

    @cred_mutex.synchronize do
      while true
        cred = @creds.pop
        @creds.push(cred)
        return cred unless cred[:mutex].locked?
        sleep 0.25 # chill
      end
    end
    cred
  end

  def self.buy_mode(pair)
    if @config['buy_overrides'] && @config['buy_overrides'][pair]
      @config['buy_overrides'][pair].to_sym
    else
      @config['buy']['mode'].to_sym
    end
  end

  def self.max_balance_count
    @config['buy']['max_balance_count'] || 0
  end

  def self.default_period
    @config['cache']['default_period'] || 900
  end

  def self.poller_intervals
    { 'history' => 15, 'balances' => 15, 'orders' => 15}.merge(@config['poller'])
  end

  def self.trade_history_days
    @config['cache']['trade_history_days'] || 1
  end

  def self.web_price_ema
    @config['web']['price_ema'] || 16
  end

  def self.web_volume_ema
    @config['web']['volume_ema'] || 16
  end

  def self.web_progress_bar_interval
    @config['web']['progress_bar'] || 0
  end

  def self.default_position
    @config['cache']['default_position'] || 0.0
  end

  #------------------------------------------------------------------------------------------------------------------

  def self.start!
    load_config
    logger.info('config') { "Watching #{Dir.pwd}/config.yml" }

    @listener = Listen.to(Dir.pwd, only: %r{config.yml$}, wait_for_delay: 0.5 ) do |modified, added, removed|
      load_config if modified
    end
    @listener.start
  end

  def self.load_config
    logger.debug('config') { "Reloading Configuration"}
    @config = YAML.load_file('config.yml')

    @config = {
      'cache': { 'periods': 50 },
      'stats': { 'interval': 30},
      'log': { 'level': 'INFO'},
      'buy': {'mode': 'blocked' },
      'buy_overrides': {}
    }.merge(@config)


    log_level = @config['log']['level']
    log_level = Logger.const_get log_level rescue Logger::INFO
    logger.level = log_level
    logger.info('config') { "Log level set to #{logger.level}"}

    # setup creds
    @cred_mutex.synchronize do
      @creds.clear
      @config['poloniex']['creds'].each do |x|
        @creds.push({ key: x['key'], secret: x['secret'], mutex: Mutex.new }) if x['key'] && x['secret']
      end
    end
    logger.info('config') { "#{@creds.length} polo keys loaded."}

    relay.start_poller

    buy_mode = (@config['buy']['mode']).to_sym
    unless [:blocked,:normal,:passthrough].include?(buy_mode)
      logger.warn('config') { "Invalid buy mode specified -- #{buy_mode} -- all buys will be BLOCKED" }
      @config['buy']['mode'] = :blocked
    end
    logger.info('config') { "Buy mode set to #{buy_mode}"}

    config_log = @config.clone
    config_log.delete('poloniex')
    logger.info('config') { "Config reloaded:  #{config_log}" }
  end
end