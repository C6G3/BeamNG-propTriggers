-- This Source Code Form is subject to the terms of the MIT License.
-- Copyright (c) 2026 
-- Author C6g3. 
--
-- For the latest updates, documentation, and examples, please check the official repository:
-- GitHub: https://github.com/Psynolyn/BeamNG-propTriggers.git


local M = {}
M.drawBoxes = false
local logTag = 'propTriggers'
local triggersByVeh = {}
local propTriggerLinksDict = {}  -- [vehId][triggerId][triggerInput] = {links}
local cursorVisible = true
local initializedVehicles = false
local prevHoveredPropTrigger = { vehId = nil, triggerId = nil }

local is039OrHigher = nil
local function checkIs039OrHigher()
    if is039OrHigher ~= nil then return is039OrHigher end
    local ver = beamng_version or beamng_versiond or beamng_versionb
    if type(ver) == "string" then
        local major, minor = string.match(ver, "^(%d+)%.(%d+)")
        if major and minor then
            local majNum = tonumber(major) or 0
            local minNum = tonumber(minor) or 0
            if majNum > 0 or minNum >= 39 then
                is039OrHigher = true
                return true
            else
                is039OrHigher = false
                return false
            end
        end
    end
    if core_vehicle_triggerLabelPlacement or (extensions and extensions.core_vehicle_triggerLabelPlacement) then
        is039OrHigher = true
        return true
    end
    is039OrHigher = false
    return false
end

-- Find the first keyboard binding for a given action string, matching inversion state.
local function findKeyboardBindingForAction(actionStr, desiredInverted)
    for _, device in ipairs(core_input_bindings and core_input_bindings.bindings or {}) do
        local contents = device.contents or {}
        if contents.devicetype == 'keyboard' then
            for _, b in ipairs(contents.bindings or {}) do
                if b.action == actionStr and ((b.isInverted or false) == (desiredInverted or false)) then
                    return device.devname, b
                end
            end
        end
    end
end

local function isControllerDeviceType(deviceType)
    return deviceType ~= "keyboard" and deviceType ~= "mouse"
end

-- Preferred binding finder for 0.39+ (matching core/vehicleTriggers.lua)
local function findBindingForAction(actionStr, desiredInverted)
    local preferredPad = core_camera and core_camera.getLastFilter and core_camera.getLastFilter() == FILTER_PAD
    local recentDevices = core_input_bindings and core_input_bindings.getRecentDevices and core_input_bindings.getRecentDevices() or {}
    local recentRank = {}
    for i, devname in ipairs(recentDevices) do
        recentRank[devname] = i
    end

    local bestDeviceName, bestBinding, bestScore = nil, nil, -math.huge

    for _, device in ipairs(core_input_bindings and core_input_bindings.bindings or {}) do
        local contents = device.contents or {}
        local deviceType = contents.devicetype
        for _, b in ipairs(contents.bindings or {}) do
            if b.action == actionStr and ((b.isInverted or false) == (desiredInverted or false)) then
                local score = 0
                local isController = isControllerDeviceType(deviceType)
                if preferredPad then
                    if isController then score = score + 100 end
                else
                    if deviceType == "keyboard" then
                        score = score + 100
                    elseif deviceType == "mouse" then
                        score = score + 80
                    end
                end

                local rank = recentRank[device.devname]
                if rank then
                    score = score + math.max(0, 50 - rank)
                end

                if score > bestScore then
                    bestScore = score
                    bestDeviceName = device.devname
                    bestBinding = b
                end
            end
        end
    end

    return bestDeviceName, bestBinding
end

-- ── 0.39 Screen Projection & Bubble Placement ──
local w2sCamRight = vec3()
local w2sCamForward = vec3()
local w2sCamUp = vec3()
local w2sToPoint = vec3()
local w2sContextValid = false
local w2sContextCamPos = nil
local w2sContextHalfTan = 0
local w2sContextAspect = 0

local function rotateVecByQuatInPlace(outVec, quatValue, inX, inY, inZ)
    local qx, qy, qz, qw = quatValue.x, quatValue.y, quatValue.z, quatValue.w
    local tx = 2 * (qy * inZ - qz * inY)
    local ty = 2 * (qz * inX - qx * inZ)
    local tz = 2 * (qx * inY - qy * inX)
    outVec:set(
        inX - qw * tx + (qy * tz - qz * ty),
        inY - qw * ty + (qz * tx - qx * tz),
        inZ - qw * tz + (qx * ty - qy * tx)
    )
end

local function updateWorldPosToScreenContext()
    w2sContextValid = false
    if not core_camera or not core_camera.getPosition or not core_camera.getQuat then return false end
    local camPos = core_camera.getPosition()
    local camRot = core_camera.getQuat()
    if not camPos or not camRot then return false end

    local canvas = scenetree.findObject("Canvas")
    if not canvas or not canvas.getWindowClientSizeXY then return false end
    local clientW, clientH = canvas:getWindowClientSizeXY()
    if not clientW or not clientH or clientW <= 0 or clientH <= 0 then return false end

    local fovRad = core_camera.getFovRad and core_camera.getFovRad() or nil
    if not fovRad or fovRad <= 0 then return false end
    local aspect = clientW / clientH
    if aspect <= 0 then return false end

    local halfTan = math.tan(fovRad * 0.5)
    if halfTan == 0 then return false end

    rotateVecByQuatInPlace(w2sCamRight, camRot, 1, 0, 0)
    rotateVecByQuatInPlace(w2sCamForward, camRot, 0, 1, 0)
    rotateVecByQuatInPlace(w2sCamUp, camRot, 0, 0, 1)

    w2sContextCamPos = camPos
    w2sContextHalfTan = halfTan
    w2sContextAspect = aspect
    w2sContextValid = true
    return true
end

local function worldPosToScreenPercent01(worldPos, out)
    if not worldPos then return nil end
    if extensions.core_vehicleTriggers and extensions.core_vehicleTriggers.worldPosToScreenPercent01 then
        return extensions.core_vehicleTriggers.worldPosToScreenPercent01(worldPos, out)
    end
    if not w2sContextValid and not updateWorldPosToScreenContext() then return nil end

    w2sToPoint:setSub2(worldPos, w2sContextCamPos)

    local depth = w2sToPoint:dot(w2sCamForward)
    if not depth or depth <= 0 then return nil end

    local nx = w2sToPoint:dot(w2sCamRight) / (depth * w2sContextHalfTan * w2sContextAspect)
    local ny = w2sToPoint:dot(w2sCamUp) / (depth * w2sContextHalfTan)

    out = out or {}
    out.x = (nx + 1) * 0.5
    out.y = (1 - ny) * 0.5
    return out
end

local LABEL_OFFSET_REM = "0.6em"
local function clamp01(v) return math.max(0, math.min(1, v)) end

