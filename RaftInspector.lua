-- RAFT CHEST SCOUT | optional add-on for Raft Inspector V11
-- Uses only ordinary visible Roblox instances and prompt activation.
-- Does not defeat shields, server checks or hidden inventory.
local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local LP=Players.LocalPlayer
local PG=LP:WaitForChild('PlayerGui')
local E=(getgenv and getgenv()) or _G
if type(E.RaftChestStop)=='function' then pcall(E.RaftChestStop) end
local old=PG:FindFirstChild('RaftChestScout');if old then old:Destroy()end
local on=false
local active=true
local session=0
local activity={}
local attempted={}
local function record(msg)
 activity[#activity+1]=string.format('[%.1f] %s',os.clock(),tostring(msg))
 if #activity>1400 then table.remove(activity,1)end
end
local function root()
 local ch=LP.Character
 return ch and ch:FindFirstChild('HumanoidRootPart')
end
local function getRafts()return workspace:FindFirstChild('Rafts')end
local function myRaft()
 local rafts=getRafts();if not rafts then return nil end
 for _,m in ipairs(rafts:GetChildren()) do
  if m.Name:lower():find(LP.Name:lower(),1,true) then return m end
 end
 return nil
end
local function partOf(x)
 if x:IsA('BasePart') then return x end
 if x:IsA('Model') and x.PrimaryPart then return x.PrimaryPart end
 return x:FindFirstChildWhichIsA('BasePart',true)
end
local function shielded(raft)
 -- Shield status isn't proven by mere presence of a shield tool/part.
 -- Fail closed if any active-looking shield state can be observed.
 for _,obj in ipairs({raft}) do
  for k,v in pairs(obj:GetAttributes()) do
   local s=k:lower()
   if (s:find('shield',1,true) or s:find('protected',1,true)) and v==true then return true,k end
  end
 end
 for _,x in ipairs(raft:GetDescendants()) do
  if x:IsA('ForceField') then return true,'ForceField' end
  if x:IsA('BoolValue') and x.Value and x.Name:lower():find('shield',1,true) then return true,x.Name end
 end
 return false
end
local function chestPrompt(raft)
 for _,obj in ipairs(raft:GetDescendants()) do
  if obj:IsA('ProximityPrompt') and obj.Enabled then
   local d=obj.Parent
   local s=(obj.Name..' '..obj.ActionText..' '..obj.ObjectText):lower()
   local cur=d
   for _=1,5 do
    if cur and cur~=raft then s=s..' '..cur.Name:lower();cur=cur.Parent end
   end
   if s:find('chest',1,true) or s:find('steal',1,true) or s:find('صندوق',1,true) then
    return obj,partOf(d)
   end
  end
 end
 return nil
end
local function targetList()
 local rafts=getRafts()
 local mine=myRaft()
 local out={}
 if not rafts then return out end
 for _,raft in ipairs(rafts:GetChildren()) do
  if raft~=mine and raft:IsA('Model') then
   local safe,reason=shielded(raft)
   if not safe then
    local p,part=chestPrompt(raft)
    if p and part then out[#out+1]={raft=raft,prompt=p,part=part} end
   else
    record('SKIP protected '..raft.Name..' ('..tostring(reason)..')')
   end
  end
 end
 return out
end
local function moveNear(part)
 local r=root();if not r or not part then return false end
 local dest=part.Position+Vector3.new(0,3,0)
 pcall(function()r.CFrame=CFrame.new(dest,part.Position)end)
 return (r.Position-dest).Magnitude<15
end
local function usePrompt(prompt)
 if not prompt or not prompt.Parent or not prompt.Enabled then return false,'prompt missing' end
 if type(fireproximityprompt)=='function' then
  local ok,why=pcall(function()fireproximityprompt(prompt,math.max(0,prompt.HoldDuration))end)
  return ok,ok and 'fireproximityprompt attempted' or tostring(why)
 end
 local ok,why=pcall(function()
  local vim=game:GetService('VirtualInputManager')
  vim:SendKeyEvent(true,Enum.KeyCode.E,false,game)
  task.wait(math.max(.15,prompt.HoldDuration+.15))
  vim:SendKeyEvent(false,Enum.KeyCode.E,false,game)
 end)
 return ok,ok and 'E key attempted' or tostring(why)
end
local gui=Instance.new('ScreenGui')
gui.Name='RaftChestScout';gui.ResetOnSpawn=false;gui.DisplayOrder=1002;gui.Parent=PG
local frame=Instance.new('Frame')
frame.Size=UDim2.fromOffset(328,284);frame.Position=UDim2.new(0,16,.5,-142)
frame.BackgroundColor3=Color3.fromRGB(20,25,40);frame.Active=true;frame.Draggable=true;frame.Parent=gui
Instance.new('UICorner',frame).CornerRadius=UDim.new(0,12)
local function b(text,y,color)
 local x=Instance.new('TextButton');x.Position=UDim2.fromOffset(10,y);x.Size=UDim2.fromOffset(308,36)
 x.BackgroundColor3=color;x.Text=text;x.TextColor3=Color3.new(1,1,1)
 x.Font=Enum.Font.GothamBold;x.TextSize=14;x.Parent=frame
 Instance.new('UICorner',x).CornerRadius=UDim.new(0,7)
 return x
end
local title=Instance.new('TextLabel');title.Parent=frame;title.Size=UDim2.fromOffset(270,34)
title.Position=UDim2.fromOffset(12,4);title.BackgroundTransparency=1;title.Text='الصناديق | CHEST SCOUT'
title.Font=Enum.Font.GothamBold;title.TextSize=16;title.TextColor3=Color3.new(1,1,1)
local hide=Instance.new('TextButton');hide.Parent=frame;hide.Position=UDim2.fromOffset(287,5)
hide.Size=UDim2.fromOffset(29,28);hide.Text='–';hide.TextSize=20;hide.BackgroundColor3=Color3.fromRGB(67,81,110);hide.TextColor3=Color3.new(1,1,1)
local scan=b('فحص الصناديق',43,Color3.fromRGB(47,105,175))
local start=b('بدء التجربة',84,Color3.fromRGB(30,145,98))
local stop=b('ايقاف',125,Color3.fromRGB(170,70,70))
local copy=b('نسخ النتائج',166,Color3.fromRGB(108,80,180))
local result=Instance.new('TextLabel');result.Parent=frame;result.Position=UDim2.fromOffset(12,210)
result.Size=UDim2.fromOffset(304,65);result.BackgroundTransparency=1
result.TextWrapped=true;result.TextXAlignment=Enum.TextXAlignment.Left
result.TextYAlignment=Enum.TextYAlignment.Top;result.Font=Enum.Font.Code
result.TextSize=12;result.TextColor3=Color3.fromRGB(153,238,179);result.Text='جاهز للفحص'
local opener=Instance.new('TextButton');opener.Parent=gui
opener.Size=UDim2.fromOffset(100,34);opener.Position=UDim2.fromOffset(8,90)
opener.Text='الصناديق';opener.TextColor3=Color3.new(1,1,1)
opener.BackgroundColor3=Color3.fromRGB(62,98,170);opener.Visible=false
opener.MouseButton1Click:Connect(function()frame.Visible=true;opener.Visible=false end)
hide.MouseButton1Click:Connect(function()frame.Visible=false;opener.Visible=true end)
local function setText(s)result.Text=s;record(s)end
scan.MouseButton1Click:Connect(function()
 local targets=targetList()
 setText('صناديق مرئية وقابلة للتفاعل: '..#targets..' | سفينتي: '..(myRaft() and myRaft().Name or 'غير معروفة'))
 for _,c in ipairs(targets) do record('CHEST '..c.raft.Name..' prompt='..c.prompt:GetFullName())end
end)
start.MouseButton1Click:Connect(function()
 if on then return end
 on=true;session=session+1;local id=session
 task.spawn(function()
  setText('بدأ البحث عن الصناديق...')
  local failures=0
  while on and active and session==id do
   local targets=targetList()
   if #targets==0 then
    failures=failures+1
    if failures>=3 then setText('ما لقيت صناديق قابلة للتفاعل بدون درع. افحص النتائج.')end
    task.wait(2)
   else
    failures=0
    for _,entry in ipairs(targets) do
     if not on or session~=id then break end
     local raft=entry.raft
     if raft.Parent and not shielded(raft) and entry.part.Parent then
      local count=(attempted[entry.prompt] or 0)
      if count<3 then
       attempted[entry.prompt]=count+1
       local my=myRaft();local home=my and partOf(my)
       if not home then
        setText('ما قدرت احدد موقع سفينتك. توقفت لتجنب ضياع الصندوق.')
        on=false;break
       end
       if moveNear(entry.part) then
        task.wait(.22)
        local ok,msg=usePrompt(entry.prompt)
        record('PROMPT '..raft.Name..' attempt='..(count+1)..' ok='..tostring(ok)..' '..msg)
        task.wait(.6)
        moveNear(home)
        record('RETURN own raft; carry success UNVERIFIED')
        setText('جربت الصندوق عند '..raft.Name..' ورجعت لسفينتك. النجاح غير مؤكد.')
       else record('MOVE FAILED '..raft.Name) end
       task.wait(.65)
      end
     end
    end
   end
   task.wait(.5)
  end
  on=false
 end)
end)
stop.MouseButton1Click:Connect(function()on=false;session=session+1;setText('توقف الفحص الآلي')end)
copy.MouseButton1Click:Connect(function()
 local s=table.concat({'RAFT CHEST SCOUT REPORT','Player='..LP.Name,'Own raft='..(myRaft() and myRaft().Name or 'not found'),'Note: prompt and carry attempts do not confirm theft','===== EVENTS =====',table.concat(activity,'\n')},'\n')
 if type(setclipboard)=='function' then
  local ok=pcall(setclipboard,s)
  result.Text=ok and 'تم نسخ تقرير الصناديق' or 'فشل النسخ'
 else result.Text='نسخ تلقائي غير متاح' end
end)
E.RaftChestStop=function()
 on=false;active=false;session=session+1
 if gui.Parent then gui:Destroy()end
end
record('Chest scout loaded; checks visible proximity prompts only.')
