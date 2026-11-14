-- Raft Inspector | client-visible diagnostics only
-- Upload this file to a public GitHub repository and use its Raw URL.
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer
if not player then return end
local pg = player:WaitForChild('PlayerGui')
local old = pg:FindFirstChild('RaftInspectorFinal')
if old then old:Destroy() end

local DURATION, RANGE, INTERVAL, LIMIT = 30, 220, 0.75, 250
local words = {'wood','metal','iron','steel','scrap','loot','chest','crate','barrel','resource','pickup','floating','plank','log','supply','treasure','drop'}
local logs = {Resources={}, Events={}, Others={}, Test={}}
local seen, last = {}, {}
local running, generation, clicks, remaining, tab = false, 0, 0, DURATION, 'Resources'
local alive = true
local function record(section, message)
    local a=logs[section]
    if #a<LIMIT then a[#a+1]=string.format('[%.1f] %s',os.clock(),tostring(message)) end
end
local function safePath(x)
    local ok,v=pcall(function() return x:GetFullName() end)
    return ok and v or '<removed>'
end
local function ignored(x)
    local char=player.Character
    if char and x:IsDescendantOf(char) then return true end
    local p=x
    while p and p~=workspace do
        if p.Name=='Rafts' then return true end
        p=p.Parent
    end
    return false
end
local function candidate(name)
    name=string.lower(name)
    for _,w in ipairs(words) do if string.find(name,w,1,true) then return true end end
    return false
end
local function toolName()
    local c=player.Character
    local t=c and c:FindFirstChildOfClass('Tool')
    return t and t.Name or '<none>'
