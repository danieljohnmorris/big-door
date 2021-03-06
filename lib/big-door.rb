require 'rubygems'
require 'httparty'
require 'json'
require 'uri'
require 'cgi'
require 'uuidtools'

module BigDoor
	BASE_URL = 'http://api.bigdoor.com'.freeze
	BASE_URI = 'api/publisher'.freeze
	
	class BigDoorError < StandardError; end
	
	module ClassMethods
		def self.included(base)
			base.extend ClassMethods
		end
		
		def remote_id
		    @id || nil
		end

		def self.app_key
			@app_key
		end
		
		def self.secret_key
			@secret_key
		end
		
		def parse_out_classes(content)
			output = []
			unless content.is_a? Array
				content = Array[content]
			end
			content.each do |result|
				begin
					output << case result["resource_name"]
						when 'end_user'
							User.new(result)
						when 'currency'
							Currency.new(result)
						when 'named_transaction'
						  NamedTransaction.new(result)
						when 'named_transaction_group'
							NamedTransactionGroup.new(result)
						when 'named_level'
						  NamedLevel.new(result)
						when 'named_level_collection'
						  NamedLevelCollection.new(result)
						when 'named_award'
						  NamedAward.new(result)
						when 'named_award_collection'
						  NamedAwardCollection.new(result)
						else
							result
					end
				rescue
					debugger
				end
			end
			
			output.length == 1 ? output.first : output
		end

		def perform_request(*args)
			request_type, action, args, envelope = args
			envelope = {} unless envelope

			raise BigDoorError, "Unknown request type" unless ['get', 'post', 'put', 'delete'].include? request_type

			query = args
			params = {}
			query = {} if (query.is_a? Array and query.empty?) or query.nil?
			
			action << '/' + query.delete(:id).to_s if query.has_key? :id

			if request_type == 'delete'
				query = {:delete_token => SecureRandom.hex}
			elsif ['post', 'put'].include?(request_type)
				params[:body] = query
				params[:body][:time] = "%.2f" % Time.now.to_f
				params[:body][:token] = SecureRandom.hex
				query = {}
				
				envelope.each_pair do |key, value|
				  params[:body][key] = value
				end
			end
			params.keys.sort!

			path = [BASE_URI, ClassMethods.app_key, action].join('/')
			params[:query] = query
			params[:query][:time] = params[:body][:time] rescue "%.2f" % Time.now.to_f
			params[:query][:sig] = calculate_sha2_hash(path, params)
			params[:query][:format] = 'json'
			url = [BASE_URL, path].join('/')
			
			p request_type
			p url
			p params
			
			parse_response(BigDoor::Request.send(request_type, url, params))
		end

		private
			def parse_response(response)
				if response.response.class.ancestors.include? Net::HTTPClientError
					raise BigDoorError, "#{response.response.code} #{response.response.message} - #{response.headers['bdm-reason-phrase'].to_s}"
				end
				
				if response.parsed_response.is_a? Numeric
					response_code = BigDoor::ResponseCodes.find response.parsed_response
					if response_code[:is_error]
						raise BigDoorError, "#{response_code[:code]} #{response_code[:response_condition]} - #{response_code[:reason_phrase]}"
					else
						return true
					end
				elsif response.parsed_response.first.is_a? Array
					content = response.parsed_response.first
				else
					content = ([] << response.parsed_response.first)
				end
				parse_out_classes(content)
			end
			
			def calculate_sha2_hash(path, query)
				path = '/' + path
				Digest::SHA2.new(bitlen = 256).update(path + concat_query(query[:query]) + concat_query(query[:body]) + ClassMethods.secret_key).to_s
			end
			
			def concat_query(query)
				str = ''
				unless query.nil?
					query.keys.map(&:to_s).sort.each do |key|
						str << key.to_s + query[key.to_sym].to_s unless [:sig, :format].include?(key)
					end
				end
				str
			end
			
			def to_url_params(hash)
				elements = []
				hash.each_pair do |key, val|
					elements << "#{CGI::escape(key.to_s)}=#{CGI::escape(val.to_s)}"
				end
				elements.join('&')
			end
	end
end

directory = File.expand_path(File.dirname(__FILE__))
Dir[File.join(directory, "big-door", "*.rb").to_s].each {|file| require file }
