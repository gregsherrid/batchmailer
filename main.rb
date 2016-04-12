require 'net/smtp'
require 'rubygems'
require 'json'
require 'csv'

def main
	config = get_config

	template = load_template
	mailing_list = load_mailing_list(config)

	mailing_list.each do |member|
		puts "Sending #{ member["email"] }..."
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
	subject = subject[0].gsub(/#{ BEGIN_SUBJECT }/, "").gsub(/#{ END_SUBJECT }/, "").strip

	body = template.match(/#{ BEGIN_BODY }.*#{ END_BODY }/m)
	if body.nil? || body.length != 1
		puts "Template should have one BODY"
		exit
	end
	body = body[0].gsub(/#{BEGIN_BODY}/, "").gsub(/#{ END_BODY }/, "").strip

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
	smtp = Net::SMTP.new('smtp.gmail.com', 587)
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
		parse_csv(list_file)

	elsif get_input("Test send to #{ config['sender_email'] } (y/n): ").downcase != "y"
		get_input("Pick list .csv file (press enter): ")
		list_file = open_file_picker("Pick Template File")
		parse_csv(list_file)
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
		get_input("Pick template .txt file (press enter): ")
		template_file = open_file_picker("Pick List File")
	end
	puts File.exist?(template_file)
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

	config["use_bcc"] = get_input("Add BCC address (y/n): ").downcase
	if config["use_bcc"] == "y"
		config["bcc_email"] = get_input("BCC address: ")
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

def open_file_picker(title)
	if RUBY_PLATFORM.include?("linux")
		`zenity --title=#{ title } --file-selection`.strip
	else

	end
end

def parse_csv(file)
	rows = []
	CSV.open(file, "r") do |row|
		rows << row
	end
	header = rows.shift

	rows.map do |row|
		i = 0
		row_hash = {}
		header.each do |h|
			row_hash[h] = row[i]
			i += 1
		end
		row_hash
	end
end

CONFIG_PATH = "./config.txt"

# Template flags
BEGIN_SUBJECT = "\\{---BEGIN_SUBJECT---\\}"
END_SUBJECT   = "\\{---END_SUBJECT---\\}"
BEGIN_BODY    = "\\{---BEGIN_BODY---\\}"
END_BODY      = "\\{---END_BODY---\\}"

main