end
local function report()
    local a={'RAFT INSPECTOR REPORT','PlaceId: '..tostring(game.PlaceId),'Scan duration: '..DURATION..'s','Range: '..RANGE,'Clicks observed: '..clicks,'Current tool: '..toolName()}
    for _,section in ipairs({'Resources','Events','Others','Test'}) do
        a[#a+1]='\n===== '..string.upper(section)..' ('..#logs[section]..') ====='
        for _,v in ipairs(logs[section]) do a[#a+1]=v end
    end
    return table.concat(a,'\n')
end

local gui=Instance.new('ScreenGui')
gui.Name='RaftInspectorFinal';gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=999;gui.Parent=pg
local frame=Instance.new('Frame')
frame.Size=UDim2.fromOffset(370,465);frame.Position=UDim2.new(.5,-185,.5,-232)
frame.BackgroundColor3=Color3.fromRGB(20,26,42);frame.BorderSizePixel=0;frame.Active=true;frame.Parent=gui
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,13)
local border=Instance.new('UIStroke',frame);border.Color=Color3.fromRGB(76,135,210);border.Thickness=1
local function label(text,x,y,w,h,size)
    local z=Instance.new('TextLabel');z.BackgroundTransparency=1;z.Position=UDim2.fromOffset(x,y);z.Size=UDim2.fromOffset(w,h)
    z.Text=text;z.TextColor3=Color3.fromRGB(230,240,255);z.TextSize=size or 13;z.Font=Enum.Font.GothamBold
    z.TextXAlignment=Enum.TextXAlignment.Left;z.Parent=frame;return z
end
local function button(text,x,y,w,h,color)
    local z=Instance.new('TextButton');z.Position=UDim2.fromOffset(x,y);z.Size=UDim2.fromOffset(w,h)
    z.Text=text;z.TextSize=12;z.Font=Enum.Font.GothamBold;z.TextColor3=Color3.new(1,1,1)
    z.BackgroundColor3=color or Color3.fromRGB(58,78,116);z.Parent=frame
    Instance.new('UICorner',z).CornerRadius=UDim.new(0,7);return z
end
local title=label('RAFT INSPECTOR',12,8,245,30,18)
local close=button('X',331,8,29,29,Color3.fromRGB(176,60,69))
local minimize=button('-',295,8,29,29,Color3.fromRGB(75,85,108))
local status=label('READY | 30 seconds',12,43,346,24,13)
local stats=label('Resources: 0  |  Others: 0  |  Clicks: 0',12,69,346,23,12)
local start=button('START 30s',12,102,109,36,Color3.fromRGB(29,146,98))
local stop=button('STOP',130,102,109,36,Color3.fromRGB(173,73,76))
local reset=button('RESET',248,102,110,36)
local tabs={}
for i,name in ipairs({'Resources','Events','Others','Test'}) do
    tabs[name]=button(string.upper(name),12+(i-1)*89,149,83,33)
end
local box=Instance.new('TextBox')
box.Position=UDim2.fromOffset(12,191);box.Size=UDim2.fromOffset(346,209)
box.BackgroundColor3=Color3.fromRGB(9,15,27);box.TextColor3=Color3.fromRGB(138,241,185)
box.Font=Enum.Font.Code;box.TextSize=12;box.TextXAlignment=Enum.TextXAlignment.Left;box.TextYAlignment=Enum.TextYAlignment.Top
box.MultiLine=true;box.TextWrapped=true;box.ClearTextOnFocus=false;box.TextEditable=true
box.Text='Press START. Move near floating items and fire the harpoon.\nTEST tab checks basic functionality.';box.Parent=frame
Instance.new('UICorner',box).CornerRadius=UDim.new(0,7)
local copy=button('COPY FULL REPORT',12,412,220,40,Color3.fromRGB(83,70,181))
local test=button('RUN TEST',242,412,116,40,Color3.fromRGB(37,110,157))
local content={status,stats,start,stop,reset,box,copy,test}
for _,b in pairs(tabs) do content[#content+1]=b end
local function refresh()
    if not alive then return end
    stats.Text=string.format('Resources: %d  |  Others: %d  |  Clicks: %d',#logs.Resources,#logs.Others,clicks)
    local a=logs[tab]
    box.Text=(#a>0) and table.concat(a,'\n') or ('No '..tab..' entries yet.')
    for name,b in pairs(tabs) do b.BackgroundColor3=(name==tab) and Color3.fromRGB(39,118,185) or Color3.fromRGB(55,68,95) end
end
for name,b in pairs(tabs) do b.MouseButton1Click:Connect(function() tab=name;refresh() end) end
local function scan()
    local c=player.Character
    local root=c and c:FindFirstChild('HumanoidRootPart')
    if not root then record('Events','Character/root missing');return end
    local ok,parts=pcall(function() return workspace:GetPartBoundsInRadius(root.Position,RANGE) end)
    if not ok then record('Events','Spatial scan failed: '..tostring(parts));return end
    local current={}
    for _,part in ipairs(parts) do
        if part:IsA('BasePart') and not ignored(part) then
            local obj=part:FindFirstAncestorOfClass('Model') or part
            if not ignored(obj) then
                current[obj]=true
                if not seen[obj] then
                    seen[obj]=true
                    local line=string.format('NAME: %s | PART: %s | DIST: %.0f\nPATH: %s\n---',obj.Name,part.Name,(part.Position-root.Position).Magnitude,safePath(obj))
                    local section=(candidate(obj.Name) or candidate(part.Name)) and 'Resources' or 'Others'
                    record(section,line)
                end
            end
        end
    end
    for obj in pairs(last) do
        if not current[obj] then record('Events','No longer in scan radius or removed: '..tostring(obj.Name)) end
    end
    last=current
end
-- Separate explicit classification avoids boolean-precedence mistakes.
local function scanSafe()
    local ok,err=pcall(scan)
    if not ok then record('Events','SCAN ERROR: '..tostring(err)) end
end
local function stopScan(reason)
    running=false;generation=generation+1
    status.Text=reason or 'FINISHED'
    record('Events',status.Text)
    refresh()
end
start.MouseButton1Click:Connect(function()
    if running then return end
    running=true;generation=generation+1;local id=generation
    remaining=DURATION;status.Text='SCANNING: 30s'
    record('Events','START | tool='..toolName())
    task.spawn(function()
        local begun=os.clock()
        while alive and running and id==generation do
            local elapsed=os.clock()-begun
            remaining=math.max(0,math.ceil(DURATION-elapsed))
            status.Text='SCANNING: '..remaining..'s'
            scanSafe();refresh()
            if elapsed>=DURATION then break end
            task.wait(INTERVAL)
        end
        if alive and running and id==generation then stopScan('FINISHED | COPY REPORT') end
    end)
end)
stop.MouseButton1Click:Connect(function() if running then stopScan('STOPPED | COPY REPORT') end end)
reset.MouseButton1Click:Connect(function()
    running=false;generation=generation+1;seen={};last={};clicks=0
    logs={Resources={},Events={},Others={},Test={}};remaining=DURATION
    status.Text='READY | 30 seconds';copy.Text='COPY FULL REPORT';refresh()
end)
local function runTest()
    record('Test','GUI: WORKING')
    record('Test','PLACE ID: '..tostring(game.PlaceId))
    record('Test','TOOL: '..toolName())
    record('Test','ROOT: '..tostring((player.Character and player.Character:FindFirstChild('HumanoidRootPart'))~=nil))
    record('Test','CLIPBOARD API: '..tostring(type(setclipboard)=='function'))
    local ok,err=pcall(function() return #workspace:GetPartBoundsInRadius(Vector3.new(0,0,0),10) end)
    record('Test','SPATIAL QUERY: '..(ok and 'OK' or tostring(err)))
    tab='Test';refresh()
end
test.MouseButton1Click:Connect(runTest)
copy.MouseButton1Click:Connect(function()
    local data=report()
    if type(setclipboard)=='function' then
        local ok=pcall(setclipboard,data)
        copy.Text=ok and 'COPIED!' or 'COPY FAILED'
        if not ok then box.Text=data end
    else
        box.Text=data;copy.Text='SELECT TEXT TO COPY'
    end
end)
local inputConn=UIS.InputBegan:Connect(function(input,processed)
    if not running or processed then return end
    if input.UserInputType==Enum.UserInputType.MouseButton1 then
        clicks=clicks+1
        local target=player:GetMouse().Target
        record('Events','LEFT CLICK | tool='..toolName()..' | target='..(target and safePath(target) or '<none>'))
    end
end)
local minimized=false
minimize.MouseButton1Click:Connect(function()
    minimized=not minimized;frame.Size=minimized and UDim2.fromOffset(370,42) or UDim2.fromOffset(370,465)
    for _,v in ipairs(content) do v.Visible=not minimized end
    minimize.Text=minimized and '+' or '-'
end)
local dragging,dragStart,startPos=false,nil,nil
title.Active=true
title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true;dragStart=input.Position;startPos=frame.Position
    end
end)
local moveConn=UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local d=input.Position-dragStart
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
local endConn=UIS.InputEnded:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
close.MouseButton1Click:Connect(function()
    alive=false;running=false;generation=generation+1
    inputConn:Disconnect();moveConn:Disconnect();endConn:Disconnect();gui:Destroy()
end)
record('Test','Loaded. Click RUN TEST to verify.');refresh()
print('RAFT INSPECTOR READY')