local function computeLabelPlacementForPropTrigger(centerWorld, ax, ay, az, hx, hy, hz, screenPos)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local hasAnyCorner = false

    local tmpWorld = vec3()
    local tmpScreen = {}
    for sx = -1, 1, 2 do
        for sy = -1, 1, 2 do
            for sz = -1, 1, 2 do
                tmpWorld:setAddScaled(centerWorld, ax, hx * sx)
                tmpWorld:setAddScaled(tmpWorld, ay, hy * sy)
                tmpWorld:setAddScaled(tmpWorld, az, hz * sz)
                local sp = worldPosToScreenPercent01(tmpWorld, tmpScreen)
                if sp and type(sp.x) == "number" and type(sp.y) == "number" then
                    hasAnyCorner = true
                    minX = math.min(minX, sp.x)
                    maxX = math.max(maxX, sp.x)
                    minY = math.min(minY, sp.y)
                    maxY = math.max(maxY, sp.y)
                end
            end
        end
    end

    local bounds = {}
    if hasAnyCorner then
        bounds.minX = minX
        bounds.maxX = maxX
        bounds.minY = minY
        bounds.maxY = maxY
        bounds.centerX = (minX + maxX) * 0.5
        bounds.centerY = (minY + maxY) * 0.5
    elseif screenPos then
        local x = clamp01(screenPos.x)
        local y = clamp01(screenPos.y)
        bounds.minX = x; bounds.maxX = x
        bounds.minY = y; bounds.maxY = y
        bounds.centerX = x; bounds.centerY = y
    else
        return nil
    end

    local side = "right"
    local centerMin = 0.15
    local centerMax = 0.85
    local insideCenter70 = bounds.minX >= centerMin and bounds.maxX <= centerMax and bounds.minY >= centerMin and bounds.maxY <= centerMax
    if insideCenter70 then
        side = "bottom"
    else
        local rightSpace = 1 - bounds.maxX
        local leftSpace = bounds.minX
        local topSpace = bounds.minY
        local bottomSpace = 1 - bounds.maxY
        local bestSpace = rightSpace
        if leftSpace > bestSpace then bestSpace = leftSpace; side = "left" end
        if topSpace > bestSpace then bestSpace = topSpace; side = "top" end
        if bottomSpace > bestSpace then side = "bottom" end
    end

    local labelX, labelY, labelTx, labelTy
    if side == "right" then
        labelX = bounds.maxX; labelY = bounds.centerY; labelTx = LABEL_OFFSET_REM; labelTy = "-50%"
    elseif side == "left" then
        labelX = bounds.minX; labelY = bounds.centerY; labelTx = "calc(-100% - " .. LABEL_OFFSET_REM .. ")"; labelTy = "-50%"
    elseif side == "top" then
        labelX = bounds.centerX; labelY = bounds.minY; labelTx = "-50%"; labelTy = "calc(-100% - " .. LABEL_OFFSET_REM .. ")"
    else
        labelX = bounds.centerX; labelY = bounds.maxY; labelTx = "-50%"; labelTy = LABEL_OFFSET_REM
    end

    return {
        labelX = clamp01(labelX),
        labelY = clamp01(labelY),
        labelTx = labelTx,
        labelTy = labelTy,
        labelSide = side,
        bounds = bounds
    }
end

local function formatActionTitle(rawTitle)
    if not rawTitle or rawTitle == "" then return "" end
    if type(_tr) == "function" then
        local translated = _tr(rawTitle)
        if translated and translated ~= "" and translated ~= rawTitle then return translated end
    end
    local str = tostring(rawTitle)
    str = str:gsub("^ui%.inputActions%.vehicle%.", ""):gsub("^ui%.inputActions%.", ""):gsub("%.title$", "")
    str = str:gsub("_", " ")
    if str:match("^%l") then
        str = str:gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest:lower() end)
    end
    return str
end

local function resolveActionIcon(action, actionName, trg, actionKey)
    if action and action.icon and type(action.icon) == "string" and action.icon ~= "" then
        return action.icon
    end
    if trg and trg.icon and type(trg.icon) == "string" and trg.icon ~= "" then
        return trg.icon
    end

    local text = string.lower(tostring(actionName or "") .. " " .. tostring(trg and trg.id or "") .. " " .. tostring(action and action.title or ""))

    -- Infotainment / Audio controls
    if text:find("volup") or text:find("vol_up") or text:find("volume%s*up") or text:find("volumeplus") or text:find("volume_plus") or text:find("volume%+") then
        return "soundLoud"
    end
    if text:find("voldown") or text:find("vo_down") or text:find("vodown") or text:find("volume%s*down") or text:find("volumeminus") or text:find("volume_minus") or text:find("volume%-") then
        return "soundQuiet"
    end
    if text:find("mute") or text:find("soundoff") then
        return "soundOff"
    end
    if text:find("next") or text:find("forward") or text:find("skip_next") then
        return "nextTrack"
    end
    if text:find("prev") or text:find("rewind") or text:find("skip_prev") or text:find("back_track") then
        return "prevTrack"
    end
    if text:find("play") or text:find("pause") then
        return "playPause"
    end
    if text:find("music") or text:find("audio") or text:find("song") then
        return "music"
    end

    -- Navigation / Voice
    if text:find("voicenav") or text:find("voice_nav") or text:find("voice") then
        return "road"
    end
    if text:find("nav") or text:find("gps") or text:find("map") or text:find("route") then
        return "steeringWheelSporty"
    end

    -- Vehicle Controls
    if text:find("hazard") then
        return "hazardLights"
    end
    if text:find("light") or text:find("beam") or text:find("lamp") then
        return "lightGarageG11"
    end
    if text:find("door") then
        return "doorHandle"
    end
    if text:find("cruise") or text:find("cc") then
        return "cruiseEnable"
    end
    if text:find("diff") or text:find("differential") then
        return "differentialMiddleLocked"
    end
    if text:find("steer") then
        return "steeringWheelCommon"
    end

    -- Mouse and control fallbacks
    if actionKey == "action0" or actionKey == "leftClick" then
        return "mouseLMB"
    elseif actionKey == "action1" or actionKey == "rightClick" then
        return "mouseRMB"
    elseif actionKey == "action2" or actionKey == "middleClick" then
        return "mouseMMB"
    elseif actionKey == "wheelUp" or actionKey == "wheelDown" or actionKey == "wheel" then
        return "mouseWheel"
    end

    return "mouseLMB"
end

local lastPropTriggerCrosshairSent = false

