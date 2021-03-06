
require("stream")
require("dataparser")
require("terminal")
require("strutil")
require("process")
require("time")

SessionID=""
Version="1.5"
SettingTitles={}
transbt_host="127.0.0.1:9091"

function ColorBoolean(bool)
if bool=="true" then return "~g"..bool.."~0" end

return "~r"..bool.."~0"
end


function splitTable(input_table, start)
local new_table={}
local i, value

for i,value in ipairs(input_table)
do
	if i >= start then
	table.insert(new_table, value)
	end
end

return(new_table)
end



function DrawHeader()
Out:move(0,0)
Out:puts("Transmission Manager v" .. Version .. "    Connected to: " .. transbt_host .. "~>~0\n\n")
end


function TransmissionSingleTransact(json)
local S, str
local doc=nil

-- we don't want to see 409 errors that tell us to use the supplied session-id, 
-- as these will likely confuse that poor, dim beast we call 'the user'.
-- so we switch off debugging for the connection to the server
process.lu_set("Error:Silent","y")
S=stream.STREAM("http://" .. transbt_host .. "/transmission/rpc", "w content-type=application/json content-length=" .. string.len(json).. " X-Transmission-Session-Id="..SessionID)

if S ~= nil
then
	S:writeln(json)
	S:commit()

	str=S:getvalue("HTTP:X-Transmission-Session-ID")
	if strutil.strlen(str) > 0 then SessionID=str end

	str=S:getvalue("HTTP:ResponseCode")
	if str=="409" then return nil end

	doc=S:readdoc()
end

process.lu_set("Error:Silent","n")
return doc
end



function TransmissionTransact(str)
local doc

doc=TransmissionSingleTransact(str)
if doc==nil then doc=TransmissionSingleTransact(str) end

if doc == nil 
then
	Out:puts("~rERROR:~0 Failed to connect to "..transbt_host.."\r\n")
	return(nil)
end

--io.stderr:write(doc)
return(dataparser.PARSER("json", doc))
end



function TorrentAdd(filename)
TransmissionTransact('{"arguments":{"filename": "' .. filename .. '", "downloadDir": "/BigDisk/Torrents"}, "method": "torrent-add"}')
TransmissionTransact('{"arguments":{}, "method": "torrent-start-now"}')
end


function TorrentDel(id)
if id==nil 
then
TransmissionTransact('{"method": "torrent-remove"}')
else
TransmissionTransact('{"arguments":{ "ids": [ '..id..' ]}, "method": "torrent-remove"}')
end
end


function TorrentStop(id)
if id==nil 
then
TransmissionTransact('{"method": "torrent-stop"}')
else
TransmissionTransact('{"arguments":{ "ids": [ '..id..' ]}, "method": "torrent-stop"}')
end
end


function TorrentStart(id)
if id==nil 
then
TransmissionTransact('{"method": "torrent-start"}')
else
TransmissionTransact('{"arguments":{ "ids": [ '..id..' ]}, "method": "torrent-start"}')
end
end




function TorrentsList()
local P, item, str

P=TransmissionTransact('{"arguments":{ "fields": [ "id", "name", "percentDone", "totalSize", "peersSendingToUs", "peersGettingFromUs", "downloadDir", "uploadedEver", "error", "errorString", "isStalled", "activityDate" ]}, "method": "torrent-get"}')
if P ~= nil
then
	torrents=P:open("/arguments/torrents")
	item=torrents:first()
	while item ~= nil
	do
		str=string.format("%03d % 6.1f%%  % 7s % 3d  % 3d % 7s %s", item:value("id"), tonumber(item:value("percentDone"))*100, strutil.toMetric(tonumber(item:value("totalSize"))), tonumber(item:value("peersSendingToUs")), tonumber(item:value("peersGettingFromUs")), strutil.toMetric(tonumber(item:value("uploadedEver"))), item:value("name"))
	print(str)
	item=torrents:next()
	end
end

end







function DisplayPeers(torrent, peers)
local item, str

