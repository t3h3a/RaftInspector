-- RAFT INSPECTOR V6
-- Resource Discovery + Auto Collect Test

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local old = pg:FindFirstChild("RaftInspectorV6")
if old then old:Destroy() end

if getgenv and getgenv().RaftV6Stop then
    pcall(getgenv().RaftV6Stop)
end

local scanning = false
local auto = false
local connections = {}
local candidates = {}
local logs = {}

local keywords = {
    "wood", "metal", "iron", "scrap",
    "barrel", "crate", "plank", "log",
    "resource", "loot", "pickup",
    "supply", "chest"
}

local function log(message)
    table.insert(logs, string.format(
        "[%.2f] %s", os.clock(), tostring(message)
    ))

    if #logs > 400 then
        table.remove(logs, 1)
    end
end

local function root()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function tool()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Tool")
end

local function equipHarpoon()
    local c = player.Character
    local h = humanoid()
    if not c or not h then return false end

    local current = tool()
    if current and current.Name:lower():find("harpoon") then
        return true
    end

    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return false end

    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool")
            and item.Name:lower():find("harpoon") then
            h:EquipTool(item)
            return true
        end
    end

    return false
end

local function isResourceName(name)
    name = tostring(name):lower()

    for _, word in ipairs(keywords) do
        if name:find(word, 1, true) then
            return true
        end
    end

    return false
end

local function ignored(obj)
    if not obj or not obj:IsDescendantOf(workspace) then
        return true
    end

    local c = player.Character
    if c and obj:IsDescendantOf(c) then
        return true
    end

    local rafts = workspace:FindFirstChild("Rafts")
    if rafts and obj:IsDescendantOf(rafts) then
        return true
    end

    local visuals = workspace:FindFirstChild("LocalHarpoonVisuals")
    if visuals and obj:IsDescendantOf(visuals) then
        return true
    end

    if obj.Name == "HarpoonProjectile" then
        return true
    end

    return false
end

local function findCandidates()
    local r = root()
    if not r then return end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not ignored(obj) then
            local model = obj:FindFirstAncestorOfClass("Model")

            local match =
                isResourceName(obj.Name)
                or (model and isResourceName(model.Name))

            if match then
                local distance = (r.Position - obj.Position).Magnitude

                if distance <= 500 then
                    if not candidates[obj] then
                        candidates[obj] = true

                        log(
                            "RESOURCE CANDIDATE: " ..
                            obj:GetFullName() ..
                            " | DIST=" .. math.floor(distance)
                        )
                    end
                end
            end
        end
    end
end

-- GUI

