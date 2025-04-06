-- Dock IntelliHide Spoon for macOS using Hammerspoon
-- Author: Amr Osman

local Spoon = {}

-- === Configuration ===
local dockPosition = nil -- Will be detected dynamically
local windowFilter = hs.window.filter.new()
local lastDockState = nil
local spaceWatcher = nil
local dockRect = nil

-- === Detect Dock Position Dynamically ===
local function detectDockPosition()
    local pos = hs.execute("defaults read com.apple.dock orientation")
    return pos and pos:gsub("%s+", "") or "bottom"  -- default to bottom if not found
end

dockPosition = detectDockPosition()

-- === Get Dock Height ===
local function getDockHeight()
    local dockSizeStr = hs.execute("defaults read com.apple.dock tilesize")
    local dockSize = tonumber(dockSizeStr and dockSizeStr:gsub("%s+", "") or "48")
    print("Detected Dock size: " .. dockSize)
    return dockSize
end

-- === Calculate Dock Rectangle Dynamically ===
local function getDockRect()
    local dockApp = hs.application("Dock")
    if not dockApp then
        print("Dock application not found.")
        return hs.geometry.rect(0, 0, 0, 0)
    end

    local axApp = hs.axuielement.applicationElement(dockApp)
    local children = axApp.AXChildren
    if not children then
        print("No AX children found for Dock.")
        return hs.geometry.rect(0, 0, 0, 0)
    end

    for _, child in ipairs(children) do
        local frame = child.AXFrame
        if frame and frame.w > 0 and frame.h > 0 then
            return hs.geometry.rect(frame.x, frame.y, frame.w, frame.h)
        end
    end

    -- fallback approximation if Dock frame not found
    local screen = hs.screen.mainScreen():frame()
    local height = getDockHeight()
    local orientation = detectDockPosition()

    if orientation == "bottom" then
        return hs.geometry.rect(0, screen.h - height, screen.w, height)
    elseif orientation == "left" then
        return hs.geometry.rect(0, 0, height, screen.h)
    elseif orientation == "right" then
        return hs.geometry.rect(screen.w - height, 0, height, screen.h)
    else
        return hs.geometry.rect(0, 0, 0, 0)
    end
end

-- === Detect Dock Autohide State ===
local function isDockHidden()
    local dockState = hs.execute("defaults read com.apple.dock autohide")
    print("Detected Dock autohide state: " .. dockState)
    return dockState and dockState:gsub("%s+", "") == "1" or false
end

-- === Set Dock Visibility ===
local function hideDock(isHidden)
    if isHidden == isDockHidden() then return end
    local hidden = isHidden and "true" or "false"
    hs.execute("defaults write com.apple.dock autohide -bool " .. hidden)
    hs.eventtap.event.newKeyEvent({ "cmd", "option" }, "D", true):post()
    hs.eventtap.event.newKeyEvent({ "cmd", "option" }, "D", false):post()
    print("Dock visibility set to: " .. (isHidden and "hidden" or "visible"))
end

-- === Check Window States ===
local function isWindowMaximized(window)
    local winFrame = window:frame()
    local screen = window:screen()
    local frame = screen:frame()
    local fullFrame = screen:fullFrame()
    local tolerance = 4

    local isMaxFrame = math.abs(winFrame.x - fullFrame.x) <= tolerance
        and math.abs(winFrame.y - fullFrame.y) <= tolerance
        and math.abs(winFrame.w - fullFrame.w) <= tolerance
        and math.abs(winFrame.h - fullFrame.h) <= tolerance

    local isFrameFrame = math.abs(winFrame.x - frame.x) <= tolerance
        and math.abs(winFrame.y - frame.y) <= tolerance
        and math.abs(winFrame.w - frame.w) <= tolerance
        and math.abs(winFrame.h - frame.h) <= tolerance

    return isMaxFrame or isFrameFrame
end

-- === Improved Overlap Check for Dock ===
local function isWindowOverlappingDock(window)
    local winFrame = window:frame()

    -- Check if window is overlapping the dock based on its position and size
    local intersect = winFrame:intersect(dockRect)

    -- If the intersection area is greater than zero, there's an overlap
    return intersect.area > 0
end

local function ifTopWindowIsOverlappingOrMaximized()
    local window = hs.window.frontmostWindow()
    if window then
        return isWindowMaximized(window) or isWindowOverlappingDock(window)
    else
        print("No frontmost window found.")
        return false
    end
end

local function areAnyWindowsVisible()
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isVisible() and not win:isMinimized() and win:frame().w > 0 and win:frame().h > 0 then
            return true
        end
    end
    return false
end

-- === Update Dock Visibility Based on State ===
local function updateDock()
    local hasVisibleWindows = areAnyWindowsVisible()
    local topWindowIsCoveringDock = ifTopWindowIsOverlappingOrMaximized()
    
    if not hasVisibleWindows then
        -- No windows: always show the Dock
        hideDock(false)
        print("No visible windows — showing Dock.")   
    elseif topWindowIsCoveringDock then
        -- Hide the Dock if something overlaps or is fullscreen
        hideDock(true)
        print("Top window overlaps or is maximized — hiding Dock.")
    else
        -- Window exists but not overlapping Dock
        hideDock(false)
        print("Visible windows but Dock not overlapped — showing Dock.")
    end
end

-- === Window Event Tracking ===
local function trackWindowState(window)
    local frame = window:frame()
    if frame.w == hs.screen.mainScreen():frame().w and frame.h == hs.screen.mainScreen():frame().h then
        print("Window is maximized.")
    elseif window:isMinimized() then
        print("Window is minimized.")
    else
        print("Window is resized.")
    end
end

local function subscribeToWindowEvents()
    windowFilter:subscribe({
        "windowCreated",
        "windowDestroyed",
        "windowMoved",
        "windowFocused",
        "windowMinimized"
    }, function(window, appName, event)
        print("Detected window event: " .. event)
        trackWindowState(window)
        hs.timer.doAfter(0.1, updateDock)
    end)
end

-- === Workspace Change Tracking ===
local function trackWorkspaceChanges()
    spaceWatcher = hs.spaces.watcher.new(function()
        print("Workspace changed.")
        hs.timer.doAfter(0.1, updateDock)
    end)
    spaceWatcher:start()
end

-- === Start/Stop IntelliHide ===
function Spoon:start()
    dockRect = getDockRect()

    local success, err = pcall(function()
        subscribeToWindowEvents()
        trackWorkspaceChanges()
    end)
    if not success then
        print("Error subscribing to window events: " .. err)
    else
        print("Subscribed to window events.")
    end

    updateDock()
    print("Dock IntelliHide started")
end

function Spoon:stop()
    if windowFilter then
        windowFilter:unsubscribeAll()
        windowFilter = nil
    end
    if spaceWatcher then
        spaceWatcher:stop()
        spaceWatcher = nil
    end

    print("Dock IntelliHide stopped")
end

-- === Menubar Control ===
local menubar = hs.menubar.new()
menubar:setTitle("🚢")
menubar:setMenu({
    { title = "Start IntelliHide", fn = function() Spoon:start() end },
    { title = "Stop IntelliHide", fn = function() Spoon:stop() end },
    { title = "-" },
    { title = "Quit Hammerspoon", fn = function() hs.application.frontmostApplication():kill() end }
})

-- === Auto-start IntelliHide ===
function Spoon:init()
    self:start()
end

return Spoon
