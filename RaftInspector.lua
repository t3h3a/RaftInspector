-- RAFT CONTROL V14.1 | resource search fix: wide coverage + spiral exploration
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local LP=Players.LocalPlayer
local PG=LP:WaitForChild('PlayerGui')
local env=(getgenv and getgenv()) or _G
for _,k in ipairs({'RaftControlV14Stop','RaftControlV13Stop','RaftInspectorV12Stop','RaftInspectorV11Stop','RaftInspectorV10Stop','RaftInspectorV9Stop','RaftInspectorV8Stop','RaftInspectorV7Stop'}) do if type(env[k])=='function' then pcall(env[k]) end end
for _,name in ipairs({'RaftControlV14','RaftControlV13','RaftControlV12','RaftInspectorV11','RaftInspectorV10','RaftInspectorV9','RaftInspectorV8','RaftInspectorV7'}) do local old=PG:FindFirstChild(name); if old then old:Destroy() end end
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
local range=100000 -- search all currently streamed / replicated world resources
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
 local ok,parts=pcall(function()return workspace:GetPartBoundsInRadius(r.Position,math.min(range,1000))end)
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
 local waypoint=0;local roamPosition=nil;local roamSince=0;local lastFire=0;local focus=nil;local focusSince=0;local lastArrive=0
 local lastActivationLog=0;local lastMotion=os.clock();local lastSearch=0
 equipHarpoon();scanCandidates()
 add('AUTO','Started | filter='..resourceMode..' | range='..range..' | speed='..speed..' | candidates='..scanCount..' | spiral exploration enabled')
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
     if os.clock()-focusSince>2.5 then
      visited[target]=os.clock()+3;target=nil;autoTarget=nil;focus=nil
      add('AUTO','Target timeout: skip for 3s')
     end
    end
    -- Spiral exploration rather than repeatedly circling only 145 studs from the raft.
    -- Wide scans see replicated models; streaming can hide distant world objects.
    -- Visit distant waypoints to reveal those objects. Pause briefly at each waypoint.
    if not target then
     if not roamPosition or ((r.Position-roamPosition).Magnitude<13 and os.clock()-roamSince>0.50)
         or os.clock()-roamSince>3 then
      waypoint=waypoint+1
      local ring=math.floor((waypoint-1)/12)
      local spoke=(waypoint-1)%12
      local radius=math.min(5000,220+ring*350)
      local angle=(spoke/12)*math.pi*2+(ring%2)*math.pi/12
      roamPosition=center+Vector3.new(math.cos(angle)*radius,8,math.sin(angle)*radius)
      roamSince=os.clock()
      if waypoint>=12*15 then waypoint=0 end
     end
     p=roamPosition
    else
     roamPosition=nil
     p=p+Vector3.new(0,4,0)
    end
    if p then
     local delta=p-r.Position
     if delta.Magnitude>4 then
      local now=os.clock()
      local dt=math.clamp(now-lastMotion,.015,.075)
      lastMotion=now
      local advance=math.min(delta.Magnitude,speed*dt)
      if jumpMode then advance=delta.Magnitude end
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
-- V14: wide Arabic dashboard, page-oriented controls.
local gui=Instance.new('ScreenGui');gui.Name='RaftControlV14';gui.ResetOnSpawn=false;gui.DisplayOrder=999;gui.Parent=PG
local frame=Instance.new('Frame');frame.Size=UDim2.fromOffset(860,520);frame.Position=UDim2.new(.5,-430,.5,-260);frame.BackgroundColor3=Color3.fromRGB(13,20,36);frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,17)
local edge=Instance.new('UIStroke');edge.Color=Color3.fromRGB(48,128,206);edge.Thickness=1.5;edge.Parent=frame
local guiScale=Instance.new('UIScale');guiScale.Parent=frame
local function fitScreen()
 local camera=workspace.CurrentCamera
 if camera then guiScale.Scale=math.min(1,camera.ViewportSize.X/880,camera.ViewportSize.Y/540) end
end
fitScreen()
local sidebar=Instance.new('Frame');sidebar.Size=UDim2.fromOffset(183,520);sidebar.Position=UDim2.fromOffset(677,0);sidebar.BackgroundColor3=Color3.fromRGB(21,32,53);sidebar.Parent=frame
Instance.new('UICorner',sidebar).CornerRadius=UDim.new(0,16)
local function makeLabel(parent,txt,x,y,w,h,size,col)
 local l=Instance.new('TextLabel');l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h);l.BackgroundTransparency=1;l.Text=txt;l.TextColor3=col or Color3.fromRGB(227,236,253);l.Font=Enum.Font.GothamBold;l.TextSize=size or 14;l.TextXAlignment=Enum.TextXAlignment.Left;l.TextWrapped=true;l.Parent=parent;return l
end
local function makeBtn(parent,txt,x,y,w,h,col)
 local v=Instance.new('TextButton');v.Position=UDim2.fromOffset(x,y);v.Size=UDim2.fromOffset(w,h);v.BackgroundColor3=col or Color3.fromRGB(42,91,154);v.TextColor3=Color3.new(1,1,1);v.Font=Enum.Font.GothamBold;v.TextSize=13;v.Text=txt;v.TextWrapped=true;v.Parent=parent;Instance.new('UICorner',v).CornerRadius=UDim.new(0,9);return v
end
makeLabel(sidebar,'⚓ التحكم بالسفن',16,13,166,34,19,Color3.fromRGB(92,207,252))
local pages={};local tabButtons={};local currentPage='الرئيسية'
local function page(name)
 local p=Instance.new('Frame');p.Name=name;p.Size=UDim2.fromOffset(646,382);p.Position=UDim2.fromOffset(16,127);p.BackgroundTransparency=1;p.Visible=false;p.Parent=frame;pages[name]=p;return p
end
local names={'الرئيسية','جمع الموارد','التنقل','اللاعبون','الصناديق','الفحص والتقارير','الإعدادات','اختبارات'}
for i,name in ipairs(names) do
 local tab=makeBtn(sidebar,name,10,53+(i-1)*52,162,43,Color3.fromRGB(35,57,89));tabButtons[name]=tab
 page(name)
 tab.MouseButton1Click:Connect(function()
  currentPage=name
  for title,content in pairs(pages) do content.Visible=(title==name);tabButtons[title].BackgroundColor3=title==name and Color3.fromRGB(33,123,172) or Color3.fromRGB(35,57,89) end
 end)
