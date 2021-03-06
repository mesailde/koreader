local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = require("ui/screen")
local Device = require("ui/device")
local Geom = require("ui/geometry")
local Input = require("ui/input")
local Event = require("ui/event")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local DEBUG = require("dbg")
local _ = require("gettext")
local ReaderPanning = require("apps/reader/modules/readerpanning")

local ReaderRolling = InputContainer:new{
    old_doc_height = nil,
    old_page = nil,
    current_pos = 0,
    -- only used for page view mode
    current_page= nil,
    doc_height = nil,
    panning_steps = ReaderPanning.panning_steps,
    show_overlap_enable = true,
    overlap = 20,
}

function ReaderRolling:init()
    if Device:hasKeyboard() or Device:hasKeys() then
        self.key_events = {
            GotoNextView = {
                { Input.group.PgFwd },
                doc = "go to next view",
                event = "GotoViewRel", args = 1
            },
            GotoPrevView = {
                { Input.group.PgBack },
                doc = "go to previous view",
                event = "GotoViewRel", args = -1
            },
            MoveUp = {
                { "Up" },
                doc = "move view up",
                event = "Panning", args = {0, -1}
            },
            MoveDown = {
                { "Down" },
                doc = "move view down",
                event = "Panning", args = {0,  1}
            },
            GotoFirst = {
                {"1"}, doc = "go to start", event = "GotoPercent", args = 0},
            Goto11 = {
                {"2"}, doc = "go to 11%", event = "GotoPercent", args = 11},
            Goto22 = {
                {"3"}, doc = "go to 22%", event = "GotoPercent", args = 22},
            Goto33 = {
                {"4"}, doc = "go to 33%", event = "GotoPercent", args = 33},
            Goto44 = {
                {"5"}, doc = "go to 44%", event = "GotoPercent", args = 44},
            Goto55 = {
                {"6"}, doc = "go to 55%", event = "GotoPercent", args = 55},
            Goto66 = {
                {"7"}, doc = "go to 66%", event = "GotoPercent", args = 66},
            Goto77 = {
                {"8"}, doc = "go to 77%", event = "GotoPercent", args = 77},
            Goto88 = {
                {"9"}, doc = "go to 88%", event = "GotoPercent", args = 88},
            GotoLast = {
                {"0"}, doc = "go to end", event = "GotoPercent", args = 100},
        }
    end

    table.insert(self.ui.postInitCallback, function()
        self.doc_height = self.ui.document.info.doc_height
        self.old_doc_height = self.doc_height
        self.old_page = self.ui.document.info.number_of_pages
    end)
end

-- This method will  be called in onSetDimensions handler
function ReaderRolling:initGesListener()
    self.ges_events = {
        TapForward = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Screen:getWidth()*DTAP_ZONE_FORWARD.x,
                    y = Screen:getHeight()*DTAP_ZONE_FORWARD.y,
                    w = Screen:getWidth()*DTAP_ZONE_FORWARD.w,
                    h = Screen:getHeight()*DTAP_ZONE_FORWARD.h,
                }
            }
        },
        TapBackward = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = Screen:getWidth()*DTAP_ZONE_BACKWARD.x,
                    y = Screen:getHeight()*DTAP_ZONE_BACKWARD.y,
                    w = Screen:getWidth()*DTAP_ZONE_BACKWARD.w,
                    h = Screen:getHeight()*DTAP_ZONE_BACKWARD.h,
                }
            }
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                }
            }
        },
        Pan = {
            GestureRange:new{
                ges = "pan",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
                rate = 4.0,
            }
        },
    }
end

