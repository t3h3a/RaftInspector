-- RAFT CONTROL V13 | filtered fast collection + chest discovery
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local LP=Players.LocalPlayer
local PG=LP:WaitForChild('PlayerGui')
local env=(getgenv and getgenv()) or _G
for _,k in ipairs({'RaftControlV13Stop','RaftInspectorV12Stop','RaftInspectorV11Stop','RaftInspectorV10Stop','RaftInspectorV9Stop','RaftInspectorV8Stop','RaftInspectorV7Stop'}) do if type(env[k])=='function' then pcall(env[k]) end end
for _,name in ipairs({'RaftControlV13','RaftControlV12','RaftInspectorV11','RaftInspectorV10','RaftInspectorV9','RaftInspectorV8','RaftInspectorV7'}) do local old=PG:FindFirstChild(name); if old then old:Destroy() end end
local alive=true; local running=false; local links={}; local logs={}; local seen={}; local total=0; local changes=0; local projectiles=0; local lastSnapshot=0
local MAX=4500
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
local auto=false;local autoSerial=0;local speed=2000;local fire=true;local autoTarget=nil
local range=2500
local resourceMode='ALL'
local modes={'ALL','WOOD','METAL','SCRAP','CHESTS','OTHER'}
local modeIndex=1
local initial={Wood=tonumber(LP:GetAttribute('Mat_Wood')) or 0,Metal=tonumber(LP:GetAttribute('Mat_Metal')) or 0,Scrap=tonumber(LP:GetAttribute('Mat_Scrap')) or 0}
local foundChests={}
local chestIndex=1
local function resourceType(obj)
 local n=obj.Name:lower()
 if n:find('woodlog',1,true) or n:find('plank',1,true) then return 'WOOD' end
 if n:find('metalsheet',1,true) then return 'METAL' end
 if n:find('metalbarrel',1,true) then return 'SCRAP' end
 if n:find('chest',1,true) then return 'CHESTS' end
 return 'OTHER'
end
local function filterOK(obj)
 return resourceMode=='ALL' or resourceType(obj)==resourceMode
end

local touchMode=true;local touchTries=0;local lastTouch=0;local jumpMode=true
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
-- V9: Actual resource visuals were observed under LocalHarpoonVisuals.
-- Ignore the pooled copies parked at Y ~= -10000; use active models only.
local words={'wood','metal','scrap','resource','loot','plank','crate','barrel','supply','chest','chair','sheet'}
local function contains(s, terms)
 s=string.lower(tostring(s))
 for _,w in ipairs(terms) do if s:find(w,1,true) then return true end end
 return false
end
local function candidate(part)
 if not part:IsA('BasePart') or isPlayerObject(part) or isRaft(part) then return nil end
 local visuals=workspace:FindFirstChild('LocalHarpoonVisuals')
 if visuals and part:IsDescendantOf(visuals) then
  local group=part
  while group and group.Parent~=visuals do
   group=group.Parent
  end
  if group and group~=visuals and group:IsA('Model')
   and group.Name:sub(1,7)=='Visual_' and part.Position.Y>-500 then
   return group
  end
  return nil
 end
 -- Fallback for other visible world resources.
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
 local now=os.clock();local n=0
 -- Scan active visual models directly, because these can be non-collidable and
 -- GetPartBoundsInRadius may skip them or classify pooled children incorrectly.
 local visuals=workspace:FindFirstChild('LocalHarpoonVisuals')
 if visuals then
  for _,obj in ipairs(visuals:GetChildren()) do
   if obj:IsA('Model') and obj.Name:sub(1,7)=='Visual_' then
    local part=obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart',true)
    if part and part.Position.Y>-500 then
     local d=(part.Position-r.Position).Magnitude
     if d<=range then
      if not candidates[obj] then
       candidates[obj]={at=now,part=part,kind='ACTIVE VISUAL'}
       add('CANDIDATE','ACTIVE '..path(obj)..' | xyz='..tostring(part.Position)..' | dist='..math.floor(d))
      else candidates[obj].at=now;candidates[obj].part=part end
     end
    end
   end
  end
 end
 local ok,parts=pcall(function()return workspace:GetPartBoundsInRadius(r.Position,math.min(range,650))end)
 if ok then
  for _,part in ipairs(parts) do
   local obj=candidate(part)
   if obj and obj.Parent and not candidates[obj] then
    candidates[obj]={at=now,part=part,kind='NEARBY'}
    add('CANDIDATE','Found '..path(obj)..' | xyz='..tostring(part.Position))
   elseif obj and candidates[obj] then candidates[obj].at=now;candidates[obj].part=part end
  end
 else add('SCAN','Spatial query failed') end
 for obj,item in pairs(candidates) do
  if not obj.Parent or not item.part.Parent or now-item.at>8 then candidates[obj]=nil else n=n+1 end
 end
 scanCount=n
