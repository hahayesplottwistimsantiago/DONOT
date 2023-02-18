function GetGitSound(GithubSnd,SoundName)
	local url=GithubSnd
	if not isfile(SoundName..".mp3") then
		writefile(SoundName..".mp3", game:HttpGet(url))
	end
	local sound=Instance.new("Sound")
	sound.SoundId=(getcustomasset or getsynasset)(SoundName..".mp3")
	return sound
end
local Players = game:GetService("Players")
local ReSt = game:GetService("ReplicatedStorage")
local RS = game:GetService("RunService")
local TS = game:GetService("TweenService")
local CG = game:GetService("CoreGui")

-- Variables

local Plr = Players.LocalPlayer
local Char = Plr.Character or Plr.CharacterAdded:Wait()
local Hum = Char:WaitForChild("Humanoid")
local Camera = workspace.CurrentCamera

local StaticRushSpeed = 60

local FindPartOnRayWithIgnoreList = workspace.FindPartOnRayWithIgnoreList
local WorldToViewportPoint = Camera.WorldToViewportPoint

local SelfModules = {
    DefaultConfig = loadstring(game:HttpGet("https://raw.githubusercontent.com/RegularVynixu/Utilities/main/Doors%20Entity%20Spawner/DefaultConfig.lua"))(),
    Functions = loadstring(game:HttpGet("https://raw.githubusercontent.com/RegularVynixu/Utilities/main/Functions.lua"))(),
}
local ModuleScripts = {
    ModuleEvents = require(ReSt.ClientModules.Module_Events),
    MainGame = require(Plr.PlayerGui.MainUI.Initiator.Main_Game),
}
local EntityConnections = {}

local Spawner = {}

-- Misc Functions

function onCharacterAdded(char)
    Char, Hum = char, char:WaitForChild("Humanoid")
end

function getPlayerRoot()
    return Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChild("Head")
end

function dragEntity(entityModel, pos, speed)
    local entityConnections = EntityConnections[entityModel]

    if entityConnections.movementNode then
        entityConnections.movementNode:Disconnect()
    end

    entityConnections.movementNode = RS.Stepped:Connect(function(_, step)
        if entityModel.Parent and not entityModel:GetAttribute("NoAI") then
            local rootPos = entityModel.PrimaryPart.Position
            local diff = Vector3.new(pos.X, pos.Y, pos.Z) - rootPos

            if diff.Magnitude > 0.1 then
                entityModel:PivotTo(CFrame.new(rootPos + diff.Unit * math.min(step * speed, diff.Magnitude)))
            else
                entityConnections.movementNode:Disconnect()
            end
        end
    end)

    repeat task.wait() until not entityConnections.movementNode.Connected
end

function loadSound(soundData)
    local sound = Instance.new("Sound")
    local soundId = tostring(soundData[1])
    local properties = soundData[2]

    for i, v in next, properties do
        if i ~= "SoundId" and i ~= "Parent" then
            sound[i] = v
        end
    end

    if soundId:find("rbxasset://") then -- Custom audio
        sound.SoundId = soundId
    else
        local numberId = soundId:gsub("%D", "")

        sound.SoundId = "rbxassetid://".. numberId
    end
    
    sound.Parent = workspace

    return sound
end

-- Functions

Spawner.createEntity = function(config)
    for i, v in next, SelfModules.DefaultConfig do
        if config[i] == nil then
            config[i] = v
        end
    end

    config.Speed = StaticRushSpeed / 100 * config.Speed

    -- Model

    local entityModel = LoadCustomInstance(config.Model)

    if typeof(entityModel) == "Instance" and entityModel.ClassName == "Model" then
        entityModel.PrimaryPart = entityModel.PrimaryPart or entityModel:FindFirstChildWhichIsA("BasePart")
        
        if entityModel.PrimaryPart then
            entityModel.PrimaryPart.Anchored = true
            
            if config.CustomName then
                entityModel.Name = config.CustomName
            end

            entityModel:SetAttribute("IsCustomEntity", true)
            entityModel:SetAttribute("NoAI", false)

            -- EntityTable

            local entityTable = {
                Model = entityModel,
                Config = config,
                Debug = {
                    OnEntitySpawned = function() end,
                    OnEntityDespawned = function() end,
                    OnEntityStartMoving = function() end,
                    OnEntityFinishedRebound = function() end,
                    OnEntityEnteredRoom = function() end,
                    OnLookAtEntity = function() end,
                    OnDeath = function() end
                }
            }

            return entityTable
        end
    end
end