local function setPropTriggerCrosshairTargetStream(x, y, actionTitles, triggerColor, labelPlacement, hoveredTriggerName, actionIcons, triggerIcon)
    local function roundCoord(v)
        if not v or type(v) ~= "number" then return nil end
        return math.floor(v * 10000 + 0.5) / 10000
    end

    local xRounded = roundCoord(x)
    local yRounded = roundCoord(y)
    local action0 = actionTitles and actionTitles.action0 and (type(_tr) == "function" and _tr(actionTitles.action0) or actionTitles.action0) or nil
    local action1 = actionTitles and actionTitles.action1 and (type(_tr) == "function" and _tr(actionTitles.action1) or actionTitles.action1) or nil
    local action2 = actionTitles and actionTitles.action2 and (type(_tr) == "function" and _tr(actionTitles.action2) or actionTitles.action2) or nil
    local action0Icon = actionIcons and actionIcons.action0 or nil
    local action1Icon = actionIcons and actionIcons.action1 or nil
    local action2Icon = actionIcons and actionIcons.action2 or nil
    local primaryIcon = triggerIcon or action0Icon or (actionIcons and next(actionIcons) and select(2, next(actionIcons))) or nil
    local colorR = triggerColor and triggerColor.r or 0.235
    local colorG = triggerColor and triggerColor.g or 0.396
    local colorB = triggerColor and triggerColor.b or 1.0
    local colorA = triggerColor and triggerColor.a or 0.75
    local labelX = labelPlacement and labelPlacement.labelX or xRounded
    local labelY = labelPlacement and labelPlacement.labelY or yRounded
    local labelTx = labelPlacement and labelPlacement.labelTx or "0.6em"
    local labelTy = labelPlacement and labelPlacement.labelTy or "-50%"
    local labelSide = labelPlacement and labelPlacement.labelSide or "right"
    local boundsMinX = labelPlacement and labelPlacement.bounds and labelPlacement.bounds.minX or xRounded
    local boundsMaxX = labelPlacement and labelPlacement.bounds and labelPlacement.bounds.maxX or xRounded
    local boundsMinY = labelPlacement and labelPlacement.bounds and labelPlacement.bounds.minY or yRounded
    local boundsMaxY = labelPlacement and labelPlacement.bounds and labelPlacement.bounds.maxY or yRounded
    local boundsCenterX = labelPlacement and labelPlacement.bounds and labelPlacement.bounds.centerX or xRounded
    local boundsCenterY = labelPlacement and labelPlacement.bounds and labelPlacement.bounds.centerY or yRounded

    local payload = {
        x = xRounded,
        y = yRounded,
        action0 = action0,
        action1 = action1,
        action2 = action2,
        action0Icon = action0Icon,
        action1Icon = action1Icon,
        action2Icon = action2Icon,
        action0_icon = action0Icon,
        action1_icon = action1Icon,
        action2_icon = action2Icon,
        icon0 = action0Icon,
        icon1 = action1Icon,
        icon2 = action2Icon,
        icon = primaryIcon,
        actionIcons = actionIcons,
        colorR = colorR,
        colorG = colorG,
        colorB = colorB,
        colorA = colorA,
        hoveredTriggerName = hoveredTriggerName,
        labelX = labelX,
        labelY = labelY,
        labelTx = labelTx,
        labelTy = labelTy,
        labelSide = labelSide,
        boundsMinX = boundsMinX,
        boundsMaxX = boundsMaxX,
        boundsMinY = boundsMinY,
        boundsMaxY = boundsMaxY,
        boundsCenterX = boundsCenterX,
        boundsCenterY = boundsCenterY,
    }

    if guihooks and guihooks.triggerStream then
        guihooks.triggerStream("vehicleTriggerCrosshairTarget", payload)
        lastPropTriggerCrosshairSent = true
    end
end

local function clearPropTriggerCrosshairTargetStream()
    if lastPropTriggerCrosshairSent then
        if guihooks and guihooks.triggerStream then
            guihooks.triggerStream("vehicleTriggerCrosshairTarget", {})
        end
        lastPropTriggerCrosshairSent = false
    end
end

local function rayPointDist(rayPos, rayDir, point)
    local d = point - rayPos
    local proj = math.max(0, d:dot(rayDir))
    return (point - (rayPos + rayDir * proj)):length()
end

-- Builds a rotation matrix from a per-axis euler triple using explicit
-- single-axis matrices multiplied in X, then Y, then Z order (M = Rx*Ry*Rz).
-- This matches the confirmed-correct convention used elsewhere in the engine
-- for vehicle-attached local rotations (see screenService.lua's box/trigger
-- rotation construction), rather than relying on quatFromEuler's internal
-- (and here, unverified) axis composition order.
local function eulerToMatrix(v, isRadians)
    local x = v.x or v[1] or 0
    local y = v.y or v[2] or 0
    local z = v.z or v[3] or 0
    if not isRadians then
        x, y, z = math.rad(x), math.rad(y), math.rad(z)
    end
    local rotX = MatrixF(true)
    local rotY = MatrixF(true)
    local rotZ = MatrixF(true)
    rotX:setFromEuler(vec3(x, 0, 0))
    rotY:setFromEuler(vec3(0, y, 0))
    rotZ:setFromEuler(vec3(0, 0, z))
    local m = rotX:copy()
    m:mul(rotY)
    m:mul(rotZ)
    return m
end

local function getNodeId(vData, nodeStr)
    if type(nodeStr) == 'number' then return nodeStr end
    if not nodeStr or type(vData.vdata.nodes) ~= 'table' then return 0 end
    local n = vData.vdata.nodes[nodeStr]
    if n and n.cid then return n.cid end
    for _, node in pairs(vData.vdata.nodes) do
        if node.id == nodeStr or node.name == nodeStr then return node.cid or 0 end
    end
    return 0
end

local function drawOBBSolid(center, ax, ay, az, r, g, b, a)
    local col = color(math.floor(r*255), math.floor(g*255), math.floor(b*255), math.floor(a*255))
    local p0 = center - ax - ay - az
    local p1 = center + ax - ay - az
    local p2 = center + ax + ay - az
    local p3 = center - ax + ay - az
    local p4 = center - ax - ay + az
    local p5 = center + ax - ay + az
    local p6 = center + ax + ay + az
    local p7 = center - ax + ay + az
    debugDrawer:drawTriSolid(p0, p1, p2, col); debugDrawer:drawTriSolid(p0, p2, p3, col)
    debugDrawer:drawTriSolid(p0, p2, p1, col); debugDrawer:drawTriSolid(p0, p3, p2, col)
    debugDrawer:drawTriSolid(p4, p5, p6, col); debugDrawer:drawTriSolid(p4, p6, p7, col)
    debugDrawer:drawTriSolid(p4, p6, p5, col); debugDrawer:drawTriSolid(p4, p7, p6, col)
    debugDrawer:drawTriSolid(p0, p1, p5, col); debugDrawer:drawTriSolid(p0, p5, p4, col)
    debugDrawer:drawTriSolid(p0, p5, p1, col); debugDrawer:drawTriSolid(p0, p4, p5, col)
    debugDrawer:drawTriSolid(p3, p2, p6, col); debugDrawer:drawTriSolid(p3, p6, p7, col)
    debugDrawer:drawTriSolid(p3, p6, p2, col); debugDrawer:drawTriSolid(p3, p7, p6, col)
    debugDrawer:drawTriSolid(p0, p3, p7, col); debugDrawer:drawTriSolid(p0, p7, p4, col)
    debugDrawer:drawTriSolid(p0, p7, p3, col); debugDrawer:drawTriSolid(p0, p4, p7, col)
    debugDrawer:drawTriSolid(p1, p2, p6, col); debugDrawer:drawTriSolid(p1, p6, p5, col)
    debugDrawer:drawTriSolid(p1, p6, p2, col); debugDrawer:drawTriSolid(p1, p5, p6, col)
end

local function col(row, name, defaultIdx)
    for k, v in pairs(row) do
        if type(k) == 'string' and k:lower() == name:lower() then return v end
    end
    return row[defaultIdx]
end

local function extractTargetPropList(raw, out, seen)
    out = out or {}
    seen = seen or {}
    if not raw then return out end

    local function addCandidate(str)
        if type(str) == "string" then
            local trimmed = str:match("^%s*[\"']?(.-)[\"']?%s*$")
            if trimmed and trimmed ~= "" then
                local lowerKey = trimmed:lower()
                if not seen[lowerKey] then
                    seen[lowerKey] = true
                    table.insert(out, trimmed)
                end
            end
        end
    end

    local t = type(raw)
    if t == "string" then
        if raw:find("[,;|]") then
            for item in raw:gmatch("[^,;|]+") do
                addCandidate(item)
            end
        else
            addCandidate(raw)
        end
    elseif t == "table" then
        -- 1. Recursively traverse array elements in numeric order
        local n = #raw
        if n > 0 then
            for i = 1, n do
                extractTargetPropList(raw[i], out, seen)
            end
        end
        -- 2. Traverse any named/dict keys (e.g. targetProps, targetProp, mesh, name, prop)
        for k, v in pairs(raw) do
            if type(k) == "string" then
                local kLower = k:lower()
                if kLower == "targetprop" or kLower == "targetprops" or kLower == "mesh" or kLower == "name" or kLower == "prop" then
                    extractTargetPropList(v, out, seen)
                elseif type(k) ~= "number" or (k < 1 or k > n) then
                    if type(v) == "table" or type(v) == "string" then
                        extractTargetPropList(v, out, seen)
                    end
                end
            elseif type(k) == "number" and (k < 1 or k > n) then
                extractTargetPropList(v, out, seen)
            end
        end
    end
    return out
