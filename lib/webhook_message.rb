require "httparty"

class WebhookMessage
	attr_accessor :endpoint_route, :webhook_token

	# endpoint_route of format: 
	# => http://api.site.domain.com/user_id
	# webhook_token:
	# => sent to server (as top level param) to verify request
	def initialize(endpoint_route, webhook_token)
		if !endpoint_route.include?(USER_ID_KEY)
			raise "WebhookMessage Error: #{ USER_ID_KEY } not in enpoint path"
		end
		self.endpoint_route = endpoint_route
		self.webhook_token = webhook_token
	end

	# user_id
	# message_content: should be hash sent to server as top level params. Suggested keys:
	# => title
	# => text
	# => days_until_expire
	def send_message(user_id, message_content)
		full_route = self.endpoint_route.gsub(USER_ID_KEY, user_id)

		data = message_content.clone
		data["token"] = self.webhook_token
		query = self.get_query(data)

		url = "#{ full_route }?#{ query }"

		puts url

		response = HTTParty.get(url, body: data.to_json, headers: JSON_HEADERS)
		puts response
		if response.code < 200 || response.code >= 300
			raise "Error\nWebook HTTP Status: #{ response['code'] }. #{ response['message'] }"
		end
	end

	def get_query(hash)
		query = hash.map do |k,v|
			"#{ k }=#{ v }"
		end.join("&")
		URI.encode(query)
	end

	USER_ID_KEY = ":user_id"

	JSON_HEADERS = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

end