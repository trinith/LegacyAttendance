-- *******************************
-- ********** Constants **********
-- *******************************
local Constants = {
	Commands = {
		Help = "help",
		Options = "options",
        Log = "log",
		Get = "get",
		Reset = "reset",
	},

    Events = {
    },

    GlobalEvents = {
        PlayerLogin = "PLAYER_LOGIN",
    },

	GuildControlPermissionFlags = {
		ViewOfficerNote = 11,
	},

	GuildInfoIndex = {
		Name = 1,
		RankName = 2,
		OfficerNote = 8,
	},

	RaiderRanks = {
		"Raider",
		"Officer",
		"Guild Master",
	},

	AddonName = "LegacyAttendance",
	AddonAbbreviation = "la",

    DateFormat = "%Y-%m-%d",
}

-- *****************************
-- ********** Classes **********
-- *****************************
-- Class Printer
local Printer = {
	indent = "",
	enabled = true,
}
Printer.__index = Printer

function Printer:new(printer)
	local newPrinter = {}
	setmetatable(newPrinter, Printer)

	if printer ~= nil and type(printer) == "table" and printer.indent ~= nil then
		newPrinter.indent = printer.indent
	end

	return newPrinter
end

function Printer:Print(msg)
	if self.enabled then
		print(self.indent .. tostring(msg))
	end
end

function Printer:AddonPrint(msg)
	if self.enabled then
		print(Constants.AddonName .. ": " .. msg)
	end
end

function Printer:StartIndent()
	self.indent = self.indent .. string.rep(" ", 2)
end

