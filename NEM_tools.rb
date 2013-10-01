regLib("json")
regLib("cgi")
regLib("open-uri")

def getVersions()
	begin
		nemfeed = open("http://bot.notenoughmods.com/?json", "User-Agent" => "Rubybot/4.3 (+http://umby.d3s.co/)")
		result = nemfeed.read
		nemfeed.close()
		parsed = JSON.parse(result)
		return parsed
	rescue Exception => e
		puts "Failed to get NEM versions, falling back to hard-coded"
		err_log("NEMP: " + e.message)
		return ["1.4.5","1.4.6-1.4.7","1.5.1","1.5.2","1.6.1","1.6.2", "1.6.4"]
	end
end
def command_nem()
	case $args[1]
		when "list"
			list()
		when "multilist"
			multilist()
		when "about"
			about()
		when "setlist"
			setlist()
	end
end
def list()
	if $args.length < 3
		sendmessage($host[0,$host.index("!")] + ": Insufficent ammount of parameters provided.")
		sendmessage($host[0,$host.index("!")] + ": see #{$prefix}help nem for usage.")
		return
	end
	if $args.length >= 4
		version = $args[3]
	else
		version = $nemVersion
	end
	begin
		nemfeed = open("http://bot.notenoughmods.com/" + CGI.escape(version) + ".json", "User-Agent" => "Rubybot/4.3 (+http://umby.d3s.co/)")
		result = nemfeed.read
		nemfeed.close()
		jsonres = JSON.parse(result)
		results = []
		
		jsonres.each_index {|index|
			mod = jsonres[index]
			if mod["name"].downcase.include?($args[2].downcase)
				results += [index]
				next
			else
				aliases = mod["aliases"].split(" ")
				aliases.each {|a|
					if a.downcase.include?($args[2].downcase)
						results += [index]
					end
				}
			end
			
		}
		darkgreen = "03"
		red = "05"
		purple = "06"
		pink = "13"
		orange = "7"
		blue = "12"
		gray = "14"
		bold = 2.chr
		color = 3.chr
		count = results.length
		
		if count == 0
			sendmessage($host[0,$host.index("!")] + ": no results found.")
			return
		elsif count == 1
			count = "#{count} result"
		else
			count = "#{count} results"
		end
		
		sendmessage("Listing " + count + " for \"" + $args[2] + "\" in " +bold+color+blue+version+color+bold+":")
		
		results.each {|item|
			jstring = jsonres[item]
			talias = color
			
			if jstring["aliases"] != ""
				talias = color + "(" + color + pink + jstring["aliases"].gsub(" ", color + ", " + color + pink) + color + ") "
			end
			
			comment = color
			
			if jstring["comment"] != ""
				comment = color + "(" + color + gray + jstring["comment"] + color + ") "
			end
			dev = color
			begin
				dev = color + " (" + color + gray + "dev" + color + ": " + color + red + jsonres["dev"] + color + ")"
			rescue Exception => e
				
			end
			sendmessage(color + purple + jstring["name"] + " " + talias + color + darkgreen + jstring["version"] + dev + " " + comment + color + orange + jstring["shorturl"] + color)
		}
		
	rescue Exception => e
		sendmessage($host[0,$host.index("!")] + ": #{e.message}")
		puts e.backtrace
	end
end
def multilist()
	if $args.length != 3
		sendmessage($host[0, $host.index("!")] + ": Insufficent ammount of parameters provided.")
		sendmessage($host[0, $host.index("!")] + ": see #{$prefix}help nem for usage.")
		return
	end
	begin
		jsonres = Hash.new
		results = Hash.new
		versions = $nemVersions
		
		versions.each {|item|
			nemfeed = open("http://bot.notenoughmods.com/" + CGI.escape(item) + ".json", "User-Agent" => "Rubybot/4.3 (+http://umby.d3s.co/)")
			result = nemfeed.read()
			nemfeed.close()
			jsonres[item] = JSON.parse(result)
			
			jsonres[item].each_index {|index|
				mod = jsonres[item][index]
				if mod["name"] == $args[2].downcase
					results[item] = [index]
					break
				else
					aliases = mod["aliases"].split(" ")
					aliases.each {|alia|
						if alia.downcase == $args[2].downcase
							results[item] = [index]
							break
						end
					}
				end
			}			
		}
		
		pink = "13"
		red = "05"
		darkgreen = "03"
		purple = "06"
		orange = "07"
		blue = "12"
		gray = "14"
		lightgray = "15"
		bold = 2.chr
		color = 3.chr
		count = results.length
		
		if count == 0
			sendmessage($host[0, $host.index("!")] + ": mod not present in NEM.")
			return
		elsif count == 1
			count = count.to_s + " MC version"
		else
			count = count.to_s + " MC versions"
		end
		
		sendmessage("Listing " + count + " for \"" + $args[2] + "\":")
		
		results.each_key {|line|
			talias = color
			if jsonres[line][results[line][0]]["aliases"] != ""
				talias = color + "(" + color + pink + jsonres[line][results[line][0]]["aliases"].gsub(" ", color + ", " + color + pink) + color + ") "
			end
			comment = color
			if jsonres[line][results[line][0]]["comment"] != ""
				comment = color+"["+color+gray+jsonres[line][results[line][0]]["comment"]+color+"] "
			end
			dev = color
			begin
				if jsonres[line][results[line][0]]["dev"] != ""
					dev = color+"("+color+gray+"dev: "+ color + red + jsonres[line][results[line][0]]["dev"]+color+")"
				end
			rescue Exception => e
				# Not going to add an err_log statement here to keep spam out of it.
			end
			sendmessage(bold +color+blue+line+color+bold + ": "+color+purple+jsonres[line][results[line][0]]["name"]+" "+talias+color+darkgreen+jsonres[line][results[line][0]]["version"]+dev+" "+comment+color+orange+jsonres[line][results[line][0]]["shorturl"]+color)
		}
		
	rescue Exception => e
		sendmessage($host[0,$host.index("!")] + ": #{e.message}")
		err_log(e.backtrace)
	end
end
def about()
	sendmessage("Not Enough Mods toolkit for IRC by SinZ v3.0, ported by umby24")
end
def setlist()
	if $args.length != 3
		sendmessage($host[0, $host.index("!")] + ": Insufficient ammount of parameters provided.")
		sendmessage($host[0, $host.index("!")] + ": see #{$prefix}help nem for usage.")
		return
	end
	colorblue = 2.chr + 3.chr + "12"
    color = 3.chr + 2.chr
	
	$nemVersion = $args[2]
	sendmessage("Switched list to: " + colorblue + $args[2] + color)
end
$nemVersions = getVersions()
$nemVersion = $nemVersions[$nemVersions.length - 1]

regCmd("nem","command_nem")
regGCmd("nem","command_nem")