local gui = Instance.new("ScreenGui")
gui.Name = "RaftInspectorV6"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(370, 440)
frame.Position = UDim2.new(0.5, -185, 0.5, -220)
frame.BackgroundColor3 = Color3.fromRGB(18, 23, 38)
frame.Active = true
frame.Draggable = true
frame.Parent = gui

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local function button(name, y, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(340, 39)
    b.Position = UDim2.fromOffset(15, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.Text = name
    b.Parent = frame

    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    return b
end

local title = Instance.new("TextLabel")
title.Size = UDim2.fromOffset(340, 35)
title.Position = UDim2.fromOffset(15, 8)
title.BackgroundTransparency = 1
title.Text = "RAFT INSPECTOR V6"
title.TextColor3 = Color3.fromRGB(100, 210, 255)
title.TextSize = 19
title.Font = Enum.Font.GothamBold
title.Parent = frame

local test = button("TEST SCRIPT", 50, Color3.fromRGB(50, 105, 180))
local scan = button("SCAN RESOURCES", 96, Color3.fromRGB(45, 145, 100))
local collect = button("AUTO COLLECT: OFF", 142, Color3.fromRGB(130, 85, 190))
local stop = button("STOP ALL", 188, Color3.fromRGB(180, 65, 70))
local copy = button("COPY REPORT", 234, Color3.fromRGB(60, 115, 170))

local output = Instance.new("TextBox")
output.Size = UDim2.fromOffset(340, 105)
output.Position = UDim2.fromOffset(15, 285)
output.BackgroundColor3 = Color3.fromRGB(8, 13, 23)
output.TextColor3 = Color3.fromRGB(120, 255, 170)
output.Font = Enum.Font.Code
output.TextSize = 12
output.TextWrapped = true
output.MultiLine = true
output.TextEditable = false
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.Text = "READY"
output.Parent = frame

local close = button("CLOSE", 397, Color3.fromRGB(75, 75, 90))

local function refresh()
    local startIndex = math.max(1, #logs - 7)
    local recent = {}

    for i = startIndex, #logs do
        table.insert(recent, logs[i])
    end

    output.Text = table.concat(recent, "\n")
end

local function testScript()
    log("===== TEST =====")
    log("PLACE ID: " .. game.PlaceId)
    log("ROOT: " .. tostring(root() ~= nil))
    log("HUMANOID: " .. tostring(humanoid() ~= nil))
    log("EQUIPPED: " .. tostring(equipHarpoon()))

    local t = tool()
    log("TOOL: " .. (t and t.Name or "NONE"))

    local visuals = workspace:FindFirstChild("LocalHarpoonVisuals")
    log("LOCAL VISUALS: " .. tostring(visuals ~= nil))

    if visuals then
        for _, obj in ipairs(visuals:GetChildren()) do
            log("VISUAL: " .. obj.Name)
        end
    end

    log("CLIPBOARD: " .. tostring(type(setclipboard) == "function"))
    log("TEST COMPLETE")
    refresh()
end

test.MouseButton1Click:Connect(testScript)

scan.MouseButton1Click:Connect(function()
    if scanning then return end

    scanning = true
    log("SCAN STARTED")

    task.spawn(function()
        for i = 1, 30 do
            if not scanning then break end

            pcall(findCandidates)
            refresh()
            task.wait(1)
        end

        scanning = false

        local count = 0
        for obj in pairs(candidates) do
            if obj.Parent then count = count + 1 end
        end

        log("SCAN FINISHED | CANDIDATES=" .. count)
        refresh()
    end)
end)

local function nearestCandidate()
    local r = root()
    if not r then return nil end

    local best
    local bestDistance = math.huge

    for obj in pairs(candidates) do
        if obj.Parent and not ignored(obj) then
            local distance = (r.Position - obj.Position).Magnitude

            if distance < bestDistance then
                best = obj
                bestDistance = distance
            end
        end
    end

    return best, bestDistance
end

collect.MouseButton1Click:Connect(function()
    auto = not auto

    collect.Text = auto
        and "AUTO COLLECT: ON"
        or "AUTO COLLECT: OFF"

    if not auto then
        log("AUTO STOPPED")
        refresh()
        return
    end

    log("AUTO STARTED")
    equipHarpoon()

    task.spawn(function()
        while auto do
            pcall(findCandidates)

            local target, distance = nearestCandidate()
            local h = humanoid()
            local t = tool()

            if target and h and distance then
                log("TARGET: " .. target.Name ..
                    " | DIST=" .. math.floor(distance))

                -- Move normally toward detected candidate.
                -- Does not teleport or bypass server movement checks.
                if distance > 18 then
                    h:MoveTo(target.Position)
                else
                    if t and t.Name:lower():find("harpoon") then
                        pcall(function()
                            t:Activate()
                        end)
                        log("HARPOON ACTIVATED")
                    end
                end
            else
                log("NO VERIFIED RESOURCE TARGET")
            end

            refresh()
            task.wait(0.5)
        end
    end)
end)

stop.MouseButton1Click:Connect(function()
    scanning = false
    auto = false
    collect.Text = "AUTO COLLECT: OFF"

    local h = humanoid()
    local r = root()
    if h and r then h:MoveTo(r.Position) end

    log("STOPPED")
    refresh()
end)

table.insert(connections,
    workspace.DescendantAdded:Connect(function(obj)
        if obj.Name == "HarpoonProjectile" then
            log("HARPOON PROJECTILE CREATED")
            refresh()
        elseif obj.Name == "LocalHarpoonVisuals" then
            log("LOCAL VISUALS CREATED")
            refresh()
        elseif obj:IsA("BasePart")
            and isResourceName(obj.Name) then
            log("POSSIBLE RESOURCE ADDED: " .. obj:GetFullName())
            refresh()
        end
    end)
)

copy.MouseButton1Click:Connect(function()
    local report = {
        "RAFT INSPECTOR V6 REPORT",
        "PLACE ID: " .. game.PlaceId,
        "TOOL: " .. (tool() and tool().Name or "NONE"),
        "===== LOGS =====",
        table.concat(logs, "\n")
    }

    if type(setclipboard) == "function" then
        local ok = pcall(
            setclipboard,
            table.concat(report, "\n")
        )

        copy.Text = ok and "COPIED!" or "COPY FAILED"
    end
end)

local function cleanup()
    auto = false
    scanning = false

    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end

    gui:Destroy()
end

if getgenv then
    getgenv().RaftV6Stop = cleanup
end

close.MouseButton1Click:Connect(cleanup)

log("RAFT INSPECTOR V6 LOADED")
refresh()
