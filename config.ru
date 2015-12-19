require './backend_app'
use Rack::Deflater
run BackendApp.new