Spawner.runEntity = function(entityTable)
    -- Nodes

    local nodes = {}

    for _, room in next, workspace.CurrentRooms:GetChildren() do
        local pathfindNodes = room:FindFirstChild("PathfindNodes")
        
        if pathfindNodes then
            pathfindNodes = pathfindNodes:GetChildren()
        else
            local fakeNode = Instance.new("Part")
            fakeNode.Name = "1"
            fakeNode.CFrame = room:WaitForChild("RoomExit").CFrame - Vector3.new(0, room.RoomExit.Size.Y / 2, 0)

            pathfindNodes = {fakeNode}
        end

        table.sort(pathfindNodes, function(a, b)
            return tonumber(a.Name) < tonumber(b.Name)
        end)

        for _, node in next, pathfindNodes do
            nodes[#nodes + 1] = node
        end
    end

    -- Spawn

    local entityModel = entityTable.Model:Clone()
    local startNodeIndex = entityTable.Config.BackwardsMovement and #nodes or 1
    local startNodeOffset = entityTable.Config.BackwardsMovement and -50 or 50

    EntityConnections[entityModel] = {}
    local entityConnections = EntityConnections[entityModel]
    
    entityModel:PivotTo(nodes[startNodeIndex].CFrame * CFrame.new(0, 0, startNodeOffset) + Vector3.new(0, 3.5 + entityTable.Config.HeightOffset, 0))
    entityModel.Parent = workspace
    task.spawn(entityTable.Debug.OnEntitySpawned)

    -- Mute entity on spawn

    if CG:FindFirstChild("JumpscareGui") or (Plr.PlayerGui.MainUI.Death.HelpfulDialogue.Visible and not Plr.PlayerGui.MainUI.DeathPanelDead.Visible) then
        warn("on death screen, mute entity")

        for _, v in next, entityModel:GetDescendants() do
            if v.ClassName == "Sound" and v.Playing then
                v:Stop()
            end
        end
    end

    -- Flickering

    if entityTable.Config.FlickerLights[1] then
        ModuleScripts.ModuleEvents.flicker(workspace.CurrentRooms[ReSt.GameData.LatestRoom.Value], entityTable.Config.FlickerLights[2])
    end

    -- Movement

    task.wait(entityTable.Config.DelayTime)

    local enteredRooms = {}

    entityConnections.movementTick = RS.Stepped:Connect(function()
        if entityModel.Parent and not entityModel:GetAttribute("NoAI") then
            local entityPos = entityModel.PrimaryPart.Position
            local rootPos = getPlayerRoot().Position
            local floorRay = FindPartOnRayWithIgnoreList(workspace, Ray.new(entityPos, Vector3.new(0, -10, 0)), {entityModel, Char})
            local playerInSight = FindPartOnRayWithIgnoreList(workspace, Ray.new(entityPos, rootPos - entityPos), {entityModel, Char}) == nil
            
            -- Entered room

            if floorRay ~= nil and floorRay.Name == "Floor" then
                for _, room in next, workspace.CurrentRooms:GetChildren() do
                    if floorRay:IsDescendantOf(room) and not table.find(enteredRooms, room) then
                        enteredRooms[#enteredRooms + 1] = room
                        task.spawn(entityTable.Debug.OnEntityEnteredRoom, room)

                        -- Break lights
                        
                        if entityTable.Config.BreakLights then
                            ModuleScripts.ModuleEvents.shatter(room)
                        end

                        break
                    end
                end
            end

            -- Camera shaking
            
            local shakeConfig = entityTable.Config.CamShake
            local shakeMag = (getPlayerRoot().Position - entityModel.PrimaryPart.Position).Magnitude

            if shakeConfig[1] and shakeMag <= shakeConfig[3] then
                local shakeRep = {}

                for i, v in next, shakeConfig[2] do
                    shakeRep[i] = v
                end
                shakeRep[1] = shakeConfig[2][1] / shakeConfig[3] * (shakeConfig[3] - shakeMag)

                ModuleScripts.MainGame.camShaker.ShakeOnce(ModuleScripts.MainGame.camShaker, table.unpack(shakeRep))
            end

            -- Player in sight

            if playerInSight then
                -- Look at entity

                local _, onScreen = WorldToViewportPoint(Camera, entityModel.PrimaryPart.Position)

                if onScreen then
                    task.spawn(entityTable.Debug.OnLookAtEntity)
                end

                -- Kill player

                if entityTable.Config.CanKill and not Char:GetAttribute("IsDead") and not Char:GetAttribute("Invincible") and not Char:GetAttribute("Hiding") and (getPlayerRoot().Position - entityModel.PrimaryPart.Position).Magnitude <= entityTable.Config.KillRange then
                    task.spawn(function()
                        Char:SetAttribute("IsDead", true)

                        -- Mute entity

                        warn("mute entity")

                        for _, v in next, entityModel:GetDescendants() do
                            if v.ClassName == "Sound" and v.Playing then
                                v:Stop()
                            end
                        end

                        -- Jumpscare
                        
                        if entityTable.Config.Jumpscare[1] then
                            Spawner.runJumpscare(entityTable.Config.Jumpscare[2])
                        end

                        -- Death handling
                        
                        task.spawn(entityTable.Debug.OnDeath)
                        Hum.Health = 0
                        ReSt.GameStats["Player_".. Plr.Name].Total.DeathCause.Value = entityModel.Name
                        
                        if #entityTable.Config.CustomDialog > 0 then
                            firesignal(ReSt.Bricks.DeathHint.OnClientEvent, entityTable.Config.CustomDialog)
                        end
                        
                        -- Unmute entity

                        task.spawn(function()
                            repeat task.wait() until Plr.PlayerGui.MainUI.DeathPanelDead.Visible

                            warn("unmute entity:", entityModel)

                            for _, v in next, entityModel:GetDescendants() do
                                if v.ClassName == "Sound" then
                                    local oldVolume = v.Volume
                                
                                    v.Volume = 0
                                    v:Play()
                                    TS:Create(v, TweenInfo.new(2), {Volume = oldVolume}):Play()
                                end
                            end
                        end)
                    end)
                end
            end
        end
    end)

    task.spawn(entityTable.Debug.OnEntityStartMoving)

    -- Cycles

    local cyclesConfig = entityTable.Config.Cycles

    if entityTable.Config.BackwardsMovement then
        local inverseNodes = {}

        for nodeIdx = #nodes, 1, -1 do
            inverseNodes[#inverseNodes + 1] = nodes[nodeIdx]
        end

        nodes = inverseNodes
    end

    for cycle = 1, math.max(math.random(cyclesConfig.Min, cyclesConfig.Max), 1) do
        for nodeIdx = 1, #nodes, 1 do
            dragEntity(entityModel, nodes[nodeIdx].Position + Vector3.new(0, 3.5 + entityTable.Config.HeightOffset, 0), entityTable.Config.Speed)
        end

        if cyclesConfig.Max > 1 then
            for nodeIdx = #nodes, 1, -1 do
                dragEntity(entityModel, nodes[nodeIdx].Position + Vector3.new(0, 3.5 + entityTable.Config.HeightOffset, 0), entityTable.Config.Speed)
            end
        end

        -- Rebound finished

        task.spawn(entityTable.Debug.OnEntityFinishedRebound)
        
        if cycle < cyclesConfig.Max then
            task.wait(cyclesConfig.WaitTime)
        end
    end

    -- Destroy

    if not entityModel:GetAttribute("NoAI") then
        for _, v in next, entityConnections do
            v:Disconnect()
        end
        
        entityModel:Destroy()
        task.spawn(entityTable.Debug.OnEntityDespawned)
    end
end

Spawner.runJumpscare = function(config)
					local ScreenGui = Instance.new("ScreenGui")
					local JumpscareEnd = Instance.new("ImageLabel")
					local Full = Instance.new("ImageLabel")

					--Properties:

					ScreenGui.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
					ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

					JumpscareEnd.Name = "JumpscareEnd"
					JumpscareEnd.Parent = ScreenGui
					JumpscareEnd.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					JumpscareEnd.BackgroundTransparency = 1.000
					JumpscareEnd.Position = UDim2.new(0.468161434, 0, 0.455128193, 0)
					JumpscareEnd.Size = UDim2.new(0.0636771321, 0, 0.0884615406, 0)
					JumpscareEnd.Image = "rbxassetid://0"
					JumpscareEnd.ImageColor3 = Color3.fromRGB(255, 0, 4)

					Full.Name = "Full"
					Full.Parent = ScreenGui
					Full.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					Full.BackgroundTransparency = 1.000
					Full.Position = UDim2.new(-0.0609865487, 0, -0.224358946, 0)
					Full.Size = UDim2.new(1.12197304, 0, 1.44743586, 0)
					Full.Image = "http://www.roblox.com/asset/?id=11151804223"
					Full.ImageTransparency = 1.000

					-- Scripts:


					local function DKITLS_fake_script() -- ScreenGui.Jumpscare 
						local script = Instance.new('LocalScript', ScreenGui)

						--if not workspace:FindFirstChild("A-60") then return end
						local Gui = script.Parent
						local Plr = game.Players.LocalPlayer
						local Char = Plr.Character
						local Hum = Char:FindFirstChildOfClass("Humanoid")
						local Root = Char:FindFirstChild("HumanoidRootPart")
						local A60 = workspace:FindFirstChild("A-60")
						local Camera = workspace.CurrentCamera
						local cameraShaker = require(game.ReplicatedStorage.CameraShaker)
						local ReSt = game:GetService("ReplicatedStorage")
						local camShake = cameraShaker.new(Enum.RenderPriority.Camera.Value, function(cf)
							Camera.CFrame = Camera.CFrame * cf
						end)
						local Jumpscaring = true
						local monster1 ; Part = A60:FindFirstChild("RushNew"):Clone()
						monster1.Parent = Camera ImageChange(monster1) monster1.Name = "A-60_SCARE"
						for i,v in pairs(monster1:GetDescendants()) do
							if v:IsA("Sound") then 
								v:Destroy()
							end 
						end
						local EntityOffset = Vector3.new(0,-1.2,-5)
						local LerpAlpha = 0.8
						local JumpscareSound = GetGitSound("https://github.com/hahayesplottwistimsantiago/DONOT/blob/main/asixtyScareOmg.mp3?raw=true","asixtyScareOmg.mp3") JumpscareSound.Parent = workspace
						JumpscareSound.Volume = 6
						JumpscareSound:Play()
						camShake:ShakeOnce(25,25,0,4,90,60)
						local JumpscareContrast = Instance.new("ColorCorrectionEffect",game.Lighting)
						game.TweenService:Create(JumpscareContrast,TweenInfo.new(0.5),{Brightness = 0.2,Contrast = 0.2,Saturation = -0.2,TintColor = Color3.fromRGB(255, 0, 4)}):Play()
						spawn(function()
							while Jumpscaring do game["Run Service"].RenderStepped:Wait()
								monster1.CFrame = monster1.CFrame:Lerp(Camera.CFrame*CFrame.new(EntityOffset),LerpAlpha)
							end
							game.TweenService:Create(monster1,TweenInfo.new(1),{CFrame = Camera.CFrame*CFrame.new(Vector3.new(0,-1.2,45))}):Play()
						end)
						wait(0.5) Jumpscaring = false
						Gui.JumpscareEnd.Image = monster1:FindFirstChild("Main"):FindFirstChild("Face").Texture
						game.TweenService:Create(Gui.JumpscareEnd,TweenInfo.new(0.5),{Size = Gui.Full.Size,Position = Gui.Full.Position,Rotation = math.random(-20,20)}):Play()
						game.TweenService:Create(JumpscareContrast,TweenInfo.new(10),{Brightness = 0,Contrast = 0,Saturation = 0,TintColor = Color3.fromRGB(255, 255, 255)}):Play()
						ReSt.GameStats["Player_".. Plr.Name].Total.DeathCause.Value = "A-60"
						Char:FindFirstChildWhichIsA("Humanoid"):TakeDamage(100)
						firesignal(game.ReplicatedStorage.Bricks.DeathHint.OnClientEvent, {"You died to an enitity designated as A-60", "It can Apear at any moment, a loud scream will anounce its presence", "When you hear it spawn you must stay out of its reach as soon as possible", "It knows exactly where you are so hiding in different places will not work.."})
						wait(0.5)
						game.TweenService:Create(Gui.JumpscareEnd,TweenInfo.new(0.5),{ImageTransparency = 1}):Play()
						game.Debris:AddItem(monster1,1)

					end
					coroutine.wrap(DKITLS_fake_script)()
					local function OUNG_fake_script() -- JumpscareEnd.Script 
						local script = Instance.new('Script', JumpscareEnd)

						while true do
							wait()
							script.Parent.Rotation = script.Parent.Rotation + math.random(-6,6)
							--script.Parent.Position = script.Parent.Position + UDim2.new(0,math.random(0,100),0,math.random(-150,150))
						end
					end
					coroutine.wrap(OUNG_fake_script)()

				end
    -- Variables

  --  local image1 = LoadCustomAsset(config.Image1)
  --  local image2 = LoadCustomAsset(config.Image2)
  --  local sound1, sound2 = nil, nil

  --  if config.Sound1 then
  --      sound1 = loadSound(config.Sound1)
  --  end

  --  if config.Sound2 then
  --      sound2 = loadSound(config.Sound2)
  --  end

    -- UI Construction

   -- local JumpscareGui = Instance.new("ScreenGui")
   -- local Background = Instance.new("Frame")
   -- local Face = Instance.new("ImageLabel")

    -- Jumpscare
    
   -- Face.Image = image2
   -- Face.Size = UDim2.new(0, maxTeaseSize, 0, maxTeaseSize)
   -- sound2:Play()
    
   -- TS:Create(Face, TweenInfo.new(0.75), {Size = UDim2.new(0, absHeight * 3, 0,  absHeight * 3), ImageTransparency = 0.5}):Play()
   -- task.wait(0.75)
   -- JumpscareGui:Destroy()
    
  --  if sound1 then
  --      sound1:Destroy()
  --  end
    
   -- if sound2 then
  --      sound2:Destroy()
  --  end
end

-- Scripts

Plr.CharacterAdded:Connect(onCharacterAdded)

if not SpawnerSetup then
    getgenv().SpawnerSetup = true

    workspace.DescendantRemoving:Connect(function(des)
        if des.Name == "PathfindNodes" then
            des:Clone().Parent = des.Parent
        end
    end)
end

return Spawner