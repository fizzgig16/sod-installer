#!/usr/bin/env ruby

########################################################
# Shards of Dalaya Linux installer
# By Dave Russell a.k.a. Serinar
# (C) 2012 Dave Russell, All Rights Reserved
#
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#########################################################

require 'open4'
require 'digest/md5'
require 'net/http'
require 'getoptlong'
require 'pathname'
require 'tempfile'
require 'fileutils'

def Usage()
	puts("Usage: sod_install.rb [options]")
	puts("  where options can be one of the following:\n\n")
	puts("--help: you're reading it")
	puts("--force-root: allow the script to run as root (NOT RECOMMENDED!)")
	puts("\n\n") 
end

def RunCommand(strCommandLine)
	exit_status = -1
	output = nil

	stdout, stderr = '', ''
    status = Open4::spawn strCommandLine, 'stdout' => stdout, 'stderr' => stderr, 'raise' => false, 'ignore_exit_failure' => true    
	output = stdout
	return -1 if (status.to_s()	== "")
	return status.to_i(), output
end

def CompareVersionStrings(str1, str2)
	# Returns -1 if str1 is greater, 0 if they are equal, or 1 if str2 is greater
	return 0 if (str1 == str2) # nice easy case

	arr1 = str1.split('.')
	arr2 = str2.split('.')

	if (arr1.length != arr2.length)
		puts("WARNING: versions have different lengths. Doing my best to compare anyway, but this may lead to strange results")
	end

	for i in 0..arr1.length
		return 0 if (arr2[i] == nil)	 # Disparate sizes, just return the current result
		return -1 if (arr1[i].to_i() > arr2[i].to_i())
		return 1 if (arr1[i].to_i() < arr2[i].to_i())
	end

	return 0
end

def GetEQInstallPath()
	# Using the .desktop file created by the installer
	res = ""
	begin
		f = open(File.expand_path("~/Desktop/EverQuest.desktop"), "r")
		content = f.read()
		f.close()
		path = Pathname.new(/Path=(.*)/.match(content)[1])
		res = path.to_s()	
		#res = path.dirname.to_s()
	rescue => e
		puts("Unable to determine EQ install path - can't create desktop shortcut: " + e.message)
	end

	return res
end

def GetEQIconName()
	# Using the .desktop file created by the installer
	res = ""
	begin
		f = open(File.expand_path("~/Desktop/EverQuest.desktop"), "r")
		content = f.read()
		f.close()
		path = /Icon=(.*)/.match(content)[1]
		res = path.to_s()	
	rescue => e
		puts("Unable to determine EQ icon name: " + e.message)
	end

	return res
end

def CreateDesktopShortcut(strPath)
	desktop_file = File.expand_path("~/Desktop/SoD.desktop")
	content = "[Desktop Entry]\n"
	content += "Name=Shards of Dalaya\n"
	content += "Exec=" + strPath + "/runsod.sh\n" 
	content += "Type=Application\n"
	content += "StartupNotify=true\n"
	content += "Path=" + strPath + "\n"
	content += "Icon=" + GetEQIconName() + "\n"

	begin
		if (!File.exist?(desktop_file))
			f = open(desktop_file, "w")
			f.write(content)
			f.close()
			system("chmod +x " + desktop_file)
		end
	rescue => e
		puts("Unable to write desktop entry: " + e.message)
	end
end

