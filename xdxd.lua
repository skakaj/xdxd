getgenv().Settings = {
    ["TimeTrial Settings"] = {
        Enabled = true,
        MaxRoom = 999, -- limit místností pro farmení (999 = nekonečno)
    },
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
repeat task.wait() until LocalPlayer and LocalPlayer:GetAttribute and LocalPlayer:GetAttribute("__LOADED")
if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
local HumanoidRootPart = LocalPlayer.Character.HumanoidRootPart

local NLibrary = ReplicatedStorage:WaitForChild("Library")
local Network = require(NLibrary.Client.Network)
local TimeTrialInstance = require(NLibrary.Client.TimeTrialCmds.TimeTrialInstance)
local PetNetworking = require(NLibrary.Client.PetNetworking)

-- Anti AFK nastavení
LocalPlayer.PlayerScripts.Scripts.Core["Server Closing"].Enabled = false
LocalPlayer.PlayerScripts.Scripts.Core["Idle Tracking"].Enabled = false
Network.Fire("Idle Tracking: Stop Timer")
LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

local TT = Settings["TimeTrial Settings"]

-- Připojení do Time Trial, včetně všech potřebných remotes
local function EnterTimeTrial()
    Network.Invoke("Instancing_PlayerEnterInstance", "TimeTrial")
    task.wait(0.2)
    Network.Fire("Instances: Mark Entered", "TimeTrial")
    task.wait(0.1)
    Network.Invoke("Instancing_InvokeCustomFromClient", "TimeTrial", "RequestAreas")
    task.wait(0.2)
end

-- Opuštění Time Trial instance
local function LeaveTimeTrial()
    Network.Fire("Instancing_PlayerLeaveInstance", "TimeTrial")
    task.wait(1)
end

-- Získání aktuální instance
local function GetCurrentTT()
    return TimeTrialInstance.GetByOwner(LocalPlayer)
end

-- Získání všech breakablů v místnosti
local function GetBreakables()
    local out = {}
    for _,v in pairs(workspace.__THINGS.Breakables:GetChildren()) do
        if v:IsA("Model") and v:GetAttribute("ParentID") == "TimeTrial" and v:FindFirstChildOfClass("MeshPart") then
            table.insert(out, v)
        end
    end
    return out
end

-- Získání všech equipped petů
local function GetEquippedPets()
    local equipped = {}
    for _,pet in pairs(PetNetworking.EquippedPets()) do
        table.insert(equipped, pet.euid)
    end
    return equipped
end

-- Hlavní farmící funkce
local function FarmBreakablesTT()
    local breakables = GetBreakables()
    local pets = GetEquippedPets()
    if #pets == 0 or #breakables == 0 then return false end

    local petBreakableTable = {}
    local petTargetTable = {}
    local petIndex, breakableIndex = 1, 1
    while petIndex <= #pets do
        local petID = pets[petIndex]
        local breakable = breakables[breakableIndex]
        local breakableUID = tostring(breakable:GetAttribute("BreakableUID"))
        petBreakableTable[tostring(petID)] = breakableUID
        petTargetTable[tostring(petID)] = {["v"] = breakableUID, ["t"] = 3}
        petIndex = petIndex + 1
        breakableIndex = breakableIndex + 1
        if breakableIndex > #breakables then
            breakableIndex = 1
        end
    end

    -- Teleport na první breakable (volitelné)
    local mesh = breakables[1]:FindFirstChildOfClass("MeshPart")
    if mesh then
        HumanoidRootPart.CFrame = mesh.CFrame * CFrame.new(0,2,0)
    end

    -- Odpálí oba remotes
    Network.Fire("Breakables_JoinPetBulk", petBreakableTable)
    Network.Fire("Pets_SetTargetBulk", petTargetTable)

    return true
end

-- Hlavní smyčka: připoj, farmi, restartuj
while task.wait(1) and TT.Enabled do
    -- 1. Vstup do TimeTrial
    EnterTimeTrial()

    -- 2. Počkej na instanci
    local TTInstance
    repeat
        TTInstance = GetCurrentTT()
        task.wait(0.5)
    until TTInstance

    -- 3. Farmící loop v TimeTrial
    repeat
        local farmed = FarmBreakablesTT()
        if not farmed then
            -- Pokud není co farmit, odejdi a začni znova
            LeaveTimeTrial()
            break
        end
        task.wait(0.25)
        TTInstance = GetCurrentTT()
    until not TTInstance or TTInstance._completed or TTInstance._roomNumber >= TT.MaxRoom

    task.wait(2)
end
