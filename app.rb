 class App < Roda
  #plugin :json
  plugin :render
  plugin :partials

  route do |r|
    @proxy =PoloProxy


    r.get 'public' do
      response['Content-Type'] = 'application/json'
      result = @proxy.relay.process_public(r.params)
      if result
        result.to_json
      else
        # PoloLogger.logger.warn('app') { "NIL Result #{r.params} #{result.to_json}" }
        nil
      end
    end

    r.post 'tradingApi' do
      response['Content-Type'] = 'application/json'
      result = @proxy.relay.process_private(r.params)
      if result
        result.to_json
      else
        # PoloLogger.logger.warn('app') { "NIL Result #{r.params} #{result.to_json}" }
        nil
      end
    end

    r.get 'stats' do
      @cache = @proxy.cache
      view('stats')
    end

  end
end
