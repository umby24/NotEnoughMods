regLib("json")
regLib("cgi")
regLib("open-uri")
regLib("openssl")
$nemVersions = []
$nemVersion = ""

$newMods = false
$mods = Hash.new()

$nempRunning = false
$nempTimer = 300

##################################

def fetch_page(url, decompress=true, timeout=10)
	response = open(url, {"User-Agent" => "Rubybot/4.3 (+http://umby.d3s.co/)", :read_timeout => 10, :ssl_verify_mode=>OpenSSL::SSL::VERIFY_NONE})
	
	if response.meta["content-encoding"] == "gzip" and decompress
		puts "GZIP"
		data = ""
	else
		data = response.read
	end
	return data
end

def buildModDict()
	modList = open("settings/nemp/mods.json", "r")
	fileInfo = modList.read
	$mods = JSON.parse(fileInfo)
	
	for mod, value in $mods
		if $mods[mod].has_key?("change") == false
			$mods[mod]["change"] = "NOT_USED"
		end		
	end
end

def queryNem()
	begin
		result = fetch_page("http://bot.notenoughmods.com/?json")
		$nemVersions = JSON.parse(result).reverse
	rescue
		puts("Failed to get NEM versions, falling back to hard-coded.")
		$nemVersions = ["1.4.5","1.4.6-1.4.7","1.5.1","1.5.2","1.6.1","1.6.2","1.6.4"].reverse
	end
end

def initiateVersions()
	templist = $mods.keys()
	
	for version in $nemVersions
		if version.include?("-dev") == false
			rawJson = fetch_page("http://bot.notenoughmods.com/"+version+".json")
			jsonres = JSON.parse(rawJson)
			
			for mod in jsonres
				if templist.include?(mod["name"])
					$mods[mod["name"]]["mc"] = version
					
					if mod.include?("dev") and mod["dev"]
						$mods[mod["name"]]["dev"] = mod["dev"]
					else
						$mods[mod["name"]]["dev"] = "NOT_USED"
					end
					
					if mod.include?("version") and mod["version"]
						$mods[mod["name"]]["version"] = mod["version"]
					else
						$mods[mod["name"]]["version"] = "NOT_USED"
					end
					templist.delete(mod["name"])
				end
			end
		end
	end
end

def CheckJenkins(mod)
	result = fetch_page($mods[mod]["jenkins"]["url"])
	jsonres = JSON.parse(result)
	filename = jsonres["artifacts"][$mods[mod]["jenkins"]["item"]]["fileName"]
	match = /#{$mods[mod]["jenkins"]["regex"]}/.match(filename)
	output = Hash[match.names.zip(match.captures)]
	
	begin
		output["change"] = jsonres["changeSet"]["items"][0]["comment"]
	rescue
		output["change"] = "NOT_USED"
	end
	return output
end

def CheckMCForge(mod)
	result = fetch_page("http://files.minecraftforge.net/" + $mods[mod]["mcforge"]["name"] + "/json")
	jsonres = JSON.parse(result)
	promotionArray = jsonres["promotions"]
	devMatch = ""
	recMatch = ""
	
	for promotion in promotionArray
		if promotion["name"] == $mods[mod]["mcforge"]["dev"]
			for entry in promotion["files"]
				if entry["type"] == "universal"
					info = entry["url"]
					devMatch = /#{$mods[mod]["mcforge"]["regex"]}/.match(info)
				end
			end
		elsif promotion["name"] == $mods[mod]["mcforge"]["rec"]
			for entry in promotion["files"]
				if entry["type"] == "universal"
					info = entry["url"]
					recMatch = /#{$mods[mod]["mcforge"]["regex"]}/.match(info)
				end
			end
		end
	end
	
	if devMatch
		output = Hash.new
		tmpMC = "null"
		
		if recMatch
			output["version"] = recMatch[2]
			tmpMC = recMatch[1]
		end
		if devMatch[1] != tmpMC
			output["version"] = "NOT_USED"
			output["mc"] = devMatch[1]
		else
			output["mc"] = tmpMC
		end
		output["dev"] = devMatch[2]
		return output
	end
	
end

def CheckChickenBones(mod)
	result = fetch_page("http://www.chickenbones.craftsaddle.org/Files/New_Versions/version.php?file="+mod+"&version="+$mods[mod]["mc"])
	if result[0, 5] == "Ret: "
		return {"version" => result[5, result.length - 5]}
	end
end

def CheckmDiyo(mod)
	result = fetch_page("http://tanis.sunstrike.io/"+$mods[mod]["mDiyo"]["location"])
	lines = result.split()
	result = ""
	
	for line in lines
		if line.downcase.include?(".jar")
			result = line
		end
	end
	
	match = /#{$mods[mod]["mDiyo"]["regex"]}/.match(result)
	output = Hash[match.names.zip(match.captures)]
	return output
end

