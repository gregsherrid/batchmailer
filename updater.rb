require 'open-uri'

def main
	FILES_TO_UPDATE.each do |relative_path|
		puts "Updating #{ relative_path }..."
		url = "#{ BASE }/#{ relative_path }"
		contents = open(url).read

		File.open(relative_path, "w") do |file|
			file.puts contents
		end
	end
end

BASE = "https://raw.githubusercontent.com/gregsherrid/batchmailer/master"

# I hope its ok to update the source code of a file that's currently running...
FILES_TO_UPDATE = ["README.md", "main.rb", "updater.rb", "Gemfile", "Gemfile.lock"]

main
