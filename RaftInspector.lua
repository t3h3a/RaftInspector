--[[
    RAFT INSPECTOR V5
    Build and Defend Your Raft
    30 Second Diagnostic Scanner
]]

--====================================
-- SERVICES
--====================================

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

--====================================
-- CLEAN OLD INSTANCE
--====================================

local previousGUI = pg:FindFirstChild("RaftInspectorV5")

if previousGUI then
    previousGUI:Destroy()
end

-- Stop previous script connections if rerun
if getgenv then
    local env = getgenv()

    if env.RaftInspectorV5Cleanup then
        pcall(env.RaftInspectorV5Cleanup)
    end
end

--====================================
-- SETTINGS
--====================================

local DURATION = 30
local RANGE = 250
local INTERVAL = 0.4
local MAX_LOGS = 300

local keywords = {
    "wood",
    "metal",
    "iron",
    "steel",
    "scrap",
    "loot",
    "chest",
    "crate",
    "barrel",
    "resource",
    "pickup",
    "floating",
    "plank",
    "log",
    "supply",
    "treasure",
    "drop",
    "harpoon"
}

--====================================
-- STATE
--====================================

local running = false
local scanID = 0
local timeLeft = DURATION

local seen = {}
local nearbyPrevious = {}

local logs = {
    Resources = {},
    Events = {},
    Targets = {},
    Test = {}
}

local stats = {
    clicks = 0,
    resources = 0,
    targets = 0,
    appeared = 0,
    disappeared = 0
}

local connections = {}
local currentTab = "Resources"
local minimized = false

--====================================
-- HELPERS
--====================================

local function timestamp()
    return string.format("%.2f", os.clock())
end

local function addLog(category, message)
    local list = logs[category]

    if not list then
        return
    end

    if #list >= MAX_LOGS then
        return
    end

    table.insert(
        list,
        "[" .. timestamp() .. "] " .. tostring(message)
    )
end

local function safePath(obj)
    if not obj then
        return "<none>"
    end

    local ok, result = pcall(function()
        return obj:GetFullName()
    end)

    return ok and result or "<unavailable>"
end

local function getCharacter()
    return player.Character
end

local function getRoot()
    local character = getCharacter()

    return character and
        character:FindFirstChild("HumanoidRootPart")
end

local function getTool()
    local character = getCharacter()

    return character and
        character:FindFirstChildOfClass("Tool")
end

local function toolName()
    local tool = getTool()

    return tool and tool.Name or "<none>"
end

local function isIgnored(obj)
    if not obj then
        return true
    end

    local character = getCharacter()

    if character and obj:IsDescendantOf(character) then
        return true
    end

    local current = obj

    while current and current ~= workspace do
        if current.Name == "Rafts" then
            return true
        end

        current = current.Parent
    end

    return false
end

local function matchesResource(name)
    name = string.lower(tostring(name))

    for _, word in ipairs(keywords) do
        if string.find(name, word, 1, true) then
            return true
        end
    end

    return false
end

local function getDistance(part)
    local root = getRoot()

    if not root or not part then
        return -1
    end

    return math.floor(
        (root.Position - part.Position).Magnitude
    )
end

local function describeObject(obj)
    if not obj then
        return "<none>"
    end

    return
        "NAME: " .. obj.Name ..
        "\nCLASS: " .. obj.ClassName ..
        "\nPATH: " .. safePath(obj)
end

--====================================
-- GUI
--====================================

local gui = Instance.new("ScreenGui")
gui.Name = "RaftInspectorV5"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(390, 510)
frame.Position = UDim2.new(0.5, -195, 0.5, -255)
frame.BackgroundColor3 = Color3.fromRGB(18, 23, 38)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = frame

local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(75, 125, 210)
border.Thickness = 1.5
border.Parent = frame

local function createLabel(text, x, y, w, h, size, color)
    local label = Instance.new("TextLabel")

    label.Position = UDim2.fromOffset(x, y)
    label.Size = UDim2.new(w, 0, 0, h)

    label.BackgroundTransparency = 1
    label.Text = text
    label.TextSize = size or 14
    label.Font = Enum.Font.GothamBold

    label.TextColor3 =
        color or Color3.fromRGB(240, 245, 255)

    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    return label
end

local function createButton(text, x, y, w, h, color)
    local button = Instance.new("TextButton")

    button.Position = UDim2.fromOffset(x, y)
    button.Size = UDim2.fromOffset(w, h)

    button.BackgroundColor3 = color
    button.BorderSizePixel = 0

    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 13
    button.Font = Enum.Font.GothamBold

    button.Parent = frame

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = button

    return button
end

--====================================
-- HEADER
--====================================

