-- RAFT INSPECTOR V7 | continuous client-visible diagnostics
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local LP=Players.LocalPlayer
local PG=LP:WaitForChild('PlayerGui')
local env=(getgenv and getgenv()) or _G
if type(env.RaftInspectorV7Stop)=='function' then pcall(env.RaftInspectorV7Stop) end
local old=PG:FindFirstChild('RaftInspectorV7'); if old then old:Destroy() end
local alive=true; local running=false; local links={}; local logs={}; local seen={}; local total=0; local changes=0; local projectiles=0; local lastSnapshot=0
local MAX=2200
local function path(x) local ok,s=pcall(function()return x:GetFullName()end);return ok and s or tostring(x) end
local function stamp() return string.format('%.1f',os.clock()) end
local function add(tag,msg)
 if not alive then return end
 total=total+1
 local line='['..stamp()..']['..tag..'] '..tostring(msg)
 logs[#logs+1]=line
 if #logs>MAX then table.remove(logs,1) end
end
local function hook(signal,fn) local c=signal:Connect(fn);links[#links+1]=c;return c end
local function root()local c=LP.Character;return c and c:FindFirstChild('HumanoidRootPart')end
local function tool()local c=LP.Character;return c and c:FindFirstChildOfClass('Tool')end
local function isPlayerObject(o)
 for _,p in ipairs(Players:GetPlayers()) do
  if (p.Character and o:IsDescendantOf(p.Character)) or (p:FindFirstChild('Backpack') and o:IsDescendantOf(p.Backpack)) then return true end
 end
 return false
end
local function isRaft(o) local r=workspace:FindFirstChild('Rafts');return r and o:IsDescendantOf(r) end
local function isRelevant(o)
 if isPlayerObject(o) or isRaft(o) then return false end
 local s=string.lower(o.Name)
 return s:find('harpoon',1,true) or s:find('visual',1,true) or s:find('resource',1,true) or s:find('pickup',1,true) or s:find('loot',1,true) or s:find('scrap',1,true) or s:find('wood',1,true) or s:find('metal',1,true) or s:find('crate',1,true) or s:find('barrel',1,true)
end
local function pos(o)
 local p=o:IsA('BasePart') and o or (o:IsA('Model') and (o.PrimaryPart or o:FindFirstChildWhichIsA('BasePart',true)))
 if not p then return '' end
 local r=root();local d=r and math.floor((r.Position-p.Position).Magnitude) or -1
 return ' | xyz='..tostring(p.Position)..' | dist='..d
end
local function valueString(v)
 local ok,s=pcall(function()return tostring(v.Value)end)
 return ok and s or '?'
end
local function inspectValues(parent,label,depth)
 if not parent then return end
 local count=0
 for _,o in ipairs(parent:GetDescendants()) do
  if o:IsA('ValueBase') then
   count=count+1
   if count<=120 then add(label,path(o)..' = '..valueString(o)) end
  elseif o:IsA('Attribute') then end
 end
 add(label,'Value objects found: '..count)
end
local function attributes(o,label)
 if not o then return end
 local ok,at=pcall(function()return o:GetAttributes()end)
 if ok then for k,v in pairs(at) do add(label,path(o)..' @'..k..'='..tostring(v)) end end
end
local function snapshot()
 add('SNAPSHOT','--- BEGIN PLAYER / INVENTORY ---')
 add('PLAYER','name='..LP.Name..' | UserId='..LP.UserId..' | PlaceId='..game.PlaceId)
 local c=LP.Character
 add('PLAYER','character='..(c and path(c) or 'none')..' | tool='..(tool() and tool().Name or 'none'))
 attributes(LP,'ATTRIBUTE');if c then attributes(c,'ATTRIBUTE') end
 local ls=LP:FindFirstChild('leaderstats');inspectValues(ls,'LEADERSTATS')
 local backpack=LP:FindFirstChild('Backpack')
 if backpack then
  for _,item in ipairs(backpack:GetChildren()) do
   add('INVENTORY',item.Name..' ('..item.ClassName..')')
   attributes(item,'ATTRIBUTE')
  end
 end
 if c then for _,item in ipairs(c:GetChildren()) do if item:IsA('Tool') then add('EQUIPPED',item.Name);attributes(item,'ATTRIBUTE') end end end
 inspectValues(LP,'PLAYER VALUES')
 add('SNAPSHOT','--- END PLAYER / INVENTORY ---')
end
local function serverVisible()
 add('NETWORK','Client can inspect ReplicatedStorage only; ServerStorage and ServerScriptService contents are NOT accessible')
 local n=0
 for _,o in ipairs(RS:GetDescendants()) do
  if o:IsA('RemoteEvent') or o:IsA('RemoteFunction') or o:IsA('UnreliableRemoteEvent') then
   n=n+1;if n<=150 then add('REMOTE NAME',path(o)..' ['..o.ClassName..']') end
  end
 end
 add('NETWORK','Replicated remote objects: '..n..' (names only; no interception)')
end
local function visualsSnapshot()
 local v=workspace:FindFirstChild('LocalHarpoonVisuals')
 add('VISUAL','LocalHarpoonVisuals='..tostring(v~=nil))
 if v then
  local n=0
  for _,o in ipairs(v:GetDescendants()) do
   if o:IsA('BasePart') or o:IsA('Model') then
    n=n+1;if n<=100 then add('VISUAL',path(o)..pos(o)) end
   end
  end
  add('VISUAL','visual objects='..n)
 end
end
local gui=Instance.new('ScreenGui');gui.Name='RaftInspectorV7';gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.Parent=PG
local frame=Instance.new('Frame');frame.Size=UDim2.fromOffset(410,540);frame.Position=UDim2.new(.5,-205,.5,-270);frame.BackgroundColor3=Color3.fromRGB(17,22,34);frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,12)
local function label(txt,y,h)
 local l=Instance.new('TextLabel');l.Position=UDim2.fromOffset(12,y);l.Size=UDim2.fromOffset(386,h);l.BackgroundTransparency=1;l.Text=txt;l.TextColor3=Color3.fromRGB(220,235,250);l.Font=Enum.Font.GothamBold;l.TextSize=14;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=frame;return l
end
local function btn(txt,x,y,w,h,col)
 local b=Instance.new('TextButton');b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=col;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=12;b.Text=txt;b.Parent=frame;Instance.new('UICorner',b).CornerRadius=UDim.new(0,7);return b
end
label('RAFT INSPECTOR V7  |  LIVE REPORT',9,25)
local status=label('READY | Logs: 0',35,20)
label('1  |  CONTINUOUS SCAN',62,18)
local start=btn('START ALL',12,83,187,35,Color3.fromRGB(28,137,91))
local stop=btn('STOP',211,83,187,35,Color3.fromRGB(175,62,66))
label('2  |  TEST & SNAPSHOTS',125,18)
local test=btn('TEST SCRIPT',12,146,123,34,Color3.fromRGB(52,107,170))
local inventory=btn('MY ITEMS / STATS',143,146,128,34,Color3.fromRGB(61,95,155))
local server=btn('VISIBLE REMOTES',279,146,119,34,Color3.fromRGB(61,95,155))
label('3  |  FULL REPORT / COPY',188,18)
local copy=btn('COPY EVERYTHING',12,209,187,36,Color3.fromRGB(113,73,195))
local reset=btn('CLEAR REPORT',211,209,187,36,Color3.fromRGB(90,94,110))
local output=Instance.new('TextBox');output.Position=UDim2.fromOffset(12,256);output.Size=UDim2.fromOffset(386,238);output.BackgroundColor3=Color3.fromRGB(7,12,20);output.TextColor3=Color3.fromRGB(132,240,170);output.Font=Enum.Font.Code;output.TextSize=11;output.TextXAlignment=Enum.TextXAlignment.Left;output.TextYAlignment=Enum.TextYAlignment.Top;output.TextWrapped=true;output.MultiLine=true;output.TextEditable=false;output.ClearTextOnFocus=false;output.Text='Press START ALL';output.Parent=frame;Instance.new('UICorner',output).CornerRadius=UDim.new(0,7)
local close=btn('CLOSE',12,501,386,29,Color3.fromRGB(74,77,95))
local function report()
 return table.concat({'RAFT INSPECTOR V7 FULL REPORT','PlaceId: '..game.PlaceId,'Player: '..LP.Name,'Entries retained: '..#logs,'Total events: '..total,'Projectiles: '..projectiles,'Changes: '..changes,'Note: client-visible data only; not server-only storage','===== ALL RESULTS IN TIME ORDER =====',table.concat(logs,'\n')},'\n')
end
local function refresh()
 if not alive then return end
 status.Text=(running and 'SCANNING LIVE' or 'STOPPED')..' | Logs: '..#logs..' | Shots: '..projectiles
 local lines={};for i=math.max(1,#logs-16),#logs do lines[#lines+1]=logs[i] end
 output.Text=table.concat(lines,'\n')
end
local function watchValue(v)
 if seen[v] then return end;seen[v]=true
 if v:IsA('ValueBase') then
  hook(v.Changed,function()if running then changes=changes+1;add('VALUE CHANGE',path(v)..' => '..valueString(v));refresh()end end)
 end
end
local function watchPlayerValues()
 for _,o in ipairs(LP:GetDescendants()) do if o:IsA('ValueBase') then watchValue(o) end end
end
hook(LP.DescendantAdded,function(o)
 if not running then return end
 if o:IsA('ValueBase') then add('NEW VALUE',path(o)..'='..valueString(o));watchValue(o)
 elseif o:IsA('Tool') then add('ITEM ADDED',path(o)) end
 refresh()
end)
hook(LP.DescendantRemoving,function(o)
 if running and (o:IsA('Tool') or o:IsA('ValueBase')) then add('ITEM REMOVED',path(o));refresh() end
end)
hook(workspace.DescendantAdded,function(o)
 if not running then return end
 if o.Name=='HarpoonProjectile' then projectiles=projectiles+1;add('SHOT','HarpoonProjectile CREATED '..path(o)..pos(o))
 elseif isRelevant(o) and (o:IsA('BasePart') or o:IsA('Model')) then add('WORLD ADDED',path(o)..pos(o)) end
 refresh()
end)
hook(workspace.DescendantRemoving,function(o)
 if not running then return end
 if o.Name=='HarpoonProjectile' then add('SHOT','HarpoonProjectile REMOVED')
 elseif isRelevant(o) and (o:IsA('BasePart') or o:IsA('Model')) then add('WORLD REMOVED',path(o)) end
 refresh()
end)
hook(UIS.InputBegan,function(input,processed)
 if running and input.UserInputType==Enum.UserInputType.MouseButton1 and not processed then
  add('CLICK','tool='..(tool() and tool().Name or 'none'))
  refresh()
 end
end)
local function runTest()
 add('TEST','GUI OK | Root='..tostring(root()~=nil)..' | Clipboard='..tostring(type(setclipboard)=='function'))
 add('TEST','Harpoon equipped='..tostring(tool() and tool().Name or 'none'))
 local ok,parts=pcall(function()local r=root();return r and workspace:GetPartBoundsInRadius(r.Position,100)end)
 add('TEST','Spatial query='..tostring(ok)..' | nearby parts='..tostring(parts and #parts or 0))
 visualsSnapshot();refresh()
end
local generation=0
local function begin()
 if running then return end
 running=true;generation=generation+1;local id=generation
 add('SYSTEM','START continuous scan (no time limit)')
 snapshot();serverVisible();visualsSnapshot();watchPlayerValues();runTest();refresh()
 task.spawn(function()
  local n=0
  while alive and running and generation==id do
   n=n+1
   if n%5==0 then snapshot();watchPlayerValues() end
   if n%3==0 then visualsSnapshot() end
   refresh();task.wait(2)
  end
 end)
end
start.MouseButton1Click:Connect(begin)
stop.MouseButton1Click:Connect(function()running=false;generation=generation+1;add('SYSTEM','STOPPED by user');refresh()end)
test.MouseButton1Click:Connect(runTest)
inventory.MouseButton1Click:Connect(function()snapshot();refresh()end)
server.MouseButton1Click:Connect(function()serverVisible();refresh()end)
copy.MouseButton1Click:Connect(function()
 local txt=report()
 if type(setclipboard)=='function' then local ok=pcall(setclipboard,txt);copy.Text=ok and 'COPIED ALL!' or 'COPY FAILED' else add('SYSTEM','Clipboard not supported') end
 task.delay(2,function()if alive then copy.Text='COPY EVERYTHING' end end)
end)
reset.MouseButton1Click:Connect(function()logs={};total=0;changes=0;projectiles=0;add('SYSTEM','REPORT CLEARED');refresh()end)
local function cleanup()
 alive=false;running=false;generation=generation+1
 for _,c in ipairs(links) do pcall(function()c:Disconnect()end) end
 if gui.Parent then gui:Destroy()end
end
env.RaftInspectorV7Stop=cleanup
close.MouseButton1Click:Connect(cleanup)
add('SYSTEM','V7 loaded. START ALL to continuously log client-visible info.');refresh()