end
pages['الرئيسية'].Visible=true;tabButtons['الرئيسية'].BackgroundColor3=Color3.fromRGB(33,123,172)
makeLabel(frame,'RAFT CONTROL   |   V14',19,9,410,31,23,Color3.fromRGB(92,207,252))
local hide=makeBtn(frame,'إخفاء',478,12,80,29,Color3.fromRGB(51,105,166))
local close=makeBtn(frame,'إغلاق ×',570,12,87,29,Color3.fromRGB(151,62,79))
local accountLabel=makeLabel(frame,'الحساب: '..LP.Name,19,43,625,22,14)
local matsLabel=makeLabel(frame,'خشب: 0  |  حديد: 0  |  خردة: 0  |  ذهب: 0',19,68,625,22,14,Color3.fromRGB(148,236,179))
local gainsLabel=makeLabel(frame,'التغير من بداية التشغيل: +0',19,92,625,22,13,Color3.fromRGB(247,208,149))
local status=makeLabel(frame,'جاهز',19,497,635,18,12,Color3.fromRGB(138,202,243))
local float=makeBtn(gui,'⚓ RAFT',0,0,110,42,Color3.fromRGB(34,122,182));float.Position=UDim2.new(1,-128,0,95);float.Visible=false;float.Active=true;float.Draggable=true
hide.MouseButton1Click:Connect(function()frame.Visible=false;float.Visible=true end)
float.MouseButton1Click:Connect(function()frame.Visible=true;float.Visible=false;fitScreen()end)
local green=Color3.fromRGB(27,139,101);local blue=Color3.fromRGB(47,103,164)
local red=Color3.fromRGB(161,64,81);local purple=Color3.fromRGB(109,77,173)
local homePage=pages['الرئيسية']
makeLabel(homePage,'لوحة التحكم الرئيسية',9,4,620,32,21)
makeLabel(homePage,'التحكم بالتجميع والصناديق والفحص من صفحة واحدة. الإحصائيات تُقرأ من اللاعب مباشرة.',9,42,623,45,13)
local quickResources=makeBtn(homePage,'⚙ تشغيل جمع الموارد',8,98,303,49,green)
local quickStop=makeBtn(homePage,'■ إيقاف جميع العمليات',325,98,303,49,red)
local quickChests=makeBtn(homePage,'فحص سفن اللاعبين',8,165,303,46,blue)
local quickReport=makeBtn(homePage,'نسخ التقرير الشامل',325,165,303,46,purple)
local homeNote=makeLabel(homePage,'الجمع والنقل يتطلبان قبول اللعبة الفعلي. محاولات التفاعل لا تعني نجاح النقل.',10,250,620,58,14,Color3.fromRGB(241,193,130))
local rPage=pages['جمع الموارد']
makeLabel(rPage,'جمع الموارد والفلاتر',9,3,620,31,21)
local autoBtn=makeBtn(rPage,'▶ جمع تلقائي',7,48,303,42,green)
local autoStopBtn=makeBtn(rPage,'■ إيقاف جمع الموارد',322,48,303,42,red)
local filterBtn=makeBtn(rPage,'فلتر: جميع الموارد',7,100,303,42,blue)
local rangeBtn=makeBtn(rPage,'نطاق: كامل المتاح',322,100,303,42,blue)
local jumpBtn=makeBtn(rPage,'انتقال سريع: مفعل',7,152,303,42,purple)
local speedBtn=makeBtn(rPage,'السرعة: 2000',322,152,303,42,purple)
local touchBtn=makeBtn(rPage,'اختبار اللمس: مفعل',7,204,303,42,blue)
makeLabel(rPage,'الحديد = صفائح معدنية؛ الخردة = براميل (تجريبي). البحث الكامل للعناصر المحملة فقط.',8,264,616,44,13,Color3.fromRGB(235,195,133))
local movePage=pages['التنقل']
makeLabel(movePage,'التنقل والمواقع المحفوظة',9,3,615,31,21)
local savedPosition=nil
local savePositionBtn=makeBtn(movePage,'حفظ موقعي الحالي',8,48,302,44,blue)
local goPositionBtn=makeBtn(movePage,'الرجوع للموقع المحفوظ',324,48,302,44,purple)
local backRaftBtn=makeBtn(movePage,'الانتقال إلى سفينتي',8,108,618,44,green)
local moveInfo=makeLabel(movePage,'لن تتم الحركة إذا لم تتوفر شخصية أو موقع معروف.',8,169,615,80,14)
local pPage=pages['اللاعبون']
makeLabel(pPage,'اللاعبون الموجودون في السيرفر',9,3,615,31,21)
local playersInfo=makeLabel(pPage,'',8,45,620,46,14)
local playerScroll=Instance.new('ScrollingFrame');playerScroll.Parent=pPage;playerScroll.Position=UDim2.fromOffset(8,98);playerScroll.Size=UDim2.fromOffset(619,265);playerScroll.BackgroundColor3=Color3.fromRGB(18,30,49);playerScroll.ScrollBarThickness=5;playerScroll.BorderSizePixel=0
Instance.new('UICorner',playerScroll).CornerRadius=UDim.new(0,9)
local listLayout=Instance.new('UIListLayout');listLayout.Padding=UDim.new(0,6);listLayout.Parent=playerScroll
local cPage=pages['الصناديق']
makeLabel(cPage,'فحص السفن والصناديق',9,3,615,31,21)
local chestBtn=makeBtn(cPage,'فحص جميع صناديق السفن',8,43,303,45,blue)
local warpChestBtn=makeBtn(cPage,'انتقال للصندوق التالي',324,43,303,45,purple)
local chestAutoBtn=makeBtn(cPage,'بدء مراقبة الدرع والتفاعل',8,100,303,45,green)
local chestStopBtn=makeBtn(cPage,'إيقاف مراقبة الصناديق',324,100,303,45,red)
local chestInfo=makeLabel(cPage,'لم يتم فحص الصناديق بعد.',8,158,618,64,14,Color3.fromRGB(245,210,151))
local chestTargetBtn=makeBtn(cPage,'الهدف: جميع السفن',8,232,618,42,blue)
makeLabel(cPage,'يعتمد التفاعل على ظهور ProximityPrompt وحالة الدرع الظاهرة؛ التسليم غير مضمون.',8,290,618,51,13)
local dPage=pages['الفحص والتقارير']
makeLabel(dPage,'الفحص والتشخيص والتقارير',9,3,615,31,21)
local start=makeBtn(dPage,'بدء الفحص المستمر',7,37,201,39,green)
local stop=makeBtn(dPage,'إيقاف الفحص',220,37,198,39,red)
local test=makeBtn(dPage,'اختبار السكربت',431,37,196,39,blue)
local inventory=makeBtn(dPage,'المخزون',7,85,149,36,blue)
local server=makeBtn(dPage,'واجهات مرئية',166,85,149,36,blue)
local copy=makeBtn(dPage,'نسخ النتائج',326,85,149,36,purple)
local reset=makeBtn(dPage,'مسح التقرير',485,85,142,36,red)
local output=Instance.new('TextBox');output.Position=UDim2.fromOffset(7,136);output.Size=UDim2.fromOffset(619,226);output.BackgroundColor3=Color3.fromRGB(7,13,24);output.TextColor3=Color3.fromRGB(148,236,179);output.Font=Enum.Font.Code;output.TextSize=12;output.TextXAlignment=Enum.TextXAlignment.Left;output.TextYAlignment=Enum.TextYAlignment.Top;output.TextWrapped=true;output.MultiLine=true;output.TextEditable=false;output.ClearTextOnFocus=false;output.Text='جاهز للفحص';output.Parent=dPage;Instance.new('UICorner',output).CornerRadius=UDim.new(0,8)
local settingPage=pages['الإعدادات']
makeLabel(settingPage,'الإعدادات والتحكم',9,3,615,31,21)
local settingScan=makeBtn(settingPage,'تشغيل فحص الموارد',9,49,300,44,blue)
local settingStop=makeBtn(settingPage,'إيقاف كل الأنظمة',326,49,300,44,red)
makeLabel(settingPage,'لتعديل سرعة الحركة والنطاق والفلتر افتح صفحة جمع الموارد.',9,117,620,58,14)
makeLabel(settingPage,'زر الإخفاء يحافظ على تشغيل العمليات؛ زر الإغلاق يوقفها وينظف الاتصالات.',9,187,620,58,14)
-- Experimental test tab: read-only proximity sweep plus optional touch-interest experiment.
-- This intentionally never activates/equips the harpoon and never claims server grants.
local testPage=pages['اختبارات']
makeLabel(testPage,'اختبارات | هالة التقاط الموارد (Aura Pickup)',6,2,630,30,19)
makeLabel(testPage,'اختبار مستقل عن الحربة؛ العثور على مورد أو إرسال لمس لا يثبت جمعه.',6,35,632,40,13,Color3.fromRGB(252,210,146))
local auraOn=false
local auraRadius=250
local auraRadii={100,250,500,1000,2500}
local auraRadiusIndex=2
local auraMode='ALL'
local auraModes={'ALL','WOOD','METAL','SCRAP','CHESTS','OTHER'}
local auraModeIndex=1
local auraAttempts=0
local auraFound=0
local auraTouchSupported=type(firetouchinterest)=='function'
local auraTouched={}
local auraInitial={Wood=tonumber(LP:GetAttribute('Mat_Wood')) or 0,Metal=tonumber(LP:GetAttribute('Mat_Metal')) or 0,Scrap=tonumber(LP:GetAttribute('Mat_Scrap')) or 0}
local auraDetected=makeLabel(testPage,'الموارد داخل النطاق: 0 | محاولات لمس: 0',7,94,622,27,14)
local auraResults=makeLabel(testPage,'زيادة المخزون أثناء الاختبار: خشب 0 | حديد 0 | خردة 0',7,124,622,43,13,Color3.fromRGB(141,232,171))
local auraStartButton=makeBtn(testPage,'بدء اختبار الأورا',7,175,301,42,green)
local auraStopButton=makeBtn(testPage,'إيقاف اختبار الأورا',321,175,306,42,red)
local auraFilterButton=makeBtn(testPage,'الفلتر: الكل',7,226,301,42,blue)
local auraRadiusButton=makeBtn(testPage,'نطاق الفحص: 250',321,226,306,42,purple)
local auraStatus=makeLabel(testPage,'الحالة: متوقف | واجهة اللمس: '..(auraTouchSupported and 'متاحة' or 'غير متاحة'),7,279,622,33,13)
local auraCopyButton=makeBtn(testPage,'نسخ تقرير الاختبار',7,320,620,42,blue)
local function auraMatches(obj)
 return auraMode=='ALL' or resourceType(obj)==auraMode