local title = createLabel(
    "RAFT INSPECTOR V5",
    15, 10, 280, 30, 19,
    Color3.fromRGB(115, 200, 255)
)

local minimize = createButton(
    "-", 310, 10, 30, 30,
    Color3.fromRGB(70, 85, 115)
)

local close = createButton(
    "X", 347, 10, 30, 30,
    Color3.fromRGB(190, 55, 70)
)

local status = createLabel(
    "STATUS: READY",
    15, 50, 350, 25, 14,
    Color3.fromRGB(100, 255, 165)
)

local timer = createLabel(
    "TIME: 30s",
    15, 82, 150, 25, 16,
    Color3.fromRGB(255, 220, 110)
)

local counter = createLabel(
    "Clicks: 0 | Resources: 0",
    165, 82, 210, 25, 12
)

--====================================
-- CONTROL BUTTONS
--====================================

local start = createButton(
    "START",
    12, 120, 115, 40,
    Color3.fromRGB(35, 150, 95)
)

local stop = createButton(
    "STOP",
    137, 120, 115, 40,
    Color3.fromRGB(185, 65, 70)
)

local reset = createButton(
    "RESET",
    262, 120, 115, 40,
    Color3.fromRGB(75, 95, 145)
)

--====================================
-- TABS
--====================================

local tabResources = createButton(
    "RESOURCES",
    12, 175, 115, 34,
    Color3.fromRGB(45, 115, 190)
)

local tabEvents = createButton(
    "EVENTS",
    137, 175, 115, 34,
    Color3.fromRGB(55, 65, 90)
)

local tabTargets = createButton(
    "TARGETS",
    262, 175, 115, 34,
    Color3.fromRGB(55, 65, 90)
)

local tabTest = createButton(
    "TEST",
    12, 219, 115, 34,
    Color3.fromRGB(55, 65, 90)
)

local runTest = createButton(
    "RUN TEST",
    137, 219, 240, 34,
    Color3.fromRGB(75, 105, 165)
)

--====================================
-- OUTPUT
--====================================

local output = Instance.new("TextBox")

output.Position = UDim2.fromOffset(12, 265)
output.Size = UDim2.fromOffset(366, 175)

output.BackgroundColor3 = Color3.fromRGB(9, 14, 25)
output.BorderSizePixel = 0

output.TextColor3 = Color3.fromRGB(135, 255, 180)
output.TextSize = 12
output.Font = Enum.Font.Code

output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top

output.TextWrapped = true
output.MultiLine = true
output.TextEditable = true
output.ClearTextOnFocus = false

output.Text = "READY. Press START to scan."

output.Parent = frame

Instance.new("UICorner", output).CornerRadius =
    UDim.new(0, 8)

local copy = createButton(
    "COPY ALL REPORT",
    12, 451, 280, 44,
    Color3.fromRGB(95, 75, 200)
)

local copyTab = createButton(
    "COPY TAB",
    302, 451, 76, 44,
    Color3.fromRGB(55, 115, 165)
)

--====================================
-- DISPLAY
--====================================

local function refresh()
    if not gui.Parent then
        return
    end

    local list = logs[currentTab]

    output.Text = #list > 0
        and table.concat(list, "\n\n")
        or "No results yet."

    counter.Text =
        "Clicks: " .. stats.clicks ..
        " | Resources: " .. stats.resources
end

local function selectTab(name)
    currentTab = name

    local buttons = {
        Resources = tabResources,
        Events = tabEvents,
        Targets = tabTargets,
        Test = tabTest
    }

    for tabName, button in pairs(buttons) do
        button.BackgroundColor3 =
            tabName == name
            and Color3.fromRGB(45, 115, 190)
            or Color3.fromRGB(55, 65, 90)
    end

    refresh()
end

tabResources.MouseButton1Click:Connect(function()
    selectTab("Resources")
end)

tabEvents.MouseButton1Click:Connect(function()
    selectTab("Events")
end)

tabTargets.MouseButton1Click:Connect(function()
    selectTab("Targets")
end)

tabTest.MouseButton1Click:Connect(function()
    selectTab("Test")
end)

--====================================
-- RAYCAST TARGET
--====================================

local function inspectRay()
    local root = getRoot()
    local cam = workspace.CurrentCamera

    if not root or not cam then
        return
    end

    local mousePos = UIS:GetMouseLocation()

    local ray = cam:ViewportPointToRay(
        mousePos.X,
        mousePos.Y
    )

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local exclusions = {}

    if player.Character then
        table.insert(exclusions, player.Character)
    end

    local rafts = workspace:FindFirstChild("Rafts")

    if rafts then
        table.insert(exclusions, rafts)
    end

    params.FilterDescendantsInstances = exclusions

    local result = workspace:Raycast(
        ray.Origin,
        ray.Direction * 500,
        params
    )

    if result then
        local obj = result.Instance

        stats.targets = stats.targets + 1

        addLog(
            "Targets",
            "RAYCAST HIT\n" ..
            describeObject(obj) ..
            "\nPOSITION: " .. tostring(result.Position) ..
            "\nDISTANCE: " .. getDistance(obj)
        )
    else
        addLog(
            "Targets",
            "RAYCAST: NO HIT"
        )
    end
