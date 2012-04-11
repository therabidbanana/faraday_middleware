require 'test/unit'
require 'forwardable'
require 'fileutils'
require 'rack/cache'
require 'faraday'
require 'sinatra/base'
require 'faraday_middleware/response/caching'
require 'faraday_middleware/rack_compatible'
require 'faraday_middleware/response/parse_json'

class CacheTestJson < Sinatra::Base
  set :my_counter, 0
  use Rack::Cache
  before do
    content_type :json
  end
  helpers do
    def counter_up
      settings.my_counter += 1
    end
    def counter
      settings.my_counter
    end
  end
  get '/*' do
    expires 2
    counter_up
    %({"message": "request:#{counter}"})
  end
  post '/*' do
    expires 2
    counter_up
    %({"message": "request:#{counter}"})
  end

end

# RackCompatible + Rack::Cache + FaradayMiddleware::ParseJson
class HttpJsonCachingTest < Test::Unit::TestCase
  include FileUtils

  CACHE_DIR = File.expand_path('../cache', __FILE__)

  def teardown
    Process.kill "KILL", @pid
    Process.waitpid(@pid)
  end
  def setup
    @pid = fork {
      CacheTestJson.run!
    }

    rm_r CACHE_DIR if File.exists? CACHE_DIR
    sleep 2

    @conn = Faraday.new(:url => "http://localhost:4567") do |b|
      b.use FaradayMiddleware::ParseJson
      b.use FaradayMiddleware::RackCompatible, Rack::Cache::Context,
        :metastore   => "file:#{CACHE_DIR}/rack/meta",
        :entitystore => "file:#{CACHE_DIR}/rack/body",
        :ignore_headers => ['X-Content-Digest'],
        :verbose     => true

      b.adapter :net_http
    end
  end

  extend Forwardable
  def_delegators :@conn, :get, :post

  def test_cache_get
    response = get('/', :user_agent => 'test')
    assert_equal({"message" => "request:1"}, response.body)
    assert_equal :get, response.env[:method]
    assert_equal 200, response.status

    response = get('/', :user_agent => 'test')
    assert_equal({"message" => "request:1"}, response.body)
    assert_equal 'application/json;charset=utf-8', response['content-type']
    assert_equal :get, response.env[:method]
    assert response.env[:request].respond_to?(:fetch)
    assert_equal 200, response.status

    sleep 3
    response = get('/', :user_agent => 'test')
    assert_equal({"message" => "request:2"}, response.body)
    assert_equal 'application/json;charset=utf-8', response['content-type']
    assert_equal :get, response.env[:method]
    assert response.env[:request].respond_to?(:fetch)
    assert_equal 200, response.status

    assert_equal({"message" => "request:3"}, post('/').body)
  end

  def test_doesnt_cache_post
    assert_equal({"message" => "request:1"}, get('/').body)
    assert_equal({"message" => "request:2"}, post('/').body)
    assert_equal({"message" => "request:3"}, post('/').body)
  end
end unless defined? RUBY_ENGINE and "rbx" == RUBY_ENGINE  # rbx bug #1522