end
local function auraUpdate()
 if not alive then return end
 local w=(tonumber(LP:GetAttribute('Mat_Wood')) or 0)-auraInitial.Wood
 local m=(tonumber(LP:GetAttribute('Mat_Metal')) or 0)-auraInitial.Metal
 local c=(tonumber(LP:GetAttribute('Mat_Scrap')) or 0)-auraInitial.Scrap
 auraDetected.Text='الموارد داخل النطاق: '..auraFound..' | محاولات لمس: '..auraAttempts
 auraResults.Text='تغير المخزون منذ بدء الاختبار: خشب '..w..' | حديد '..m..' | خردة '..c
 auraStatus.Text='الحالة: '..(auraOn and 'يعمل' or 'متوقف')..' | واجهة اللمس: '..(auraTouchSupported and 'متاحة' or 'غير متاحة')
end
local function auraStop()
 if auraOn then auraOn=false;add('AURA','test stopped; attempts='..auraAttempts) end
 auraUpdate()
end
local function auraStart()
 if auraOn then return end
 -- Keep the experiment isolated from harpoon collection for meaningful inventory deltas.
 if auto then stopAuto();add('AURA','existing harpoon auto stopped for isolated test') end
 auraOn=true
 auraAttempts=0;auraFound=0;auraTouched={}
 auraInitial={Wood=tonumber(LP:GetAttribute('Mat_Wood')) or 0,Metal=tonumber(LP:GetAttribute('Mat_Metal')) or 0,Scrap=tonumber(LP:GetAttribute('Mat_Scrap')) or 0}
 add('AURA','test started | radius='..auraRadius..' | filter='..auraMode..' | touchAPI='..tostring(auraTouchSupported)..' | no weapon')
 task.spawn(function()
  local lastSummary=0
  while alive and auraOn do
   local ok,err=pcall(function()
    -- This scans what the client has streamed; it cannot discover absent server objects.
    scanCandidates()
    local hr=root()
    if not hr then return end
    local count=0
    local current=os.clock()
    for obj,item in pairs(candidates) do
     if obj.Parent and item.part and item.part.Parent and auraMatches(obj) then
      local part=item.part
      local distance=(part.Position-hr.Position).Magnitude
      if part.Position.Y>-500 and distance<=auraRadius then
       count=count+1
       -- Test-only synthetic touch signal. This may be ignored by the game's server.
       if auraTouchSupported and part.CanTouch and (auraTouched[obj] or 0)<current and auraAttempts<5000 then
        auraTouched[obj]=current+2
        local fired=pcall(function()
         firetouchinterest(hr,part,0)
         firetouchinterest(hr,part,1)
        end)
        auraAttempts=auraAttempts+1
        if auraAttempts<=8 or auraAttempts%30==0 then
         add('AURA TOUCH','target='..obj.Name..' distance='..math.floor(distance)..' signal='..tostring(fired)..' (not collection confirmation)')
        end
       end
      end
     end
    end
    auraFound=count
    auraUpdate()
    if current-lastSummary>8 then
     lastSummary=current
     add('AURA SCAN','visible targets='..count..' radius='..auraRadius..' filter='..auraMode..' attempts='..auraAttempts)
    end
   end)
   if not ok then add('AURA ERROR',tostring(err))end
   task.wait(.4)
  end
 end)
 auraUpdate()
