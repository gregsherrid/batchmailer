require "net/smtp"

class SMTPConnection
	def initialize(sender_email, password = nil)
		@sender_email = sender_email
		@password = password
		@send_count = 0
		@connection = nil
	end

	def send_message(message, from, to, bcc = nil)
		if (@send_count != 0) && ((@send_count % 75) == 0)
			self.rest_and_restart_connection
		end
		@send_count += 1

		if @connection.nil?
			self.init_connection
		end

		if bcc.nil? || bcc.length == 0
			@connection.send_message(message, from, to)
		else
			@connection.send_message(message, from, to, bcc)
		end
	end

	def init_connection
		@connection = Net::SMTP.new("smtp.gmail.com", 587)
		@connection.enable_starttls

		self.get_password_from_user_input if @password.nil?
		@connection.start("gmail.com", @sender_email, @password, :login)
	end

	def close
		@connection.finish if @connection
		@connection = nil
	end

	def rest_and_restart_connection
		self.close
		sleep(PAUSE_LENGTH)
		self.init_connection
	end

	def get_password_from_user_input
		print "Enter password (won't be saved): "
		@password = STDIN.gets.chomp.strip
	end

end

PAUSE_COUNT = 75 # number of emails
PAUSE_LENGTH = 300 # seconds