function Printer:EndIndent()
	if #self.indent >= 2 then
		self.indent = string.rep(" ", #self.indent - 2)
	end
end

function Printer:SetEnabled(isEnabled)
	isEnabled = (isEnabled == nil) and true or isEnabled
	self.enabled = isEnabled
end
-- END Class Printer

-- Class CommandEntry
local CommandEntry = {
	exec = nil,
	help = nil,
}
CommandEntry.__index = CommandEntry

function CommandEntry:new(execFunction, helpFunction)
	local newEntry = {}
	setmetatable(newEntry, CommandEntry)

	newEntry.exec = execFunction
	newEntry.help = helpFunction

	return newEntry
end

function CommandEntry:Execute(args)
	if self.exec ~= nil then
		return self.exec(args)
	end

	return nil
end

function CommandEntry:PrintHelpText(commandName, printer)
	if self.help ~= nil then
		return self.help(commandName, printer)
	end

	return nil
end
-- End Class CommandEntry

-- Class RecordManager
local RecordManager = {
    keys = {},
    data = {},
}
RecordManager.__index = RecordManager

function RecordManager:new(dataStore)
    local newObj = {}
    setmetatable(newObj, RecordManager)

	self.keys = dataStore.keys
	self.data = dataStore.data

    return newObj
end

function RecordManager:CreateOrUpdate(key, value)
    if self.data[key] == nil then
        table.insert(self.keys, key)
		table.sort(value)
		self.data[key] = value
		return
    end

	local function checkExists(t, target)
		for _,item in pairs(t) do
			if item == target then return true end
		end
		return false
	end

	local data = self.data[key];
	for _,newEntry in pairs(value) do
		if checkExists(data, newEntry) == false then
			table.insert(data, newEntry)
		end
	end
	table.sort(data)
end

function RecordManager:GetData(key)
    return self.data[key]
end

function RecordManager:GetKeys()
    return self.keys
end
-- End Class RecordManager

-- *******************************
-- ********** Variables **********
-- *******************************
local _eventFrame = CreateFrame("Frame")
local _commandTable = {}
local _recordManager = nil

-- *******************************
-- ********** Functions **********
-- *******************************
local function CheckRank(printer)
	local _, _, rankIndex = GetGuildInfo("player")
	local flags = C_GuildInfo.GuildControlGetRankFlags(rankIndex)
	if flags ~= nil and flags[Constants.GuildControlPermissionFlags.ViewOfficerNote] == true then return true end

	printer:Print("* No officer note view permission.")
	return false
end

local function CheckRaid(printer)
	if IsInRaid() then return true end

	printer:Print("* Not in a raid.")
	return false
end

local function CanLogAttendance(printer)
	local hasPermissions = true

	printer:Print("Checking whether or not attendance can be logged...")
	printer:StartIndent()

	hasPermissions = CheckRank(printer) and hasPermissions
	hasPermissions = CheckRaid(printer) and hasPermissions

	printer:EndIndent()
	if hasPermissions then
		printer:Print("Attendance can be logged.")
	else
		printer:Print("Attendance cannot be logged. See above reasons.")
	end

	return hasPermissions
end

local function IsMainRank(rankName)
	for i=1,#Constants.RaiderRanks do
		if rankName == Constants.RaiderRanks[i] then
			return true
		end
	end

	return false
end

local function GetPlayerMainName(raiderName)
	local raiderNameFull = raiderName .. "-" .. GetRealmName()
	local _, numOnline = GetNumGuildMembers()
	for i=1,numOnline do
		local info = {GetGuildRosterInfo(i)}
		local playerName = info[Constants.GuildInfoIndex.Name]
		if playerName == raiderName or playerName == raiderNameFull then
			--print("FOUND! " .. raiderName .. " -- " .. tostring(IsMainRank(info[2])))
			if IsMainRank(info[Constants.GuildInfoIndex.RankName]) then
				-- Player is a main, this is their name.
				return raiderName
			end

			-- Player isn't main... find their main's name in the officer note.
			return info[Constants.GuildInfoIndex.OfficerNote]
		end
	end
end

local function IsValidGuildName(playerName)
	local playerNameFull = playerName .. "-" .. GetRealmName()
	local numGuildMembers = GetNumGuildMembers()
	for i=1,numGuildMembers do
		local info = {GetGuildRosterInfo(i)}
		if playerNameFull == info[Constants.GuildInfoIndex.Name] then return true end
	end

	return false
end

local function CollectPlayersInRaid(printer)
	local players = {}
	if not IsInRaid() then
		printer:Print("* ERROR: Not in a raid... this should have been checked already. Yell at Smellybeard.")
		return players
	end

	for i=1,MAX_RAID_MEMBERS do
		local raiderName = GetRaidRosterInfo(i)
		if raiderName == nil then break end

		local playerMainName = GetPlayerMainName(raiderName)
		if playerMainName == nil or playerMainName == "" then
			printer:Print("* WARNING: Skipping '" .. raiderName .. "'! Could not find their main name, check officer note!")
		elseif raiderName ~= playerMainName and not IsValidGuildName(playerMainName) then
			printer:Print("* WARNING: Skipping '" .. raiderName .. "'! Their main name, '" .. playerMainName .. "' is not a valid guild member name. Check officer note!")
		else
			table.insert(players, playerMainName)
		end
	end

	return players
end

local function LogAttendance(printer, key)
    printer:Print("Creating entry for: " .. key)

	-- Get list of players from the raid.
	printer:Print("Collecting players...")
	printer:StartIndent()
	local players = CollectPlayersInRaid(printer)
	printer:EndIndent()

	_recordManager:CreateOrUpdate(key, players)

	printer:Print("Attendance for " .. key .. " has been updated.")
end

function LoadSettings()
	if LegacyAttendanceSettings == nil then
		LegacyAttendanceSettings = {
			Records = {
				keys = {},
				data = {}
			}
		}
	end

	_recordManager = RecordManager:new(LegacyAttendanceSettings.Records)
end

-- ***************************************
-- ********** Command Functions **********
-- ***************************************

local function CommandHelp(args, badCommand)
	local printer = Printer:new()
	printer:AddonPrint(" Help")
	printer:StartIndent()

	if badCommand ~= nil then
		printer:Print("Command, " .. badCommand .. ", not recognized.")
	end

	printer:Print("Usage:")
	printer:StartIndent()
	for commandName,commandEntry in pairs(commandTable) do
		if commandEntry.help ~= nil then
			commandEntry:PrintHelpText(commandName, Printer:new(printer))
		end
	end
end

local function CommandHelpHelp(commandName, printer)
	printer:Print("* "..commandName)
	printer:StartIndent()
	printer:Print("Shows usage for "..Constants.AddonName..".")
end

local function CommandLog(args)
    local printer = Printer:new()
    printer:AddonPrint("Log")
    printer:StartIndent()

	if not CanLogAttendance(printer) then return end

	-- GT_TODO: Uncomment for debugging.
    --local key = args ~= nil and args[1] or date(Constants.DateFormat)
	local key = date(Constants.DateFormat)
	
	LogAttendance(printer, key)
end

local function CommandLogHelp(commandName, printer)
    printer:Print("* "..commandName)
    printer:StartIndent()
    printer:Print("Creates a record for today with the current raid members. If a record exists, new players will be added to it.")
end

local function CommandGet(args)
    local printer = Printer:new()
    printer:AddonPrint("Get")
    printer:StartIndent()

	local keys = _recordManager:GetKeys()
	if keys == nil or #keys == 0 then
		printer:Print("* ERROR: No data, log some raids!")
		return
	end
	table.sort(keys)

	if args == nil or #args == 0 or args[1] == "all" then
		printer:Print("Available Records:")
		printer:StartIndent()

		for _,key in pairs(keys) do
			local dataMsg = key;

			if args ~= nil and args[1] == "all" then
				local data = _recordManager:GetData(key)
				if data == nil then
					dataMsg = "ERROR: No data at key, " .. key .. "."
				else
					dataMsg = dataMsg .. "; "
					for i=1,#data do
						if i ~= 1 then
							dataMsg = dataMsg .. ", "
						end
						dataMsg = dataMsg .. data[i]
					end
				end
			end

			printer:Print("* " .. dataMsg)
		end
	else
		local key = args[1] == "today" and date(Constants.DateFormat) or args[1]
		printer:Print("Retrieving record for: " .. key)
		printer:StartIndent()
		local data = _recordManager:GetData(key)
		if data == nil then
			printer:Print("* No record found!")
			return
		end
		local dataMsg = key .. "; "
		for i=1,#data do
			if i ~= 1 then
				dataMsg = dataMsg .. ", "
			end
			dataMsg = dataMsg .. data[i]
		end
		printer:Print("* " .. dataMsg)
	end
end

local function CommandGetHelp(commandName, printer)
    printer:Print("* "..commandName)
    printer:StartIndent()
    printer:Print("Retrieves stored data. If no arguments are supplied, all records will be listed. Otherwise, supply a date (or 'today') to see the record for that entry. Alternatively, use 'all' to show all data for all records.")
end

local function CommandReset(args)
	local printer = Printer:new()
    printer:AddonPrint("Reset")
    printer:StartIndent()

	LegacyAttendanceSettings = nil
	LoadSettings()

	printer:Print("* Settings and data have been reset.")
end

local function CommandResetHelp(commandName, printer)
    printer:Print("* "..commandName)
    printer:StartIndent()
    printer:Print("Clears all data and resets the addon's settings state.")
end

-- **************************
-- ********** MAIN **********
-- **************************

commandTable = {
	[Constants.Commands.Help] = CommandEntry:new(CommandHelp, CommandHelpHelp),
    [Constants.Commands.Log] = CommandEntry:new(CommandLog, CommandLogHelp),
	[Constants.Commands.Get] = CommandEntry:new(CommandGet, CommandGetHelp),
	[Constants.Commands.Reset] = CommandEntry:new(CommandReset, CommandResetHelp)
}

SLASH_LEGACYATTENDANCE1 = "/" .. Constants.AddonName
SLASH_LEGACYATTENDANCE2 = "/" .. Constants.AddonAbbreviation
SlashCmdList["LEGACYATTENDANCE"] = function(msg)
	local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)")
	local args = args and { strsplit(" ", args) } or nil
	if args ~= nil and #args == 1 and args[1] == "" then args = nil end

	if cmd ~= nil then
		local command = commandTable[string.lower(cmd)]
		if command ~= nil then
			command:Execute(args)
		else
			CommandHelp(args, cmd)
		end
	else
		CommandHelp(args)
	end
end

local _eventHandlers = {
    [Constants.GlobalEvents.PlayerLogin] = function(args)
		LoadSettings()
    end,
}

_eventFrame:RegisterEvent(Constants.GlobalEvents.PlayerLogin)
_eventFrame:SetScript(
	"OnEvent",
	function(self, event, ...)
		local args = {...}
		local handler = _eventHandlers[event]
		if handler ~= nil then
			handler(args)
		else
			print("Unhandled event: " .. event)
		end
	end
)