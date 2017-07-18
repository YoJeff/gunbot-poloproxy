require 'listen'
require 'singleton'
require 'yaml'
require 'benchmark'

require_relative 'polo_logger'
require_relative 'polo_config'
require_relative 'polo_cache'
require_relative 'polo_relay'
require_relative 'polo_data'

class PoloProxy
  @start_time = Time.now

  def self.logger;     PoloLogger.logger; end
  def self.uptime;     Time.now - @start_time; end
  def self.cache;      PoloCache; end
  def self.config;     PoloConfig; end
  def self.relay;      PoloRelay; end
  def self.data;       PoloData; end
  def self.start_time; @start_time; end

  def self.start!
    config.start!
  end

end