-- RAFT CONTROL V12 | unified dashboard
-- Client-side script. Works with visible objects only; server decides collections and chest transfers.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local ProximityPromptService=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local LP=Players.LocalPlayer
local PG=LP:WaitForChild('PlayerGui')
local env=(getgenv and getgenv()) or _G
for _,key in ipairs({'RaftControlV12Stop','RaftInspectorV11Stop','RaftInspectorV10Stop','RaftInspectorV9Stop','RaftInspectorV8Stop','RaftInspectorV7Stop'}) do
 if type(env[key])=='function' then pcall(env[key])end
end
for _,name in ipairs({'RaftControlV12','RaftInspectorV11','RaftInspectorV10','RaftInspectorV9','RaftInspectorV8','RaftInspectorV7'}) do
 local old=PG:FindFirstChild(name);if old then old:Destroy()end
end
local alive=true
local scan=false
local auto=false
local chestWatch=false
local markers=false
local speed=800
local range=1500
local fireInterval=.15
local lines={}
local total=0
local maxLog=5500
local lastFire=0
local lastTarget=nil
local currentTab='الموارد'
local foundResources={}
local foundChests={}
local visited={}
local shotCount=0
local collectChanges=0
local home
local playerBeams={}
local conns={}
local initial={Wood=tonumber(LP:GetAttribute('Mat_Wood'))or 0,Metal=tonumber(LP:GetAttribute('Mat_Metal'))or 0,Scrap=tonumber(LP:GetAttribute('Mat_Scrap'))or 0}
local function link(sig,fn)local c=sig:Connect(fn);conns[#conns+1]=c;return c end
local function path(o)local ok,v=pcall(function()return o:GetFullName()end);return ok and v or tostring(o)end
local function log(cat,msg)
 total=total+1
 lines[#lines+1]=string.format('[%.2f][%s] %s',os.clock(),cat,tostring(msg))
 if #lines>maxLog then table.remove(lines,1)end
end
local function root()local c=LP.Character;return c and c:FindFirstChild('HumanoidRootPart')end
local function hum()local c=LP.Character;return c and c:FindFirstChildOfClass('Humanoid')end
local function harpoon()
 local c=LP.Character;if not c then return end
 local t=c:FindFirstChildOfClass('Tool')
 if t and t.Name:lower():find('harpoon',1,true) then return t end
 local bag=LP:FindFirstChild('Backpack');local h=hum()
 if bag and h then
  for _,obj in ipairs(bag:GetChildren())do
   if obj:IsA('Tool') and obj.Name:lower():find('harpoon',1,true) then
    pcall(function()h:EquipTool(obj)end)
    return obj
   end
  end
 end
end
local function position(obj)
 if not obj or not obj.Parent then return end
 if obj:IsA('BasePart') then return obj.Position end
 if obj:IsA('Model') then
  local ok,cf=pcall(function()return obj:GetPivot()end)
  if ok then return cf.Position end
 end
 local p=obj:FindFirstChildWhichIsA('BasePart',true)
 return p and p.Position
end
local types={Visual_WoodLog='خشب',Visual_MetalSheet='حديد',Visual_MetalBarrel='برميل',Visual_Crate='صندوق موارد',Visual_Chest='غنيمة',Visual_Chair='كرسي'}
local function resourceScan()
 local folder=workspace:FindFirstChild('LocalHarpoonVisuals')
 local r=root();if not folder or not r then return 0 end
 local now=os.clock();local count=0
 for _,obj in ipairs(folder:GetChildren())do
  if types[obj.Name] then
   local p=position(obj)
   if p and p.Y>-1000 and (p-r.Position).Magnitude<=range then
    count=count+1
    if not foundResources[obj] then log('مورد','اكتشاف '..types[obj.Name]..' '..path(obj)..' @ '..tostring(p))end
    foundResources[obj]={pos=p,last=now,kind=types[obj.Name]}
   end
  end
 end
 for o,data in pairs(foundResources)do if not o.Parent or now-data.last>5 then foundResources[o]=nil end end
 return count
end
local function chestScan()
 local rafts=workspace:FindFirstChild('Rafts')
 if not rafts then log('صناديق','Workspace.Rafts غير موجود');return 0 end
 local count=0
 foundChests={}
 for _,raft in ipairs(rafts:GetChildren())do
  local own=raft.Name:lower():find(LP.Name:lower(),1,true)~=nil
  local attrs=raft:GetAttributes()
  local shieldParts={}
  for k,v in pairs(attrs)do if tostring(k):lower():find('shield',1,true) then shieldParts[#shieldParts+1]=k..'='..tostring(v)end end
  local raftCount=0
  for _,obj in ipairs(raft:GetDescendants())do
   local n=obj.Name:lower()
   if n:find('chest',1,true) and (obj:IsA('Model') or obj:IsA('BasePart')) then
    local p=position(obj)
    if p then
     count=count+1;raftCount=raftCount+1
     local rec={obj=obj,raft=raft,own=own,pos=p,shield=table.concat(shieldParts,',')}
     foundChests[#foundChests+1]=rec
     if count<=70 then log('صندوق','raft='..raft.Name..' own='..tostring(own)..' '..path(obj)..' xyz='..tostring(p)..' shield='..rec.shield)end
    end
   elseif obj:IsA('ProximityPrompt') then
    log('تفاعل','raft='..raft.Name..' '..path(obj)..' action='..obj.ActionText..' hold='..tostring(obj.HoldDuration)..' enabled='..tostring(obj.Enabled))
   end
  end
  log('سفينة','raft='..raft.Name..' own='..tostring(own)..' chestMatches='..raftCount..' shield='..table.concat(shieldParts,','))
 end
 log('صناديق','عدد أجسام الصناديق المرئية: '..count..' (قد تتكرر أجزاء الصندوق)')
 return count
end
local function nearestResource()
 local r=root();if not r then return end
 local best,bestPos,bestDist
 for obj,data in pairs(foundResources) do
  local p=position(obj)
  if p and p.Y>-1000 and (not visited[obj] or visited[obj]<os.clock()) then
   local d=(p-r.Position).Magnitude
   if d<range and (not bestDist or d<bestDist) then best,bestPos,bestDist=obj,p,d end
  end
 end
 return best,bestPos,bestDist
end
local function startPos()local r=root();return r and r.Position end
local function moveTo(p)
 local r=root();if not r then return end
 local delta=p-r.Position
 if delta.Magnitude>2 then
  local step=math.min(speed*.12,delta.Magnitude)
  local np=r.Position+delta.Unit*step
  pcall(function()r.CFrame=CFrame.new(np,np+r.CFrame.LookVector);r.AssemblyLinearVelocity=Vector3.zero end)
 end
end
local function beginAuto()
 if auto then return end
 auto=true;scan=true
 if not home then home=startPos()end
 log('أوتو','تجميع الموارد بدأ range='..range..' speed='..speed)
 local id=os.clock()
 task.spawn(function()
  local targetStart=0;local orbit=0
  while alive and auto do
   local ok,err=pcall(function()
    resourceScan()
    local t,p,d=nearestResource()
    if t then
     if lastTarget~=t then lastTarget=t;targetStart=os.clock();log('هدف','نوع='..t.Name..' dist='..math.floor(d))end
     if os.clock()-targetStart>4.5 then
      visited[t]=os.clock()+16;lastTarget=nil
      log('هدف','تجاوز هدف غير مكتمل: '..t.Name)
     else
      moveTo(p+Vector3.new(0,5,0))
      if d<85 and os.clock()-lastFire>=fireInterval then
       local weapon=harpoon()
       if weapon then
        local cam=workspace.CurrentCamera
        if cam then pcall(function()cam.CFrame=CFrame.lookAt(cam.CFrame.Position,p)end)end
        pcall(function()weapon:Activate()end)
        lastFire=os.clock()
       end
      end
     end
    else
     lastTarget=nil;orbit=orbit+1
     local center=home or startPos()
     if center then
      local a=(orbit%28)*math.pi/14
      local radius=(math.floor(orbit/28)%3+1)*95
      moveTo(center+Vector3.new(math.cos(a)*radius,11,math.sin(a)*radius))
     end
    end
   end)
   if not ok then log('خطأ','auto: '..tostring(err))end
   task.wait(.12)
  end
 end)
end
local function stopAuto()
 if auto then auto=false;lastTarget=nil;log('أوتو','إيقاف التجميع')end
end
local function clearMarkers()
 for _,obj in pairs(playerBeams)do pcall(function()obj:Destroy()end)end
 playerBeams={}
end
local function updateMarkers()
 clearMarkers()
 if not markers then return end
 local r=root();if not r then return end
 for _,p in ipairs(Players:GetPlayers())do
  if p~=LP and p.Character then
   local hr=p.Character:FindFirstChild('HumanoidRootPart')
   if hr then
    local a=Instance.new('Attachment');a.Name='RaftPlayerLink_A';a.Parent=r
    local b=Instance.new('Attachment');b.Name='RaftPlayerLink_B';b.Parent=hr
    local beam=Instance.new('Beam');beam.FaceCamera=true;beam.Width0=.08;beam.Width1=.08
    beam.Color=ColorSequence.new(Color3.fromRGB(80,205,255))
    beam.Attachment0=a;beam.Attachment1=b;beam.Parent=r
    local bb=Instance.new('BillboardGui');bb.Size=UDim2.fromOffset(175,35);bb.StudsOffset=Vector3.new(0,4,0);bb.AlwaysOnTop=true;bb.Adornee=hr;bb.Parent=hr
    local text=Instance.new('TextLabel');text.Size=UDim2.fromScale(1,1);text.BackgroundColor3=Color3.fromRGB(15,25,39);text.BackgroundTransparency=.25;text.TextColor3=Color3.new(1,1,1);text.TextScaled=true;text.Font=Enum.Font.GothamBold;text.Text=p.DisplayName..' | '..math.floor((hr.Position-r.Position).Magnitude)..' studs';text.Parent=bb
    playerBeams[#playerBeams+1]=a;playerBeams[#playerBeams+1]=b;playerBeams[#playerBeams+1]=beam;playerBeams[#playerBeams+1]=bb
   end
  end
 end
end

-- GUI
local gui=Instance.new('ScreenGui');gui.Name='RaftControlV12';gui.ResetOnSpawn=false;gui.DisplayOrder=1100;gui.Parent=PG
local main=Instance.new('Frame');main.Size=UDim2.fromOffset(470,575);main.Position=UDim2.new(.5,-235,.5,-285);main.BackgroundColor3=Color3.fromRGB(14,19,33);main.Active=true;main.Draggable=true;main.Parent=gui
Instance.new('UICorner',main).CornerRadius=UDim.new(0,16)
local stroke=Instance.new('UIStroke');stroke.Color=Color3.fromRGB(64,129,221);stroke.Thickness=1.4;stroke.Parent=main
local scale=Instance.new('UIScale');scale.Parent=main
local function fit()local c=workspace.CurrentCamera;if c then scale.Scale=math.min(1,c.ViewportSize.X/485,c.ViewportSize.Y/590)end end
fit()
local function label(parent,txt,x,y,w,h,size,color)
 local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.Text=txt;l.Position=UDim2.fromOffset(x,y);l.Size=UDim2.fromOffset(w,h);l.Font=Enum.Font.GothamBold;l.TextSize=size or 13;l.TextColor3=color or Color3.fromRGB(231,239,255);l.TextXAlignment=Enum.TextXAlignment.Left;l.Parent=parent;return l
end
local function button(parent,txt,x,y,w,h,color)
 local b=Instance.new('TextButton');b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.Text=txt;b.Font=Enum.Font.GothamBold;b.TextSize=12;b.TextColor3=Color3.new(1,1,1);b.BackgroundColor3=color or Color3.fromRGB(44,94,161);b.Parent=parent
 Instance.new('UICorner',b).CornerRadius=UDim.new(0,8);return b
end
label(main,'RAFT CONTROL  /  V12',16,10,340,28,21,Color3.fromRGB(105,206,255))
local hide=button(main,'اخفاء ـ',371,10,83,30,Color3.fromRGB(71,78,108))
local nameLabel=label(main,'اللاعب: '..LP.Name,16,43,435,20,14)
local stats=label(main,'',16,69,440,28,13,Color3.fromRGB(144,250,179))
local gains=label(main,'',16,96,440,23,12,Color3.fromRGB(250,215,142))
local tabs={}
local content=Instance.new('Frame');content.Position=UDim2.fromOffset(15,170);content.Size=UDim2.fromOffset(440,340);content.BackgroundTransparency=1;content.Parent=main
local layouts={}
for i,title in ipairs({'الموارد','الصناديق','اللاعبون','الفحص'})do
 local tab=button(main,title,15+(i-1)*111,129,105,32,Color3.fromRGB(34,68,115));tabs[title]=tab
 local pane=Instance.new('Frame');pane.Size=UDim2.fromScale(1,1);pane.BackgroundTransparency=1;pane.Visible=(i==1);pane.Parent=content;layouts[title]=pane
 tab.MouseButton1Click:Connect(function()
  currentTab=title
  for n,p in pairs(layouts)do p.Visible=(n==title);tabs[n].BackgroundColor3=(n==title and Color3.fromRGB(39,127,198) or Color3.fromRGB(34,68,115))end
 end)
end
tabs['الموارد'].BackgroundColor3=Color3.fromRGB(39,127,198)
local green=Color3.fromRGB(26,143,101)
local blue=Color3.fromRGB(42,104,177)
local red=Color3.fromRGB(171,57,77)
local purple=Color3.fromRGB(105,68,179)
local res=layouts['الموارد']
label(res,'فحص الأجسام المرئية وجمع الموارد تلقائيا',0,0,430,23,14)
local start=button(res,'تشغيل التجميع',0,35,211,42,green)
local stop=button(res,'إيقاف التجميع',224,35,211,42,red)
local rangeBtn=button(res,'النطاق: 1500',0,86,211,35,blue)
local speedBtn=button(res,'السرعة: 800',224,86,211,35,purple)
local jumpHome=button(res,'الرجوع لموقع البداية',0,130,435,36,blue)
local resourceInfo=label(res,'أهداف مرئية: 0 | إطلاقات: 0',0,178,435,30,13)
label(res,'التجميع الفعلي يخضع لخوادم اللعبة.',0,219,435,24,12,Color3.fromRGB(197,204,219))
start.MouseButton1Click:Connect(beginAuto)
stop.MouseButton1Click:Connect(stopAuto)
rangeBtn.MouseButton1Click:Connect(function()range=(range==1500 and 2500 or (range==2500 and 650 or 1500));rangeBtn.Text='النطاق: '..range;log('إعداد','نطاق الموارد='..range)end)
speedBtn.MouseButton1Click:Connect(function()speed=(speed==800 and 2000 or (speed==2000 and 250 or 800));speedBtn.Text='السرعة: '..speed;log('إعداد','سرعة مطلوبة='..speed)end)
jumpHome.MouseButton1Click:Connect(function()local r=root();if r and home then r.CFrame=CFrame.new(home+Vector3.new(0,6,0));log('انتقال','عودة إلى نقطة البداية')else log('انتقال','لا توجد نقطة بداية')end end)
local chest=layouts['الصناديق']
label(chest,'فحص صناديق السفن وخصائص الحماية الظاهرة',0,0,435,24,14)
local chestBtn=button(chest,'فحص جميع السفن والصناديق',0,35,435,41,blue)
local chestInfo=label(chest,'عدد الصناديق: لم يتم الفحص',0,86,435,27,13)
local chestStatus=label(chest,'الفحص لا ينقل ممتلكات اللاعبين.',0,115,435,37,12,Color3.fromRGB(244,208,149))
local chestLogs=Instance.new('TextBox');chestLogs.Position=UDim2.fromOffset(0,164);chestLogs.Size=UDim2.fromOffset(435,166);chestLogs.Text='نتائج الصناديق تظهر هنا';chestLogs.TextEditable=false;chestLogs.MultiLine=true;chestLogs.TextWrapped=true;chestLogs.TextXAlignment=Enum.TextXAlignment.Left;chestLogs.TextYAlignment=Enum.TextYAlignment.Top;chestLogs.TextSize=12;chestLogs.Font=Enum.Font.Code;chestLogs.TextColor3=Color3.fromRGB(145,237,183);chestLogs.BackgroundColor3=Color3.fromRGB(8,13,24);chestLogs.Parent=chest
Instance.new('UICorner',chestLogs).CornerRadius=UDim.new(0,8)
chestBtn.MouseButton1Click:Connect(function()
 local n=chestScan();chestInfo.Text='عدد مطابقات الصناديق: '..n
 local data={};for i=math.max(1,#lines-18),#lines do data[#data+1]=lines[i]end
 chestLogs.Text=table.concat(data,'\n')
end)
local playersTab=layouts['اللاعبون']
label(playersTab,'خطوط اللاعبين الظاهرين وبيانات السفن',0,0,435,28,14)
local beamsBtn=button(playersTab,'إظهار خطوط اللاعبين',0,39,211,41,blue)
local refreshP=button(playersTab,'تحديث الخطوط',224,39,211,41,purple)
local playerInfo=label(playersTab,'',0,94,435,60,13)
local scanShips=button(playersTab,'فحص السفن',0,160,435,42,green)
beamsBtn.MouseButton1Click:Connect(function()markers=not markers;beamsBtn.Text=markers and 'إخفاء خطوط اللاعبين' or 'إظهار خطوط اللاعبين';updateMarkers();log('لاعبون','خطوط='..tostring(markers))end)
refreshP.MouseButton1Click:Connect(updateMarkers)
scanShips.MouseButton1Click:Connect(chestScan)
local reportPane=layouts['الفحص']
label(reportPane,'نسخ تقرير موحد + اختبار النظام',0,0,435,25,14)
local scanBtn=button(reportPane,'START SCAN',0,32,138,40,green)
local testBtn=button(reportPane,'RUN TEST',148,32,138,40,blue)
local stopScan=button(reportPane,'STOP SCAN',296,32,139,40,red)
local copyBtn=button(reportPane,'نسخ كل النتائج',0,82,211,39,purple)
local clearBtn=button(reportPane,'مسح التقرير',224,82,211,39,red)
local console=Instance.new('TextBox');console.Position=UDim2.fromOffset(0,132);console.Size=UDim2.fromOffset(435,198);console.TextEditable=false;console.MultiLine=true;console.TextWrapped=true;console.TextXAlignment=Enum.TextXAlignment.Left;console.TextYAlignment=Enum.TextYAlignment.Top;console.TextSize=11;console.Font=Enum.Font.Code;console.TextColor3=Color3.fromRGB(149,236,188);console.BackgroundColor3=Color3.fromRGB(8,13,24);console.Parent=reportPane
Instance.new('UICorner',console).CornerRadius=UDim.new(0,8)
local bottom=label(main,'جاهز  |  النسخ من تبويب الفحص',17,519,435,32,12,Color3.fromRGB(135,189,228))
local tiny=button(gui,'OPEN RAFT',14,96,114,40,Color3.fromRGB(32,117,183));tiny.Visible=false
hide.MouseButton1Click:Connect(function()main.Visible=false;tiny.Visible=true end)
tiny.MouseButton1Click:Connect(function()main.Visible=true;tiny.Visible=false end)
local function runTest()
 log('TEST','GUI=OK player='..LP.Name..' root='..tostring(root()~=nil)..' clipboard='..tostring(type(setclipboard)=='function'))
 local visual=workspace:FindFirstChild('LocalHarpoonVisuals')
 log('TEST','LocalHarpoonVisuals='..tostring(visual~=nil)..' Rafts='..tostring(workspace:FindFirstChild('Rafts')~=nil))
 log('TEST','Harpoon='..tostring(harpoon() and harpoon().Name or 'none'))
 resourceScan();chestScan()
end
local function buildReport()
 local ar={
  'RAFT CONTROL V12 - FULL REPORT',
  'Player='..LP.Name..' PlaceId='..game.PlaceId,
  'Wood='..tostring(LP:GetAttribute('Mat_Wood'))..' Metal='..tostring(LP:GetAttribute('Mat_Metal'))..' Scrap='..tostring(LP:GetAttribute('Mat_Scrap'))..' Cash='..tostring(LP:GetAttribute('Cash')),
  'Gained wood='..tostring((tonumber(LP:GetAttribute('Mat_Wood'))or 0)-initial.Wood)..' metal='..tostring((tonumber(LP:GetAttribute('Mat_Metal'))or 0)-initial.Metal)..' scrap='..tostring((tonumber(LP:GetAttribute('Mat_Scrap'))or 0)-initial.Scrap),
  'Shot projectiles='..shotCount..' Attribute changes='..collectChanges..' Entries='..#lines..' Total='..total,
  'Auto='..tostring(auto)..' Range='..range..' Speed='..speed..' VisibleTargets='..tostring(resourceScan()),
  'Note: client side data only. No server-only inventory or chest transfer verified.',
  '=== FULL CHRONOLOGICAL LOG ===',table.concat(lines,'\n')
 }
 return table.concat(ar,'\n')
end
scanBtn.MouseButton1Click:Connect(function()scan=true;log('فحص','تشغيل الفحص المستمر')end)
stopScan.MouseButton1Click:Connect(function()scan=false;stopAuto();log('فحص','إيقاف')end)
testBtn.MouseButton1Click:Connect(runTest)
copyBtn.MouseButton1Click:Connect(function()
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,buildReport());copyBtn.Text=ok and 'تم النسخ!' or 'فشل النسخ'
 else bottom.Text='نسخ الحافظة غير متاح' end
 task.delay(2,function()if alive then copyBtn.Text='نسخ كل النتائج' end end)
end)
clearBtn.MouseButton1Click:Connect(function()lines={};total=0;shotCount=0;collectChanges=0;log('نظام','تم مسح التقرير')end)
link(LP.AttributeChanged,function(k)
 if not alive then return end
 if k:sub(1,4)=='Mat_' or k=='Cash' then
  collectChanges=collectChanges+1
  log('قيمة',k..'='..tostring(LP:GetAttribute(k)))
 end
end)
link(workspace.DescendantAdded,function(obj)
 if not alive or not scan then return end
 if obj.Name=='HarpoonProjectile' then shotCount=shotCount+1;log('حربة','طلقة رقم '..shotCount)end
end)
link(ProximityPromptService.PromptShown,function(prompt)
 if chestWatch or scan then log('تفاعل','ظهر '..path(prompt)..' action='..prompt.ActionText..' hold='..prompt.HoldDuration)end
end)
link(ProximityPromptService.PromptTriggered,function(prompt,p)
 if p==LP then log('تفاعل','تم التفعيل '..path(prompt))end
end)
local function cleanup()
 alive=false;auto=false;scan=false;clearMarkers()
 for _,c in ipairs(conns)do pcall(function()c:Disconnect()end)end
 if gui.Parent then gui:Destroy()end
end
env.RaftControlV12Stop=cleanup
log('نظام','V12 loaded. Visible-resource collection + chest inspection + player lines.')
home=startPos()
scan=true
local n=0
local statusClock=0
task.spawn(function()
 while alive do
  n=n+1
  if scan and n%3==0 then pcall(resourceScan)end
  if markers and n%10==0 then pcall(updateMarkers)end
  local wood=tonumber(LP:GetAttribute('Mat_Wood'))or 0
  local metal=tonumber(LP:GetAttribute('Mat_Metal'))or 0
  local scrap=tonumber(LP:GetAttribute('Mat_Scrap'))or 0
  stats.Text='🪵 '..wood..'   🔩 '..metal..'   ♻ '..scrap..'   💰 '..tostring(LP:GetAttribute('Cash')or 0)
  gains.Text='المكتسب: خشب +'..(wood-initial.Wood)..' | حديد +'..(metal-initial.Metal)..' | سكراب +'..(scrap-initial.Scrap)
  local candidates=0;for _ in pairs(foundResources)do candidates=candidates+1 end
  resourceInfo.Text='أهداف مرئية: '..candidates..' | إطلاقات: '..shotCount..' | '..(auto and 'AUTO ON' or 'AUTO OFF')
  playerInfo.Text='اللاعبون بالسيرفر: '..#Players:GetPlayers()..' | الخطوط: '..(markers and 'مفعلة' or 'موقفة')
  bottom.Text=(auto and 'التجميع يعمل' or 'جاهز')..' | السجلات: '..#lines..' | '..(lastTarget and lastTarget.Name or 'بدون هدف')
  local items={};for i=math.max(1,#lines-14),#lines do items[#items+1]=lines[i]end
  console.Text=table.concat(items,'\n')
  task.wait(.5)
 end
end)