end

--====================================
-- OBJECT SCANNER
--====================================

local function scanObjects()
    local root = getRoot()

    if not root then
        addLog("Events", "ROOT NOT FOUND")
        return
    end

    local ok, parts = pcall(function()
        return workspace:GetPartBoundsInRadius(
            root.Position,
            RANGE
        )
    end)

    if not ok then
        addLog("Events", "SPATIAL QUERY FAILED")
        return
    end

    local current = {}

    for _, part in ipairs(parts) do
        if part:IsA("BasePart") and not isIgnored(part) then
            local model = part:FindFirstAncestorOfClass("Model")
            local obj = model or part

            if not isIgnored(obj) then
                current[obj] = true

                if not seen[obj] then
                    seen[obj] = true

                    stats.appeared = stats.appeared + 1

                    local info =
                        describeObject(obj) ..
                        "\nPART: " .. part.Name ..
                        "\nDISTANCE: " .. getDistance(part)

                    if matchesResource(obj.Name)
                        or matchesResource(part.Name) then

                        stats.resources = stats.resources + 1

                        addLog(
                            "Resources",
                            "POSSIBLE RESOURCE\n" .. info
                        )
                    else
                        addLog(
                            "Events",
                            "OBJECT DISCOVERED\n" .. info
                        )
                    end
                end
            end
        end
    end

    for obj in pairs(nearbyPrevious) do
        if not current[obj] then
            stats.disappeared = stats.disappeared + 1

            local removed = obj.Parent == nil

            addLog(
                "Events",
                (removed and "REMOVED: " or "LEFT RANGE: ") ..
                obj.Name ..
                "\nPATH: " .. safePath(obj)
            )
        end
    end

    nearbyPrevious = current
end

--====================================
-- OBJECT CHANGE TRACKER
--====================================

local function trackAdded(obj)
    if not running then
        return
    end

    if not obj:IsA("BasePart") then
        return
    end

    if isIgnored(obj) then
        return
    end

    local root = getRoot()

    if not root then
        return
    end

    local distance = getDistance(obj)

    if distance < 0 or distance > RANGE then
        return
    end

    addLog(
        "Events",
        "NEW PART\n" ..
        describeObject(obj) ..
        "\nDISTANCE: " .. distance
    )
end

local function trackRemoving(obj)
    if not running then
        return
    end

    if not obj:IsA("BasePart") then
        return
    end

    if isIgnored(obj) then
        return
    end

    addLog(
        "Events",
        "PART REMOVING\n" ..
        describeObject(obj)
    )
end

table.insert(
    connections,
    workspace.DescendantAdded:Connect(trackAdded)
)

table.insert(
    connections,
    workspace.DescendantRemoving:Connect(trackRemoving)
)

--====================================
-- HARPOON INPUT LOGGER
--====================================

table.insert(
    connections,
    UIS.InputBegan:Connect(function(input, processed)
        if not running then
            return
        end

        if input.UserInputType ==
            Enum.UserInputType.MouseButton1 then

            stats.clicks = stats.clicks + 1

            addLog(
                "Events",
                "LEFT CLICK #" .. stats.clicks ..
                "\nTOOL: " .. toolName() ..
                "\nPROCESSED: " .. tostring(processed)
            )

            inspectRay()
            refresh()
        end
    end)
)

--====================================
-- START / STOP
--====================================

local function stopScan()
    if not running then
        return
    end

    running = false
    scanID = scanID + 1

    status.Text = "STATUS: FINISHED"

    addLog(
        "Events",
        "SCAN FINISHED\n" ..
        "CLICKS: " .. stats.clicks ..
        "\nRESOURCES: " .. stats.resources ..
        "\nOBJECTS SEEN: " .. stats.appeared
    )

    refresh()
end

local function startScan()
    if running then
        return
    end

    running = true
    scanID = scanID + 1

    local myID = scanID

    timeLeft = DURATION
    status.Text = "STATUS: SCANNING..."

    addLog(
        "Events",
        "SCAN STARTED\n" ..
        "TOOL: " .. toolName() ..
        "\nRANGE: " .. RANGE
    )

    task.spawn(function()
        local started = os.clock()

        while running and scanID == myID do
            local elapsed = os.clock() - started

            timeLeft = math.max(
                0,
                math.ceil(DURATION - elapsed)
            )

            timer.Text = "TIME: " .. timeLeft .. "s"

            local ok, err = pcall(scanObjects)

            if not ok then
                addLog(
                    "Events",
                    "SCAN ERROR: " .. tostring(err)
                )
            end

            refresh()

            if elapsed >= DURATION then
                break
            end

            task.wait(INTERVAL)
        end

        if running and scanID == myID then
            stopScan()
        end
    end)