end
auraStartButton.MouseButton1Click:Connect(auraStart)
auraStopButton.MouseButton1Click:Connect(auraStop)
auraFilterButton.MouseButton1Click:Connect(function()
 auraModeIndex=auraModeIndex%#auraModes+1
 auraMode=auraModes[auraModeIndex]
 auraFilterButton.Text='الفلتر: '..auraMode
 add('AURA','filter='..auraMode)
end)
auraRadiusButton.MouseButton1Click:Connect(function()
 auraRadiusIndex=auraRadiusIndex%#auraRadii+1
 auraRadius=auraRadii[auraRadiusIndex]
 auraRadiusButton.Text='نطاق الفحص: '..auraRadius
 add('AURA','radius='..auraRadius)
end)
auraCopyButton.MouseButton1Click:Connect(function()
 local txt='AURA TEST | player='..LP.Name..' radius='..auraRadius..' filter='..auraMode
  ..' visible='..auraFound..' touchAttempts='..auraAttempts
  ..' touchSupported='..tostring(auraTouchSupported)
  ..' | inventory delta W='..((tonumber(LP:GetAttribute('Mat_Wood')) or 0)-auraInitial.Wood)
  ..' M='..((tonumber(LP:GetAttribute('Mat_Metal')) or 0)-auraInitial.Metal)
  ..' S='..((tonumber(LP:GetAttribute('Mat_Scrap')) or 0)-auraInitial.Scrap)
  ..'\nTOUCH IS NOT PROOF OF SERVER HARVEST\n'..table.concat(logs,'\n')
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,txt)
  add('AURA',ok and 'report copied' or 'clipboard error')
 else add('AURA','setclipboard unavailable') end
end)
-- V14.3: HARPOON LAB -- confined to the existing TESTS page.
-- The pre-existing collection, navigation, chest logic and visual layout remain unchanged.
-- A single Tool:Activate request is NOT a verified shot; burst attempts are rate-limited.
local testsScroll=Instance.new('ScrollingFrame')
testsScroll.Name='TestsContent'
testsScroll.Size=UDim2.fromScale(1,1)
testsScroll.Position=UDim2.fromOffset(0,0)
testsScroll.BackgroundTransparency=1
testsScroll.BorderSizePixel=0
testsScroll.ScrollBarThickness=7
testsScroll.CanvasSize=UDim2.fromOffset(0,820)
testsScroll.ScrollingDirection=Enum.ScrollingDirection.Y
testsScroll.Parent=testPage
-- Move only existing TEST page children into the scrolling panel without changing positions.
for _,child in ipairs(testPage:GetChildren()) do
 if child~=testsScroll and child:IsA('GuiObject') then child.Parent=testsScroll end