Out:clear()
DrawHeader()
Out:puts(" Peers for torrent No.".. torrent:value("id").. "  ~m"..torrent:value("name").."~0\n")
Out:puts(string.format(" Peers: ~c%d~0  Sending: ~c%d~0  Leaching: ~c%d~0\n", peers:size(), tonumber(torrent:value("peersSendingToUs")), tonumber(torrent:value("peersGettingFromUs")) ))

Out:move(0,Out:length() -1)
Out:puts("~w up/down:~ymenu prev/next~w   enter:~yselect~w   ESC:~cback~>~0")


Out:move(0,5)
Out:puts("   Address            Client                          Progress   Flags")
Menu=terminal.TERMMENU(Out, 1, 6, Out:width()-2, 10)
item=peers:next()
while item ~= nil
do
	str=string.format("%- 16s   %- 30s  %6.2f%%    ", item:value("address"), item:value("clientName"), tonumber(item:value("progress")) * 100.0)
	if item:value("peerIsChoked")=="true" then str=str.."choked," end
	if item:value("peerIsInterested")=="true" then str=str.."interested," end
	if item:value("isEncrypted")=="true" then str=str.."encrypted," end
	if item:value("isDownloadingFrom")=="true" then str=str.."downloading," end
	if item:value("isUTP")=="true" then str=str.."utp," end
	if item:value("isIncoming")=="true" then str=str.."incoming," end

	Menu:add(str)
	item=peers:next()
end

Menu:add("Back to Previous Screen", "exit")
Menu:run()

end




function DisplayTrackers(torrent, trackers)
local item, str

Out:clear()
DrawHeader()
Out:puts(" Trackers for torrent No.".. torrent:value("id").. "  ~m"..torrent:value("name").."~0\n")
Out:puts(string.format(" No of Trackers: ~c%d~0 \n", trackers:size()))

Out:move(0,Out:length() -1)
Out:puts(" ~wup/down:~ymenu prev/next~w   enter:~yselect~w   ESC:~cback~>~0")


Out:move(0,5)
Out:puts("    ID    Tier       Announce\n")
Menu=terminal.TERMMENU(Out, 1, 6, Out:width()-2, 10)
item=trackers:next()
while item ~= nil
do
	str=string.format("%03d       %s       %- 16s", tonumber(item:value("id")), item:value("tier"), item:value("announce"))
	Menu:add(str)
	item=trackers:next()
end

Menu:add("Back to Previous Screen", "exit")
Menu:run()

end




function DisplayTorrent(torrent_id)
local item, Menu, str, peers, dl_percent, val, torrents, selected
local dl_color="~c"
local status="unknown"


