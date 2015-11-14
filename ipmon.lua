local string = require "string"
local io = require "io"
local os = require "os"
local table = require "table"


monitorips =
{
	{ 	"168.0.180.101" ,
		match = {
			interface = "eth0",
			--masklen = 16,
			},
		gateway = "168.0.0.254",
		-- tableid = 10, "never set it!"
	},
	{ 	"168.0.180.100" ,
		match = {
			--interface = "eth0",
			--masklen = 16,
			},
		gateway = "168.0.0.254",
		-- tableid = 10, "never set it!"
	},
}


-- hepler functions
function log(s)
	os.execute("logger -t ipmon.lua " .. s)
end

function exec(cmd)
	local f = io.popen(cmd .. " 2>&1")
	log("execute " .. cmd)
	log("ret: " .. f:read"*a")
end

function subnet(ip, masklen)
	if masklen == 32 then return ip end
	local ip = {string.match(ip, "(%d+).(%d+).(%d+).(%d+)")}
	local pos = math.floor((masklen)/8) + 1
	ip[pos] =  ip[pos] - ip[pos] % 2^(8-masklen%8)
	for i = pos + 1, #ip do
		ip[i] = 0
	end
	return table.concat(ip, ".")
end

-- functions operate route
function flushrt(ip, ipargs)
	-- ip route flush table tableid
	exec("ip route flush table " .. ipargs.tableid)
end

function addrt(ip, ipargs)
	-- ip route add ip/masklen dev interface table tableid
	-- ip route add default via gateway dev interface table tableid
	ipargs.ip = ip
	exec(string.gsub("ip route add $subnet/$masklen dev $interface table $tableid",  "%$(%w+)", ipargs))
	if ipargs.gateway then
		exec(string.gsub("ip route add default via $gateway dev $interface table $tableid",  "%$(%w+)", ipargs))
	end
end

function delrule(ip, ipargs)
	-- ip rule del pref ?
	local f = io.popen"ip rule"
	local cmds = {}
	for l in f:lines() do
		if string.find(l, ip, 1, true) then
			pref = string.match(l, "%d+")
			if pref == "0" or pref == "32766" or pref == "32767" then
				log("Error!!! Try to delete defult rule when delete rule of " .. ip)
				return
			end
			table.insert(cmds, "ip rule del pref " .. pref)
		end
	end

	-- delete all rule match ip
	for _, v in ipairs(cmds) do
		exec(v)
	end
end

function addrule(ip, ipargs) 
	-- ip rule add from ip lookup tableid
	exec("ip rule add from " .. ip .. " lookup " .. ipargs.tableid)
end

-- 
-- match ip and return a ipargs include
-- {
-- 	action = "ADD | DEL"
-- 	interface = ?
-- 	masklen = ?
-- 	tableid = ?
-- }
function matchip(monitorips, event)
	local pat=[[([^%s]*)%s*%d+:%s+([^%s]+)%s+inet%s+([%d.]+)/(%d+)]]	
	-- Deleted 2: eth0    inet 192.168.22.2/24 brd 192.168.22.255 scope global eth0:2
	-- ^del	      ^interface   ^ip		^masklen
	local del, interface, ip, masklen = string.match(event, pat)		
	local ipargs = {}
	local hit = nil
	for i, monip in ipairs(monitorips) do
		if monip[1] == ip then
			hit = i
		end
	end
	if not hit then return false end
	if monitorips[hit].match then
		if monitorips[hit].match.interface and monitorips[hit].match.interface ~= interface then 
			return false 
		end
		if monitorips[hit].match.masklen and monitorips[hit].match.masklen ~= masklen then 
			return false 
		end
	end
	ipargs.action = del == "" and "ADD" or "DEL"
	ipargs.interface = interface
	ipargs.masklen = masklen
	ipargs.subnet = subnet(ip, masklen)
	ipargs.tableid = 9 + hit
	ipargs.gateway = monitorips[hit].gateway
	return true, ip, ipargs
end

function run(config)
	if not config then config = monitorips end
	local f = io.popen"ip monitor addr"
	for event in f:lines() do
		repeat
			ret, ip, ipargs = matchip(config, event)
			if not ret then break end 
			if ipargs.action == "ADD" then
				log("ADD IP: " .. ip .. " on " .. ipargs.interface)
				delrule(ip, ipargs)
				flushrt(ip, ipargs)
				addrt(ip, ipargs)
				addrule(ip, ipargs)
			elseif ipargs.action == "DEL" then
				log("DEL IP: " .. ip .. " on " .. ipargs.interface)
				delrule(ip, ipargs)
				flushrt(ip, ipargs)
			end
		until true
	end
end


-- run()
