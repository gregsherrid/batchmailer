require "rubygems"
require "json"
require "csv"
require "redcarpet"
require "redcarpet/render_strip"

require "./lib/webhook_message"
require "./lib/smtp_connection"

def main
	config = get_config

	template = load_template
	mailing_list = load_mailing_list(config)

	from = config["sender_display_email"]
	bcc = config["bcc_email"] 

	smtp_connection = SMTPConnection.new(config["sender_email"], config["sender_password"])
	webhook = WebhookMessage.new(config["default_webhook_route"], config["default_webhook_token"])

	mailing_list.each_with_index do |member, index|

		if ((!member["email"].to_s.empty?) || (!member["user_id"].to_s.empty?))
			id_line = [member["user_id"], member["email"]].compact.join("/")
			puts "Sending #{ id_line }..."
			message_data = compose_message(member, template, config)

			type = message_data[:type]
			message = message_data[:message]

			if type == WEBHOOK
				webhook.send_message(member["user_id"], JSON.parse(message))
			else
				smtp_connection.send_message(message, from, member["email"], bcc)
			end
		end
	end

	smtp_connection.close
end

def compose_message(member, template, config)
	custom_values = config.merge(member)

	if template.include?("{---MARKDOWN---}")
		type = MARKDOWN_EMAIL
	elsif template.include?("{---WEBHOOK---}")
		type = WEBHOOK
	else
		type = PLAINTEXT_EMAIL
	end

	body = template.match(/#{ BEGIN_BODY }.*#{ END_BODY }/m)
	if body.nil? || body.length != 1
		puts "Template should have one BODY"
		exit
	end
	body = body[0].gsub(/#{BEGIN_BODY}/, "").gsub(/#{ END_BODY }/, "").strip
	body = replace_tags(body, custom_values)

	if type != WEBHOOK
		subject = template.match(/#{ BEGIN_SUBJECT }.*#{ END_SUBJECT }/m)
		if subject.nil? || subject.length != 1
			puts "Template should have one SUBJECT"
			exit
		end
		subject = subject[0].gsub(/#{ BEGIN_SUBJECT }/, "").gsub(/#{ END_SUBJECT }/, "").strip
		subject = replace_tags(subject, custom_values)

		from = "#{ config['sender_first_name'] } #{ config['sender_last_name'] }"
		from << " <#{ config['sender_display_email'] }>"
		to = member['email']
	end


	if type == MARKDOWN_EMAIL
		message = format_markdown_message(from, to, subject, body)

	elsif type == WEBHOOK
		message = body

	elsif type == PLAINTEXT_EMAIL
		message = format_plain_text_message(from, to, subject, body)

	else
		raise "Unknown Type: #{ type }"
	end

	{ type: type, message: message }
end

def format_plain_text_message(from, to, subject, body)
	message = "From: #{ from }\nTo: #{ to }\nSubject: #{ subject }\n#{ body }"
	message
end

def format_markdown_message(from, to, subject, body)
	renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
	html_markdown = Redcarpet::Markdown.new(renderer, extensions = {})
	html_body = html_markdown.render(body)
	html_body = "<html><body>#{ html_body }</body></html>"

	plain_markdown = Redcarpet::Markdown.new(Redcarpet::Render::StripDown)
	plain_body = plain_markdown.render(body)
	
	message = "MIME-Version: 1.0"
	message << "\nFrom: #{ from }\nTo: #{ to }\nSubject: #{ subject }"
	message << "\nContent-Type: multipart/alternative; boundary=\"2012squid\""
	message << "\n--2012squid\nContent-Type: text/plain; charset=\"UTF-8\""
	message << "\n\n" + plain_body
	message << "\n--2012squid\nContent-Type: text/html; charset=\"UTF-8\""
	message << "\n\n" + html_body
	message << "\n--2012squid--"
	message
end

def replace_tags(text, custom_values)
	custom_values.each_pair do |key, value|
		replace_key = "{{#{ key }}}"
		text = text.gsub(replace_key, value)
	end
	if text.include?("{{") && text.include?("}}")
		puts "Template contains a merge tag {{like_this}} that wasn't in the mailing list."
		exit
	end
	text
end

# Config should be passed to form fallback test
def load_mailing_list(config)
	list_file = ARGV[1]
	if list_file && File.exist?(list_file)
		parse_csv(list_file)

	elsif get_input("Test send (y/n): ").downcase != "y"
		get_input("Pick mailing list .csv file (just press enter): ")
		list_file = open_file_picker("Pick List File")
		parse_csv(list_file)
	else
		# Load test data
		[{
			"first_name" => config["sender_first_name"] + '[test]',
			"last_name" => config["sender_last_name"] + '[test]',
			"user_id" => config["test_webhook_user_id"],
			"email" => config["sender_email"].gsub("@","+test@")
		}]
	end
end

def load_template
	template_file = ARGV[0]

	if template_file.nil? || !File.exist?(template_file)
		get_input("Pick template .txt file (just press enter): ")
		template_file = open_file_picker("Pick Template File")
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

	config["use_bcc"] = get_input("Add BCC address (y/n): ").downcase
	if config["use_bcc"] == "y"
		config["bcc_email"] = get_input("BCC address: ")
	end

	config["default_webhook_route"] = get_input("Default webhook endpoint (or leave blank): ")
	config["default_webhook_token"] = get_input("Default webhook token (or leave blank): ")
	config["test_webhook_user_id"] = get_input("Test webhook user ID (or leave blank): ")

	File.open(CONFIG_PATH, "w") do |file|
		file.puts JSON.pretty_generate(config)
	end
	return parse_config_file
end

def parse_config_file
	JSON.parse(File.read(CONFIG_PATH))
end

def open_file_picker(title)
	if RUBY_PLATFORM.include?("linux")
		`zenity --title=#{ title } --file-selection`.strip
	elsif File.exist?(COCOA_DIALOG_PATH)
		`#{ COCOA_DIALOG_PATH } fileselect --title=#{ title }`.strip
	else
		puts "NOTICE: If you are using MacOS, consider installing CocoaDialog."
		get_input("Please enter the file path for: '#{ title }': ")
	end
end

def get_input(prompt)
	print prompt
	@password = STDIN.gets.chomp.strip
end

def parse_csv(file)
	rows = []
	CSV.foreach(file, headers: true) do |row|
		rows << row.to_h
	end

	rows
end

# From when we couldn't have the "CSV" gem
def parse_csv_legacy(file)
	rows = []
	lines = File.read(file).split("\n").map(&:strip).reject { |l| l.empty? }
	rows = lines.map { |r| r.split(",").map(&:strip) }

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

PLAINTEXT_EMAIL = "plaintext_email"
MARKDOWN_EMAIL = "markdown_email"
WEBHOOK = "webhook"

COCOA_DIALOG_PATH = "/Applications/CocoaDialog.app/Contents/MacOS/CocoaDialog"
CONFIG_PATH = "./config.json"

# Template flags
BEGIN_SUBJECT = "\\{---BEGIN_SUBJECT---\\}"
END_SUBJECT   = "\\{---END_SUBJECT---\\}"
BEGIN_BODY    = "\\{---BEGIN_BODY---\\}"
END_BODY      = "\\{---END_BODY---\\}"

main