function ReaderRolling:onReadSettings(config)
    local soe = config:readSetting("show_overlap_enable")
    if not soe then
        self.show_overlap_enable = soe
    end
    local last_xp = config:readSetting("last_xpointer")
    if last_xp then
        table.insert(self.ui.postInitCallback, function()
            self:gotoXPointer(last_xp)
            -- we have to do a real jump in self.ui.document._document to
            -- update status information in CREngine.
            self.ui.document:gotoXPointer(last_xp)
        end)
    end
    -- we read last_percent just for backward compatibility
    if not last_xp then
        local last_per = config:readSetting("last_percent")
        if last_per then
            table.insert(self.ui.postInitCallback, function()
                self:gotoPercent(last_per)
                -- we have to do a real pos change in self.ui.document._document
                -- to update status information in CREngine.
                self.ui.document:gotoPos(self.current_pos)
            end)
        end
    end
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getCurrentPage()))
    end
end

function ReaderRolling:onSaveSettings()
    -- remove last_percent config since its deprecated
    self.ui.doc_settings:saveSetting("last_percent", nil)
    self.ui.doc_settings:saveSetting("last_xpointer", self.ui.document:getXPointer())
    self.ui.doc_settings:saveSetting("percent_finished", self:getLastPercent())
end

function ReaderRolling:getLastPercent()
    if self.view.view_mode == "page" then
        return self.current_page / self.old_page
    else
        -- FIXME: the calculated percent is not accurate in "scroll" mode.
        return self.ui.document:getPosFromXPointer(
            self.ui.document:getXPointer()) / self.doc_height
    end
end

function ReaderRolling:onTapForward()
    self:onGotoViewRel(1)
    return true
end

function ReaderRolling:onTapBackward()
    self:onGotoViewRel(-1)
    return true
end

function ReaderRolling:onSwipe(arg, ges)
    if ges.direction == "west" or ges.direction == "north" then
        self:onGotoViewRel(1)
    elseif ges.direction == "east" or ges.direction == "south" then
        self:onGotoViewRel(-1)
    end
end

function ReaderRolling:onPan(arg, ges)
    if self.view.view_mode == "scroll" then
        if ges.direction == "north" then
            self:gotoPos(self.current_pos + ges.distance)
        elseif ges.direction == "south" then
            self:gotoPos(self.current_pos - ges.distance)
        end
    end
    return true
end

function ReaderRolling:onPosUpdate(new_pos)
    self.current_pos = new_pos
    self:updateBatteryState()
end

function ReaderRolling:onPageUpdate(new_page)
    self.current_page = new_page
    self:updateBatteryState()
end

function ReaderRolling:onResume()
    self:updateBatteryState()
end

function ReaderRolling:onNotCharging()
    self:updateBatteryState()
end

function ReaderRolling:onGotoPercent(percent)
    DEBUG("goto document offset in percent:", percent)
    self:gotoPercent(percent)
    return true
end

function ReaderRolling:onGotoViewRel(diff)
    DEBUG("goto relative screen:", diff, ", in mode: ", self.view.view_mode)
    if self.view.view_mode == "scroll" then
        local pan_diff = diff * self.ui.dimen.h
        if self.show_overlap_enable then
            if pan_diff > self.overlap then
                pan_diff = pan_diff - self.overlap
            elseif pan_diff < -self.overlap then
                pan_diff = pan_diff + self.overlap
            end
        end
        self:gotoPos(self.current_pos + pan_diff)
    elseif self.view.view_mode == "page" then
        self:gotoPage(self.current_page + diff)
    end
    return true
end

function ReaderRolling:onPanning(args, key)
    --@TODO disable panning in page view_mode?  22.12 2012 (houqp)
    local _, dy = unpack(args)
    DEBUG("key =", key)
    self:gotoPos(self.current_pos + dy * self.panning_steps.normal)
    return true
end

function ReaderRolling:onZoom()
    --@TODO re-read doc_height info after font or lineheight changes  05.06 2012 (houqp)
    self:updatePos()
end

--[[
    remember to signal this event when the document has been zoomed,
    font has been changed, or line height has been changed.
--]]
function ReaderRolling:onUpdatePos()
    UIManager:scheduleIn(0.1, function () self:updatePos() end)
    return true
end

