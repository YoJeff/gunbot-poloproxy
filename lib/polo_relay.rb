require 'net/http'
require 'openssl'
require 'rufus-scheduler'
require 'json'

module PoloRelay
  @mutex_keys = {}

  def self.buy(params)
    pair = params['currencyPair']
    unless pair
      logger.error('BUY') { "Blocked attempt to buy nil pair"}
      return {}
    end

    symbol = pair.split("_").last
    buy_mode = config.buy_mode(pair)
    buy_result = nil
    buy_reason = nil


    if buy_mode == :passthrough
      logger.warn('BUY') { "PASSTHROUGH - #{pretty_parms(params)}  ask=#{data.ticker_ask(pair)}"}
      return {}
    elsif buy_mode == :normal
      if !data.balances_loaded?
        logger.warn('BUY') { "BLOCK/DATA balances not loaded - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
        return {}
      end
      if !data.orders_loaded?
        logger.warn('BUY') { "BLOCK/DATA orders not loaded - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
        return {}
      end
      if cache.cache_valid?(params)
        logger.warn('BUY') { "BLOCK/timeout - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
        return {}
      end
      if data.has_balance?(symbol)
        logger.warn('BUY') { "BLOCK/balance - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
        return {}
      end
      if data.has_orders?(pair)
        logger.warn('BUY') { "BLOCK/orders - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
        return {}
      end

      if config.max_balance_count > 0 && data.balance_count >= config.max_balance_count
        logger.warn('BUY') { "BLOCK/max_balance - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
        return {}
      end
      # let it rip skip
      results = cache.cache(params) do
        cache_hit = false
        relay_private(params)
      end
      logger.warn('BUY') { "RELAYED - #{pretty_parms(params)} - #{results}  ask=#{data.ticker_ask(pair)}"}
      return results
    else
      logger.warn('BUY') { "BLOCK/policy - #{pretty_parms(params)} ask=#{data.ticker_ask(pair)}"}
      return {}
    end
  end

  def self.sell(params)
    amount = Float(params['amount']) rescue 0
    pair = params['currencyPair']

    if amount == 0
      logger.warn('SELL') { "BLOCK /zerosell - #{pretty_parms(params)} bid=#{data.ticker_bid(pair)}"}
      return {}
    end
    results = cache.cache(params) do
      relay_private(params)
    end
    logger.warn('SELL') { "RELAYED - #{pretty_parms(params)} - #{results} bid=#{data.ticker_bid(pair)}"}
    return results
  end

  def self.data
    PoloData
  end


  def self.logger
    PoloLogger.logger
  end

  def self.config
    PoloConfig
  end

  def self.cache
    PoloCache
  end

  def self.start_poller
    @scheduler ||= Rufus::Scheduler.new
    intervals = config.poller_intervals

    @jobs ||= [
      { name: :history, task: -> { set_history }, job: nil },
      { name: :balances, task: -> { set_balances }, job: nil },
      { name: :orders, task: -> { set_orders }, job: nil }
    ]

    @jobs.each do |job|
      j = job[:job]
      if j
        j.unschedule
        j.kill
      end
      j = @scheduler.interval "#{intervals[job[:name].to_s]}s", :job=>true, :first=>:now do
        job[:task].call
      end
      job[:job] = j
    end
  end


  def self.get_complete_balances(params,ttl)
    results, metrics = cache.get_with_metrics(params['command'])
    logger.warn('relay') { "Balances are empty, returning nil for now." } unless results
    logger.warn('relay') { "Balances are stale.   #{metrics['age']} seconds." } if results && metrics[:stale]
    [results,true]
  end

  def self.get_trade_history(params,ttl)
    pair = params['currencyPair'] || "all"
    results, metrics = cache.get_with_metrics(params['command'])
    logger.warn('relay') { "History is empty, returning nil for now." } unless results
    logger.warn('relay') { "History is stale.   #{metrics['age']} seconds." } if results && metrics[:stale]

    results = results[pair] || [] rescue nil if results && pair != 'all'
    [results,true]
  end

  def self.get_open_orders(params,ttl)
    pair = params['currencyPair'] || "all"
    results, metrics = cache.get_with_metrics(params['command'])
    logger.warn('relay') { "Orders are empty, returning nil for now." } unless results
    logger.warn('relay') { "Orders are stale.   #{metrics['age']} seconds." } if results && metrics[:stale]

    results = results[pair] || [] rescue nil if results && pair != 'all'
    [results,true]
  end


  def self.process_public(params)
    result = nil
    cache_hit = true
    command = params['command']
    return json_error_message("No Command given") unless command
    ttl = config.ttl(command)

    time = Benchmark.realtime do
      if command == 'returnChartData'
        result = cache.cache(params) do
          cache_hit = false
          start = params['start'].to_i
          period = params['period'].to_i
          params['start'] = [start,Time.now.getutc.to_i - (config.cache_periods * period)].min
          params['end'] = 9999999999
          PoloRelay.relay_public(params)
        end
      else
        result = cache.cache(params) do
          cache_hit = false
          PoloRelay.relay_public(params)
        end
      end
    end
    logger.debug('api') {"get - #{cache_hit ? 'HIT' : 'MIS'} #{'%.3f' % time} #{pretty_parms(params)}"}
    result
  end



  def self.process_private(params)
    result = cache_hit = nil
    command = params['command']
    return json_error_message("No Command given") unless command
    ttl = config.ttl(command)

    time = Benchmark.realtime do
      case command
      when 'returnCompleteBalances'
        result, cache_hit = get_complete_balances(params,ttl)
      when 'returnTradeHistory'
        result, cache_hit = get_trade_history(params,ttl)
      when 'returnOpenOrders'
        result, cache_hit = get_open_orders(params,ttl)
      when 'buy'
        cache_hit = false
        result = buy(params)
      when 'sell'
        cache_hit = false
        result = sell(params)
      else
        # just relay the damn thing
        cache_hit = false
        result = relay_private(params)
        logger.warn('relay') {"PASSTHROUGH - #{pretty_parms(params)} - #{result}"}
        # return json_error_message("Unknown Command #{command}")
      end
    end
    logger.debug('api') {"post- #{cache_hit ? 'HIT' : 'MIS'} #{'%.3f' % time} #{pretty_parms(params)}"}
    result
  end


  def self.relay_private( params )
    results = headers = nil
    creds = config.creds
    throw "NO/BAD CREDS!" unless creds[:key] && creds[:secret]

    mutex = creds[:mutex]
    mutex.synchronize do

      uri = URI('https://www.poloniex.com/tradingApi')
      http = Net::HTTP.new(uri.host,uri.port)
      http.use_ssl = true

      params['nonce'] = (Time.now.to_f * 10000000).to_i
      uri.query = URI.encode_www_form(params)
      sig = OpenSSL::HMAC.hexdigest( 'sha512', creds[:secret] , uri.query )
      headers = { 'Key': creds[:key], 'Sign': sig }

      begin
        res = http.post(uri.path,uri.query,headers)
        http.finish if http.started?

        if res.is_a?(Net::HTTPSuccess)
          results = JSON.parse(res.body)
          if results.is_a?(Hash) && results['error']
            logger.warn('relay')  { "API Error Ignored - #{pretty_parms(params)} - #{results}" }
            results = nil
          end
        else
          results = nil
          logger.warn('relay')  { "HTTP #{res.code} Intercepted - #{pretty_parms(params)} - #{res.message} #{creds[:key]}" }
        end
        rescue => e
          logger.error('relay')  { "Fatal Error during post.  #{params}  #{e} " }
          results = nil
      end
    end
    results
  end

  def self.pretty_parms(params)
    params = params.clone
    params.delete('nonce')
    result = []
    result << params.delete('command')

    pair_period = params.delete('currencyPair')
    pair_period += ':' + params.delete('period') if params['period']
    result << pair_period

    range = params.delete('start').to_s
    range += ':' + params.delete('end').to_s if range && params['end']
    result << range

    result << "amount: #{params.delete('amount').to_s}" if params['amount']
    result << "rate: #{params.delete('rate').to_s}" if params['rate']

    if !params.empty?
      result << params.inspect
    end

    result.compact.join(' ')
  end


  private

  def self.set_balances
    time = Benchmark.realtime do
      params = { 'command' => 'returnCompleteBalances'}
      balances = relay_private(params)
      cache.cache(params,true) { balances }
    end
    logger.debug('relay') { "Poll:Balances - Update took #{'%.3f' % time} seconds." }
    time
  end

  def self.set_history
    time = Benchmark.realtime do
      start = Time.now.to_i - 86400 * config.trade_history_days
      params = { 'command' => 'returnTradeHistory', 'currencyPair' => 'all', 'start' => start }
      history = relay_private(params)
      params.delete('start')
      cache.cache(params,true) { history }
    end
    logger.debug('relay') { "Poll:History - Update took #{'%.3f' % time} seconds." }
    time
  end


  def self.set_orders
    orders = nil
    time = Benchmark.realtime do
      params = { 'command' => 'returnOpenOrders', 'currencyPair' => 'all' }
      orders = relay_private(params)
      cache.cache(params,true) { orders }
    end
    # check to see if any orders' charts are NOT cached and cache them up
    # disable for now until we get an update mech/method
    #orders.each {|k,v| cache_pair(k) unless v.length == 0 }  if orders

    logger.debug('relay') { "Poll:Orders - Update took #{'%.3f' % time} seconds." }
    time
  end

  # def self.cache_pair(pair)
  #   time = Benchmark.realtime do
  #     period = config.default_period
  #     params = { 'command' => 'returnChartData', 'period' => period, 'currencyPair' => pair, 'start' => Time.now.utc.to_i, 'end' => 9999999999 }
  #     PoloLogger.console_logger.debug "Caching #{pair} #{params}"
  #     process_public(params)
  #   end
  #   logger.debug('relay') { "Poll:Seed Chart #{params}" }
  # end


  def self.json_error_message(message)
    logger.error('proxy') { message }
    { error: message }
  end


  def self.relay_public( params = {})
    results = nil
    begin
      url = URI('https://www.poloniex.com/public')
      url.query = URI.encode_www_form(params)
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(url.request_uri)

      res = http.request(request)
      http.finish if http.started?

      if res.is_a?(Net::HTTPSuccess)
        results = JSON.parse(res.body)
      else
        logger.error('relay')  { "HTTP #{res.code} Intercepted - #{pretty_parms(params)} - #{res.message}" }
        results = nil
      end
    rescue => e
      logger.error "Fatal Error during get.  #{params}  #{e} "
      results = nil
    end
    results
  end


end