def CheckAE(mod)
	result = fetch_page("http://ae-mod.info/releases")
	jsonres = JSON.parse(result)
	jsonres = jsonres.sort_by{|k| k["Released"]}
	relVersion = ""
	devVersion = ""
	devMC = ""
	
	for version in jsonres
		if version["Channel"] == "Stable"
			relVersion = version["Version"]
		else
			devVersion = version["Version"]
			devMC = version["Minecraft"]
		end
	end
	
	return {"version" => relVersion, "dev" => devVersion, "mc" => devMC}
end

def CheckDropBox(mod)
	result = fetch_page($mods[mod]["html"]["url"])
	match = nil
	
	result.scan(/#{$mods[mod]["html"]["regex"]}/) {|b|
		match = b
	}
	
	
	if match != nil
		if $nemVersions.include?(match[0]) == false
			match = {"mc" => $mods[mod]["mc"], "version"=>match[0]}
		else
			match = {"mc" => match[0], "version"=>match[1]}
		end
		
		return match
	else
		return Hash.new
	end
end

def CheckHTML(mod)
	result = fetch_page($mods[mod]["html"]["url"])
	output = Hash.new
	
	for line in result.split("\n")
		match = /#{$mods[mod]["html"]["regex"]}/.match(line)
		
		if match != nil
			output = Hash[match.names.zip(match.captures)]
		end
	end
	
	return output
end

def CheckSpacechase(mod)
	result = fetch_page("http://spacechase0.com/wp-content/plugins/mc-mod-manager/nem.php?mc=6")
	
	for line in result.split("\n")
		info = line.split(",")
		if info[1] == mod
			return {"version" => info[5]}
		end
	end
end

def checkMod(mod)
	begin
		# First False is for if there was an update.
        # Next two Falses are for if there was an dev or version change
        status = [false, false, false]
        output = send($mods[mod]["function"], mod)
        
        if output.has_key?("dev")
			if $mods[mod]["dev"] != output["dev"]
				$mods[mod]["dev"] = output["dev"]
				status[0] = true
				status[1] = true
			end
		end
		if output.has_key?("version")
			if $mods[mod]["version"] != output["version"]
				$mods[mod]["version"] = output["version"]
				status[0] = true
				status[2] = true
			end
		end
		if output.has_key?("mc")
			$mods[mod]["mc"] = output["mc"]
		end
		if output.has_key?("change")
			$mods[mod]["change"] = output["change"]
		end
		
		return status
	rescue
		puts "Mod failed to be polled."
		return [false, false, false]
	end
end

#####################################
#   Begin Command Section          #
###################################

def running()
	if $args.length >= 3 and ($args[2] == "true" or $args[2] == "on")
		if $nempRunning == false
			sendmessage("Turning NotEnoughModPolling on.")
			initiateVersions()
			#NOTE THAT TIME BETWEEN POLLS IS 300
			if $args.length == 4
				$nempTimer = $args[3].to_i
			end
			$nempRunning = true
			Thread.new([$current]) {|a| MainTimerEvent(a)}
			
		end
	else
		sendmessage("NotEnoughMods-Polling is already running.")
	end
	
	if $args.length == 3 and ($args[2] == "false" or $args[2] == "off")
		if $nempRunning == true
			sendmessage("Turning NotEnoughModsPolling off.")
			$nempRunning = false
		else
			sendmessage("NotEnoughModsPolling isn't running!")
		end
	end
end

def PollingThread()
	if $newMods == true
		$mods = newMods
		initiateVersions()
	end
	tempList = {}
	
	$mods.each {|mod, info|
		
		if info.has_key?("name")
			real_name = info["name"]
		else
			real_name = mod
		end
		
		if $mods[mod]["active"]
			result = checkMod(mod)
			
			if result[0]
				if tempList.has_key?($mods[mod]["mc"])
					tempList[$mods[mod]["mc"]] = tempList[$mods[mod]["mc"]] << [real_name, result[1, result.length - 1]]
				else
					tempVersion = [real_name, result[1, result.length - 1]]
					tempList[$mods[mod]["mc"]] = [tempVersion]
				end
			end
		end

	}
	
	return tempList
end

def MainTimerEvent(channels)
	begin	
		begin
			tempList = PollingThread()
			MicroTimerEvent(channels, tempList)
		rescue
			$nempRunning = false
			puts "Temp Error: #{e.message}"
		end
		sleep($nempTimer)
	end while ($nempRunning == true)
end

def MicroTimerEvent(channels, tempList)
	for channel in channels
		for version, values in tempList
			tempList[version].each {|item|
				mod = item[0]
				flags = item[1]
				
				if $mods[mod]["dev"] != "NOT_USED" and flags[0]
					pm("!ldev" + version + " " + mod + " " + $mods[mod]["dev"], channel)
				end
				
				if $mods[mod]["version"] != "NOT_USED" and flags[1]
					pm("!lmod " + version + " " + mod + " " + $mods[mod]["version"], channel)
				end

				if $mods[mod]["change"] != "NOT_USED"
					pm(" * " + $mods[mod]["change"], channel)
				end
				
			}
		end
	end
end


