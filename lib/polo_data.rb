class PoloData
  def self.cache
    PoloCache
  end

  def self.config
    PoloConfig
  end

  def self.cache_efficiency
    hit, miss = cache.stats
    Float(hit)/Float(hit + miss) * 100 rescue 0.0
  end

  def self.proxy_uptime
    secs = @proxy.uptime
    [[60, :seconds], [60, :minutes], [24, :hours], [1000, :days]].map{ |count, name|
      if secs > 0
        secs, n = secs.divmod(count)
        "#{n.to_i} #{name}"
      end
    }.compact.reverse.join("\n")
  end

  def self.btc_total
    return 0 unless balances_loaded?
    all_balances.sum {|x| x['btcValue'] }
  end

  def self.btc_on_orders
    return 0 unless balances_loaded?
    btc_balance = balance('BTC')
    btc_balance ? btc_balance['onOrders'] : 0
  end

  def self.btc_available
    return 0 unless balances_loaded?
    btc_balance = balance('BTC')
    btc_balance ? btc_balance['available'] : 0
  end

  def self.btc_in_trades
    return 0 unless balances_loaded?
    all_balances.sum {|x| x['symbol'] == 'BTC' ? 0 : x['btcValue'] }
  end


  def self.ticker_stats
    data = cache.get('returnTicker')
    results = nil
    if data
      results = {}
      ticker = data.inject([]) do |r,(k,v)|
        if k =~ /^BTC/
          v['pair'] = k
          v['percentChange'] = Float(v['percentChange'])
          v['baseVolume'] = Float(v['baseVolume'])
          r << v
        else
          r
        end
      end
      results[:market_average] = ticker.inject(0.0) {|r,v| r + v['percentChange'] } / ticker.size * 100
      results[:down] = ticker.inject(0) {|r,v| r += 1 if v['percentChange'] < 0 ; r}
      results[:up] = ticker.inject(0) {|r,v| r += 1 if v['percentChange'] >= 0 ; r}
      results[:top5] = ticker.sort {|x,y| y['percentChange'] <=> x['percentChange']}.slice(0,5)
      results[:bottom5] = ticker.sort {|x,y| y['percentChange'] <=> x['percentChange']}.reverse.slice(0,5)
      results[:weighted_avg] = ticker.inject(0.0) {|r,v| r + v['percentChange'] * v['baseVolume'] } / ticker.sum{ |x| x['baseVolume'] } * 100
    end
    results
  end



  def self.pair_periods_tracked
    cache.keys.select{|key| key.include?(':') }
  end

  def self.pairs_tracked
    pair_periods_tracked.map {|x| x.split(':').first }.uniq.sort
  end

  def self.pair_summary
    pair_periods_tracked.sort.inject([]) do |r,key|
      c = cache.read(key)
      data = c.get
      if data
        pair = key.split(':').first
        period = key.split(':').last
        last_close = data.last['close']

        last_buy_price = last_buy_price(pair)
        last_buy = last_buy(pair)
        pct_change = ((last_close / last_buy_price ) - 1.0) * 100 rescue 0

        r.push({
          pair: pair,
          period: period,
          age: c.age,
          stale: c.stale?,
          values: data,
          buy_mode: config.buy_mode(pair),
          has_orders: has_orders?(pair),
          has_balance: has_balance?(pair),
          last_buy_price: last_buy_price,
          last_buy: last_buy,
          pct_change:  pct_change,
          balance: balance(pair)
        })
      end
      r
    end
  end

  def self.buy_timeouts
    cache.keys.inject([]) do |r,key|
      if key.include?('$')
        symbol = key.split('$').last
        time_left = cache.read(key).time_left
        r << [symbol,time_left] if time_left > 0
      end
      r
    end
  end

  # -----------------------------------------------------------------------

  def self.balances_loaded?
    cache.loaded?('returnCompleteBalances')
  end

  def self.balances_age
    return unless balances_loaded?
    cache.read('returnCompleteBalances').age
  end

  def self.balance(symbol)
    return unless balances_loaded?
    symbol = symbol.split("_").last if symbol.include?("_")
    all_balances.find {|x| x['symbol'] == symbol } || []
  end

  def self.all_balances
    return unless balances_loaded?
    b = cache.get('returnCompleteBalances')
    return [] unless b

    b.inject([]) do |r,(k,v)|
      v['available'] = Float(v['available'])
      v['onOrders'] = Float(v['onOrders'])
      v['btcValue'] = Float(v['btcValue'])
      if v['available'] != 0 || v['onOrders'] != 0 || v['btcValue'] != 0
        v['symbol'] = k
        r << v
      end
      r
    end
  end

  def self.balance_count
    all_balances.length
  end

  def self.has_balance?(symbol)
    return unless balances_loaded?
    balance(symbol).length > 0
  end

  # -----------------------------------------------------------------------

  def self.history_loaded?
    cache.loaded?('returnTradeHistory')
  end

  def self.history_age
    return unless history_loaded?
    cache.read('returnTradeHistory').age
  end


  def self.history(pair)
    return unless history_loaded?
    all_history.select {|x| x['pair'] == pair }
  end

  def self.last_buy(pair)
    history_loaded? && all_history.find {|x| x['pair'] == pair && x['type'] == 'buy' }
  end

  def self.all_history
    return unless history_loaded?
    b = cache.get('returnTradeHistory')
    return [] unless b

    b.inject([]) do |r,(k,v)|
      v.each do |trade|
        trade['pair'] = k
        r << trade
      end
      r
    end
  end

  def self.has_history?(pair)
    return unless history_loaded?
    history(pair).length > 0
  end

  def self.last_buy_price(pair)
    return unless history_loaded?
    Float(last_buy(pair)['rate']) rescue nil
  end

  # -----------------------------------------------------------------------

  def self.orders_loaded?
    cache.loaded?('returnOpenOrders')
  end

  def self.orders_age
    return unless orders_loaded?
    cache.read('returnOpenOrders').age
  end


  def self.orders(pair)
    return unless orders_loaded?
    all_orders.find {|x| x['pair'] == pair } || []
  end

  def self.all_orders
    return unless orders_loaded?
    b = cache.get('returnOpenOrders')
    return [] unless b

    b.inject([]) do |r,(k,v)|
      v.each do |order|
        order['pair'] = k
        r << order
      end
      r
    end
  end

  def self.has_orders?(pair)
    return unless orders_loaded?
    orders(pair).length > 0
  end

  # -----------------------------------------------------------------------





  private

  def self.ema(data,period,key, *options)
    d = options.include?(:exclude_last) ? data.slice(0,data.length-1) : data.slice(0,data.length)
    initial = d.first[key]
    result = d.inject(initial) do |r,x|
      r + ((x[key] - r) * 2/(period+1))
    end
    result
  end

  def self.injectEMA(data,period,source,dest)
    if data
      last = data.first[source]
      data.each do |v|
        ema =  last + ((v[source] - last) * 2/(period+1))
        ema = Float('%.8f' % ema)
        v[dest] = ema
        last = ema
      end
    end
  end


end