end

local function propMatchesCandidate(prop, candidate)
    if not prop or not candidate or candidate == "" then return false end
    local candClean = candidate:lower():match("^%s*[\"']?(.-)[\"']?%s*$")
    if not candClean or candClean == "" then return false end

    local function checkStr(val)
        if type(val) ~= "string" then return false end
        local valClean = val:lower():match("^%s*(.-)%s*$")
        if valClean == candClean then return true end
        local vBase = valClean:gsub("%.%w+$", "")
        local cBase = candClean:gsub("%.%w+$", "")
        if vBase == cBase and vBase ~= "" then return true end
        return false
    end

    if checkStr(prop.mesh) then return true end
    if checkStr(prop.originalMesh) then return true end
    if checkStr(prop.name) then return true end
    return false
end

local function findAvailableProp(beObj, vData, targetProps)
    if not targetProps or #targetProps == 0 then return nil, nil, nil end
    if not vData or not vData.vdata or not vData.vdata.props then return nil, nil, nil end

    local propsTable = vData.vdata.props

    -- Primary search: iterate candidate props in priority order, looking for an enabled prop
    -- whose live C++ SimObject (beObj:getProp(pid)) is available and valid.
    for _, candidate in ipairs(targetProps) do
        for k, prop in pairs(propsTable) do
            if prop and not prop.disabled and propMatchesCandidate(prop, candidate) then
                local pid = prop.pid or (type(k) == "number" and k) or prop.id
                if pid ~= nil then
                    if beObj then
                        local pObj = beObj:getProp(pid)
                        if pObj then
                            return pid, pObj, prop
                        end
                    else
                        return pid, nil, prop
                    end
                end
            end
        end
    end

    -- Secondary fallback: if beObj exists but live getProp wasn't ready yet during early spawn,
    -- match the first candidate that exists in the vehicle's compiled props table.
    for _, candidate in ipairs(targetProps) do
        for k, prop in pairs(propsTable) do
            if prop and not prop.disabled and propMatchesCandidate(prop, candidate) then
                local pid = prop.pid or (type(k) == "number" and k) or prop.id
                if pid ~= nil then
                    local pObj = beObj and beObj:getProp(pid) or nil
                    return pid, pObj, prop
                end
            end
        end
    end

    return nil, nil, nil
end

local function parseTriggersTable(vehId, triggersTable, isTriggers2)
    local vData = core_vehicle_manager.getVehicleData(vehId)
    for _, row in pairs(triggersTable) do
        if type(row) == 'table' then
            local ok, err = pcall(function()
                local rawSize    = col(row, "size", 4)
                local szvec = vec3(1, 1, 1)
                if type(rawSize) == 'table' then
                    szvec = vec3(rawSize.x or rawSize[1] or 1, rawSize.y or rawSize[2] or 1, rawSize.z or rawSize[3] or 1)
                elseif type(rawSize) == 'cdata' then
                    szvec = vec3(rawSize)
                elseif type(rawSize) == 'number' then
                    szvec = vec3(rawSize, rawSize, rawSize)
                end

                local rawBT = col(row, "baseTranslation", 6)
                local btvec = vec3(0, 0, 0)
                if type(rawBT) == 'table' then
                    btvec = vec3(rawBT.x or rawBT[1] or 0, rawBT.y or rawBT[2] or 0, rawBT.z or rawBT[3] or 0)
                elseif type(rawBT) == 'cdata' then
                    btvec = vec3(rawBT)
                end

                local rawBR = col(row, "baseRotation", -1) -- No longer array indexed by default
                local brMat = MatrixF(true)
                if rawBR then
                    brMat = eulerToMatrix(rawBR, isTriggers2)
                end

                local idRef = getNodeId(vData, col(row, "idRef", -1))
                local idX   = getNodeId(vData, col(row, "idX",   -1))
                local idY   = getNodeId(vData, col(row, "idY",   -1))

                local triggerId  = col(row, "id", 1) or col(row, "name", 1)
                local rawTargetProp1 = col(row, "targetProps", -1)
                local rawTargetProp2 = col(row, "targetProp", 2)
                local targetProps = extractTargetPropList(rawTargetProp1)
                if rawTargetProp2 then extractTargetPropList(rawTargetProp2, targetProps) end
                local firstTargetProp = targetProps[1] or (type(rawTargetProp2) == "string" and rawTargetProp2 or (type(rawTargetProp1) == "string" and rawTargetProp1 or nil))

                if triggerId and triggerId ~= "id" and triggerId ~= "name" then
                    table.insert(triggersByVeh[vehId], {
                        idRef       = idRef,
                        idX         = idX,
                        idY         = idY,
                        baseTrans   = btvec,
                        baseRot     = brMat,
                        halfSize    = szvec * 0.5,
                        triggerType = col(row, "type", 3) or "box",
                        id          = triggerId,
                        targetProp  = firstTargetProp,
                        targetProps = targetProps,
                        rawTargetProp = rawTargetProp2 or rawTargetProp1,
                        action      = col(row, "action", 7) or "",
                        meshName    = col(row, "meshName", 5),
                        icon        = col(row, "icon", -1),
                        alpha       = 0,
                        isTriggers2 = isTriggers2,
                    })
                end
            end)
            if not ok then
                jsonWriteFile("propTriggers_debug.json", { ERROR_parseTriggersTable = tostring(err) }, true)
            end
        end
    end
end

local function getCppCenterForTrigger(beObj, vData, triggerId)
    if not vData or not vData.vdata or not vData.vdata.triggers then return nil, nil end
    for _, trg in pairs(vData.vdata.triggers) do
        if trg.name == triggerId and trg.cid ~= nil then
            local to = beObj:getTrigger(trg.cid)
            if to then
                local c = to:getCenter()
                return vec3(c), trg.cid
            end
        end
    end
    return nil, nil
end

-- Build a string-keyed event links dictionary from the propTriggerEventLinks jbeam section.
-- This replicates how the game's processTriggerEventLinks builds triggerEventLinksDict,
-- but uses string trigger IDs (matching propTriggers entries) instead of numeric cids.
local function buildPropTriggerEventLinks(vehId)
    local vData = core_vehicle_manager.getVehicleData(vehId)
    if not vData or not vData.vdata then return end
    propTriggerLinksDict[vehId] = {}
    local linksTable = vData.vdata.propTriggerEventLinks
    if not linksTable then return end

    for _, lnk in pairs(linksTable) do
        if type(lnk) == 'table' then
            local tId = col(lnk, "triggerId", 1)
            local tIn = col(lnk, "triggerInput", 2)
            local iAc = col(lnk, "inputAction", 3)

            if tId and tId ~= "triggerId" and tIn and iAc then
                -- Parse namespace:action format just like triggerEventLinks2
                local namespace, inputActionName = string.match(iAc, "^(%a+):(.*)")
                if namespace == nil then
                    inputActionName = iAc
                    namespace = 'vehicle'
                end

                local entry = {
                    triggerId   = tId,
                    triggerInput = tIn,
                    inputAction = inputActionName,
                    namespace   = namespace,
                    version     = 2,
                    isInverted  = col(lnk, "invert", -1) or false,
                }

                if not propTriggerLinksDict[vehId][tId] then propTriggerLinksDict[vehId][tId] = {} end
                if not propTriggerLinksDict[vehId][tId][tIn] then propTriggerLinksDict[vehId][tId][tIn] = {} end
                table.insert(propTriggerLinksDict[vehId][tId][tIn], entry)
            end
        end
    end