while 1 == 1
do
	torrents=TransmissionGetTorrents()
	item=torrents:first()
	while item ~= nil
	do
		if torrent_id == item:value("id") then break end
		item=torrents:next()
	end
	
	if item==nil then return end
	

	Out:clear()
	DrawHeader()
	
	dl_percent=tonumber(item:value("percentDone")) * 100.0
	if dl_percent > 75.0 then dl_color="~y" end
	if dl_percent >= 100.0 then dl_color="~g" end
	
	val=tonumber(item:value("status"))
	if val==0 
	then
		status="~rstopped~0"
	elseif val==1 or val==2
	then
		status="~cvalidating~0"
	elseif val==3 or val==4
	then
		status="~mdownloading~0"
	elseif val==5 or val==6 
	then
		status="~gseeding~0"
	end

	if tonumber(item:value("error")) > 0 then status="~R~wERROR~0" end

	peers=item:open("peers")
	trackers=item:open("trackers")
	Out:puts("Torrent: ~e~m" .. item:value("name") .. "~0\n")
	Out:puts(string.format("State: ~c%s~0  Size: ~c%s~0  PercentDownloaded: %s%6.1f%%~0\n", status, strutil.toMetric(tonumber(item:value("totalSize"))), dl_color, dl_percent));

	if tonumber(item:value("error")) > 0 then Out:puts("~rERROR: ".. item:value("errorString") .."~0\n") end
	
	--Out:puts("Comment: "..item:value("comment").."\n");
	Out:puts("Added: ~c" .. time.formatsecs("%Y/%m/%d", item:value("addedDate")) .. "~0  Started: ~c" .. time.formatsecs("%Y/%m/%d", item:value("startDate")) .. "~0  LastActive: ~c" .. time.formatsecs("%Y/%m/%d", item:value("activityDate")) .."~0\n")
	
	Out:puts(string.format("Peers: ~c%d~0  Sending: ~c%d~0  Leaching: ~c%d~0\n", peers:size(), tonumber(item:value("peersSendingToUs")), tonumber(item:value("peersGettingFromUs")) ))
	Out:puts(string.format("Trackers: ~c%d~0\n", trackers:size()))
	str= "Download Rate: ~c" .. strutil.toMetric(tonumber(item:value("rateDownload"))) .. "~0  Upload Rate: ~c" .. strutil.toMetric(tonumber(item:value("rateUpload")))  .. "~0"
	str=str .. "  Downloaded: ~c" .. strutil.toMetric(tonumber(item:value("downloadedEver"))) .. "~0  Uploaded: ~c" .. strutil.toMetric(tonumber(item:value("uploadedEver"))) .."~0"

	
	Out:puts(str .. "\n")

	Out:move(0,Out:length() -1)
	Out:puts(" up/down:~ymenu prev/next~w   enter:~yselect~w   ESC:~cback~>~0")


	Menu=terminal.TERMMENU(Out, 1, 10, Out:width() -2, 10)
	val=tonumber(item:value("status"))
	if val==0 or val==16
	then
	Menu:add("start")
	else
	Menu:add("stop")
	end
	
	Menu:add("remove")
	if peers:size() > 0 then Menu:add("view peers") end
	if trackers:size() > 0 then Menu:add("view trackers") end
	Menu:add("Back to Main Screen", "exit")
	
	selected=Menu:run()
	
	if strutil.strlen(selected)==0 then break end

	if selected=="view peers"
	then
		DisplayPeers(item, peers)
	elseif selected=="view trackers"
	then
		DisplayTrackers(item, trackers)
	elseif selected=="remove"
	then
		TorrentDel(item:value("id"))
		--break becasue torrent should be gone
		break
	elseif selected=="stop"
	then
		TorrentStop(item:value("id"))
		process.sleep(1)
	elseif selected=="start"
	then
		TorrentStart(item:value("id"))
		process.sleep(1)
	elseif selected=="exit"
	then
		break
	end
	
end

end





function DisplaySessionInfo()
local P, values, str, port_open

P=TransmissionTransact('{"arguments":{}, "method": "port-test"}')
port_open=P:value("port-is-open")

P=TransmissionTransact('{"arguments":{ "fields": [ "encryption", "lpd-enabled", "dht-enabled", "pex-enabled", "utp-enabled", "peer-port", "peer-port-random-on-start"  ]}, "method": "session-get"}')

values=P:open("/arguments")
str=" Server Version: ".."~m"..values:value("version") .. "~0" .. "  LPD:"..ColorBoolean(values:value("lpd-enabled")).."  DHT:"..ColorBoolean(values:value("dht-enabled")).."  UTvalues:"..ColorBoolean(values:value("utp-enabled")) .. "  PEX:"..ColorBoolean(values:value("pex-enabled"))

Out:puts(str.."\n")

if values:value("peer-port-random-on-start")=="true"
then
	str=" PeerPort: random"
else
	str=" PeerPort: "..P:value("peer-port")
end

if port_open=="true" 
then 
	str=str.."  ~cOpen to Internet~0" 
else
	str=str.."  ~gFirewalled~0"
end

Out:puts(str.."\n")

str=" Global Speed Limits:   ~mUP~0: "
if values:value("speed-limit-up-enabled")=="true"
then
	str=str..values:value("speed-limit-up").. "Kb/s"
else
	str=str.."~cnone~0"
end


str=str.."  ~cDOWN~0: "
if values:value("speed-limit-down-enabled")=="true"
then
	str=str..values:value("speed-limit-down").. "Kb/s"
else
	str=str.."~cnone~0"
end

Out:puts(str.."\n")
end




function DisplayAddTorrent()
local url

Out:clear()
DrawHeader()
Out:move(0,4)
Out:puts("~mAdd New Torrent~0\n")
url=Out:prompt("Enter URL: ")


TorrentAdd(url)
end



