--!nocheck
-- get the fuck out of here

local Players = game:GetService("Players")

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

--========================================================================
-- GAME LOGIC
--========================================================================

local function getItemRoots()
	local main = workspace:FindFirstChild("ItemSpawns")
	if main then
		return { main }
	end
	local found = workspace:FindFirstChild("ItemSpawns", true)
	if found then
		return { found }
	end
	return { workspace }
end

local function getFloorPart()
	local map = workspace:FindFirstChild("Map")
	local floor = map and map:FindFirstChild("FloorPart")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	local any = workspace:FindFirstChild("FloorPart", true)
	if any and any:IsA("BasePart") then
		return any
	end
	return nil
end

local function teleportAboveFloor(character, root)
	local floor = getFloorPart()
	if not floor then
		return false, "no FloorPart found"
	end

	local topY = floor.Position.Y + floor.Size.Y / 2
	local target = Vector3.new(floor.Position.X, topY + 8, floor.Position.Z)
	character:PivotTo(CFrame.new(target))
	root.AssemblyLinearVelocity = Vector3.zero
	if root.AssemblyAngularVelocity then
		root.AssemblyAngularVelocity = Vector3.zero
	end

	return true, target
end

local function collectItems(rarity)
	local items, seen = {}, {}

	for _, itemRoot in ipairs(getItemRoots()) do
		for _, descendant in ipairs(itemRoot:GetDescendants()) do
			if
				descendant:IsA("Model")
				and descendant.Name == "SpawnedItem"
				and not seen[descendant]
			then
				seen[descendant] = true

				local ok, value = pcall(descendant.GetAttribute, descendant, "Rarity")
				if ok and value == rarity then
					local prompt = descendant:FindFirstChild("GrabPrompt", true)
					if prompt and prompt:IsA("ProximityPrompt") then
						table.insert(items, { model = descendant, prompt = prompt })
					end
				end
			end
		end
	end

	return items
end

