# Gunbot PoloProxy

### **Warning** ###

This is an open proxy (Poloniex only).   It only currently works on BTC_* pairs.

## Features ##

* Greatly improves the efficiency of gunbot
* Eliminates 422 errors from poloniex
* configurable caching
* Global and pair-level buy mode overrides
* Double buy protection
* Hot reload config
* Stats


## Requirements ##

* Ruby (Tested on 2.4.1)
* Bundler
* A terminating SSL proxy in front (such as haproxy)
* Poloniex account

#### Running Gunbot Proxy ####

1. clone repo
2. run `bundle install` to install dependencies
3. copy `config.yml.example` to `config.yml` and edit accordingly
4. start gunbot proxy via `puma -t 30 -b tcp://0.0.0.0:5000`
5. setup your ssl proxy to listen on port 443, and relay to port 5000
6. setup gunbot to allow the ssl proxy's certificate ( `NODE_TLS_REJECT_UNAUTHORIZED=0` )
7. edit your `/etc/hosts` to redirect poloniex.com to 127.0.0.1
5. stats are available via `http://<proxy>:5000/stats`

*notes*

This is designed for gunbot.   It  intercepts and changes api calls per the below table.   It may or may not work for non-gunbot purposes.   Web stats assume all-in, all-out for performance stats.

You can change the number of threads puma uses via the `-t` option.   I would set haproxy's `maxconn` to threads - 1 for starters.


##### Caching #####
Request|Cache Type
---|---
chartdata | Request is altered to include at least `periods` as defined in config.    Chartdata is cached via TTL as defined in config.   Chartdata always is from `min(periods,request)` to `Time.now`
balances | served from cache
open orders | served from cache
trade history | served from cache
buys|depends on buy mode
sells|relayed exactly
other private methods|relayed exactly

##### Buy Modes #####
Mode|Description
---|---
passthrough|relay everything, untouched
blocked|all buys will be blocked
normal|block buys if attempted again before `timeout` -or- if we have a balance -or- if we have an open order


##### Polo Keys #####
The proxy makes a maximum of 1 request per key at a time.   The maximum number of simultaneous private requests == the number of keys supplied.   Polling uses up to 3 no matter how many pairs. 3 is a good baseline.

