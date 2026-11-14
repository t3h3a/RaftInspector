-- RAFT INSPECTOR V8 | continuous client-visible diagnostics
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local LP=Players.LocalPlayer
local PG=LP:WaitForChild('PlayerGui')
local env=(getgenv and getgenv()) or _G
if type(env.RaftInspectorV8Stop)=='function' then pcall(env.RaftInspectorV8Stop) end
local old=PG:FindFirstChild('RaftInspectorV8'); if old then old:Destroy() end
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
local auto=false;local autoSerial=0;local speed=70;local fire=true;local autoTarget=nil
local visited={};local candidates={};local scanCount=0
local function equipHarpoon()
 local c=LP.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if not h then return nil end
 local active=tool()
 if active and active.Name:lower():find('harpoon',1,true) then return active end
 local bag=LP:FindFirstChild('Backpack')
 if not bag then return nil end
 for _,item in ipairs(bag:GetChildren()) do
  if item:IsA('Tool') and item.Name:lower():find('harpoon',1,true) then
   pcall(function() h:EquipTool(item) end)
   return item
  end
 end
 return nil
end
local words={'wood','metal','scrap','resource','loot','plank','crate','barrel','supply'}
local function contains(s, terms)
 s=s:lower()
 for _,w in ipairs(terms) do if s:find(w,1,true) then return true end end
 return false
end
local function candidate(part)
 if not part:IsA('BasePart') or isPlayerObject(part) or isRaft(part) then return nil end
 local visuals=workspace:FindFirstChild('LocalHarpoonVisuals')
 if visuals and part:IsDescendantOf(visuals) then return nil end
 local n=part
 while n and n~=workspace do
  if contains(n.Name,{'revolver','blunderbuss','harpoonprojectile','sword','gun','hammer'}) then return nil end
  if contains(n.Name,words) then return n end
  n=n.Parent
 end
 return nil
end
local function scanCandidates()
 local r=root();if not r then return end
 local ok,parts=pcall(function() return workspace:GetPartBoundsInRadius(r.Position,350) end)
 if not ok then add('SCAN','query failed');return end
 local now=os.clock();local n=0
 for _,part in ipairs(parts) do
  local obj=candidate(part)
  if obj and not candidates[obj] then
   candidates[obj]={at=now,part=part}
   add('CANDIDATE','Found '..path(obj)..' | xyz='..tostring(part.Position))
  elseif obj then candidates[obj].at=now;candidates[obj].part=part end
 end
 for obj,item in pairs(candidates) do
  if not obj.Parent or now-item.at>10 then candidates[obj]=nil else n=n+1 end
 end
 scanCount=n
end
local function nearestCandidate()
 local r=root();if not r then return nil end
 local best,bestDistance,bestPos
 for obj,item in pairs(candidates) do
  if obj.Parent and item.part and item.part.Parent and (visited[obj] or 0)<os.clock() then
   local p=item.part.Position;local d=(p-r.Position).Magnitude
   if d<350 and (not bestDistance or d<bestDistance) then best=obj;bestDistance=d;bestPos=p end
  end
 end
 return best,bestDistance,bestPos
end
local function stopAuto()
 if not auto then return end
 auto=false;autoSerial=autoSerial+1;autoTarget=nil
 local h=LP.Character and LP.Character:FindFirstChildOfClass('Humanoid')
 if h and root() then pcall(function()h:MoveTo(root().Position)end)end
 add('AUTO','Stopped')
end
local function autoStart()
 stopAuto()
 auto=true;autoSerial=autoSerial+1
 local id=autoSerial
 local startRoot=root();local center=startRoot and startRoot.Position
 if not center then auto=false;add('AUTO','No character root');return end
 local waypoint=0;local lastFire=0;local focus=nil;local focusSince=0
 equipHarpoon();add('AUTO','Experimental traverse started | speed='..speed)
 task.spawn(function()
  while alive and auto and autoSerial==id do
   local ok,err=pcall(function()
    local r=root();local c=LP.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
    if not r or not h or h.Health<=0 then stopAuto();return end
    scanCandidates()
    local target,d,p=nearestCandidate();autoTarget=target
    if target then
     if target~=focus then focus=target;focusSince=os.clock();add('AUTO','Target '..path(target))end
     if os.clock()-focusSince>6 then
      visited[target]=os.clock()+15;target=nil;autoTarget=nil;focus=nil
     end
    end
    if not target then
     waypoint=waypoint+1
     local a=(waypoint%24)*math.pi/12
     p=center+Vector3.new(math.cos(a)*105,5,math.sin(a)*105)
    end
    if p then
     local delta=p-r.Position
     if delta.Magnitude>5 then
      local advance=math.min(delta.Magnitude,speed*0.14)
      -- Experimental client movement; server may correct position.
      local new=r.Position+delta.Unit*advance
      pcall(function()r.CFrame=CFrame.new(new,new+r.CFrame.LookVector)end)
     end
    end
    if target and fire and os.clock()-lastFire>0.2 then
     local t=equipHarpoon()
     if t then
      pcall(function()t:Activate()end)
      lastFire=os.clock()
      add('AUTO','Harpoon activate toward '..target.Name..' (collection unverified)')
     end
    end
   end)
   if not ok then add('AUTO ERROR',tostring(err))end
   task.wait(.14)
  end
 end)
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
local gui=Instance.new('ScreenGui');gui.Name='RaftInspectorV8';gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.Parent=PG
local frame=Instance.new('Frame');frame.Size=UDim2.fromOffset(410,625);frame.Position=UDim2.new(.5,-205,.5,-312);frame.BackgroundColor3=Color3.fromRGB(17,22,34);frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,12)
local function label(txt,y,h)
 local l=Instance.new('TextLabel');l.Position=UDim2.fromOffset(12,y);l.Size=UDim2.fromOffset(386,h);l.BackgroundTransparency=1;l.Text=txt;l.TextColor3=Color3.fromRGB(220,235,250);l.Font=Enum.Font.GothamBold;l.TextSize=14;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=frame;return l