end
local labLine=Instance.new('Frame')
labLine.Position=UDim2.fromOffset(7,380)
labLine.Size=UDim2.fromOffset(620,2)
labLine.BackgroundColor3=Color3.fromRGB(58,139,206)
labLine.BorderSizePixel=0
labLine.Parent=testsScroll
makeLabel(testsScroll,'مختبر الحربة | HARPOON LAB',7,391,620,32,20,Color3.fromRGB(92,207,252))
makeLabel(testsScroll,'اختبار طلبات تفعيل السلاح وقياس المقذوفات وتغيّر المخزون. لا يضمن تعدد الإصابات.',7,426,620,40,12,Color3.fromRGB(252,210,146))
local labCountOptions={1,5,20,100}
local labCountIndex=1
local labCount=labCountOptions[labCountIndex]
local labDelayOptions={0.5,0.25,0.15}
local labDelayIndex=1
local labDelay=labDelayOptions[labDelayIndex]
local labRunning=false
local labProjectileCount=0
hook(workspace.DescendantAdded,function(obj)
 if labRunning and obj.Name=='HarpoonProjectile' then labProjectileCount=labProjectileCount+1 end
end)
local labStopRequested=false
local labTries=0
local labLastReport='لم يبدأ اختبار الحربة بعد'
local labBatchButton=makeBtn(testsScroll,'عدد المحاولات: 1',7,475,301,40,blue)
local labDelayButton=makeBtn(testsScroll,'الفاصل: 0.50 ثانية',321,475,306,40,purple)
local labStartButton=makeBtn(testsScroll,'بدء اختبار الحربة',7,525,301,43,green)
local labStopButton=makeBtn(testsScroll,'إيقاف الاختبار',321,525,306,43,red)
local labStatus=makeLabel(testsScroll,'الحالة: متوقف | المحاولات: 0',7,577,620,40,13,Color3.fromRGB(141,232,171))
local labResult=makeLabel(testsScroll,'المقذوفات: 0 | تغير المخزون: خشب 0، حديد 0، خردة 0',7,617,620,52,13)
local labCopyButton=makeBtn(testsScroll,'نسخ تقرير مختبر الحربة',7,682,620,42,blue)
makeLabel(testsScroll,'مهم: 100 محاولة تفعيل ليست 100 طلقة معتمدة. الخادم قد يرفض معظمها.',7,733,620,55,12,Color3.fromRGB(252,210,146))
labBatchButton.MouseButton1Click:Connect(function()
 if labRunning then return end
 labCountIndex=labCountIndex%#labCountOptions+1
 labCount=labCountOptions[labCountIndex]
 labBatchButton.Text='عدد المحاولات: '..labCount
end)
labDelayButton.MouseButton1Click:Connect(function()
 if labRunning then return end
 labDelayIndex=labDelayIndex%#labDelayOptions+1
 labDelay=labDelayOptions[labDelayIndex]
 labDelayButton.Text=string.format('الفاصل: %.2f ثانية',labDelay)
end)
labStartButton.MouseButton1Click:Connect(function()
 if labRunning then return end
 -- Isolate the trial: never combine with auto collection or synthetic touches.
 if auto then stopAuto() end
 if auraOn then auraStop() end
 local harpoon=equipHarpoon()
 if not harpoon then
  labStatus.Text='الحالة: لم يتم العثور على الحربة'
  add('HARPOON LAB','Cannot start: no harpoon tool')
  return
 end
 labRunning=true
 labStopRequested=false
 labTries=0
 local beforeShots=labProjectileCount
 local beforeWood=tonumber(LP:GetAttribute('Mat_Wood')) or 0
 local beforeMetal=tonumber(LP:GetAttribute('Mat_Metal')) or 0
 local beforeScrap=tonumber(LP:GetAttribute('Mat_Scrap')) or 0
 local started=os.clock()
 add('HARPOON LAB','START requested='..labCount..' interval='..labDelay..' tool='..harpoon.Name..' no remote spoofing')
 task.spawn(function()
  for index=1,labCount do
   if not alive or labStopRequested then break end
   if not harpoon.Parent or not LP.Character or not harpoon:IsDescendantOf(LP.Character) then
    add('HARPOON LAB','Harpoon unequipped, test stopped')
    break
   end
   local ok,err=pcall(function()harpoon:Deactivate();harpoon:Activate()end)
   labTries=labTries+1
   if not ok then add('HARPOON LAB ERROR',tostring(err))end
   labStatus.Text='الحالة: اختبار جار | الطلبات: '..labTries..' / '..labCount
   task.wait(labDelay)
  end
  -- Give visual projectiles / replicated inventory changes a small observation window.
  local waitEnd=os.clock()+2
  while alive and not labStopRequested and os.clock()<waitEnd do task.wait(.15) end
  local dShots=labProjectileCount-beforeShots
  local dWood=(tonumber(LP:GetAttribute('Mat_Wood')) or 0)-beforeWood
  local dMetal=(tonumber(LP:GetAttribute('Mat_Metal')) or 0)-beforeMetal
  local dScrap=(tonumber(LP:GetAttribute('Mat_Scrap')) or 0)-beforeScrap
  local elapsed=os.clock()-started
  labLastReport=string.format('HARPOON LAB | player=%s | requests=%d/%d | interval=%.2fs | visibleProjectiles=%d | deltaWood=%d deltaMetal=%d deltaScrap=%d | elapsed=%.2fs | note: activation and projectile counts do not confirm server harvest',LP.Name,labTries,labCount,labDelay,dShots,dWood,dMetal,dScrap,elapsed)
  labResult.Text='المقذوفات المرئية: '..dShots..' | خشب '..dWood..' | حديد '..dMetal..' | خردة '..dScrap
  labStatus.Text='الحالة: '..(labStopRequested and 'متوقف مبكرا' or 'انتهى')..' | محاولات: '..labTries
  add('HARPOON LAB',labLastReport)
  labRunning=false
 end)
end)
labStopButton.MouseButton1Click:Connect(function()
 labStopRequested=true
 labStatus.Text='الحالة: جار إيقاف الاختبار'
 add('HARPOON LAB','Stop requested')
end)
labCopyButton.MouseButton1Click:Connect(function()
 local txt=labLastReport..'\n=== HARPOON LAB LOGS ===\n'
 for _,line in ipairs(logs) do if line:find('%[HARPOON LAB') then txt=txt..line..'\n' end end
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,txt)
  add('HARPOON LAB',ok and 'Report copied' or 'Clipboard failure')
 else add('HARPOON LAB','Clipboard unavailable') end
