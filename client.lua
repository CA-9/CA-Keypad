local QBCore = exports["qb-core"]:GetCoreObject()
local txReplaceDict, txReplaceName = 'ch_prop_casino_keypads', 'prop_ld_keypad'
local propHash = `ch_prop_casino_keypad_01`
local keypadHandle = nil
local keypadCam = nil
local duiHandle = nil
local prevButtonID = -1
local codeInput = ''
local passcode = 0
local buttonThreshold = 2.5

-- Define button rotations (relative to initial rotation)
local buttonCamRots = {
    [1] = vec3(-3.52, 0.0, 8.06),
    [2] = vec3(-3.52, 0.0, 2.70),
    [3] = vec3(-3.52, 0.0, -2.58),
    [4] = vec3(-8.56, 0.0, 8.06),
    [5] = vec3(-8.56, 0.0, 2.58),
    [6] = vec3(-8.56, 0.0, -2.64),
    [7] = vec3(-13.48, 0.0, 8.0),
    [8] = vec3(-13.51, 0.0, 2.77),
    [9] = vec3(-13.51, 0.0, -2.7),
    [10] = vec3(-18.0, 0.0, 8.06), -- Cancel
    [11] = vec3(-18.1, 0.0, 2.7), -- 0
    [12] = vec3(-18.2, 0.0, -2.58)  -- #
}

function CreateDUI()
    if duiHandle ~= nil then return end
    duiHandle = lib.dui:new({
        url = ("nui://%s/html/ui.html"):format(cache.resource), 
        width = 512, 
        height = 1024,
        debug = false
    })
    lib.waitFor(function()
        if duiHandle ~= nil and duiHandle.dictName ~= nil and duiHandle.txtName ~= nil then return true end
    end)    
    AddReplaceTexture(txReplaceDict, txReplaceName, duiHandle.dictName, duiHandle.txtName)
    Wait(500)   -- Sometimes webpage hasnt loaded, not generally an issue if the dui isnt created as soon as resource starts
    duiHandle:sendMessage({
        action = "KEYPAD",
        value = true
    })
end


function CreateKeypad(x, y, z, w)
    local prop = CreateObject(propHash, x, y, z, true, false, false)
    SetEntityHeading(prop, w)

     exports['qb-target']:AddTargetEntity(prop, {
    options = {
      {
        icon = "fas fa-hashtag",
        label = "Interact with Mafia Keypad",
        targeticon = "fas fa-user",
        action = function(data)
                TransitionToKeypadCam(prop) 
            end
      }
    },
    distance = 2.0
  })
  return prop
end


function CalculateInitialCameraRotation(keypadHeading)
    local heading = (keypadHeading + 360.0) % 360.0
    return vec3(0.0, 0.0, heading)
end

function TransitionToKeypadCam(prop)
    local keypadCoords = GetEntityCoords(prop)
    local camOffset = GetOffsetFromEntityInWorldCoords(prop, 0.0, -0.25, 0.0)
    keypadCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(keypadCam, camOffset.x, camOffset.y, camOffset.z)
    local initialRot = CalculateInitialCameraRotation(GetEntityHeading(prop))
    SetCamRot(keypadCam, initialRot.x, initialRot.y, initialRot.z, 2)
    SetCamActive(keypadCam, true)
    RenderScriptCams(true, true, 1000, true, true)
    
    FreezeEntityPosition(cache.ped, true)
    TriggerEvent('zoom:updateBlock', true)          -- <= Will be different per server, hide / disable what you want here
    TriggerEvent('hud:client:ToggleHUD', false)     -- ..................................................................

    CreateThread(function()
        Wait(1000)
        SendNUIMessage({
            action = 'MOUSE',
            value = true
        })
    end)

    local camRot = initialRot
    local btnLookingAt = -1

    -- Track the camera's rotation and determine which button is being looked at
    CreateThread(function()
        while DoesCamExist(keypadCam) and IsCamActive(keypadCam) do
            DisableAllControlActions(0)

            -- Get mouse input
            xMouse = GetDisabledControlNormal(0, 1) * 8.0
            yMouse = GetDisabledControlNormal(0, 2) * 8.0
            camRot = vector3(
                math.clamp(camRot.x - yMouse, initialRot.x - 22.0, initialRot.x + 15.0),
                camRot.y,
                math.clamp(camRot.z - xMouse, initialRot.z - 15.0, initialRot.z + 15.0) 
            )
            
            -- Update camera rotation
            SetCamRot(keypadCam, camRot.x, camRot.y, camRot.z, 2)

            -- Check which button the camera is looking at
            for buttonId, buttonRot in pairs(buttonCamRots) do
                if IsCameraLookingAtButton(camRot, buttonRot, initialRot) then
                    btnLookingAt = buttonId
                end
            end

            -- Highlight the button or clear highlight
            if btnLookingAt ~= -1 then 
                HighlightButton(btnLookingAt)
            else
                HighlightButton(0)
            end

            -- Handle click action
            if IsDisabledControlJustPressed(0, 24) and btnLookingAt > 0 then
                ClickButton(btnLookingAt)
            end

            -- Handle exit interaction
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) then
                ResetToDefaultCam()
                break
            end

            btnLookingAt = -1
            Wait(0)
        end
    end)
end

function NormalizeAngle(angle)
    return ((angle + 180) % 360) - 180
end