end
local function nearestCandidate()
 local r=root();if not r then return nil end
 local best,bestDistance,bestPos
 for obj,item in pairs(candidates) do
  if obj.Parent and item.part and item.part.Parent and filterOK(obj) and (visited[obj] or 0)<os.clock() then
   local p=item.part.Position;local d=(p-r.Position).Magnitude
   if p.Y>-500 and d<range and (not bestDistance or d<bestDistance) then
    best=obj;bestDistance=d;bestPos=p
   end
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
 local waypoint=0;local roamPosition=nil;local lastFire=0;local focus=nil;local focusSince=0;local lastArrive=0
 local lastActivationLog=0;local lastMotion=os.clock();local lastSearch=0
 equipHarpoon();scanCandidates()
 add('AUTO','Started | filter='..resourceMode..' | range='..range..' | speed='..speed..' | candidates='..scanCount)
 task.spawn(function()
  while alive and auto and autoSerial==id do
   local ok,err=pcall(function()
    local r=root();local c=LP.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
    if not r or not h or h.Health<=0 then stopAuto();return end
    if os.clock()-lastSearch>.22 then scanCandidates();lastSearch=os.clock() end
    local target,d,p=nearestCandidate();autoTarget=target
    if target then
     if target~=focus then
      focus=target;focusSince=os.clock()
      add('AUTO TARGET','Active visual '..path(target)..' | dist='..math.floor(d))
     end
     if os.clock()-focusSince>0.85 then
      visited[target]=os.clock()+1.1;target=nil;autoTarget=nil;focus=nil
      add('AUTO','Target timeout: skip for 1.1s')
     end
    end
    -- Without a target, remain at a waypoint until reached. Previous V8 changed
    -- the waypoint every 0.14s, making the avatar bounce unpredictably.
    if not target then
     if not roamPosition or (r.Position-roamPosition).Magnitude<13 then
      waypoint=waypoint+1
      local a=(waypoint%20)*math.pi/10
      roamPosition=center+Vector3.new(math.cos(a)*145,8,math.sin(a)*145)
     end
     p=roamPosition
    else
     p=p+Vector3.new(0,4,0)
    end
    if p then
     local delta=p-r.Position
     if delta.Magnitude>4 then
      local now=os.clock()
      local dt=math.clamp(now-lastMotion,.015,.075)
      lastMotion=now
      local advance=math.min(delta.Magnitude,speed*dt)
      if target and jumpMode then advance=delta.Magnitude end
      local new=r.Position+delta.Unit*advance
      pcall(function()r.CFrame=CFrame.new(new,new+r.CFrame.LookVector);r.AssemblyLinearVelocity=Vector3.zero end)
     end
    end
    -- Proximity / touch collection experiment, separate from harpoon.
    -- Only actual world touch triggers may be authoritative; local visual models
    -- are often cosmetic. Never treat this as a confirmed harvest.
    if target and touchMode and os.clock()-lastTouch>.35 then
     lastTouch=os.clock()
     local rpart=root()
     local touchPart=(target:IsA('BasePart') and target or target:FindFirstChildWhichIsA('BasePart',true))
     if rpart and touchPart and touchPart.Position.Y>-500 then
      touchTries=touchTries+1
      local touched=false
      if touchPart.CanTouch and type(firetouchinterest)=='function' then
       touched=pcall(function()
        firetouchinterest(rpart,touchPart,0)
        firetouchinterest(rpart,touchPart,1)
       end)
      end
      if touchTries%10==1 then
       add('TOUCH TEST','attempt '..touchTries..' target='..target.Name..' touchAPI='..tostring(touched)..' (not proof of collection)')
      end
     end
    end
    -- Tool:Activate() is only a request. A server-controlled harpoon may require
    -- genuine input/camera ray and enforce a cooldown; this cannot guarantee firing.
    if target and fire and d and d<130 and os.clock()-lastFire>0.06 then
     local t=equipHarpoon()
     if t then
      local cam=workspace.CurrentCamera
      if cam then
       pcall(function()cam.CFrame=CFrame.lookAt(cam.CFrame.Position,p-Vector3.new(0,5,0))end)
      end
      local success,msg=pcall(function()
       t:Deactivate()
       t:Activate()
      end)
      lastFire=os.clock()
      if os.clock()-lastActivationLog>1.2 then
       add('AUTO FIRE','tool='..t.Name..' activateAPI='..tostring(success)..' target='..target.Name..' dist='..math.floor(d)..' | projectile is separate proof')
       lastActivationLog=os.clock()
      end
      if not success then add('AUTO ERROR','activate: '..tostring(msg))end
     else add('AUTO','Harpoon missing')end
    end
   end)
   if not ok then add('AUTO ERROR',tostring(err))end
   task.wait(.025)
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
local gui=Instance.new('ScreenGui');gui.Name='RaftControlV13';gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.Parent=PG
local frame=Instance.new('Frame');frame.Size=UDim2.fromOffset(410,710);frame.Position=UDim2.new(.5,-205,.5,-355);frame.BackgroundColor3=Color3.fromRGB(17,22,34);frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,12)
local guiScale=Instance.new('UIScale');guiScale.Parent=frame
local function fitScreen()
 local camera=workspace.CurrentCamera
 if camera then
  guiScale.Scale=math.min(1,camera.ViewportSize.X/435,camera.ViewportSize.Y/740)
 end