function ReaderRolling:updatePos()
    -- reread document height
    self.ui.document:_readMetadata()
    -- update self.current_pos if the height of document has been changed.
    local new_height = self.ui.document.info.doc_height
    local new_page = self.ui.document.info.number_of_pages
    if self.old_doc_height ~= new_height or self.old_page ~= new_page then
        self:gotoXPointer(self.ui.document:getXPointer())
        self.old_doc_height = new_height
        self.old_page = new_page
        self.ui:handleEvent(Event:new("UpdateToc"))
    end
    UIManager.repaint_all = true
end

function ReaderRolling:onUpdateXPointer()
    local xp = self.ui.document:getXPointer()
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getPageFromXPointer(xp)))
    else
        self.ui:handleEvent(Event:new("PosUpdate", self.ui.document:getPosFromXPointer(xp)))
    end
    return true
end

function ReaderRolling:onChangeViewMode()
    self.ui.document:_readMetadata()
    self.old_doc_height = self.ui.document.info.doc_height
    self.old_page = self.ui.document.info.number_of_pages
    self.ui:handleEvent(Event:new("UpdateToc"))
    self:gotoXPointer(self.ui.document:getXPointer())
    if self.view.view_mode == "scroll" then
        self.current_pos = self.ui.document:getCurrentPos()
    else
        self.current_page = self.ui.document:getCurrentPage()
    end
    return true
end

function ReaderRolling:onRedrawCurrentView()
    if self.view.view_mode == "page" then
        self.ui:handleEvent(Event:new("PageUpdate", self.current_page))
    else
        self.ui:handleEvent(Event:new("PosUpdate", self.current_pos))
    end
    return true
end

function ReaderRolling:onSetDimensions()
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:initGesListener()
    end
end

function ReaderRolling:onChangeScreenMode(mode)
    self.ui:handleEvent(Event:new("SetScreenMode", mode))
    self:onChangeViewMode()
end

--[[
    PosUpdate event is used to signal other widgets that pos has been changed.
--]]
function ReaderRolling:gotoPos(new_pos)
    if new_pos == self.current_pos then return end
    if new_pos < 0 then new_pos = 0 end
    if new_pos > self.doc_height then new_pos = self.doc_height end
    -- adjust dim_area according to new_pos
    if self.view.view_mode ~= "page" and self.show_overlap_enable then
        local panned_step = new_pos - self.current_pos
        self.view.dim_area.x = 0
        self.view.dim_area.h = self.ui.dimen.h - math.abs(panned_step)
        self.view.dim_area.w = self.ui.dimen.w
        if panned_step < 0 then
            self.view.dim_area.y = self.ui.dimen.h - self.view.dim_area.h
        elseif panned_step > 0 then
            self.view.dim_area.y = 0
        end
    end
    self.ui:handleEvent(Event:new("PosUpdate", new_pos))
end

function ReaderRolling:gotoPage(new_page)
    self.ui.document:gotoPage(new_page)
    self.ui:handleEvent(Event:new("PageUpdate", self.ui.document:getCurrentPage()))
end

function ReaderRolling:gotoXPointer(xpointer)
    if self.view.view_mode == "page" then
        self:gotoPage(self.ui.document:getPageFromXPointer(xpointer))
    else
        self:gotoPos(self.ui.document:getPosFromXPointer(xpointer))
    end
end

function ReaderRolling:gotoPercent(new_percent)
    self:gotoPos(new_percent * self.doc_height / 10000)
end

function ReaderRolling:onGotoPage(number)
    self:gotoPage(number)
    return true
end

--[[
currently we don't need to get page links on each page/pos update
since we can check link on the fly when tapping on the screen
--]]
function ReaderRolling:updatePageLink()
    DEBUG("update page link")
    local links = self.ui.document:getPageLinks()
    self.view.links = links
end

function ReaderRolling:updateBatteryState()
    DEBUG("update battery state")
    if self.view.view_mode == "page" then
        local powerd = Device:getPowerDevice()
        local state = powerd:isCharging() and -1 or powerd:getCapacity()
        if state then
            self.ui.document:setBatteryState(state)
        end
    end
end

return ReaderRolling
