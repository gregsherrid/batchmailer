require 'net/smtp'
require 'json'
require 'csv'

def main
	template = load_template
	config = get_config
	mailing_list = load_mailing_list(config)

	mailing_list.each do |member|
		message = compose_message(member, template, config)
		send_message(member, message, config)
	end
end

def compose_message(member, template, config)
	subject = template.match(/#{ BEGIN_SUBJECT }.*#{ END_SUBJECT }/m)
	if subject.nil? || subject.length != 1
		puts "Template should have one SUBJECT"
		exit
	end
	subject = subject[0].gsub(BEGIN_SUBJECT, "").gsub(END_SUBJECT, "").strip

	body = template.match(/#{ BEGIN_BODY }.*#{ END_BODY }/m)
	if body.nil? || body.length != 1
		puts "Template should have one BODY"
		exit
	end
	body = body[0].gsub(BEGIN_BODY, "").gsub(END_BODY, "").strip

	custom_values = config.merge(member)

	subject = replace_tags(subject, custom_values)
	body = replace_tags(body, custom_values)

	from = "#{ config['sender_first_name'] } #{ config['sender_last_name'] }"
	from << " <#{ config['sender_display_email'] }>"

	to = member['email']
	
	message = "From: #{ from }\nTo: #{ to }\nSubject: #{ subject }\n#{ body }"
	message
end

def send_message(member, message, config)
	smtp = Net::SMTP.new 'smtp.gmail.com', 587
	smtp.enable_starttls

	password = config["sender_password"] ||= get_input("Enter password (won't be saved): ")

	smtp.start('gmail.com', config["sender_email"], password, :login)
	smtp.send_message(message, config["sender_display_email"], member["email"])
	smtp.finish
end

def replace_tags(text, custom_values)
	custom_values.each_pair do |key, value|
		replace_key = "{{#{ key }}}"
		text = text.gsub(replace_key, value)
	end
	text
end

# Config should be passed to form fallback test
def load_mailing_list(config)
	list_file = ARGV[1]
	if list_file && File.exist?(list_file)
		CSV.read(list_file, headers: true)
	else
		# Load test data
		[{
			"first_name" => config["sender_first_name"] + '[test]',
			"last_name" => config["sender_last_name"] + '[test]',
			"email" => config["sender_email"].gsub("@","+test@")
		}]
	end
end

def load_template
	template_file = ARGV[0]

	if template_file.nil? || !File.exist?(template_file)
		puts "Please provide a template file. Valid command format:"
		puts ">> ruby main.rb ./templates/sample.txt ./lists/sample.csv"
		puts ""
		puts "(2nd argument, the list, is optional. If empty, a test email will send)"
		exit
	end

	File.read(template_file)
end

def get_config
	if File.exist?(CONFIG_PATH)
		if get_input("Use existing config y/n: ").downcase == "y"
			return parse_config_file
		end
	end

	config = {}

	config["sender_first_name"] = get_input("Sender first name: ")
	config["sender_last_name"] = get_input("Sender last name: ")
	config["sender_email"] = get_input("Sender email account: ")

	config["store_password"] = get_input("Save password (y/n): ").downcase
	if config["store_password"] == "y"
		config["sender_password"] = get_input("Password: ")
	end

	config["alternate_display_email"] = get_input("Use alternate display email (y/n): ").downcase
	if config["alternate_display_email"] == "y"
		config["sender_display_email"] = get_input("Alternate display email: ")
	else
		config["sender_display_email"] = config["sender_email"]
	end

	File.open(CONFIG_PATH, "w") do |file|
		file.puts config.to_json
	end
	return parse_config_file
end

def parse_config_file
	JSON.parse(File.read(CONFIG_PATH))
end

def get_input(query)
	print query
	STDIN.gets.chomp.strip
end

CONFIG_PATH = "./config.txt"

# Template flags
BEGIN_SUBJECT = "{---BEGIN_SUBJECT---}"
END_SUBJECT   = "{---END_SUBJECT---}"
BEGIN_BODY    = "{---BEGIN_BODY---}"
END_BODY      = "{---END_BODY---}"

main