end

-- Execute a single propTrigger event link, replicating the core executeLink logic.
local function executePropLink(vehId, lnk, actionValue)
    local vData = core_vehicle_manager.getVehicleData(vehId)
    if not vData or not vData.vdata then return 0 end

    local value = actionValue
    if lnk.isInverted then value = -value end

    if lnk.namespace == 'vehicle' then
        if not vData.vdata.inputActions or not vData.vdata.inputActions[lnk.inputAction] then
            log('E', logTag, 'input action not found: ' .. tostring(lnk.inputAction))
            return 0
        end
        return core_input_actions.executeCommand(vData.vdata.inputActions[lnk.inputAction], value, vehId)
    elseif lnk.namespace == 'common' then
        -- Check if this common action has a Lua binding in the vehicle's inputActions
        if vData.vdata.inputActions and vData.vdata.inputActions[lnk.inputAction] then
            return core_input_actions.executeCommand(vData.vdata.inputActions[lnk.inputAction], value, vehId)
        end
        -- Otherwise invoke C++ actionmap binding
        local triggeredCount = ActionMap.triggerBindingByNameDigital(lnk.inputAction, actionValue > 0.9, os.clockhp(), vehId)
        return triggeredCount or 0
    end
    return 0
end

-- Fire all propTriggerEventLinks for a given trigger ID and action string.
local function firePropTriggerEvent(vehId, triggerId, actionStr, actionValue)
    local vehLinks = propTriggerLinksDict[vehId]
    if not vehLinks then return end
    local trgLinks = vehLinks[triggerId]
    if not trgLinks then return end
    local actionLinks = trgLinks[actionStr]
    if not actionLinks then return end
    for _, lnk in ipairs(actionLinks) do
        executePropLink(vehId, lnk, actionValue)
    end
end

local cachedOBJs = {}

