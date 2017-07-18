class PoloCacheItem
  attr_accessor :key, :ttl, :value
  def initialize(key)
    throw "NO NIL KEYS" if key.nil?
    @key = key
    @ttl = 0
    @value = nil
    @mutex = Mutex.new
    @timestamp = 0
  end

  def config
    PoloConfig
  end

  def logger
    PoloLogger.logger
  end



  def set(value,ttl)
    if value
      @mutex.synchronize do 
        @value = value
        @ttl = ttl
        @timestamp = Time.now.to_i
      end
    else
      if super_stale?
        logger.info('cache') { "Force expiring #{@key}, age #{age}."}
        @value = nil 
      end
    end
    value
  end

  def get(start=nil)
    #throw "Unknown request for #{key} #{start}" if start && start > 0 && !is_chart?

    @mutex.synchronize do 
      if super_stale?
        logger.info('cache') { "Force expiring #{@key}, age #{age}."}
        @value = nil 
      end

      if start && is_chart? && start > 0
        @value.select {|x| x['date'] >= start }
      else
        @value.clone
      end
    end
  end

  def age
    Time.now.to_i - @timestamp
  end

  def time_left
    @timestamp + ttl - Time.now.to_i
  end

  def stale?
    (age > ttl)
  end

  def super_stale?
    (age > config.global_expiry)
  end


  def includes_time?(start)
    return true unless is_chart?
    return false unless @value

    oldest_start = @value.first['date']
    oldest_start <= start
  end

  def is_chart?
    @key.include?(':')
  end

  def loaded?
    (@timestamp > 0)
  end

  def to_json(options)
    {
      ttl: @ttl,
      timestamp: @timestamp,
      values: @value    
    }.to_json
  end


end