def poll()
	begin
		if $args.length != 4
			sendmessage($name + ": Insufficient amount of parameters provided.")
		else
			setting = false
			
			if $mods.has_key?($args[2])
				if $args[3].downcase == "true" or $args[3].downcase == "yes" or $args[3].downcase == "on"
					setting = true
				elsif $args[3].downcase == "false" or $args[3].downcase == "no" or $args[3].downcase == "off"
					setting = false
				end
				
				$mods[$args[2]]["active"] = setting
				sendmessage($name + ": " + $args[2] + "'s poll status is now " + setting.to_s)
			elsif $args[2].downcase == "all"
				if $args[3].downcase == "true" or $args[3].downcase == "yes" or $args[3].downcase == "on"
					setting = true
				elsif $args[3].downcase == "false" or $args[3].downcase == "no" or $args[3].downcase == "off"
					setting = false
				end
				
				for mod, key in $mods
					$mods[mod]["active"] = setting
				end
				
				sendmessage($name + ": All mods are now set to " + setting.to_s)
			end
		end
	rescue Exception => e
		err_log(e.message)
	end
end

def command_nemp()
	case $args[1]
	when "running"
		running()
	when "poll"
		poll()
	when "list"
		nemp_list()
	when "about"
		about()
	when "setversion"
		setversion()
	when "getversion"
		getversion()
	when "testparse"
		test_parser()
	when "testpolling"
		test_polling()
	when "reload"
		nemp_reload()
	when "nktest"
		nktest()
	when "setv"
		setversion()
	when "getv"
		getversion()
	when "polling"
		running()
	when "testpoll"
		test_polling()
	when "refresh"
		nemp_reload()

	end
end

def setversion()
	if $args.length != 2
		sendmessage($name + ": Insufficent amount of parameters provided.")
	else
		colorblue = 2.chr + 3.chr + "12"
		color = 3.chr + 2.chr
		$nemVersion = $args[2]
		sendmessage("Set default list to: " + colorblue + $args[1] + color)
	end
end

def getversion()
	sendmessage($nemVersion)
end

def about()
	sendmessage("Not Enough Mods: Polling for IRC by SinZ and Nightkev, Ported by Umby24 - v1.0")
	sendmessage("Source code available at: https://github.com/umby24/NotEnoughMods")
end

def nemp_list()
	dest = $name
	if $args.length > 2 and $args[2] == "broadcast"
		dest = $current
	end
	darkgreen = "03"
    red = "05"
    blue = "12"
    bold = 2.chr
    color = 3.chr
    tempList = {}
    
    for key, info in $mods
		real_name = info.fetch("name", key)
		if $mods[key]["active"]
			relType = ""
			mcver = $mods[key]["mc"]
			
			if $mods[key]["version"] != "NOT_USED"
				relType = relType + color + darkgreen + "[R]" + color
			end
			if $mods[key]["dev"] != "NOT_USED"
				relType = relType + color + red + "[D]" + color
			end
			
			if tempList.has_key?(mcver) == false
				tempList[mcver] = []
			end
			
			tempList[mcver] = tempList[mcver] + [real_name + relType]
		end
	end
    
    for mcver, value in tempList
		pm("Mods checked for " + color + blue + bold + mcver + color + bold + ": " + tempList[mcver].join(", "), dest)
	end
end

def nemp_reload()
	buildModDict()
	queryNem()
	initiateVersions()
	
	sendmessage("Reloaded the NEMP Database.")
end
def test_parser()
	if $args.length > 1
		begin
			result = send($mods[$args[2]]["function"], $args[2])
			
			if result.has_key?("mc")
				sendmessage("!setlist " + result["mc"])
			end
			if result.has_key?("version")
				sendmessage("!mod " + $args[2] + " " + result["version"])
			end
			if result.has_key?("dev")
				sendmessage("!dev " + $args[2] + " " + result["dev"])
			end
			if result.has_key?("change")
				sendmessage(" * " + result["change"])
			end
			
		rescue Exception => e
			sendmessage($name + ": " + e.message)
			sendmessage($args[2] + " failed to be polled.")
			puts e.backtrace
		end
	end
	
end
##################
#initiation
##################

buildModDict()
queryNem()
initiateVersions()

##################
# Command and help registration #

regCmd("nemp", "command_nemp")
regGCmd("nemp", "command_nemp")
###################################
regHelp("nemp", "running",["=nemp running <true/false>", "Enables or Disables the polling of latest builds."])
regHelp("nemp", "poll", ["=nemp poll <mod> <true/false>", "Enables or Disables the polling of <mod>."])
regHelp("nemp", "list",  ["=nemp list", "Lists the mods that NotEnoughModPolling checks"])
regHelp("nemp", "about", ["=nemp about", "Shows some info about this plugin."])
regHelp("nemp", "setversion", ["=nemp setversion <version>", "Sets the version to <version> for polling to assume."])
regHelp("nemp", "getversion", ["=nemp getversion", "gets the version for polling to assume."])
regHelp("nemp", "refresh", ["=nemp refresh", "Queries NEM to get the \"latest\" versions"])
regHelp("nemp", "testparse", ["=nemp testparse <mod>", "Tests the parser for <mod> and outputs the contents to IRC"])
