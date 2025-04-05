-- Dock IntelliHide Spoon for macOS using Hammerspoon
-- Author: Amr Osman

local Spoon = {}

-- === Configuration ===
local dockHeight = 65 -- Adjust based on your Dock size
local dockPosition = "bottom" -- "bottom", "left", or "right"
local windowFilter = hs.window.filter.new() -- Initialize window filter here
local lastDockState = nil -- Track the last state of the Dock

-- === Calculate Dock Rectangle Based on Position ===
local function getDockRect()
    local screen = hs.screen.mainScreen()
    local frame = screen:frame()

    if dockPosition == "bottom" then
        return hs.geometry.rect(0, frame.h - dockHeight, frame.w, dockHeight)
    elseif dockPosition == "left" then
        return hs.geometry.rect(0, 0, dockHeight, frame.h)
    elseif dockPosition == "right" then
        return hs.geometry.rect(frame.w - dockHeight, 0, dockHeight, frame.h)
    end
end

local dockRect = getDockRect()

-- Function to check if the window is maximized
local function isWindowMaximized(window)
    local windowFrame = window:frame()
    local screenFrame = hs.screen.mainScreen():frame()

    return windowFrame.w == screenFrame.w and windowFrame.h == screenFrame.h and windowFrame.x == 0 and windowFrame.y == 0
end

-- Function to check if the frontmost window is overlapping the Dock area
local function isWindowOverlappingDock(window)
    local windowFrame = window:frame()
    return windowFrame:intersect(dockRect).area > 0
end

-- Function to check if the frontmost window is maximized or overlapping with the Dock
local function ifTopWindowIsOverlappingOrMaximized()
    local window = hs.window.frontmostWindow()
    if window then
        return isWindowMaximized(window) or isWindowOverlappingDock(window)
    else
        print("No frontmost window found.")
        return false
    end
end

-- === Detect Current Dock Visibility ===
local function isDockHidden()
    local dockState = hs.execute("defaults read com.apple.dock autohide")
    return (dockState:match("1") ~= nil)
end

-- === Set Dock Visibility ===
local function hideDock(isHidden)
    if isHidden == lastDockState then return end  -- Avoid unnecessary state changes
    local hidden = isHidden and "true" or "false"
    hs.execute("defaults write com.apple.dock autohide -bool " .. hidden)
    hs.eventtap.event.newKeyEvent({ "cmd", "option" }, "D", true):post()
    hs.eventtap.event.newKeyEvent({ "cmd", "option" }, "D", false):post()
    lastDockState = isHidden
    print("Dock visibility set to: " .. (isHidden and "hidden" or "visible"))
end

-- === Check if Any Windows are Visible ===
local function areAnyWindowsVisible()
    for _, win in ipairs(hs.window.allWindows()) do
        if win:isVisible() and not win:isMinimized() and win:frame().w > 0 and win:frame().h > 0 then
            return true
        end
    end
    return false
end

-- === Trigger Update Based on Window Overlap or Visibility ===
local function updateDock()
    -- If no windows are visible, show the Dock
    if not areAnyWindowsVisible() then
        if isDockHidden() then
            hideDock(false) -- Show the Dock if no windows are visible
        end
    elseif ifTopWindowIsOverlappingOrMaximized() and not isDockHidden() then
        hideDock(true) -- Hide the Dock if window is overlapping or maximized
    elseif not ifTopWindowIsOverlappingOrMaximized() and isDockHidden() then
        hideDock(false) -- Show the Dock if window is not overlapping or maximized
    end
end

-- === Track Window State (Moved, Created, Destroyed) ===
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

-- === Subscribe to Window Events ===
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
        hs.timer.doAfter(0.1, updateDock)  -- Delay for proper event processing
    end)
end

-- === Track Workspace Changes ===
local function trackWorkspaceChanges()
    hs.spaces.watcher.new(function()
        print("Workspace changed.")
        hs.timer.doAfter(0.1, updateDock)  -- Ensure that we update the Dock after workspace change
    end):start()
end

-- === Start IntelliHide Behavior ===
function Spoon:start()
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

-- === Stop IntelliHide ===
function Spoon:stop()
    if windowFilter then
        windowFilter:unsubscribeAll()
        windowFilter = nil
    end
    print("Dock IntelliHide stopped")
end

-- === Optional: Menubar Control ===
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

-- Return the Spoon object
return Spoon