function IsCameraLookingAtButton(camRot, buttonRot, initialRot)
    local relativeRot = vector3(
        NormalizeAngle(camRot.x - initialRot.x), 
        NormalizeAngle(camRot.y - initialRot.y), 
        NormalizeAngle(camRot.z - initialRot.z)
    )
    local deltaX = math.abs(relativeRot.x - buttonRot.x)
    local deltaY = math.abs(relativeRot.y - buttonRot.y)
    local deltaZ = math.abs(relativeRot.z - buttonRot.z)
    return deltaX <= buttonThreshold and deltaY <= buttonThreshold and deltaZ <= buttonThreshold
end

function math.clamp(value, min, max)
    return math.max(min, math.min(value, max))
end

function ResetToDefaultCam()
    if DoesCamExist(keypadCam) then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(keypadCam, false)
        keypadCam = nil
    end
    HighlightButton(0)
    FreezeEntityPosition(cache.ped, false)
    TriggerEvent('zoom:updateBlock', false)     -- <= Will be different per server, show / enable what you want here
    TriggerEvent('hud:client:ToggleHUD', true)  -- ..................................................................
    SendNUIMessage({
        action = 'MOUSE',
        value = false
    })
    codeInput = ''
    if duiHandle then
        duiHandle:sendMessage({
            action = "DISPLAY",
            value = 'ENTER CODE'
        })
    end
end

function PlayKeypadSound(sType)
    local sounds = {
        [1] = { -- Key press
            name = "Press",
            ref = "DLC_SECURITY_BUTTON_PRESS_SOUNDS"
        },
        [2] = { -- Error
            name = "Hack_Fail",
            ref = "DLC_sum20_Business_Battle_AC_Sounds"
        },
        [3] = { -- Success
            name = "Keypad_Access",
            ref = "DLC_Security_Data_Leak_2_Sounds"
        }

    }
    local sid = GetSoundId()
    PlaySoundFrontend(sid, sounds[sType].name, sounds[sType].ref, 1)
    ReleaseSoundId(sid)
end


function ClickButton(buttonId)
    local playerdata = QBCore.Functions.GetPlayerData()
    for _, zone in ipairs(Config.Zones) do
        local createdZone = CircleZone:Create(zone.coords, zone.radius, {
            name = zone.name,
            useZ = zone.useZ,
            debugPoly = zone.debugPoly
        })
        createdZone:onPlayerInOut(function(isInside)
            if isInside then
                Citizen.Wait(1)
    if ((buttonId > 0 and buttonId < 10) or buttonId == 11) and #codeInput < 5 then
        if buttonId == 11 then buttonId = 0 end
        codeInput = tostring(codeInput) .. tostring(buttonId)
        duiHandle:sendMessage({
            action = "DISPLAY",
            value = codeInput
        })
    elseif buttonId == 10 then -- Cancel
        codeInput = ''
        duiHandle:sendMessage({
            action = "DISPLAY",
            value = 'ENTER CODE'
        })
    elseif buttonId == 12 then -- Submit
        if codeInput == zone.pass and playerdata.gang.name==zone.gang and zone.name=="Mafia" then
            PlayKeypadSound(3)
            TriggerEvent("client:showBlackMarket")
            duiHandle:sendMessage({
                action = "DISPLAY",
                value = 'SUCCESS'
            })
        elseif codeInput == zone.pass and playerdata.gang.name==zone.gang and zone.name=="Mafia2" then
            PlayKeypadSound(3)
            duiHandle:sendMessage({
                action = "DISPLAY",
                value = 'SUCCESS'
            })
        elseif codeInput ~= zone.pass then
            codeInput = ''
            PlayKeypadSound(2)
            duiHandle:sendMessage({
                action = "DISPLAY",
                value = 'INVALID'
            })
        end
    end
           else
                print("Far away")
            end
        end)
    end
end

function HighlightButton(buttonId)
    if prevButtonID ~= buttonId and duiHandle then
        duiHandle:sendMessage({
            action = "BUTTON",
            value = buttonId
        })
        prevButtonID = buttonId
    end
end

-- RegisterCommand('createkeypad', function(source, args)
--     CreateDUI()
--     passcode = Config.Mafia[1].pass
--     print('Code: ' .. passcode)
--     local coords = Config.Mafia[1].coords
--     keypadHandle = CreateKeypad(coords.x, coords.y, coords.z, coords.w)
	
-- end, false)

-- RegisterCommand('createkeypad2', function(source, args)
--     CreateDUI()
--     passcode = Config.Mafia[2].pass
--     print('Code: ' .. passcode)
--     local coords = Config.Mafia[2].coords
--     keypadHandle = CreateKeypad(coords.x, coords.y, coords.z, coords.w)
	
-- end, false)

-- Citizen.CreateThread(function ()
--     ExecuteCommand("createkeypad")
--     ExecuteCommand("createkeypad2")
-- end)

Citizen.CreateThread(function()
    for _, Zone in ipairs(Config.Zones) do
    CreateDUI()
    passcode = Zone.pass
    local coords = Zone.coords
    keypadHandle = CreateKeypad(Zone.coords.x, Zone.coords.y, Zone.coords.z, Zone.coords.w)

    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    RemoveReplaceTexture(txReplaceDict, txReplaceName)
    DeleteEntity(keypadHandle)
    ResetToDefaultCam()
end)