end
fitScreen()
local function label(txt,y,h)
 local l=Instance.new('TextLabel');l.Position=UDim2.fromOffset(12,y);l.Size=UDim2.fromOffset(386,h);l.BackgroundTransparency=1;l.Text=txt;l.TextColor3=Color3.fromRGB(220,235,250);l.Font=Enum.Font.GothamBold;l.TextSize=14;l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=frame;return l
end
local function btn(txt,x,y,w,h,col)
 local b=Instance.new('TextButton');b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=col;b.TextColor3=Color3.new(1,1,1);b.Font=Enum.Font.GothamBold;b.TextSize=12;b.Text=txt;b.Parent=frame;Instance.new('UICorner',b).CornerRadius=UDim.new(0,7);return b
end
label('RAFT CONTROL V13  |  RESOURCE FILTERS',9,25)
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
label('4  |  AUTO RESOURCES / FAST TRAVEL',252,18)
local autoBtn=btn('AUTO FIND + FIRE',12,275,187,35,Color3.fromRGB(112,75,192))
local autoStopBtn=btn('STOP AUTO',211,275,115,35,Color3.fromRGB(173,60,67))
local speedBtn=btn('2000',335,275,63,35,Color3.fromRGB(69,99,157))
local jumpBtn=btn('FLASH: ON',12,315,187,32,Color3.fromRGB(50,107,148))
local touchBtn=btn('TOUCH TEST: ON',211,315,187,32,Color3.fromRGB(50,107,148))
local filterBtn=btn('FILTER: ALL',12,353,187,35,Color3.fromRGB(28,120,151))
local rangeBtn=btn('RANGE: 2500',211,353,187,35,Color3.fromRGB(59,103,170))
local chestBtn=btn('SCAN ALL RAFT CHESTS',12,395,187,35,Color3.fromRGB(70,109,160))
local warpChestBtn=btn('WARP NEXT CHEST (TEST)',211,395,187,35,Color3.fromRGB(103,73,153))
local accountLabel=label('ACCOUNT: '..LP.Name,438,24)
local matsLabel=label('WOOD - | METAL - | SCRAP - | GOLD -',464,23)
local gainsLabel=label('GAIN: W +0 | M +0 | S +0',488,22)