def Main()
	force_root = false
	strToInstall = ""
	
	puts("Shards of Dalaya Linux Installer v0.1\n")
	puts("-------------------------------------\n\n")

	opts = GetoptLong.new(
        [ '--force-root', GetoptLong::NO_ARGUMENT ],
        [ '--help', GetoptLong::NO_ARGUMENT ]
	)

	opts.each do |opt, arg|
		case opt
			when '--help'
				Usage()
				exit 0
			when '--force-root'
				force_root = true
		end
	end

	# 0) We should not run as root
	if (Process.uid == 0 && !force_root)
		puts("You should not be running this program as root! If you *really* know what you are doing, run again with --force-root\n")
		exit -1
	end
	
	# 1) do we have the required dependencies installed?
	puts("Checking for required packages...\n")
	exit_status, strWineVersion = RunCommand("wine --version")
	if (exit_status != 0)
		strToInstall += "- Wine 1.5.13 or greater\n"			
	end

	exit_status, strWineTricksVersion = RunCommand("winetricks --version")
    if (exit_status != 0)
        strToInstall += "- winetricks\n"
    end

	exit_status, strMonoVersion = RunCommand("mono --version")
	if (exit_status != 0)
		strToInstall += "- mono (mono-complete for some users)\n"			
	end

	exit_status, strCabExtractVersion = RunCommand("cabextract --version")
	if (exit_status != 0)
		strToInstall += "- cabextract\n"			
	end
	
	# Report missing packages and quit
	if (strToInstall != "")
		puts("ERROR: The following packages must be installed prior to running this script. Use your favorite package manager or compile from source.")
		puts(strToInstall)
		exit -1
	end
	puts("All good!\n")

	# 2) Are they the right versions?
	puts("Checking executable versions...\n")
	strWineVersion = strWineVersion.split('-')[1].chop
	res = CompareVersionStrings(strWineVersion, "1.5.13")
	puts ("WARNING: you are using version " + strWineVersion + " of Wine. 1.5.13 or higher is recommended.") if (res == 1)

	strWineTricksVersion = strWineTricksVersion.chop
	puts("WARNING: you are using version " + strWineTricksVersion + " of winetricks. 20120819 or higher is recommended.") if (strWineTricksVersion.to_i() < 20120819)
	puts("All good!\n")

	# 3) Is the everquest EXE in this directory, and is it the right MD5sum?
	puts("Validating EQLive executable...\n")
	if (!File.exist?("EQ_setup.exe"))
		puts("ERROR: the Everquest Live executable was not found in this directory. Please download it from http://everquest.station.sony.com and make sure it is named EQ_setup.exe (case is important!)")
		exit -1
	end	

	digest = Digest::MD5.hexdigest(File.read("EQ_setup.exe"))
	unless (digest == "25a22975f78cfd0262e46831ff58916d" or digest == "692d56ecfa277f7926be2f6584e6b98a")
		puts("ERROR: the Everquest Live executable had an incorrect checksum. Please download it from http://everquest.station.sony.com.")
		exit -1
	end
	puts("All good!\n")

	# 4) Do we have the SoD patcher? If not, download it
	puts("Checking for SoD patcher and downloading if needed...\n")
	if (!File.exist?("sodpatcher.exe"))
		puts("SoD patcher not found, downloading. Please wait...")
		
		Net::HTTP.start("shardsofdalaya.com") do |http|
			f = open('sodpatcher.exe', 'wb')
			begin
    			http.request_get('/patcher2/sodpatcher.exe') do |resp|
        			resp.read_body do |segment|
            			f.write(segment)
        			end
    			end
			ensure
    			f.close()
			end
		end
	end	
	puts("All good!\n")

	# Got all the files we need, start doing something useful	
	
	# winetricks packages	
	puts("Validating we have the winetricks packages we need...\n")
		
	exit_status, output = RunCommand("winetricks list-installed")
    if (exit_status != 0)
        puts("ERROR: unable to enumerate winetricks packages. The output from the command follows: \n\n" + output)
        exit -1
    end

	res = /directx9/.match(output)
	if (res == nil)
		# Need to install DirectX9
		puts("Installing directx9 winetricks package - this may take a long time...")	
		exit_status, install_output = RunCommand("winetricks -q directx9")
    	if (exit_status != 0)
        	puts("ERROR: unable to install 'directx9' winetricks package. The output from the command follows: \n\n" + output)
        	exit -1
		end	
	end

	res = /corefonts/.match(output)
	if (res == nil)
		# Need to install corefonts
		puts("Installing corefonts winetricks package...")	
		exit_status, install_output = RunCommand("winetricks -q corefonts")
    	if (exit_status != 0)
        	puts("ERROR: unable to install 'corefonts' winetricks package. The output from the command follows: \n\n" + output)
        	exit -1
		end
	end
	puts("All good!\n")

	# EQLive executable
	puts("\nNow we are going to install the Live game itself. Log in with your Station account, but DO NOT hit play when the installation is finished, simply close out of the game.\nTHIS WILL TAKE A LONG TIME!\nNOTE: The installer may ask you to install DirectX. Allow it to do so, but it will likely fail. That's ok, just ignore the error and move on.\n\n(Press Enter to continue)")
	gets()
	puts("Running EQLive executable...\n")
	exit_status, install_output = RunCommand("wine EQ_setup.exe")
    if (exit_status < 0)
       	puts("ERROR: unable to install EQLive executable. The output from the command follows: \n\n" + output)
       	exit -1
	end

	# SoD patcher
	install_path = GetEQInstallPath()
	puts("\nNow we are going to patch the game to run the Shards of Dalaya content. You must do a few things when this window opens:\n\n")
	if (install_path == "")
		puts("1) Use the Browse button to locate your Everquest directory. By default, this will be either ~/.wine/drive_c/Program Files/Sony Online Entertainment/Installed Games/Everquest or ~/.wine/drive_c/Program Files (x86)/Sony Online Entertainment/Installed Games/Everquest\n")
	else
		puts("1) Use the Browse button to locate your Everquest directory. This should be in " + install_path + "\n")
	end	
	puts("2) Uncheck the 'Use EQW' box. Using EQW in Wine is not supported\n")
	puts("3) Click Patch and Run\n")
	puts("4) When the game loads, walk through the screens until you get to the login screen, then quit\n")
	puts("\n(Press Enter to continue)")
	gets()
	puts("Running SoD patcher...\n")
	exit_status, install_output = RunCommand("wine sodpatcher.exe")
    if (exit_status < 0)
       	puts("ERROR: unable to run SoD patcher executable. The output from the command follows: \n\n" + output)
       	exit -1
	end
	
	# Modify the Windowed Mode line in the eqclient.ini file
	if (File.exists?(install_path + "/eqclient.ini"))
		puts("Modifying eqclient.ini")
		path = install_path + "/eqclient.ini"
		temp_file = Tempfile.new('eqclient_temp')
		begin
  			File.open(path, 'r') do |file|
    				file.each_line do |line|
					if (line.start_with?("WindowedMode="))
						# Replace to make sure we run in windowed mode
						puts("Found WindowedMode line, replacing")	
						line = "WindowedMode=TRUE\n"
					end      					
					temp_file.puts(line)
    				end
  			end
  			temp_file.rewind
  			FileUtils.cp(path, path + ".bak")	
			FileUtils.mv(temp_file.path, path)
		ensure
  			temp_file.close
  			temp_file.unlink
		end
	end	

	#Create the shell script to launch
	if (!File.exists?('runsod.sh'))
		content = "#!/bin/sh\n\nwine sodpatcher.exe"
		File.open('runsod.sh', 'w') {|f| f.write(content) }
		system("chmod +x runsod.sh")	# totally cheating
	else
		puts("Shortcut already exists, leaving it alone\n")
	end 

	# Create a shortcut to launch the program
	CreateDesktopShortcut(Dir.pwd)
	
	puts("\nCongratulations! Shards of Dalaya is now installed. you can run it by executing './runsod.sh' If you are getting messages on your button saying 'String not found', re-run the SoD patcher, and check the 'Repatch All' button. This should fix the problem.\n\n")

	
end

Main()