end

start.MouseButton1Click:Connect(startScan)
stop.MouseButton1Click:Connect(stopScan)

--====================================
-- RESET
--====================================

reset.MouseButton1Click:Connect(function()
    running = false
    scanID = scanID + 1

    seen = {}
    nearbyPrevious = {}

    logs = {
        Resources = {},
        Events = {},
        Targets = {},
        Test = {}
    }

    stats = {
        clicks = 0,
        resources = 0,
        targets = 0,
        appeared = 0,
        disappeared = 0
    }

    timeLeft = DURATION

    status.Text = "STATUS: READY"
    timer.Text = "TIME: 30s"

    refresh()
end)

--====================================
-- TEST PANEL
--====================================

runTest.MouseButton1Click:Connect(function()
    addLog("Test", "GUI: WORKING")
    addLog("Test", "PLACE ID: " .. game.PlaceId)
    addLog("Test", "TOOL: " .. toolName())
    addLog("Test", "ROOT: " .. tostring(getRoot() ~= nil))

    addLog(
        "Test",
        "CLIPBOARD: " ..
        tostring(type(setclipboard) == "function")
    )

    local ok = pcall(function()
        local root = getRoot()

        if root then
            workspace:GetPartBoundsInRadius(
                root.Position,
                20
            )
        end
    end)

    addLog(
        "Test",
        "SPATIAL QUERY: " ..
        (ok and "OK" or "FAILED")
    )

    selectTab("Test")
end)

--====================================
-- REPORT
--====================================

local function buildReport()
    local report = {}

    table.insert(report, "RAFT INSPECTOR V5 REPORT")
    table.insert(report, "PLACE ID: " .. game.PlaceId)
    table.insert(report, "SCAN DURATION: " .. DURATION)
    table.insert(report, "SCAN RANGE: " .. RANGE)
    table.insert(report, "TOOL: " .. toolName())

    table.insert(report, "\n===== SUMMARY =====")
    table.insert(report, "CLICKS: " .. stats.clicks)
    table.insert(report, "RESOURCES: " .. stats.resources)
    table.insert(report, "TARGET HITS: " .. stats.targets)
    table.insert(report, "OBJECTS SEEN: " .. stats.appeared)
    table.insert(report, "LEFT RANGE/REMOVED: " .. stats.disappeared)

    for _, category in ipairs({
        "Resources",
        "Events",
        "Targets",
        "Test"
    }) do
        table.insert(
            report,
            "\n===== " .. string.upper(category) .. " ====="
        )

        table.insert(
            report,
            table.concat(logs[category], "\n\n")
        )
    end

    return table.concat(report, "\n")
end

copy.MouseButton1Click:Connect(function()
    local report = buildReport()

    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, report)

        copy.Text = ok
            and "COPIED SUCCESSFULLY!"
            or "COPY FAILED"
    else
        output.Text = report
        copy.Text = "SELECT TEXT TO COPY"
    end
end)

copyTab.MouseButton1Click:Connect(function()
    local text = table.concat(
        logs[currentTab],
        "\n\n"
    )

    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, text)

        copyTab.Text = ok and "COPIED!" or "FAILED"
    else
        output.Text = text
    end
end)

--====================================
-- MINIMIZE
--====================================

local content = {
    status,
    timer,
    counter,
    start,
    stop,
    reset,
    tabResources,
    tabEvents,
    tabTargets,
    tabTest,
    runTest,
    output,
    copy,
    copyTab
}

minimize.MouseButton1Click:Connect(function()
    minimized = not minimized

    frame.Size = minimized
        and UDim2.fromOffset(390, 48)
        or UDim2.fromOffset(390, 510)

    for _, obj in ipairs(content) do
        obj.Visible = not minimized
    end

    minimize.Text = minimized and "+" or "-"
end)

--====================================
-- CLEANUP
--====================================

local function cleanup()
    running = false
    scanID = scanID + 1

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    if gui.Parent then
        gui:Destroy()
    end
end

if getgenv then
    getgenv().RaftInspectorV5Cleanup = cleanup
end

close.MouseButton1Click:Connect(cleanup)

--====================================
-- READY
--====================================

addLog("Test", "RAFT INSPECTOR V5 LOADED")
addLog("Test", "PRESS RUN TEST FIRST")

print("RAFT INSPECTOR V5 READY")