local output=Instance.new('TextBox');output.Position=UDim2.fromOffset(12,517);output.Size=UDim2.fromOffset(386,140);output.BackgroundColor3=Color3.fromRGB(7,12,20);output.TextColor3=Color3.fromRGB(132,240,170);output.Font=Enum.Font.Code;output.TextSize=11;output.TextXAlignment=Enum.TextXAlignment.Left;output.TextYAlignment=Enum.TextYAlignment.Top;output.TextWrapped=true;output.MultiLine=true;output.TextEditable=false;output.ClearTextOnFocus=false;output.Text='Press START ALL';output.Parent=frame;Instance.new('UICorner',output).CornerRadius=UDim.new(0,7)
local close=btn('CLOSE',12,669,386,29,Color3.fromRGB(74,77,95))
local hide=btn('HIDE -',326,9,72,25,Color3.fromRGB(48,116,159))
local float=Instance.new('TextButton')
float.Name='OpenInspector';float.Size=UDim2.fromOffset(100,35)
float.Position=UDim2.new(1,-112,0,105)
float.BackgroundColor3=Color3.fromRGB(50,90,170)
float.Text='OPEN V13';float.TextColor3=Color3.new(1,1,1)
float.TextSize=12;float.Font=Enum.Font.GothamBold
float.Visible=false;float.Active=true;float.Draggable=true;float.Parent=gui
Instance.new('UICorner',float).CornerRadius=UDim.new(0,8)
hide.MouseButton1Click:Connect(function()
 frame.Visible=false;float.Visible=true
end)
float.MouseButton1Click:Connect(function()
 float.Visible=false;frame.Visible=true
end)
local function report()
 return table.concat({'RAFT CONTROL V13 FULL REPORT','PlaceId: '..game.PlaceId,'Player: '..LP.Name,'Entries retained: '..#logs,'Total events: '..total,'Projectiles: '..projectiles,'Changes: '..changes,'Candidates: '..scanCount..' | Auto active: '..tostring(auto)..' | Auto target: '..(autoTarget and autoTarget.Name or 'none'),'Filter='..resourceMode..'; range='..range..'; speed='..speed..'; instant jump='..tostring(jumpMode)..'; touch test='..tostring(touchMode)..'; touch attempts='..touchTries,'Materials: Wood='..tostring(LP:GetAttribute('Mat_Wood'))..' Metal='..tostring(LP:GetAttribute('Mat_Metal'))..' Scrap='..tostring(LP:GetAttribute('Mat_Scrap'))..' Gold='..tostring(LP:GetAttribute('Cash')),'Note: server controls actual materials; chest inspection does not confirm transfers.','===== ALL RESULTS IN TIME ORDER =====',table.concat(logs,'\n')},'\n')
end
local function refresh()
 if not alive then return end
 status.Text=(running and 'SCANNING LIVE' or 'STOPPED')..' | AUTO: '..(auto and 'ON' or 'OFF')..' | '..resourceMode..' | Targets: '..scanCount
 matsLabel.Text='WOOD '..tostring(LP:GetAttribute('Mat_Wood') or 0)..' | METAL '..tostring(LP:GetAttribute('Mat_Metal') or 0)..' | SCRAP '..tostring(LP:GetAttribute('Mat_Scrap') or 0)..' | GOLD '..tostring(LP:GetAttribute('Cash') or 0)
 gainsLabel.Text='GAIN: W +'..((tonumber(LP:GetAttribute('Mat_Wood')) or 0)-initial.Wood)..' | M +'..((tonumber(LP:GetAttribute('Mat_Metal')) or 0)-initial.Metal)..' | S +'..((tonumber(LP:GetAttribute('Mat_Scrap')) or 0)-initial.Scrap)
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
hook(LP.AttributeChanged,function(name)
 if running and (name:sub(1,4)=='Mat_' or name=='Cash') then
  changes=changes+1
  add('MATERIAL CHANGE',name..' => '..tostring(LP:GetAttribute(name)))
  refresh()
 end
end)
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
   if n%15==0 then snapshot();watchPlayerValues() end
   if n%2==0 then pcall(scanCandidates) end
   if n%12==0 then visualsSnapshot() end
   refresh();task.wait(2)
  end
 end)
end

local function chestScan()
 foundChests={};chestIndex=1
 local rafts=workspace:FindFirstChild('Rafts')
 if not rafts then add('CHEST','Workspace.Rafts not visible');refresh();return end
 for _,raft in ipairs(rafts:GetChildren()) do
  local own=raft.Name:lower():find(LP.Name:lower(),1,true)~=nil
  local flags={}
  for k,v in pairs(raft:GetAttributes()) do
   if string.lower(tostring(k)):find('shield',1,true) then flags[#flags+1]=tostring(k)..'='..tostring(v) end
  end
  local count=0
  for _,obj in ipairs(raft:GetDescendants()) do
   if (obj:IsA('BasePart') or obj:IsA('Model')) and obj.Name:lower():find('chest',1,true) then
    local bp=obj:IsA('BasePart') and obj or (obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart',true))
    if bp and bp.Position.Y>-1000 then
     count=count+1
     if not own and obj:IsA('Model') then foundChests[#foundChests+1]={object=obj,part=bp,owner=raft.Name} end
     if count<=8 then add('CHEST','raft='..raft.Name..' '..path(obj)..' pos='..tostring(bp.Position)) end
    end
   end
   if obj:IsA('ProximityPrompt') then
    add('CHEST PROMPT',path(obj)..' enabled='..tostring(obj.Enabled)..' hold='..tostring(obj.HoldDuration))
   end
  end
  add('RAFT','owner='..raft.Name..' | own='..tostring(own)..' | matches='..count..' | shields='..table.concat(flags,','))
 end
 add('CHEST','Total visible candidate chest models (other rafts): '..#foundChests)
 refresh()
end
filterBtn.MouseButton1Click:Connect(function()
 modeIndex=modeIndex%#modes+1;resourceMode=modes[modeIndex]
 filterBtn.Text='FILTER: '..resourceMode
 visited={};autoTarget=nil
 add('FILTER','Selected '..resourceMode..' (metal barrels=SCRAP; sheets=METAL; logs=WOOD)')
 refresh()
end)
rangeBtn.MouseButton1Click:Connect(function()
 range=(range==2500 and 3500 or range==3500 and 800 or 2500)
 rangeBtn.Text='RANGE: '..range
 add('SCAN','Range updated '..range);refresh()
end)
chestBtn.MouseButton1Click:Connect(chestScan)
warpChestBtn.MouseButton1Click:Connect(function()
 if #foundChests==0 then chestScan() end
 if #foundChests==0 then add('CHEST','No chest models discovered. No movement.');refresh();return end
 if chestIndex>#foundChests then chestIndex=1 end
 local e=foundChests[chestIndex];chestIndex=chestIndex+1
 local r=root()
 if r and e.object.Parent and e.part.Parent then
  local xyz=e.part.Position+Vector3.new(0,4,0)
  pcall(function()r.CFrame=CFrame.new(xyz)end)
  add('CHEST TEST','Moved to '..e.owner..' | '..path(e.object)..' | interactive transfer NOT assumed')
 end
 refresh()
end)
start.MouseButton1Click:Connect(begin)
autoBtn.MouseButton1Click:Connect(function() if not running then begin()end;autoStart();refresh()end)
autoStopBtn.MouseButton1Click:Connect(function()stopAuto();refresh()end)
jumpBtn.MouseButton1Click:Connect(function()jumpMode=not jumpMode;jumpBtn.Text='FLASH: '..(jumpMode and 'ON' or 'OFF');add('AUTO','Instant near-target movement='..tostring(jumpMode));refresh()end)
touchBtn.MouseButton1Click:Connect(function()touchMode=not touchMode;touchBtn.Text='TOUCH TEST: '..(touchMode and 'ON' or 'OFF');add('AUTO','Proximity touch experiment='..tostring(touchMode));refresh()end)
speedBtn.MouseButton1Click:Connect(function()speed=(speed==2000 and 1000 or speed==1000 and 500 or speed==500 and 2000 or 2000);speedBtn.Text=tostring(speed);add('AUTO','Speed='..speed);refresh()end)
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
env.RaftControlV13Stop=cleanup
close.MouseButton1Click:Connect(cleanup)
add('SYSTEM','V13 loaded; fast filter collection + chest scan. No guarantee of server acceptance.');refresh()