end
local function btn(txt,x,y,w,h,col)
 local b=Instance.new('TextButton');b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=col;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=12;b.Text=txt;b.Parent=frame;Instance.new('UICorner',b).CornerRadius=UDim.new(0,7);return b
end
label('RAFT INSPECTOR V8  |  LIVE REPORT',9,25)
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
label('4  |  EXPERIMENTAL AUTO (SERVER MAY BLOCK)',252,18)
local autoBtn=btn('AUTO TRAVERSE + FIRE',12,275,187,35,Color3.fromRGB(112,75,192))
local autoStopBtn=btn('STOP AUTO',211,275,115,35,Color3.fromRGB(173,60,67))
local speedBtn=btn('70',335,275,63,35,Color3.fromRGB(69,99,157))
local output=Instance.new('TextBox');output.Position=UDim2.fromOffset(12,322);output.Size=UDim2.fromOffset(386,255);output.BackgroundColor3=Color3.fromRGB(7,12,20);output.TextColor3=Color3.fromRGB(132,240,170);output.Font=Enum.Font.Code;output.TextSize=11;output.TextXAlignment=Enum.TextXAlignment.Left;output.TextYAlignment=Enum.TextYAlignment.Top;output.TextWrapped=true;output.MultiLine=true;output.TextEditable=false;output.ClearTextOnFocus=false;output.Text='Press START ALL';output.Parent=frame;Instance.new('UICorner',output).CornerRadius=UDim.new(0,7)
local close=btn('CLOSE',12,586,386,29,Color3.fromRGB(74,77,95))
local function report()
 return table.concat({'RAFT INSPECTOR V8 FULL REPORT','PlaceId: '..game.PlaceId,'Player: '..LP.Name,'Entries retained: '..#logs,'Total events: '..total,'Projectiles: '..projectiles,'Changes: '..changes,'Candidates: '..scanCount..' | Auto active: '..tostring(auto)..' | Auto target: '..(autoTarget and autoTarget.Name or 'none'),'Note: client-visible data only; not server-only storage; collection unverified','===== ALL RESULTS IN TIME ORDER =====',table.concat(logs,'\n')},'\n')
end
local function refresh()
 if not alive then return end
 status.Text=(running and 'SCANNING LIVE' or 'STOPPED')..' | Auto: '..(auto and 'ON' or 'OFF')..' | Targets: '..scanCount..' | Shots: '..projectiles
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
   if n%2==0 then pcall(scanCandidates) end
   if n%3==0 then visualsSnapshot() end
   refresh();task.wait(2)
  end
 end)
end
start.MouseButton1Click:Connect(begin)
autoBtn.MouseButton1Click:Connect(function() if not running then begin()end;autoStart();refresh()end)
autoStopBtn.MouseButton1Click:Connect(function()stopAuto();refresh()end)
speedBtn.MouseButton1Click:Connect(function()speed=(speed==70 and 120 or speed==120 and 40 or 70);speedBtn.Text=tostring(speed);add('AUTO','Speed='..speed);refresh()end)
stop.MouseButton1Click:Connect(function()stopAuto();running=false;generation=generation+1;add('SYSTEM','STOPPED by user');refresh()end)
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
 stopAuto();alive=false;running=false;generation=generation+1
 for _,c in ipairs(links) do pcall(function()c:Disconnect()end) end
 if gui.Parent then gui:Destroy()end
end
env.RaftInspectorV8Stop=cleanup
close.MouseButton1Click:Connect(cleanup)
add('SYSTEM','V7 loaded. START ALL to continuously log client-visible info.');refresh()