function TransmissionGetSettings()
local Settings, values

Settings=TransmissionTransact('{"arguments":{ "fields": [ "encryption", "lpd-enabled", "dht-enabled", "pex-enabled", "utp-enabled", "peer-port", "peer-port-random-on-start", "download-dir", "download-queue-size", "rename-partial-files", "script-torrent-done-filename", "seedRatioLimit", "seed-queue-size", "speed-limit-down", "speed-limit-up", "start-added-torrents", "peer-limit-global", "peer-limit-per-torrent"  ]}, "method": "session-get"}')
values=Settings:open("/arguments")

return values
end



function InteractiveModeSettingsMenuAdd(Menu, Settings, Key)
local value

value=Settings:value(Key)
if Key=="peer-port"
then
	if Key == "peer-port" and Settings:value("peer-port-random-on-start") == "true" then value="random ("..value..")" end
end

Menu:add(string.format("%40s:   %s", SettingTitles[Key], value) , Key)
end



function InteractiveModeProcessTextSetting(Settings, key)
local NewValue
local extra=""

if SettingTitles[key] ~= nil
then
	Out:clear()
	DrawHeader()
	Out:move(0, 4)
	Out:puts("Change Setting: ~c".. SettingTitles[key] .."~0 ("..key..")\n")
	Out:puts("Current Value: "..Settings:value(key).."\n")
	NewValue=Out:prompt("Enter New Value: ")

	if strutil.strlen(NewValue) > 0
	then
		if key=="speed-limit-down" or key=="speed-limit-up"
		then
			extra='"' .. key.. '-enabled": "true", '
		elseif key=="download-dir" or key=="script-torrent-done-filename"
		then
			NewValue='"' .. NewValue .. '"'
		end

		TransmissionTransact('{"arguments":{' .. extra .. ' "' .. key .. '": '.. NewValue .. '}, "method": "session-set"}')
	end
end

end



function InteractiveModeSettingsMenuProcessSelection(Menu, key)
local Settings, value

Settings=TransmissionGetSettings()

if key == "utp-enabled" or key == "lpd-enabled" or key == "dht-enabled" or key == "pex-enabled" or key == "start-added-torrents" or key == "rename-partial-files"
then
	if Settings:value(key) == "true" 
	then value="false"
	else value="true"
	end

	TransmissionTransact('{"arguments":{ "' .. key .. '": "' .. value .. '"}, "method": "session-set"}')
elseif  key == "encryption" 
then
		value=Settings:value(key)

		if value == "required"
		then value="preferred"
		elseif value=="preferred"
		then value="tolerated"
		elseif value=="tolerated"
		then value="required"
		end
		TransmissionTransact('{"arguments":{ "' .. key .. '": "' .. value .. '"}, "method": "session-set"}')
else
	InteractiveModeProcessTextSetting(Settings, key)
end


end



function InteractiveModeDrawSettingsMenu(Menu)
local Settings

Settings=TransmissionGetSettings()

Out:puts("  Torrents   ~e<Settings>~0\n")
InteractiveModeSettingsMenuAdd(Menu, Settings, "peer-port")
InteractiveModeSettingsMenuAdd(Menu, Settings, "encryption")
InteractiveModeSettingsMenuAdd(Menu, Settings, "utp-enabled")
InteractiveModeSettingsMenuAdd(Menu, Settings, "lpd-enabled")
InteractiveModeSettingsMenuAdd(Menu, Settings, "dht-enabled")
InteractiveModeSettingsMenuAdd(Menu, Settings, "pex-enabled")
InteractiveModeSettingsMenuAdd(Menu, Settings, "speed-limit-up")
InteractiveModeSettingsMenuAdd(Menu, Settings, "speed-limit-down")
InteractiveModeSettingsMenuAdd(Menu, Settings, "peer-limit-global")
InteractiveModeSettingsMenuAdd(Menu, Settings, "peer-limit-per-torrent")
InteractiveModeSettingsMenuAdd(Menu, Settings, "start-added-torrents")
InteractiveModeSettingsMenuAdd(Menu, Settings, "download-dir")
InteractiveModeSettingsMenuAdd(Menu, Settings, "download-queue-size")
InteractiveModeSettingsMenuAdd(Menu, Settings, "script-torrent-done-filename")
InteractiveModeSettingsMenuAdd(Menu, Settings, "rename-partial-files")
end



