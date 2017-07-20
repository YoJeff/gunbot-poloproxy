  # frozen_string_literal: true
require 'rufus-scheduler'
require_relative 'polo_cache_item'

class PoloCache
  @cache = {}
  @mutexes = {}
  @hit = 0
  @miss = 0

  def self.stats(clear=false)
    pct = Float(@hit)/Float(@hit + @miss) * 100
    result = [@hit,@miss,pct]
    @hit = @miss = 0 if clear
    result
  end

  def self.config
    PoloConfig
  end

  def self.parse_params(params)
    results = {}
    command = params['command']
    period = params['period'].to_i
    pair = params['currencyPair']
    start = params['start'].to_i
    ttl = config.ttl(command)
    if command == 'returnChartData'
      key = [pair,period].join(':')
    elsif command == 'buy'
      key = [command,pair].join('$')
    else
      key = command
    end
    [key,ttl,start]
  end

  def self.cache(params,force=false)
    key,ttl,start = parse_params(params)
    @cache[key] ||= PoloCacheItem.new(key)

    mut(key).synchronize do
      data = @cache[key]

      if block_given?
        if data.stale? || !data.includes_time?(start) || force
          @miss += 1 unless force
          yield.tap { |value| data.set(value, ttl) }
        else
          @hit += 1
        end
      end
      data.get(start)
    end
  end

  def self.cache_valid?(params)
    key = parse_params(params).first
    result = false
    !@cache[key].stale? if @cache[key]
  end

  def self.mut(key)
    @mutexes[key] ||= Mutex.new
  end

  # def self.read(key,hit=false)
  #   @hit += 1 if hit
  #   @cache[key]
  # end

  def self.loaded?(key)
    @cache[key] && @cache[key].loaded?
  end

  def self.get(key)
    result = nil
    c = @cache[key]
    if c
      if c.super_stale?
        delete(key)
      else
        @hit += 1
        result = c.get
      end
    end
    result
  end

  def self.get_with_metrics(key)
    [get(key),metrics(key)]
  end


  def self.metrics(key)
    c = @cache[key]
    return {} unless c
    {
      ttl: c.ttl,
      age: c.age,
      time_left: c.time_left,
      stale: c.stale?,
    }

  end

  def self.delete(key)
    @cache.delete(key)
    true
  end

  def self.keys
    @cache.keys
  end

  def self.whole_cache
    @cache
  end
end