end)
-- V14.4: TIMING LAB (passive observer). Added ONLY to the Tests page.
-- Does not fire, change, equip or move the tool. Timing is observational, not proof of causality.
testsScroll.CanvasSize=UDim2.fromOffset(0,1350)
local timingLine=Instance.new('Frame')
timingLine.Position=UDim2.fromOffset(7,802)
timingLine.Size=UDim2.fromOffset(620,2)
timingLine.BackgroundColor3=Color3.fromRGB(58,139,206)
timingLine.BorderSizePixel=0
timingLine.Parent=testsScroll
makeLabel(testsScroll,'مختبر توقيت الجمع | TIMING LAB',7,816,620,32,19,Color3.fromRGB(92,207,252))
makeLabel(testsScroll,'مراقبة فقط: أطلق الحربة يدويا على مورد واحد. لا يتم تفعيل السلاح تلقائيا.',7,856,620,48,13,Color3.fromRGB(252,210,146))
local timingStart=makeBtn(testsScroll,'بدء تسجيل التوقيت',7,916,301,43,green)
local timingStop=makeBtn(testsScroll,'إيقاف تسجيل التوقيت',321,916,306,43,red)
local timingStatus=makeLabel(testsScroll,'الحالة: متوقف',7,967,620,35,13,Color3.fromRGB(141,232,171))
local timingStats=makeLabel(testsScroll,'الإطلاقات: 0 | المقذوفات: 0 | اختفاء المرئيات: 0 | تغيرات الموارد: 0',7,1001,620,54,13)
local timingCopy=makeBtn(testsScroll,'نسخ تقرير التوقيت الكامل',7,1068,620,42,blue)
local timingOutput=Instance.new('TextBox')
timingOutput.Position=UDim2.fromOffset(7,1120)
timingOutput.Size=UDim2.fromOffset(620,204)
timingOutput.BackgroundColor3=Color3.fromRGB(7,13,24)
timingOutput.TextColor3=Color3.fromRGB(148,236,179)
timingOutput.Font=Enum.Font.Code
timingOutput.TextSize=12
timingOutput.TextXAlignment=Enum.TextXAlignment.Left
timingOutput.TextYAlignment=Enum.TextYAlignment.Top
timingOutput.TextWrapped=true
timingOutput.MultiLine=true
timingOutput.TextEditable=false
timingOutput.ClearTextOnFocus=false
timingOutput.Text='لم يبدأ القياس'
timingOutput.Parent=testsScroll
Instance.new('UICorner',timingOutput).CornerRadius=UDim.new(0,8)
local timingActive=false
local timingStarted=0
local timingEvents={}
local timingCounts={fires=0,projectiles=0,removed=0,changes=0}
local timingLastFire=nil
local timingLastProjectile=nil
local timingLastRemoval=nil
local timingLastChange=nil
local timingPending={}
local timingObservedTool=nil
local timingToolConnection=nil
local timingStartInventory=nil
local function timingValue(name) return tonumber(LP:GetAttribute(name)) or 0 end
local function timingEvent(tag,msg)
 if not timingActive then return end
 local t=os.clock()-timingStarted
 local entry=string.format('+%.3fs [%s] %s',t,tag,msg)
 timingEvents[#timingEvents+1]=entry
 if #timingEvents>1500 then table.remove(timingEvents,1) end
 add('TIMING',entry)
 timingOutput.Text=table.concat(timingEvents,'\n',math.max(1,#timingEvents-14),#timingEvents)
 timingStats.Text=string.format('إطلاقات: %d | مقذوفات: %d | مرئيات اختفت: %d | تغيرات المخزون: %d',timingCounts.fires,timingCounts.projectiles,timingCounts.removed,timingCounts.changes)
end
local function timingBindTool()
 if timingToolConnection then timingToolConnection:Disconnect();timingToolConnection=nil end
 timingObservedTool=nil
 local t=tool()
 if t and t.Name:lower():find('harpoon',1,true) then
  timingObservedTool=t
  timingToolConnection=t.Activated:Connect(function()
   if not timingActive then return end
   timingCounts.fires=timingCounts.fires+1
   timingLastFire=os.clock()
   timingEvent('FIRE','Tool.Activated | #='..timingCounts.fires)
  end)
  timingEvent('TOOL','tracking '..t.Name)
 else
  timingEvent('TOOL','No equipped harpoon; equip it manually')
 end
end
local function timingCheckpoint()
 if not timingActive then return end
 local t=tool()
 if t~=timingObservedTool then timingBindTool() end
end
local function timingMarker(obj)
 if not timingActive then return false end
 local folder=workspace:FindFirstChild('LocalHarpoonVisuals')
 if not folder or not obj:IsDescendantOf(folder) then return false end
 local n=obj.Name
 if n:sub(1,7)~='Visual_' then return false end
 local ok,p=pcall(function()
  if obj:IsA('BasePart') then return obj.Position end
  if obj:IsA('Model') then return obj:GetPivot().Position end
 end)
 if not ok or not p or p.Y < -1000 then return false end
 return true
end
hook(workspace.DescendantAdded,function(obj)
 if not timingActive then return end
 if obj.Name=='HarpoonProjectile' then
  timingCounts.projectiles=timingCounts.projectiles+1
  local now=os.clock()
  timingLastProjectile=now
  local dt=timingLastFire and string.format(' after last activation %.3fs',now-timingLastFire) or ' no observed activation'
  timingEvent('PROJECTILE','visible projectile #'..timingCounts.projectiles..dt)
 end
end)
hook(workspace.DescendantRemoving,function(obj)
 if not timingMarker(obj) then return end
 timingCounts.removed=timingCounts.removed+1
 timingLastRemoval=os.clock()
 local dt=timingLastProjectile and string.format(' after last projectile %.3fs',timingLastRemoval-timingLastProjectile) or ' no observed projectile'
 timingEvent('VISUAL_REMOVED',obj.Name..dt..' (may be streaming/despawn, not proven harvest)')
end)
hook(LP.AttributeChanged,function(name)
 if not timingActive or (name~='Mat_Wood' and name~='Mat_Metal' and name~='Mat_Scrap') then return end
 timingCounts.changes=timingCounts.changes+1
 timingLastChange=os.clock()
 local dt=timingLastProjectile and string.format(' after last projectile %.3fs',timingLastChange-timingLastProjectile) or ' no observed projectile'
 timingEvent('INVENTORY',name..'='..tostring(LP:GetAttribute(name))..dt)
end)
timingStart.MouseButton1Click:Connect(function()
 if timingActive then return end
 if auto then stopAuto() end
 if auraOn then auraStop() end
 if labRunning then labStopRequested=true;add('TIMING','Harpoon lab stopping; wait until it ends before manual measurement');return end
 timingEvents={};timingCounts={fires=0,projectiles=0,removed=0,changes=0}
 timingLastFire=nil;timingLastProjectile=nil;timingLastRemoval=nil;timingLastChange=nil
 timingStartInventory={Wood=timingValue('Mat_Wood'),Metal=timingValue('Mat_Metal'),Scrap=timingValue('Mat_Scrap')}
 timingStarted=os.clock();timingActive=true
 timingStatus.Text='الحالة: جاري الرصد | اطلق الحربة يدويا'
 timingStats.Text='إطلاقات: 0 | مقذوفات: 0 | مرئيات اختفت: 0 | تغيرات المخزون: 0'
 timingEvent('START','Passive observation only; no automatic fire')
 timingBindTool()
end)
timingStop.MouseButton1Click:Connect(function()
 if not timingActive then return end
 timingEvent('END',string.format('delta wood=%d metal=%d scrap=%d',timingValue('Mat_Wood')-timingStartInventory.Wood,timingValue('Mat_Metal')-timingStartInventory.Metal,timingValue('Mat_Scrap')-timingStartInventory.Scrap))
 timingActive=false
 if timingToolConnection then timingToolConnection:Disconnect();timingToolConnection=nil end
 timingStatus.Text='الحالة: التسجيل متوقف'
end)
timingCopy.MouseButton1Click:Connect(function()
 local header=string.format('RAFT TIMING LAB | player=%s | place=%s | active=%s | fires=%d projectiles=%d visualsRemoved=%d inventoryChanges=%d\nCAUTION: Time correlation does not prove which hit produced an inventory change.\n',LP.Name,tostring(game.PlaceId),tostring(timingActive),timingCounts.fires,timingCounts.projectiles,timingCounts.removed,timingCounts.changes)
 local body=header..table.concat(timingEvents,'\n')
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,body)
  if ok then timingStatus.Text='تم نسخ تقرير التوقيت' else timingStatus.Text='تعذر نسخ التقرير' end
 else timingStatus.Text='النسخ غير متاح' end
end)
task.spawn(function()
 while alive do
  if timingActive then timingCheckpoint() end
  task.wait(0.3)
 end
 if timingToolConnection then timingToolConnection:Disconnect() end
end)
local function report()
 return table.concat({'RAFT CONTROL V14 FULL REPORT','PlaceId: '..game.PlaceId,'Player: '..LP.Name,'Entries retained: '..#logs,'Total events: '..total,'Projectiles: '..projectiles,'Changes: '..changes,'Candidates: '..scanCount..' | Auto active: '..tostring(auto)..' | Auto target: '..(autoTarget and autoTarget.Name or 'none'),'Filter='..resourceMode..'; range='..range..'; speed='..speed..'; instant jump='..tostring(jumpMode)..'; touch test='..tostring(touchMode)..'; touch attempts='..touchTries,'Materials: Wood='..tostring(LP:GetAttribute('Mat_Wood'))..' Metal='..tostring(LP:GetAttribute('Mat_Metal'))..' Scrap='..tostring(LP:GetAttribute('Mat_Scrap'))..' Gold='..tostring(LP:GetAttribute('Cash')),'Note: server controls actual materials; chest inspection does not confirm transfers.','===== ALL RESULTS IN TIME ORDER =====',table.concat(logs,'\n')},'\n')
end
local function refresh()
 if not alive then return end
 status.Text=(running and 'SCANNING LIVE' or 'STOPPED')..' | AUTO: '..(auto and 'ON' or 'OFF')..' | '..resourceMode..' | Targets: '..scanCount
 matsLabel.Text='خشب '..tostring(LP:GetAttribute('Mat_Wood') or 0)..' | حديد '..tostring(LP:GetAttribute('Mat_Metal') or 0)..' | خردة '..tostring(LP:GetAttribute('Mat_Scrap') or 0)..' | ذهب '..tostring(LP:GetAttribute('Cash') or 0)
 gainsLabel.Text='التغير: خشب '..((tonumber(LP:GetAttribute('Mat_Wood')) or 0)-initial.Wood)..' | حديد '..((tonumber(LP:GetAttribute('Mat_Metal')) or 0)-initial.Metal)..' | خردة '..((tonumber(LP:GetAttribute('Mat_Scrap')) or 0)-initial.Scrap)
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
 filterBtn.Text='فلتر: '..resourceMode
 visited={};autoTarget=nil
 add('FILTER','Selected '..resourceMode..' (metal barrels=SCRAP; sheets=METAL; logs=WOOD)')
 refresh()
end)
rangeBtn.MouseButton1Click:Connect(function()
 range=(range==100000 and 3500 or range==3500 and 800 or 100000)
 rangeBtn.Text=(range==100000 and 'نطاق: كامل المتاح' or 'نطاق: '..range)
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
jumpBtn.MouseButton1Click:Connect(function()jumpMode=not jumpMode;jumpBtn.Text='انتقال سريع: '..(jumpMode and 'مفعل' or 'متوقف');add('AUTO','Instant near-target movement='..tostring(jumpMode));refresh()end)
touchBtn.MouseButton1Click:Connect(function()touchMode=not touchMode;touchBtn.Text='اختبار اللمس: '..(touchMode and 'مفعل' or 'متوقف');add('AUTO','Proximity touch experiment='..tostring(touchMode));refresh()end)
speedBtn.MouseButton1Click:Connect(function()speed=(speed==2000 and 1000 or speed==1000 and 500 or speed==500 and 2000 or 2000);speedBtn.Text='السرعة: '..tostring(speed);add('AUTO','Speed='..speed);refresh()end)
stop.MouseButton1Click:Connect(function()stopAuto();running=false;generation=generation+1;add('SYSTEM','STOPPED by user');refresh()end)
test.MouseButton1Click:Connect(runTest)
inventory.MouseButton1Click:Connect(function()snapshot();refresh()end)
server.MouseButton1Click:Connect(function()serverVisible();refresh()end)
copy.MouseButton1Click:Connect(function()
 local txt=report()
 if type(setclipboard)=='function' then local ok=pcall(setclipboard,txt);copy.Text=ok and 'تم النسخ' or 'فشل النسخ' else add('SYSTEM','Clipboard not supported') end
 task.delay(2,function()if alive then copy.Text='نسخ النتائج' end end)
end)
reset.MouseButton1Click:Connect(function()logs={};total=0;changes=0;projectiles=0;add('SYSTEM','REPORT CLEARED');refresh()end)
local function cleanup()
 stopAuto();alive=false;running=false;generation=generation+1
 for _,c in ipairs(links) do pcall(function()c:Disconnect()end) end
 if gui.Parent then gui:Destroy()end
end
env.RaftControlV14Stop=cleanup
close.MouseButton1Click:Connect(function()cleanup()end)
-- Additional V14 navigation and chest-monitor controls.
local function getMyRaft()
 local folder=workspace:FindFirstChild('Rafts')
 if not folder then return nil end
 for _,raft in ipairs(folder:GetChildren()) do
  if raft.Name:lower():find(LP.Name:lower(),1,true) then return raft end
 end
end
local function nearestPart(obj)
 if obj:IsA('BasePart') then return obj end
 return obj:FindFirstChildWhichIsA('BasePart',true)
end
local function sendTo(part)
 local r=root();if not r or not part then return false end
 local ok=pcall(function()r.CFrame=CFrame.new(part.Position+Vector3.new(0,4,0))end)
 return ok
end
savePositionBtn.MouseButton1Click:Connect(function()
 local r=root();if r then savedPosition=r.CFrame;moveInfo.Text='تم حفظ الموقع: '..tostring(r.Position);add('MOVE','saved '..tostring(r.Position)) end
end)
goPositionBtn.MouseButton1Click:Connect(function()
 local r=root();if r and savedPosition then pcall(function()r.CFrame=savedPosition end);add('MOVE','returned to saved position')else moveInfo.Text='لا يوجد موقع محفوظ' end
end)
backRaftBtn.MouseButton1Click:Connect(function()
 local raft=getMyRaft();local bp=raft and nearestPart(raft)
 if sendTo(bp) then moveInfo.Text='تم طلب الانتقال إلى '..raft.Name;add('MOVE','requested own raft') else moveInfo.Text='سفينتك غير ظاهرة حاليا' end
end)
local function updatePlayers()
 for _,item in ipairs(playerScroll:GetChildren()) do if item:IsA('GuiObject') then item:Destroy()end end
 playersInfo.Text='عدد اللاعبين: '..#Players:GetPlayers()..' | اضغط اللاعب للانتقال إلى موقعه'
 for _,plr in ipairs(Players:GetPlayers()) do
  local line=makeBtn(playerScroll,(plr==LP and '● ' or '◉ ')..plr.DisplayName..'  (@'..plr.Name..')',3,0,590,38,plr==LP and Color3.fromRGB(44,101,89) or Color3.fromRGB(43,68,104))
  line.MouseButton1Click:Connect(function()
   if plr==LP then return end
   local p=plr.Character and plr.Character:FindFirstChild('HumanoidRootPart')
   if sendTo(p) then add('MOVE','requested near player '..plr.Name) else add('MOVE','player position unavailable '..plr.Name)end
  end)
 end
 playerScroll.CanvasSize=UDim2.fromOffset(0,#Players:GetPlayers()*44)
end
hook(Players.PlayerAdded,updatePlayers);hook(Players.PlayerRemoving,function()task.defer(updatePlayers)end)
updatePlayers()
local chestActive=false
local chestSerial=0
local chosenRaft=nil
local chestAttempts=0
local function shieldStatus(raft)
 for k,v in pairs(raft:GetAttributes()) do
  local name=tostring(k):lower()
  if name:find('shield',1,true) or name:find('protect',1,true) then
   if v==true then return 'protected',k end
   if v==false then return 'unprotected',k end
  end
 end
 for _,o in ipairs(raft:GetDescendants()) do
  if o:IsA('ForceField') then return 'protected','ForceField' end
  if o:IsA('BoolValue') and o.Name:lower():find('shield',1,true) then return o.Value and 'protected' or 'unprotected',o.Name end
 end
 return 'unknown','no verified state'
end
local function searchChestPrompt(raft)
 for _,o in ipairs(raft:GetDescendants()) do
  if o:IsA('ProximityPrompt') and o.Enabled then
   local par=o.Parent
   local str=(o.Name..' '..o.ActionText..' '..o.ObjectText..' '..(par and par.Name or '')):lower()
   if str:find('chest',1,true) or str:find('steal',1,true) or str:find('صندوق',1,true) then
    local bp=par and nearestPart(par)
    if bp then return o,bp end
   end
  end
 end
end
local function chooseRaft()
 local rafts=workspace:FindFirstChild('Rafts');if not rafts then return nil end
 local names={}
 for _,raft in ipairs(rafts:GetChildren()) do
  if raft~=getMyRaft() then names[#names+1]=raft end
 end
 table.sort(names,function(a,b)return a.Name<b.Name end)
 if #names==0 then return nil end
 local idx=1
 for i,x in ipairs(names) do if x==chosenRaft then idx=i%#names+1;break end end
 chosenRaft=names[idx];return chosenRaft
end
chestTargetBtn.MouseButton1Click:Connect(function()
 local raft=chooseRaft();chestTargetBtn.Text=raft and ('الهدف: '..raft.Name) or 'لا توجد سفن أخرى'
 if raft then local s,reason=shieldStatus(raft);chestInfo.Text='الحالة المرئية: '..s..' | '..reason end
end)
local function attemptPrompt(prompt)
 if not prompt.Parent or not prompt.Enabled then return false,'prompt disabled' end
 if type(fireproximityprompt)=='function' then
  local ok,err=pcall(function()fireproximityprompt(prompt,math.max(prompt.HoldDuration,0))end)
  return ok,ok and 'requested prompt' or tostring(err)
 end
 local ok,err=pcall(function()
  local vim=game:GetService('VirtualInputManager')
  vim:SendKeyEvent(true,Enum.KeyCode.E,false,game)
  task.wait(math.max(prompt.HoldDuration+.2,.3))
  vim:SendKeyEvent(false,Enum.KeyCode.E,false,game)
 end)
 return ok,ok and 'requested key press' or tostring(err)
end
chestAutoBtn.MouseButton1Click:Connect(function()
 if chestActive then return end
 stopAuto();chestActive=true;chestSerial=chestSerial+1;local id=chestSerial
 add('CHEST','monitor started; unknown shield => wait')
 task.spawn(function()
  while alive and chestActive and id==chestSerial do
   local folder=workspace:FindFirstChild('Rafts');local mine=getMyRaft()
   if folder and mine then
    for _,raft in ipairs(folder:GetChildren()) do
     if not chestActive or id~=chestSerial then break end
     if raft~=mine and (not chosenRaft or raft==chosenRaft) then
      local shield,reason=shieldStatus(raft)
      chestInfo.Text=raft.Name..' | الدرع: '..shield..' ('..reason..')'
      if shield=='unprotected' then
       local prompt,part=searchChestPrompt(raft)
       if prompt and part and (os.clock()-(visited[prompt] or 0)>0) then
        visited[prompt]=os.clock()+8
        chestAttempts=chestAttempts+1
        add('CHEST','attempt '..chestAttempts..' on '..raft.Name..' | '..path(prompt))
        if sendTo(part) then
         task.wait(.25)
         local nowShield=shieldStatus(raft)
         if nowShield=='unprotected' then
          local ok,msg=attemptPrompt(prompt)
          add('CHEST','interaction requested='..tostring(ok)..' | '..msg..' | pickup NOT verified')
          task.wait(.65)
          local home=nearestPart(mine)
          if sendTo(home) then add('CHEST','returned to own raft; delivery NOT verified')end
         end
        end
       end
      end
     end
    end
   else chestInfo.Text='موقع سفينتك أو قائمة السفن غير متاح' end
   task.wait(1)
  end
 end)
end)
chestStopBtn.MouseButton1Click:Connect(function()
 chestActive=false;chestSerial=chestSerial+1;add('CHEST','monitor stopped');chestInfo.Text='مراقبة الصناديق متوقفة'
end)
quickResources.MouseButton1Click:Connect(function()if not running then begin()end;autoStart()end)
quickStop.MouseButton1Click:Connect(function()stopAuto();running=false;generation=generation+1;chestActive=false;chestSerial=chestSerial+1;add('SYSTEM','all operations stopped');refresh()end)
quickChests.MouseButton1Click:Connect(function()chestScan();chestInfo.Text='صناديق مرئية: '..#foundChests..' | اختر صفحة الصناديق' end)
quickReport.MouseButton1Click:Connect(function()
 if type(setclipboard)=='function' then pcall(setclipboard,report());add('REPORT','copied full session report')else add('REPORT','clipboard unavailable')end
end)
settingScan.MouseButton1Click:Connect(begin)
settingStop.MouseButton1Click:Connect(function()stopAuto();running=false;generation=generation+1;chestActive=false;chestSerial=chestSerial+1;refresh()end)
-- Ensure chest monitor exits when script is reloaded or UI closed.
local oldCleanup=cleanup
cleanup=function()
 auraOn=false
 chestActive=false;chestSerial=chestSerial+1
 oldCleanup()
end
env.RaftControlV14Stop=cleanup
add('SYSTEM','V14.4 loaded; passive timing lab added to Tests. Existing collector unchanged.');refresh()