function InteractiveModeTorrentsMenuProcessSelection(Menu, torrents, selected)

	if selected == "add"
	then
		DisplayAddTorrent()
		torrents=TransmissionGetTorrents()
	elseif selected ~= "exit"
	then
		DisplayTorrent(selected, torrents)
		torrents=TransmissionGetTorrents()
	end

return torrents
end



function InteractiveModeDrawTorrentsMenu(Menu, torrents)
local item, str, seeds, leeches, seeded, val, status

Out:puts(" ~e<Torrents>~0   Settings\n")
Out:puts("    ID  st  %down     size seeds leach  seeded  name ");

Menu:add("+ add new", "add")
item=torrents:first()
while item ~= nil
do
	val=tonumber(item:value("peersSendingToUs")) 
	if val > 0 
	then 
			seeds=string.format("~b% 5d~0", val)
	else
			seeds=string.format("% 5d", val)
	end

	val=tonumber(item:value("peersGettingFromUs"))
	if val > 0 
	then 
			leeches=string.format("~b% 5d~0", val)
	else
			leeches=string.format("% 5d", val)
	end

	val=tonumber(item:value("uploadedEver"))
	if val > 0 
	then 
			seeded=string.format("~b% 7s~0", strutil.toMetric(val))
	else
			seeded=string.format("% 7s", strutil.toMetric(val))
	end

	val=tonumber(item:value("status"))
	if val==0 
	then
		status="~rS~0"
	elseif val==1 or val==2
	then
		status="~G~nV~0"
	elseif val==3 or val==4
	then
		status="D"
	elseif val==5 or val==6 
	then
		status="~ys~0"
	else
		status="~M~w?~0"
	end

	if tonumber(item:value("error")) > 0 then status="~R~w!~0" end



	str=string.format("%03d  %s % 6.1f%%  % 7s %s %s %s  %s", item:value("id"), status, tonumber(item:value("percentDone"))*100, strutil.toMetric(tonumber(item:value("totalSize"))), seeds, leeches, seeded, item:value("name"))

	Menu:add(str, item:value("id"))
	item=torrents:next()
end

-- check if function exists, so we still work with earlier versions of libUseful-lua that don't have Menu:setpos
if Menu.setpos ~= nil
then
if strutil.strlen(torrents_curr) > 0 then Menu:setpos(torrents_curr) end
end

Out:move(0,Out:length() -3)
Out:puts("  status key:  ~M~w?~0:unknown ~R~w!~0:error  ~rS~0:stopped  ~G~nV~0:verifying  D:downloading  ~ys~0:seeding\n")

end




function InteractiveModeDrawMainScreen(MenuType, torrents)

if Menu ~= nil and MenuType == "torrents" then torrents_curr=Menu:curr() end

Menu=terminal.TERMMENU(Out, 1, 8, Out:width() -2, Out:length()-12)

--corking the terminal presents screen-flash as we recreate the menu
Out:cork()
Out:clear()
Menu:clear()
DrawHeader()
DisplaySessionInfo()
Out:move(0,Out:length() -1)
Out:puts(" left/right:~yswitch menu~0 up/down:~ymenu prev/next~0 enter:~yselect~0 u:~yupdate~0 a:~yadd torrent~0 q:~rexit~>~0")


Out:move(0,6)
if MenuType == "torrents"
then
	InteractiveModeDrawTorrentsMenu(Menu, torrents)
else
	InteractiveModeDrawSettingsMenu(Menu)
end

Menu:draw()

Out:flush()

return Menu
end



function TransmissionGetTorrents()
local P

P=TransmissionTransact('{"arguments":{ "fields": [ "id", "name", "comment", "percentDone", "totalSize", "status", "addedDate", "startDate", "doneDate", "activityDate", "peersSendingToUs", "peersGettingFromUs", "downloadDir", "downloadedEver", "uploadedEver", "peers", "trackers", "rateDownload", "rateUpload", "error", "errorString", "isStalled", "activityDate" ]}, "method": "torrent-get"}')
if P == nil then return nil end

