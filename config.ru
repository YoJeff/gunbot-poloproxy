require 'rubygems'
require 'bundler'

Bundler.require

require_relative 'lib/polo_proxy'

require './app'
PoloProxy.start!
run App.freeze.app