module FbGraph
  class Node
    include Comparison

    attr_accessor :identifier, :endpoint, :access_token

    def initialize(identifier, options = {})
      @identifier   = identifier
      @endpoint     = File.join(ROOT_URL, identifier.to_s)
      @access_token = options[:access_token]
    end

    def fetch(options = {})
      options[:access_token] ||= self.access_token if self.access_token
      _fetched_ = get(options)
      self.class.new(_fetched_.delete(:id), _fetched_.merge(:access_token => options[:access_token]))
    end

    def self.fetch(identifier, options = {})
      new(identifier).fetch(options)
    end

    def connection(connection, options = {})
      collection = options[:cached_collection] || Collection.new(get(options.merge(:connection => connection)))
      Connection.new(self, connection, options.merge(:collection => collection))
    end

    def update(options = {})
      post(options)
    end

    def destroy(options = {})
      delete(options)
    end

    protected

    def get(params = {})
      _params_ = stringfy_params(params)
      _endpoint_ = build_endpoint(_params_.merge!(:method => :get))
      handle_response do
        RestClient.get(_endpoint_)
      end
    end

    def post(params = {})
      _params_ = stringfy_params(params)
      _endpoint_ = build_endpoint(_params_.merge!(:method => :post))
      handle_response do
        RestClient.post(_endpoint_, _params_)
      end
    end

    def delete(params = {})
      _params_ = stringfy_params(params)
      _endpoint_ = build_endpoint(_params_.merge!(:method => :delete))
      handle_response do
        RestClient.delete(_endpoint_)
      end
    end

    private

    def build_endpoint(params = {})
      _endpoint_ = File.join([self.endpoint, params.delete(:connection), params.delete(:connection_scope)].compact.collect(&:to_s))
      params.delete_if do |k, v|
        v.blank?
      end
      if [:get, :delete].include?(params.delete(:method)) && params.present?
        _endpoint_ << "?#{params.to_query}"
      end
      _endpoint_
    end

    def stringfy_params(params)
      _params_ = params.dup
      _params_[:access_token] ||= self.access_token
      if _params_[:access_token].is_a?(Rack::OAuth2::AccessToken::Legacy)
        _params_[:access_token] = _params_[:access_token].access_token
      end
      _params_.each do |key, value|
        if value.present? && ![Symbol, String, Numeric, IO].any? { |klass| value.is_a? klass }
          _params_[key] = value.to_json
        end
      end
      _params_
    end

    def handle_response
      response = yield
      case response.body
      when 'true'
        true
      when 'false'
        # NOTE: When the object is not found, Graph API returns
        #  - error response (JSON) when the identifier contains alphabet (ex. graph.facebook.com/iamnotfound)
        #  - false when the identifier is only integer + underbar (ex. graph.facebook.com/1234567890, graph.facebook.com/12345_67890)
        # This is an undocumented behaviour, so facebook might chaange it without any announcement.
        # I've posted this issue on their forum, so hopefully I'll get a document about Graph API error responses.
        # ref) http://forum.developers.facebook.com/viewtopic.php?pid=228256#p228256
        raise NotFound.new('Graph API returned false, so probably it means your requested object is not found.')
      when 'null'
        nil
      else
        _response_ = JSON.parse(response.body)
        case _response_
        when Array
          _response_.map!(&:with_indifferent_access)
        when Hash
          _response_.with_indifferent_access
        end
      end
    rescue RestClient::Exception => e
      handle_restclient_error(e)
    end

    def handle_restclient_error(e)
      _response_ = JSON.parse(e.http_body).with_indifferent_access
      case _response_[:error][:type]
      when /OAuth/
        raise Unauthorized.new(e.message, e.http_body)
      else
        raise BadRequest.new(e.message, e.http_body)
      end
    rescue JSON::ParserError
      raise Exception.new(e.http_code, e.message, e.http_body)
    end
  end
end