return(P:open("/arguments/torrents"))
end



function InteractiveMode()
local ch, torrents, selected
local Menu, MenuType, screen_redraw_needed

screen_redraw_needed=true
torrents=TransmissionGetTorrents()

if torrents ~= nil
then
MenuType="torrents"

while selected ~= "exit"
do

if screen_redraw_needed == true 
then 
	Menu=InteractiveModeDrawMainScreen(MenuType, torrents) 
	screen_redraw_needed=false
end

selected=""

--register window-change signal as one we watch and that interrupts system calls like 'select' or 'read'
process.sigwatch(process.SIGWINCH)

ch=Out:getc()

if ch=="q" or ch=="Q"
then 
	break 
elseif ch == "u"
then
	torrents=TransmissionGetTorrents()
	screen_redraw_needed=true
elseif ch == "a"
then
	DisplayAddTorrent()
	torrents=TransmissionGetTorrents()
	screen_redraw_needed=true
elseif ch == "LEFT"
then
	MenuType="torrents"
	screen_redraw_needed=true
elseif ch == "RIGHT"
then
	MenuType="settings"
	screen_redraw_needed=true
elseif ch ~= ""
then
	selected=Menu:onkey(ch)
end


--did we get a 'window changed' signal? Of so we need to redraw the screen
if process.sigcheck ~= nil and process.sigcheck(process.SIGWINCH) == true then screen_redraw_needed=true end

if strutil.strlen(selected) > 0 
then
	if MenuType=="torrents"
	then
		torrents=InteractiveModeTorrentsMenuProcessSelection(Menu, torrents, selected)
	else
		InteractiveModeSettingsMenuProcessSelection(Menu, selected)
	end

	screen_redraw_needed=true
end

end

Out:clear()
Out:move(0,0)
end

end



function SetupSettingTitles()
SettingTitles["peer-port"]="Peer Port"
SettingTitles["encryption"]="Encryption"
SettingTitles["lpd-enabled"]="LPD: Local Peer Discovery"
SettingTitles["dht-enabled"]="DHT: Distributed Hash Discovery"
SettingTitles["pex-enabled"]="PEX: Peer EXchange peer/torrent info"
SettingTitles["utp-enabled"]="uTP: Micro Transport Protocol"
SettingTitles["speed-limit-up"]="Max Upload Speed (Kb/s)"
SettingTitles["speed-limit-down"]="Max Download Speed (Kb/s)"
SettingTitles["peer-limit-global"]="Max Peers"
SettingTitles["peer-limit-per-torrent"]="Max Peers per Torrent"
SettingTitles["start-added-torrents"]="Start Added Torrents"
SettingTitles["download-dir"]="Download Directory"
SettingTitles["download-queue-size"]="Download Queue Size"
SettingTitles["script-torrent-done-filename"]="Run Script on Torrent Done"
SettingTitles["rename-partial-files"]="Append .part to downloading files"
end



function ParseCommandLine(cmd_line)
local i, value, args
local action="interact"

for i,value in ipairs(cmd_line)
do
	if value=="add" or value=="del" or value=="stop" or value=="start"
	then
		action=value
		args=splitTable(cmd_line, i+1)
		break
	elseif value=="clear" or value=="list"
	then
		action=value
	else
		transbt_host=value
	end
end

return action, args
end


-- Main starts here --------------------------------------------------------

Out=terminal.TERM()
SetupSettingTitles()

action,args=ParseCommandLine(arg)


if action=="add" 
then 
	for i,value in ipairs(args)
	do
	TorrentAdd(value) 
	end
elseif action=="del"
then 
	for i,value in ipairs(args)
	do
	TorrentDel(value) 
	end
elseif action=="clear"
then 
	TorrentDel(nil) 
elseif action=="start"
then 
	for i,value in ipairs(args)
	do
	TorrentStart(value) 
	end
elseif action=="stop"
then 
	for i,value in ipairs(args)
	do
	TorrentStop(value) 
	end
elseif action=="list"
then
	TorrentsList()
else
	InteractiveMode()
end


Out:reset()