local function loadOBJ(filepath)
    if cachedOBJs[filepath] then return cachedOBJs[filepath] end
    
    local f = io.open(filepath, "r")
    if not f then
        log('E', logTag, "Could not open OBJ file: " .. tostring(filepath))
        return nil
    end

    local verts = {}
    local tris = {}

    for line in f:lines() do
        local type, rest = line:match("^%s*(%S+)%s+(.*)$")
        if type == "v" then
            local x, y, z = rest:match("([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if x and y and z then
                table.insert(verts, vec3(tonumber(x), tonumber(y), tonumber(z)))
            end
        elseif type == "f" then
            local faceVerts = {}
            for vstr in rest:gmatch("%S+") do
                local vidx = vstr:match("^(%d+)")
                if vidx then
                    table.insert(faceVerts, tonumber(vidx))
                end
            end
            -- Triangulate simple polygons (fan triangulation)
            if #faceVerts >= 3 then
                for i = 2, #faceVerts - 1 do
                    local v1 = verts[faceVerts[1]]
                    local v2 = verts[faceVerts[i]]
                    local v3 = verts[faceVerts[i+1]]
                    if v1 and v2 and v3 then
                        table.insert(tris, {v1, v2, v3})
                    end
                end
            end
        end
    end
    f:close()

    cachedOBJs[filepath] = tris
    return tris
end

local function loadMeshTriggersOBJ(vehId)
    local triggers = triggersByVeh[vehId]
    if not triggers then return end
    
    local vData = core_vehicle_manager.getVehicleData(vehId)
    if not vData then return end
    
    local vehDir = vData.dir or vData.vehicleDirectory
    if not vehDir then return end
    
    local beObj = be:getObjectByID(vehId)
    for _, trg in ipairs(triggers) do
        local candidates = (trg.targetProps and #trg.targetProps > 0) and trg.targetProps or (trg.targetProp and trg.targetProp ~= "" and { trg.targetProp } or nil)
        if candidates and #candidates > 0 then
            local pid, pObj, prop = findAvailableProp(beObj, vData, candidates)
            if pid ~= nil and prop then
                trg._targetPropId = pid
                trg._activeTargetProp = prop.mesh or prop.originalMesh or prop.name
                if not trg.meshName or trg.meshName == "" then
                    trg.meshName = prop.mesh or prop.originalMesh
                end
            else
                log('D', logTag, "Trigger " .. tostring(trg.id) .. " targetProps not found in vehicle props!")
            end
        end

        if trg.triggerType == "mesh" and trg.meshName then
            local meshNameStr = type(trg.meshName) == "table" and trg.meshName[1] or trg.meshName
            if type(meshNameStr) == "string" then
                local meshPath = meshNameStr
                if not meshPath:lower():match("%.obj$") then
                    meshPath = meshPath .. ".obj"
                end
                
                if not meshPath:match("^/?vehicles/") then
                    if string.sub(meshPath, 1, 1) == "/" then
                        meshPath = string.sub(meshPath, 2)
                    end
                    meshPath = vehDir .. meshPath
                end
                if string.sub(meshPath, 1, 1) == "/" then
                    meshPath = string.sub(meshPath, 2)
                end
                trg._debugMeshPath = meshPath
                local verts = loadOBJ(meshPath)
                trg.meshVerts = verts
                
                if verts and #verts > 0 then
                    local minB = vec3(math.huge, math.huge, math.huge)
                    local maxB = vec3(-math.huge, -math.huge, -math.huge)
                    for _, tri in ipairs(verts) do
                        for i=1, 3 do
                            local v = tri[i]
                            minB.x = math.min(minB.x, v.x)
                            minB.y = math.min(minB.y, v.y)
                            minB.z = math.min(minB.z, v.z)
                            maxB.x = math.max(maxB.x, v.x)
                            maxB.y = math.max(maxB.y, v.y)
                            maxB.z = math.max(maxB.z, v.z)
                        end
                    end
                    local extents = maxB - minB
                    local objCenter = (maxB + minB) * 0.5
                    
                    local meshScale = trg.halfSize * 2
                    trg._meshScale = meshScale
                    trg.halfSize = vec3(extents.x * meshScale.x, extents.y * meshScale.y, extents.z * meshScale.z) * 0.5
                    trg._meshBoxCenterOffset = vec3(objCenter.x * meshScale.x, objCenter.y * meshScale.y, objCenter.z * meshScale.z)
                end
            else
                log('E', logTag, "Trigger " .. tostring(trg.id) .. " has an invalid meshName. Did you forget to add the mesh string at column 7 in your JBeam?")
            end
        end
    end
end

local function loadTriggersFromJBeam(vehId)
    local vData = core_vehicle_manager.getVehicleData(vehId)
    if not vData or not vData.vdata then return end
    triggersByVeh[vehId] = {}
    if vData.vdata.propTriggers then parseTriggersTable(vehId, vData.vdata.propTriggers, false) end
    if vData.vdata.triggers2    then parseTriggersTable(vehId, vData.vdata.triggers2,    true)  end
    buildPropTriggerEventLinks(vehId)
    loadMeshTriggersOBJ(vehId)
end



local function onVehicleSpawned(vehId)
    loadTriggersFromJBeam(vehId)
end

local function onVehicleResetted(vehId)
    if vehId then
        loadTriggersFromJBeam(vehId)
    end
end

local function onVehicleDestroyed(vehId)
    triggersByVeh[vehId] = nil
    propTriggerLinksDict[vehId] = nil
end

local function onVehicleSwitched(oldVeh, newVeh, player)
    if newVeh then loadTriggersFromJBeam(newVeh) end
end

local function onCursorVisibilityChanged(visible)
    cursorVisible = visible
end

local function onPreRender(dt)
    if not cursorVisible then
        if checkIs039OrHigher() then clearPropTriggerCrosshairTargetStream() end
        return
    end
    local ray = getCameraMouseRay()
    if not ray then
        if checkIs039OrHigher() then clearPropTriggerCrosshairTargetStream() end
        return
    end
    
    local propTriggers_globalActionsToDraw = nil
    local propTriggers_targetToPublish = nil
    local im = ui_imgui
    if im.GetIO().WantCaptureMouse then
        if checkIs039OrHigher() then clearPropTriggerCrosshairTargetStream() end
        return
    end

    if not initializedVehicles then
        initializedVehicles = true
        for i = 0, be:getObjectCount()-1 do
            local v = be:getObject(i)
            if v then loadTriggersFromJBeam(v:getID()) end
        end
    end

    for vehId, triggers in pairs(triggersByVeh) do
        local ok, err = pcall(function()
            local beObj = be:getObjectByID(vehId)
            local stObj = scenetree.findObject(vehId)
            if not beObj or not stObj then return end

            local rawRefPhys = beObj:getNodePosition(beObj:getRefNodeId())
            if not rawRefPhys then return end
            local pRefNodePhys = vec3(rawRefPhys)

            local currentRefPos = stObj:getPosition()
            if not currentRefPos then return end

            local vData = core_vehicle_manager.getVehicleData(vehId)
            


            local hoveredId   = nil
            local closestDist = math.huge

            for _, trg in ipairs(triggers) do
                local center, ax, ay, az



                local pid = trg._targetPropId
                local propObj = pid and beObj:getProp(pid) or nil

                -- Dynamic fallback: if propObj is missing, re-resolve across candidate targetProps
                local candidates = (trg.targetProps and #trg.targetProps > 0) and trg.targetProps or (trg.targetProp and trg.targetProp ~= "" and { trg.targetProp } or nil)
                if not propObj and candidates and #candidates > 0 then
                    local newPid, newPropObj, prop = findAvailableProp(beObj, vData, candidates)
                    if newPid and prop then
                        trg._targetPropId = newPid
                        trg._activeTargetProp = prop.mesh or prop.originalMesh or prop.name
                        if not trg.meshName or trg.meshName == "" then
                            trg.meshName = prop.mesh or prop.originalMesh
                        end
                        pid = newPid
                        propObj = newPropObj or beObj:getProp(newPid)
                    end
                end

                if propObj then
                    local worldMat = propObj:getLiveTransformWorld()
                    
                    local tempMat = MatrixF(true)
                    tempMat:setColumn(0, worldMat:getColumn(0))
                    tempMat:setColumn(1, worldMat:getColumn(1))
                    tempMat:setColumn(2, worldMat:getColumn(2))
                    tempMat:mul(trg.baseRot)
                    
                    ax = tempMat:getColumn(0)
                    ay = tempMat:getColumn(1)
                    az = tempMat:getColumn(2)
                    
                    local baseCenter = worldMat:getColumn(3) + vec3(currentRefPos)
                    center = baseCenter + ax*trg.baseTrans.x + ay*trg.baseTrans.y + az*trg.baseTrans.z
                elseif (trg.targetProps and #trg.targetProps > 0) or (trg.targetProp and trg.targetProp ~= "") then
                    goto skip_trg
                else
                    local rawPRef = beObj:getNodePosition(trg.idRef)
                    if not rawPRef then goto skip_trg end
                    local pRef = vec3(rawPRef)

                    local refMat = stObj:getRefNodeMatrix()
                    if not refMat then goto skip_trg end

                    local offsetFromRef = pRef - pRefNodePhys
                    local pRefWorld = vec3(refMat:getPosition()) + offsetFromRef

                    local mat = MatrixF(true)

                    if trg.idX == 0 or trg.idY == 0 then
                        mat:setPosition(pRefWorld)
                    else
                        local rawPX = beObj:getNodePosition(trg.idX)
                        local rawPY = beObj:getNodePosition(trg.idY)
                        if not rawPX or not rawPY then goto skip_trg end

                        local pX = vec3(rawPX)
                        local pY = vec3(rawPY)
                        trg._pX = { x=pX.x, y=pX.y, z=pX.z }
                        trg._pY = { x=pY.x, y=pY.y, z=pY.z }

                        local dirX = (pX - pRef):normalized()
                        local dirY = (pY - pRef):normalized()

                        if trg.triggerType == "mesh" then
                            local refRotX = refMat:getColumn(0)
                            local refRotY = refMat:getColumn(1)
                            local refRotZ = refMat:getColumn(2)

                            if not trg._meshInitialLocalDirX then
                                trg._meshInitialLocalDirX = vec3(dirX:dot(refRotX), dirX:dot(refRotY), dirX:dot(refRotZ))
                                trg._meshInitialLocalDirY = vec3(dirY:dot(refRotX), dirY:dot(refRotY), dirY:dot(refRotZ))
                            end

                            dirX = (refRotX * trg._meshInitialLocalDirX.x + refRotY * trg._meshInitialLocalDirX.y + refRotZ * trg._meshInitialLocalDirX.z):normalized()
                            dirY = (refRotX * trg._meshInitialLocalDirY.x + refRotY * trg._meshInitialLocalDirY.y + refRotZ * trg._meshInitialLocalDirY.z):normalized()
                        end

                        local dirZ = dirX:cross(dirY):normalized()
                        dirY = dirZ:cross(dirX):normalized()

                        if dirX:squaredLength() < 0.0001 then dirX = vec3(1, 0, 0) end
                        if dirY:squaredLength() < 0.0001 then dirY = vec3(0, 1, 0) end
                        if dirZ:squaredLength() < 0.0001 then dirZ = vec3(0, 0, 1) end

                        mat:setColumn(0, dirX)
                        mat:setColumn(1, dirZ)
                        mat:setColumn(2, dirY)
                        mat:setPosition(pRefWorld)
                    end

                    mat:mul(trg.baseRot)

                    local worldTrans = mat:getColumn(0) * trg.baseTrans.x
                                     + mat:getColumn(1) * trg.baseTrans.y
                                     + mat:getColumn(2) * trg.baseTrans.z
                    mat:setPosition(mat:getPosition() + worldTrans)

                    center = mat:getPosition()
                    ax = mat:getColumn(0)
                    ay = mat:getColumn(1)
                    az = mat:getColumn(2)
                end
                local hx, hy, hz = trg.halfSize.x, trg.halfSize.y, trg.halfSize.z

                if trg._prevDrawCenter then
                    local hitCenter = trg._prevDrawCenter
                    if trg._meshBoxCenterOffset then
                        hitCenter = hitCenter + trg._prevAx * trg._meshBoxCenterOffset.x
                                              + trg._prevAy * trg._meshBoxCenterOffset.y
                                              + trg._prevAz * trg._meshBoxCenterOffset.z
                    end
                    local hitDist = intersectsRay_OBB(ray.pos, ray.dir, hitCenter, trg._prevAx*hx, trg._prevAy*hy, trg._prevAz*hz)
                    if hitDist < 5 and hitDist < closestDist then
                        closestDist = hitDist
                        hoveredId = trg.id
                    end
                end

                trg._prevAx = ax; trg._prevAy = ay; trg._prevAz = az
                trg._center = center
                trg._ax = ax; trg._ay = ay; trg._az = az



                ::skip_trg::
            end


            for _, trg in ipairs(triggers) do
                if not trg._center then goto skip_draw end

                local drawCenter = trg._center
                local oldDrawCenter = trg._prevDrawCenter or drawCenter
                trg._prevDrawCenter = drawCenter
                
                local actualFadeCenter = oldDrawCenter
                if trg._meshBoxCenterOffset and trg._prevAx then
                    actualFadeCenter = actualFadeCenter + trg._prevAx * trg._meshBoxCenterOffset.x
                                                        + trg._prevAy * trg._meshBoxCenterOffset.y
                                                        + trg._prevAz * trg._meshBoxCenterOffset.z
                end

                local hx, hy, hz = trg.halfSize.x, trg.halfSize.y, trg.halfSize.z
                local maxH = math.max(hx, hy, hz)
                local isHovered = (hoveredId == trg.id)
                local rDist = rayPointDist(ray.pos, ray.dir, actualFadeCenter)
                
                local coreDist = math.max(0.03, maxH)
                local fadeDist = math.max(0.30, maxH + 0.27)
                local proximity = 1 - math.max(0, math.min(1, (rDist - coreDist) / (fadeDist - coreDist)))
                
                local tr, tg, tb = 0.35, 0.51, 0.76
                local targetAlpha = 0.28 * proximity

                local mouseWheel = im.GetIO().MouseWheel or 0
                local isMouseDown = im.IsMouseDown(0) or im.IsMouseDown(1) or im.IsMouseDown(2) or mouseWheel ~= 0
                if isHovered and isMouseDown then
                    tr, tg, tb, targetAlpha = 0.10, 1.00, 0.40, 1.00
                elseif isHovered then
                    tr, tg, tb, targetAlpha = 0.10, 0.75, 0.30, 0.28
                end

                trg.alpha = trg.alpha + (targetAlpha - trg.alpha) * math.min(1, dt * 10)

                if trg.triggerType == "sphere" then
                    if trg.alpha < 0.004 then goto skip_draw end
                    local cF = ColorF(tr, tg, tb, trg.alpha)
                    debugDrawer:drawSphere(drawCenter, hx, cF)
                elseif trg.triggerType == "mesh" then
                    if trg.meshVerts then
                        if trg.alpha < 0.004 then goto skip_draw end
                        local col = color(math.floor(tr*255), math.floor(tg*255), math.floor(tb*255), math.floor(trg.alpha*255))
                        local sx = trg._meshScale and trg._meshScale.x or (hx * 2)
                        local sy = trg._meshScale and trg._meshScale.y or (hy * 2)
                        local sz = trg._meshScale and trg._meshScale.z or (hz * 2)
                        local ax, ay, az = trg._ax, trg._ay, trg._az
                        for i=1, #trg.meshVerts do
                            local tri = trg.meshVerts[i]
                            local tv1, tv2, tv3 = tri[1], tri[2], tri[3]
                            
                            local v1 = drawCenter + ax*(tv1.x*sx) + ay*(tv1.y*sy) + az*(tv1.z*sz)
                            local v2 = drawCenter + ax*(tv2.x*sx) + ay*(tv2.y*sy) + az*(tv2.z*sz)
                            local v3 = drawCenter + ax*(tv3.x*sx) + ay*(tv3.y*sy) + az*(tv3.z*sz)
                            
                            debugDrawer:drawTriSolid(v1, v2, v3, col)
                        end
                    end
                else
                    if trg.alpha < 0.004 then goto skip_draw end
                    drawOBBSolid(drawCenter, trg._ax*hx, trg._ay*hy, trg._az*hz, tr, tg, tb, trg.alpha)
                end

                ::skip_draw::
            end

            -- ── Show title + key binding legend / 0.39 bubble on hover ──
            local actionsListToDraw = nil
            local hoveredTrgObj = nil
            if hoveredId then
                for _, trg in ipairs(triggers) do
                    if trg.id == hoveredId then
                        hoveredTrgObj = trg
                        break
                    end
                end
            end

            if hoveredId and hoveredTrgObj then
                local vehLinks = propTriggerLinksDict[vehId]
                local vData = extensions.core_vehicle_manager.getVehicleData(vehId)
                local actionTitles = {}
                local actionIcons = {}
                local actionsList = {}

                local actionKeys = { "action0", "action1", "action2", "wheelUp", "wheelDown" }
                for _, actionKey in ipairs(actionKeys) do
                    local links = vehLinks and vehLinks[hoveredId] and vehLinks[hoveredId][actionKey]
                    local lnk = type(links) == "table" and links[1] or nil
                    if lnk and lnk.inputAction then
                        local actionName = lnk.inputAction
                        local action = nil
                        if vData and vData.vdata and vData.vdata.inputActions then
                            action = vData.vdata.inputActions[actionName]
                        end
                        if not action and core_input_actions and core_input_actions.getActiveActions then
                            local activeActions = core_input_actions.getActiveActions()
                            if activeActions then action = activeActions[actionName] end
                        end

                        local rawTitle = action and action.title or actionName
                        local title = formatActionTitle(rawTitle)
                        actionTitles[actionKey] = title

                        local actionIcon = resolveActionIcon(action, actionName, hoveredTrgObj, actionKey)
                        actionIcons[actionKey] = actionIcon

                        local actionStr = actionName
                        if action and action.vehicle and lnk.namespace == 'vehicle' then
                            actionStr = action.vehicle .. '__' .. actionStr
                        end

                        local desiredInverted = lnk.isInverted == true
                        local bindingDev, actionBinding = findBindingForAction(actionStr, desiredInverted)
                        if not actionBinding then
                            bindingDev, actionBinding = findKeyboardBindingForAction(actionStr, desiredInverted)
                        end

                        local defaultMouseControl = "button0"
                        if actionKey == "action1" then
                            defaultMouseControl = "button1"
                        elseif actionKey == "action2" then
                            defaultMouseControl = "button2"
                        elseif actionKey == "wheelUp" then
                            defaultMouseControl = "wheelup"
                        elseif actionKey == "wheelDown" then
                            defaultMouseControl = "wheeldown"
                        end

                        local bindingsData = nil
                        if actionBinding and bindingDev then
                            bindingsData = {{ device = bindingDev, control = actionBinding.control }}
                        else
                            bindingsData = {{ device = "mouse0", control = defaultMouseControl }}
                        end

                        table.insert(actionsList, {
                            action = actionStr,
                            label = title,
                            icon = actionIcon,
                            bindings = bindingsData
                        })
                    end
                end

                if not next(actionTitles) then
                    local rawFallback = hoveredTrgObj.action and hoveredTrgObj.action ~= "" and hoveredTrgObj.action or hoveredId
                    local fallbackTitle = formatActionTitle(rawFallback)
                    local fallbackIcon = resolveActionIcon(nil, hoveredTrgObj.action, hoveredTrgObj, "action0")
                    actionTitles["action0"] = fallbackTitle
                    actionIcons["action0"] = fallbackIcon
                    table.insert(actionsList, {
                        action = hoveredId,
                        label = fallbackTitle,
                        icon = fallbackIcon,
                        bindings = {{ device = "mouse0", control = "button0" }}
                    })
                end

                if #actionsList > 0 then
                    actionsListToDraw = actionsList
                end

                -- In >=0.39, prepare the 3D/screen-space bubble target payload
                if checkIs039OrHigher() and hoveredTrgObj._center then
                    local drawCenter = hoveredTrgObj._center
                    local screenPos = worldPosToScreenPercent01(drawCenter)
                    if screenPos then
                        local hx = hoveredTrgObj.halfSize and hoveredTrgObj.halfSize.x or 0.1
                        local hy = hoveredTrgObj.halfSize and hoveredTrgObj.halfSize.y or 0.1
                        local hz = hoveredTrgObj.halfSize and hoveredTrgObj.halfSize.z or 0.1
                        local ax = hoveredTrgObj._ax or vec3(1,0,0)
                        local ay = hoveredTrgObj._ay or vec3(0,1,0)
                        local az = hoveredTrgObj._az or vec3(0,0,1)
                        local labelPlacement = computeLabelPlacementForPropTrigger(drawCenter, ax, ay, az, hx, hy, hz, screenPos)
                        propTriggers_targetToPublish = {
                            x = screenPos.x,
                            y = screenPos.y,
                            actionTitles = actionTitles,
                            actionIcons = actionIcons,
                            triggerIcon = hoveredTrgObj.icon,
                            color = {r=0.235, g=0.396, b=1.0, a=0.75},
                            labelPlacement = labelPlacement,
                            name = hoveredId
                        }
                    end
                end
            end

            if actionsListToDraw then
                propTriggers_globalActionsToDraw = actionsListToDraw
            end

            -- ── Click and Scroll handling ──
            if hoveredId and cursorVisible then
                -- Left Mouse Button (action0)
                if im.IsMouseClicked(0) then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'action0', 1)
                            firePropTriggerEvent(vehId, trg.id, 'leftClick', 1)
                            firePropTriggerEvent(vehId, trg.id, 'mouseLeft', 1)
                            break
                        end
                    end
                end

                if im.IsMouseReleased(0) then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            -- Legacy: still execute hardcoded action string if present
                            if trg.action and trg.action ~= "" then
                                beObj:queueLuaCommand(string.format('%s', trg.action))
                            end
                            firePropTriggerEvent(vehId, trg.id, 'action0', 0)
                            firePropTriggerEvent(vehId, trg.id, 'leftClick', 0)
                            firePropTriggerEvent(vehId, trg.id, 'mouseLeft', 0)
                            break
                        end
                    end
                end

                -- Right Mouse Button (action1)
                if im.IsMouseClicked(1) then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'action1', 1)
                            firePropTriggerEvent(vehId, trg.id, 'rightClick', 1)
                            firePropTriggerEvent(vehId, trg.id, 'mouseRight', 1)
                            break
                        end
                    end
                end

                if im.IsMouseReleased(1) then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'action1', 0)
                            firePropTriggerEvent(vehId, trg.id, 'rightClick', 0)
                            firePropTriggerEvent(vehId, trg.id, 'mouseRight', 0)
                            break
                        end
                    end
                end

                -- Middle Mouse Button (action2)
                if im.IsMouseClicked(2) then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'action2', 1)
                            firePropTriggerEvent(vehId, trg.id, 'middleClick', 1)
                            firePropTriggerEvent(vehId, trg.id, 'mouseMiddle', 1)
                            break
                        end
                    end
                end

                if im.IsMouseReleased(2) then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'action2', 0)
                            firePropTriggerEvent(vehId, trg.id, 'middleClick', 0)
                            firePropTriggerEvent(vehId, trg.id, 'mouseMiddle', 0)
                            break
                        end
                    end
                end

                -- Mouse Wheel Up / Down
                local mouseWheel = im.GetIO().MouseWheel or 0
                if mouseWheel > 0 then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'wheelUp', 1)
                            firePropTriggerEvent(vehId, trg.id, 'wheel_up', 1)
                            firePropTriggerEvent(vehId, trg.id, 'mouseWheelUp', 1)
                            firePropTriggerEvent(vehId, trg.id, 'wheel', 1)
                            firePropTriggerEvent(vehId, trg.id, 'wheelUp', 0)
                            firePropTriggerEvent(vehId, trg.id, 'wheel_up', 0)
                            firePropTriggerEvent(vehId, trg.id, 'mouseWheelUp', 0)
                            firePropTriggerEvent(vehId, trg.id, 'wheel', 0)
                            break
                        end
                    end
                elseif mouseWheel < 0 then
                    for _, trg in ipairs(triggers) do
                        if trg.id == hoveredId then
                            firePropTriggerEvent(vehId, trg.id, 'wheelDown', 1)
                            firePropTriggerEvent(vehId, trg.id, 'wheel_down', 1)
                            firePropTriggerEvent(vehId, trg.id, 'mouseWheelDown', 1)
                            firePropTriggerEvent(vehId, trg.id, 'wheel', -1)
                            firePropTriggerEvent(vehId, trg.id, 'wheelDown', 0)
                            firePropTriggerEvent(vehId, trg.id, 'wheel_down', 0)
                            firePropTriggerEvent(vehId, trg.id, 'mouseWheelDown', 0)
                            firePropTriggerEvent(vehId, trg.id, 'wheel', 0)
                            break
                        end
                    end
                end
            end
        end)

        if not ok then
            log('E', logTag, 'Error in onPreRender for vehicle ' .. tostring(vehId) .. ': ' .. tostring(err))
        end
    end

    -- In >=0.39, update or clear the trigger details bubble
    if checkIs039OrHigher() then
        if propTriggers_targetToPublish then
            setPropTriggerCrosshairTargetStream(
                propTriggers_targetToPublish.x,
                propTriggers_targetToPublish.y,
                propTriggers_targetToPublish.actionTitles,
                propTriggers_targetToPublish.color,
                propTriggers_targetToPublish.labelPlacement,
                propTriggers_targetToPublish.name,
                propTriggers_targetToPublish.actionIcons,
                propTriggers_targetToPublish.triggerIcon
            )
        else
            clearPropTriggerCrosshairTargetStream()
        end
    end

    if extensions.ui_bindingsLegend then
        if propTriggers_globalActionsToDraw then
            extensions.ui_bindingsLegend.addActions('propTriggers', propTriggers_globalActionsToDraw, { priority = 11, hideConstant = true })
        else
            extensions.ui_bindingsLegend.addActions('propTriggers', {})
        end
    end
end

local function onExtensionLoaded()
end

local function onExtensionUnloaded()
    clearPropTriggerCrosshairTargetStream()
    if extensions.ui_bindingsLegend then
        extensions.ui_bindingsLegend.addActions('propTriggers', {})
    end
end

M.onExtensionLoaded         = onExtensionLoaded
M.onExtensionUnloaded       = onExtensionUnloaded
M.onPreRender               = onPreRender
M.onVehicleSpawned          = onVehicleSpawned
M.onVehicleResetted         = onVehicleResetted
M.onVehicleDestroyed        = onVehicleDestroyed
M.onVehicleSwitched         = onVehicleSwitched
M.onCursorVisibilityChanged = onCursorVisibilityChanged
return M