-- grab a single item: teleport and fire its prompt. Does NOT return to
local function grabOne(rarity)
	rarity = rarity or "Godly"

	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return false, "character has no HumanoidRootPart"
	end

	local candidates = collectItems(rarity)
	if #candidates == 0 then
		return false, ("no %s SpawnedItem found"):format(rarity)
	end

	for i = #candidates, 2, -1 do
		local j = math.random(i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	for _, entry in ipairs(candidates) do
		local model, prompt = entry.model, entry.prompt

		if model.Parent and prompt.Parent and prompt.Enabled then
			local target = model:GetPivot().Position
			local info = {
				rarity = model:GetAttribute("Rarity"),
				area = model:GetAttribute("AreaName"),
				objectText = prompt.ObjectText,
				position = target,
			}

			character:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
			root.AssemblyLinearVelocity = Vector3.zero
			if root.AssemblyAngularVelocity then
				root.AssemblyAngularVelocity = Vector3.zero
			end

			-- rq
			task.wait(0.25)

			if model.Parent then
				fireproximityprompt(prompt)
				task.wait(0.35)
			end

			if model.Parent == nil or not prompt.Enabled then
				return true, info
			end
		end
	end

	return false, ("found %d %s SpawnedItem(s) but none could be grabbed"):format(#candidates, rarity)
end

-- detect how many items player can carry (LocalPlayer.CarryLevel).
local function getCarryLevel()
	local level = tonumber(Players.LocalPlayer:GetAttribute("CarryLevel"))
	if not level or level < 1 then
		return 1
	end
	return math.floor(level)
end

local function grabBatch(rarity, count)
	count = math.max(1, math.floor(tonumber(count) or 1))

	local grabbed = {}

	for _ = 1, count do
		local ok, info = grabOne(rarity)
		if not ok then
			return #grabbed > 0, { collected = grabbed, failed = info }
		end
		table.insert(grabbed, info)
	end

	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local moved, spot = false, "character has no HumanoidRootPart"
	if root then
		moved, spot = teleportAboveFloor(character, root)
	end

	return true, {
		collected = grabbed,
		returnedTo = moved and spot or nil,
		returnError = (not moved) and spot or nil,
	}
end

--========================================================================
-- UI
--========================================================================

local RARITIES = { "Mythical", "Common", "Godly", "Epic", "Rare" }
local COOLDOWN_MIN = 1
local COOLDOWN_MAX = 5

local KEYBINDS = {
	"RightShift",
	"LeftShift",
	"K",
	"J",
	"Z",
	"X",
	"C",
	"V",
	"F1",
	"F2",
	"Insert",
	"Delete",
	"Home",
	"End",
	"PageUp",
	"PageDown",
}

local state = {
	rarity = "Godly",
	cooldown = 3,
	autoFarm = false,
	runId = 0,
	theme = "Dark",
}

local Window = WindUI:CreateWindow({
	Title = "R1zz hub",
	Author = "i love 67 phonk",
	Icon = "box",
	Folder = "SigmaRizzHub",
	Size = UDim2.fromOffset(460, 420),
	Theme = "Amber",
	ToggleKey = Enum.KeyCode.RightShift,
})

local FarmTab = Window:Tab({
	Title = "Farm",
	Icon = "sparkles",
})

FarmTab:Dropdown({
	Title = "Rarity",
	Desc = "Which rarity to grab?",
	Values = RARITIES,
	Value = state.rarity,
	Callback = function(selected)
		if type(selected) == "string" then
			state.rarity = selected
		end
	end,
})

FarmTab:Slider({
	Title = "Cooldown",
	Desc = "the time before going again",
	Value = {
		Min = COOLDOWN_MIN,
		Max = COOLDOWN_MAX,
		Default = state.cooldown,
	},
	Step = 0.5,
	Callback = function(value)
		if type(value) == "number" then
			state.cooldown = math.clamp(value, COOLDOWN_MIN, COOLDOWN_MAX)
		end
	end,
})

local function stopAutoFarm()
	state.autoFarm = false
	state.runId += 1
end

local function autoFarmLoop(runId)
	while state.autoFarm and state.runId == runId do
		local carryLevel = getCarryLevel()
		local ok, info = grabBatch(state.rarity, carryLevel)

		if state.runId ~= runId or not state.autoFarm then
			return
		end

		if ok then
			local collected = info.collected or {}
			WindUI:Notify({
				Title = ("%dx %s grabbed"):format(#collected, state.rarity),
				Content = ("carry level %d%s"):format(
					carryLevel,
					info.failed and (" - stopped early: " .. tostring(info.failed)) or ""
				),
				Duration = 2.5,
				Icon = "gem",
			})
		else
			warn(("[godly] %s"):format(tostring(info.failed or info)))
		end

		local waited = 0
		while waited < state.cooldown and state.autoFarm and state.runId == runId do
			local step = math.min(0.1, state.cooldown - waited)
			task.wait(step)
			waited += step
		end
	end
end

FarmTab:Toggle({
	Title = "Auto Farm Lucky Block",
	Desc = "automatically grabs blocks of selected rarity and tps back",
	Value = false,
	Callback = function(on)
		if on then
			state.autoFarm = true
			state.runId += 1
			task.spawn(autoFarmLoop, state.runId)
		else
			stopAutoFarm()
		end
	end,
})

--========================================================================
-- UI SETTINGS TAB
--========================================================================

local UiTab = Window:Tab({
	Title = "UI",
	Icon = "palette",
})

-- WindUI:GetThemes() is documented as a table of theme names; normalise it in
-- case it comes back keyed instead of as an array.
local themeValues = {}
do
	local ok, themes = pcall(function()
		return WindUI:GetThemes()
	end)
	if ok and type(themes) == "table" then
		for key, value in pairs(themes) do
			if type(key) == "number" then
				table.insert(themeValues, tostring(value))
			else
				table.insert(themeValues, tostring(key))
			end
		end
	end
	if #themeValues == 0 then
		themeValues = { "Dark", "Light" }
	end
	table.sort(themeValues)
end

-- Theme switching lives on the WindUI object, not on the window. The window
-- only has SetUIScale / SetBackgroundTransparency / SetToggleKey in this
-- build, so `Window:SetTheme` was a nil call and silently did nothing.
local function hasTheme(name)
	for _, value in ipairs(themeValues) do
		if value == name then
			return true
		end
	end
	return false
end

local function applyTheme(name)
	if type(name) == "table" then
		name = name.Title or name[1]
	end
	if type(name) ~= "string" then
		return false, "theme name must be a string"
	end

	local ok, result = pcall(function()
		return WindUI:SetTheme(name)
	end)

	if not ok then
		warn(("[sigma] theme %q failed: %s"):format(name, tostring(result)))
		return false, result
	end
	if result == nil then
		warn(("[sigma] unknown theme %q"):format(name))
		return false, "unknown theme"
	end

	state.theme = name
	return true
end

local initialTheme = "Amber"
if not hasTheme(initialTheme) then
	initialTheme = themeValues[1] or "Dark"
end
applyTheme(initialTheme)

local themeDropdown = UiTab:Dropdown({
	Title = "Theme",
	Desc = "WindUI colour theme",
	Values = themeValues,
	Value = initialTheme,
	Callback = function(selected)
		if applyTheme(selected) then
			WindUI:Notify({
				Title = "loaded",
				Content = "pls like my script in scriptblox",
				Duration = 2.5,
				Icon = "palette",
			})
		end
	end,
})

UiTab:Slider({
	Title = "UI Scale",
	Desc = "Scales the whole window",
	Value = { Min = 0.7, Max = 1.4, Default = 1 },
	Step = 0.05,
	Callback = function(value)
		if type(value) == "number" then
			Window:SetUIScale(value)
		end
	end,
})

UiTab:Slider({
	Title = "Window Transparency",
	Desc = "0 = opaque, 0.8 = nearly invisible",
	Value = { Min = 0, Max = 0.8, Default = 0 },
	Step = 0.05,
	Callback = function(value)
		if type(value) == "number" then
			Window:SetBackgroundTransparency(value)
		end
	end,
})

UiTab:Toggle({
	Title = "Acrylic Blur",
	Desc = "Requires graphics +3",
	Value = false,
	Callback = function(on)
		WindUI:ToggleAcrylic(on)
	end,
})

UiTab:Toggle({
	Title = "Lower Notifications",
	Desc = "Move notifications away from the jump button",
	Value = false,
	Callback = function(on)
		WindUI:SetNotificationLower(on)
	end,
})

UiTab:Dropdown({
	Title = "Menu Keybind",
	Desc = "Key that hides/shows the window",
	Values = KEYBINDS,
	Value = "RightShift",
	Callback = function(selected)
		local ok, keyCode = pcall(function()
			return Enum.KeyCode[selected]
		end)
		if ok and keyCode then
			Window:SetToggleKey(keyCode)
		end
	end,
})

-- Exposed for testing / console use.
return {
	grabOne = grabOne,
	grabBatch = grabBatch,
	getCarryLevel = getCarryLevel,
	autoFarmLoop = autoFarmLoop,
	applyTheme = applyTheme,
	themeDropdown = themeDropdown,
	state = state,
	Window = Window,
	WindUI = WindUI,
}
