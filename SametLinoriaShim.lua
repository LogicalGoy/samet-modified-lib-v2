--[[
    Samet-Linoria Compatibility Shim
    Allows using LinoriaLib syntax on top of Samet UI.
--]]

local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")

local LocalPlayer       = Players.LocalPlayer

local Shim = {}

function Shim:Init(config)
    config = config or {}
    local UI_NAME           = config.Name or "Placeholder"
    local UI_SUB            = config.SubName or "Citra hub"
    local UI_LOGO           = config.Logo or "91942884565368"
    local UI_ACCENT         = config.Accent or Color3.fromRGB(255, 165, 0)
    local DEFAULT_TAB_ICON  = config.DefaultTabIcon or "108839695397679"
    local UI_SHOW_TAB_ICONS = config.ShowTabIcons ~= false
    local CONFIG_FOLDER     = config.ConfigFolder or "BaseUI/configs"
    local THEME_FOLDER      = config.ThemeFolder or "BaseUI"
    local SAMET_URL         = "https://raw.githubusercontent.com/bigdanix/roblox-ui-libs/main/samet%20ui/source%20%2B%20example"
    local SAMET_CACHE       = "BaseUI/samet_lib_v2.lua"

    -- 1. Load Samet UI
    local Samet do
        local src
        if isfile and readfile then
            local ok, c = pcall(function() return isfile(SAMET_CACHE) and readfile(SAMET_CACHE) or nil end)
            if ok and type(c) == "string" and #c > 1000 then src = c end
        end
        if not src then
            src = game:HttpGet(SAMET_URL)
            local cut = src:find("\nlocal Window = Library:Window")
            if cut then src = src:sub(1, cut - 1) .. "\nreturn Library\n" end
            pcall(function()
                if makefolder and isfolder and not isfolder("BaseUI") then makefolder("BaseUI") end
                if writefile then writefile(SAMET_CACHE, src) end
            end)
        end

        -- Apply monkey-patches to Samet UI source code
        -- A. Default Background Transparency to 0.25
        src = src:gsub("BackgroundTransparency = 0%.12", "BackgroundTransparency = 0.25")
        src = src:gsub("Default = 0%.12", "Default = 0.25")

        -- B. Inject NoModes field in Keybind constructor
        src = src:gsub('Mode = Data%.Mode or Data%.mode or Enum%.KeyCode%.RightShift,', 'Mode = Data.Mode or Data.mode or Enum.KeyCode.RightShift,\n                NoModes = Data.NoModes or false,')

        -- C. Hide Mode Selection buttons if NoModes is true
        src = src:gsub('Items%["Modes"%] = Instances:Create%("Frame", {%s*Parent = Items%["Label"%]%.Instance,', 'Items["Modes"] = Instances:Create("Frame", {\n                    Parent = Items["Label"].Instance,\n                    Visible = not (Data.NoModes or false),')

        -- D. Force "Toggle" mode behavior on Press and Set if NoModes is true
        src = src:gsub('function Keybind:Press%(Bool%)%s*if Keybind%.ModeSelected == "Toggle" then', 'function Keybind:Press(Bool)\n                if Keybind.NoModes then Keybind.ModeSelected = "Toggle" end\n                if Keybind.ModeSelected == "Toggle" then')
        
        src = src:gsub('function Keybind:Set%(Key%)', 'function Keybind:Set(Key)\n                if Keybind.NoModes then\n                    if type(Key) == "table" then\n                        Key.Mode = "Toggle"\n                        Key.ModeSelected = false\n                    elseif type(Key) == "string" and (Key == "Hold" or Key == "Always") then\n                        return\n                    end\n                end')

        -- E. Set Default to RightShift and NoModes = true for Settings Menu Keybind
        src = src:gsub('Flag = "MenuBind",%s*Default = Enum%.KeyCode%.Z,', 'Flag = "MenuBind",\n                    Default = Enum.KeyCode.RightShift,\n                    NoModes = true,')

        -- F. Safety fix for SetOpen during startup
        src = src:gsub("Window:SetOpen%(Value%)", "if Window.SetOpen then Window:SetOpen(Value) end")

        -- G. Safety fix for Instances methods when Library is nil (during unload)
        src = src:gsub("Library:ChangeItemTheme%(self, Properties%)", "if Library then Library:ChangeItemTheme(self, Properties) end")
        src = src:gsub("Library:AddToTheme%(self, Properties%)", "if Library then Library:AddToTheme(self, Properties) end")
        src = src:gsub("return Library:Connect%(self%.Instance%[Event%], Callback, Name%)", "if Library then return Library:Connect(self.Instance[Event], Callback, Name) end")
        src = src:gsub("return Library:Disconnect%(Name%)", "if Library then return Library:Disconnect(Name) end")

        -- H. Prevent local Library reference from being cleared during Unload to avoid post-unload nil-indexing errors
        src = src:gsub("Library = nil%s*getgenv%(%)%.Library = nil", "Library.Unloaded = true\n        getgenv().Library = nil")

        -- I. Support full URIs (like rbxthumb://) for tab icons to allow using Decal IDs directly
        src = src:gsub('Image = "rbxassetid://"%.%.Page%.Icon,', 'Image = string.find(tostring(Page.Icon), "://") and Page.Icon or ("rbxassetid://"..Page.Icon),')

        -- J. Optimize Tab Switching to prevent stutters (bypass deep descendants fading loop)
        src = src:gsub('local AllInstances = Items%["Page"%]%.Instance:GetDescendants%(%)%s*TableInsert%(AllInstances, Items%["Page"%]%.Instance%)%s*local NewTween', 'local AllInstances = {}\n                local NewTween = { Tween = { Completed = game:GetService("RunService").Heartbeat } }')

        -- K. Fix KeybindList:SetVisibility hardcoded bug in Samet UI
        src = src:gsub('function KeybindList:SetVisibility%(Bool%)%s*Items%["KeybindsList"%]%.Instance%.Visible = false%s*end', 'function KeybindList:SetVisibility(Bool)\n                Items["KeybindsList"].Instance.Visible = Bool\n            end')

        -- L. Fix Notification sizing and accent positioning bugs
        src = src:gsub('local Size = Items%["Notification"%]%.Instance%.AbsoluteSize%s*Items%["Notification"%]%.Instance%.Size = UDim2New%(0, 0, 0, 0%)%s*for Index, Value in Items do%s*if Value%.Instance:IsA%("Frame"%) then%s*Value%.Instance%.BackgroundTransparency = 1%s*elseif Value%.Instance:IsA%("TextLabel"%) then%s*Value%.Instance%.TextTransparency = 1%s*elseif Value%.Instance:IsA%("ImageLabel"%) then%s*Value%.Instance%.ImageTransparency = 1%s*end%s*end%s*task%.wait%(0%.2%)', [[
            for Index, Value in Items do 
                if Value.Instance:IsA("Frame") then
                    Value.Instance.BackgroundTransparency = 1
                elseif Value.Instance:IsA("TextLabel") then 
                    Value.Instance.TextTransparency = 1
                elseif Value.Instance:IsA("ImageLabel") then 
                    Value.Instance.ImageTransparency = 1
                end
            end 
            task.wait()
            local Size = Items["Notification"].Instance.AbsoluteSize
            pcall(function()
                Items["Accent"].Instance.Position = UDim2New(0, 0, 0, Items["Description"].Instance.AbsoluteSize.Y + Items["Title"].Instance.AbsoluteSize.Y + 12)
            end)
            Items["Notification"].Instance.Size = UDim2New(0, 0, 0, 0)
            task.wait(0.15)
        ]])

        -- M. Fix Library:Round floating-point precision bug in Samet UI (prevent sliders from getting stuck)
        src = src:gsub("return MathFloor%(Number %* Multiplier%) / Multiplier", "return MathFloor(Number * Multiplier + 0.5) / Multiplier")

        -- N. Default Font weight to Regular
        src = src:gsub("Library%.Font = SemiBold", "Library.Font = Regular")
        src = src:gsub('Default = "SemiBold",%s*Items = %{"Light", "Regular", "SemiBold"%}', 'Default = "Regular",\n                    Items = {"Light", "Regular", "SemiBold"}')

        Samet = loadstring(src)()
    end

    pcall(function()
        Samet:ChangeTheme("Accent", UI_ACCENT)
        Samet:ChangeTheme("AccentGradient", UI_ACCENT)
    end)

    local Toggles, Options = {}, {}
    local _searchReg = {}
    local _SametWindow
    local _windowOpen = true
    local Connections = {}

    local function keyToEnum(k)
        if typeof(k) == "EnumItem" then return k end
        if type(k) == "string" and k ~= "" and k ~= "None" then
            local ok, e = pcall(function() return Enum.KeyCode[k] end)
            if ok then return e end
        end
        return nil
    end

    local function wrapValue(store, flag, sametEl, default, userCb)
        local obj = { Value = default, Flag = flag, _l = {}, _el = sametEl }
        function obj:OnChanged(fn) table.insert(self._l, fn); return self end
        function obj:_fire(v)
            self.Value = v
            for _, fn in ipairs(self._l) do pcall(fn, v) end
            if userCb then pcall(userCb, v) end
        end
        function obj:SetValue(v)
            if self._el and self._el.Set then pcall(function() self._el:Set(v) end) else self:_fire(v) end
        end
        function obj:GetState() return self.Value == true end
        if flag then store[flag] = obj end
        return obj
    end

    local Library = { Unloaded = false, ToggleKeybind = Enum.KeyCode.RightShift, _unload = {} }

    function Library:Notify(text, dur)
        pcall(function()
            -- Description = "" so the notification's description TextLabel doesn't fall back
            -- to Roblox's default "Label" text (we only use the Title line).
            Samet:Notification({ Title = tostring(text or ""), Description = "", Duration = tonumber(dur) or 3, Icon = UI_LOGO })
        end)
    end

    function Library:OnUnload(fn) table.insert(self._unload, fn) end

    function Library:Unload()
        self.Unloaded = true
        for _, fn in ipairs(self._unload) do pcall(fn) end
        for _, conn in ipairs(Connections) do
            if typeof(conn) == "RBXScriptConnection" then pcall(function() conn:Disconnect() end) end
        end
        pcall(function() Samet:Unload() end)
    end

    local function makeGroupbox(sametSection)
        pcall(function()
            local it = sametSection.Items
            if it then
                if it.Toggle and it.Toggle.Instance then it.Toggle.Instance.Visible = false end
                if it.Circle and it.Circle.Instance then it.Circle.Instance.Visible = false end
            end
        end)
        local G = { _sec = sametSection }

        function G:AddToggle(flag, data)
            data = data or {}
            local userCb = data.Callback
            local el = self._sec:Toggle({
                Name = data.Text or flag, Flag = flag, Default = data.Default and true or false,
                Callback = function(v) if Toggles[flag] then Toggles[flag]:_fire(v) end end,
            })
            local obj = wrapValue(Toggles, flag, el, data.Default and true or false, userCb)
            obj._sec, obj._toggleEl = self._sec, el
            table.insert(_searchReg, { name = (data.Text or flag), el = el })

            function obj:AddKeyPicker(kflag, kdata)
                kdata = kdata or {}
                local kp = { Value = kdata.Default, _l = {}, _state = false, Sync = kdata.SyncToggleState, NoUI = kdata.NoUI }
                function kp:OnChanged(fn) table.insert(self._l, fn); return self end
                function kp:GetState() return self._state == true end
                function kp:SetValue(v) self.Value = v end
                if not kdata.NoUI then
                    local noModes = true
                    local kfLower = string.lower(kflag)
                    if string.find(kfLower, "aim") or string.find(kfLower, "lock") or string.find(kfLower, "target") then
                        noModes = false
                    end
                    local kb
                    kb = self._sec:Keybind({
                        Name = kdata.Text or kflag, Flag = kflag, Default = keyToEnum(kdata.Default) or "None",
                        NoModes = noModes,
                        Callback = function(toggled)
                            kp._state = toggled and true or false
                            local mode = "Toggle"
                            if kb and kb.Get then local _, m = kb:Get(); if m and m ~= "" then mode = m end end
                            if kp.Sync and mode == "Toggle" and Toggles[flag] then
                                Toggles[flag]:SetValue(kp._state)
                            end
                            for _, fn in ipairs(kp._l) do pcall(fn, kp._state) end
                        end,
                    })
                    kp._kb = kb
                end
                Options[kflag] = kp
                return obj
            end

            function obj:AddColorPicker(cflag, cdata)
                cdata = cdata or {}
                local lbl = self._sec:Label(cdata.Title or cdata.Text or cflag)
                local cel = lbl:Colorpicker({
                    Flag = cflag, Default = cdata.Default or Color3.new(1, 1, 1),
                    Callback = function(v) if Options[cflag] then Options[cflag]:_fire(v) end end,
                })
                wrapValue(Options, cflag, cel, cdata.Default or Color3.new(1, 1, 1), cdata.Callback)
                return obj
            end

            return obj
        end

        function G:AddSlider(flag, data)
            data = data or {}
            local step = 10 ^ (-(data.Rounding or 0))
            local el = self._sec:Slider({
                Name = data.Text or flag, Flag = flag, Min = data.Min or 0, Max = data.Max or 100,
                Default = data.Default or data.Min or 0, Decimals = step, Suffix = data.Suffix,
                Callback = function(v) if Options[flag] then Options[flag]:_fire(v) end end,
            })
            local obj = wrapValue(Options, flag, el, data.Default or data.Min or 0, data.Callback)
            table.insert(_searchReg, { name = (data.Text or flag), el = el })
            return obj
        end

        function G:AddDropdown(flag, data)
            data = data or {}
            local values = data.Values or {}
            local def = data.Default
            if not data.Multi and type(def) == "number" then def = values[def] end
            local maker = data.Search and self._sec.Listbox or self._sec.Dropdown
            local el = maker(self._sec, {
                Name = data.Text or flag, Flag = flag, Items = values, Default = def,
                Multi = data.Multi and true or false,
                Callback = function(v) if Options[flag] then Options[flag]:_fire(v) end end,
            })
            local obj = wrapValue(Options, flag, el, def, data.Callback)
            function obj:SetValues(list)
                if self._el and self._el.Refresh then pcall(function() self._el:Refresh(list) end) end
            end
            table.insert(_searchReg, { name = (data.Text or flag), el = el })
            return obj
        end

        function G:AddButton(a, b)
            local text, fn, tip
            if type(a) == "table" then text, fn, tip = a.Text, a.Func or a.Callback, a.Tooltip else text, fn = a, b end
            local el = self._sec:Button({ Name = text or "Button", Tooltip = tip, Callback = function() if fn then pcall(fn) end end })
            return { _el = el, SetText = function() end }
        end

        function G:AddLabel(text, _wrap)
            local L = self._sec:Label(tostring(text or ""))
            local lo = { _el = L }
            function lo:SetText(t) if L and L.SetText then pcall(function() L:SetText(tostring(t)) end) end end
            function lo:AddColorPicker(cflag, cdata)
                cdata = cdata or {}
                local cel = L:Colorpicker({
                    Name = cdata.Title or cflag, Flag = cflag, Default = cdata.Default or Color3.new(1, 1, 1),
                    Callback = function(v) if Options[cflag] then Options[cflag]:_fire(v) end end,
                })
                wrapValue(Options, cflag, cel, cdata.Default or Color3.new(1, 1, 1), cdata.Callback)
                return lo
            end
            function lo:AddKeyPicker(kflag, kdata)
                kdata = kdata or {}
                local kp = { Value = kdata.Default, _l = {}, NoUI = true }
                function kp:OnChanged(fn) table.insert(self._l, fn); return self end
                function kp:GetState() return false end
                function kp:SetValue(v) self.Value = v end
                Options[kflag] = kp
                return lo
            end
            return lo
        end

        function G:AddInput(flag, data)
            data = data or {}
            if data.Text then self._sec:Label(data.Text) end
            local el = self._sec:Textbox({
                Flag = flag, Default = data.Default or "", Placeholder = data.Placeholder or "...",
                Numeric = data.Numeric and true or false, Finished = true,
                Callback = function(v) if Options[flag] then Options[flag]:_fire(v) end end,
            })
            return wrapValue(Options, flag, el, data.Default or "", data.Callback)
        end

        function G:AddDivider() return { } end

        return G
    end

    local function makeTab(sametPage)
        local T = { _page = sametPage }
        function T:AddLeftGroupbox(name)  return makeGroupbox(self._page:Section({ Name = name or "", Side = 1 })) end
        function T:AddRightGroupbox(name) return makeGroupbox(self._page:Section({ Name = name or "", Side = 2 })) end
        return T
    end

    function Library:CreateWindow(opts)
        opts = opts or {}
        local win = Samet:Window({ Name = UI_NAME, SubName = UI_SUB, Logo = UI_LOGO })
        _SametWindow = win

        pcall(function()
            local function fixLogo(key)
                local it = win.Items and win.Items[key]
                local inst = it and it.Instance
                if inst then
                    inst.Image = "rbxthumb://type=Asset&id=" .. UI_LOGO .. "&w=150&h=150"
                    local g = inst:FindFirstChildOfClass("UIGradient")
                    if g then g.Enabled = false end
                end
            end
            fixLogo("Logo")
            fixLogo("FloatingLogo")
        end)
        pcall(function()
            local kl = Samet:KeybindList("Keybinds")
            Library.KeyList = kl
        end)
        pcall(function() win:Category("Features") end)

        local W = { _win = win }
        local _tabIcons = {
            Main = "", ["Auto Parry"] = "", Character = "",
            Aimbot = "", ESP = "", Utilities = "",
            Settings = "",
        }
        function W:AddTab(name)
            local page = self._win:Page({ Name = name, Icon = _tabIcons[name] or DEFAULT_TAB_ICON })
            if not UI_SHOW_TAB_ICONS then
                pcall(function()
                    local it = page.Items
                    if it then
                        if it.Icon and it.Icon.Instance then it.Icon.Instance.Visible = false end
                        if it.Text and it.Text.Instance then it.Text.Instance.Position = UDim2.new(0, 16, 0.5, 0) end
                    end
                end)
            end
            return makeTab(page)
        end
        function W:Init() pcall(function() win:Init() end) end
        function W:Toggle()
            _windowOpen = not _windowOpen
            pcall(function() win:SetOpen(_windowOpen) end)
        end
        return W
    end

    table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gp)
        if gp or Library.Unloaded then return end
        local tk = Library.ToggleKeybind
        local want
        if typeof(tk) == "EnumItem" then want = tk
        elseif type(tk) == "table" then want = keyToEnum(tk.Value) end
        if want and input.KeyCode == want and _SametWindow then
            _windowOpen = not _windowOpen
            pcall(function() _SametWindow:SetOpen(_windowOpen) end)
        end
    end))

    -- 3. Theme Manager
    local ThemeManager = {}
    function ThemeManager:SetLibrary() end
    function ThemeManager:SetFolder() end
    function ThemeManager:ApplyToTab(tab)
        local box = tab:AddLeftGroupbox("Theme")
        box:AddLabel("Accent colour")
        local lbl = box:AddLabel("Pick accent"):AddColorPicker("ThemeAccent", {
            Default = UI_ACCENT, Title = "Accent",
            Callback = function(c)
                pcall(function() Samet:ChangeTheme("Accent", c); Samet:ChangeTheme("AccentGradient", c) end)
            end,
        })
        local presets = {
            { "Orange",  Color3.fromRGB(255, 165, 0) },
            { "Blue",    Color3.fromRGB(0, 195, 255) },
            { "Purple",  Color3.fromRGB(138, 43, 226) },
            { "Crimson", Color3.fromRGB(220, 40, 60) },
            { "Emerald", Color3.fromRGB(40, 200, 120) },
        }
        for _, p in ipairs(presets) do
            box:AddButton({ Text = p[1], Func = function()
                pcall(function() Samet:ChangeTheme("Accent", p[2]); Samet:ChangeTheme("AccentGradient", p[2]) end)
                if Options.ThemeAccent then Options.ThemeAccent:SetValue(p[2]) end
            end })
        end
    end

    -- 4. Save Manager
    local SaveManager = { _folder = CONFIG_FOLDER, _ignore = {} }
    function SaveManager:SetLibrary() end
    function SaveManager:IgnoreThemeSettings() end
    function SaveManager:SetIgnoreIndexes(t) self._ignore = t or {} end
    function SaveManager:SetFolder(f) self._folder = f or self._folder end

    local function _smEnsureFolder(f)
        if not (makefolder and isfolder) then return end
        local acc = ""
        for seg in string.gmatch(f, "[^/]+") do
            acc = acc == "" and seg or (acc .. "/" .. seg)
            if not isfolder(acc) then pcall(function() makefolder(acc) end) end
        end
    end
    local function _smIgnored(k)
        for _, ig in ipairs(SaveManager._ignore) do if ig == k then return true end end
        return false
    end
    local function _smCollect()
        local data = { toggles = {}, options = {} }
        for k, v in pairs(Toggles) do if not _smIgnored(k) then data.toggles[k] = v.Value end end
        for k, v in pairs(Options) do
            local val = v.Value
            if typeof(val) == "Color3" then val = { __c3 = true, val.R, val.G, val.B } end
            if type(val) ~= "function" and not _smIgnored(k) then data.options[k] = val end
        end
        return data
    end
    function SaveManager:_apply(data)
        if type(data) ~= "table" then return end
        for k, val in pairs(data.toggles or {}) do if Toggles[k] then Toggles[k]:SetValue(val) end end
        for k, val in pairs(data.options or {}) do
            if Options[k] then
                if type(val) == "table" and val.__c3 then val = Color3.new(val[1], val[2], val[3]) end
                if Options[k].SetValue then Options[k]:SetValue(val) end
            end
        end
    end
    function SaveManager:_list()
        local out = {}
        if listfiles and isfolder and isfolder(self._folder) then
            for _, f in ipairs(listfiles(self._folder)) do
                local nm = f:match("([^/\\]+)%.json$")
                if nm then table.insert(out, nm) end
            end
        end
        return out
    end
    -- Read the currently-set autoload config name (trimmed), or nil.
    function SaveManager:_autoloadName()
        if isfile and readfile and isfile(self._folder .. "/autoload.txt") then
            local ok, nm = pcall(readfile, self._folder .. "/autoload.txt")
            if ok and type(nm) == "string" then
                nm = nm:gsub("%s+$", ""):gsub("^%s+", "")
                if nm ~= "" then return nm end
            end
        end
        return nil
    end
    function SaveManager:BuildConfigSection(tab)
        local box = tab:AddRightGroupbox("Save Profiles")
        box:AddInput("SM_Name", { Text = "Config name", Placeholder = "my config" })
        local list = box:AddDropdown("SM_List", { Values = self:_list(), Text = "Configs", AllowNull = true })
        local function refresh() if list then pcall(function() list:SetValues(SaveManager:_list()) end) end end

        -- Autoload status label (was missing -- this is the "doesn't show what's set to autoload" fix).
        local autoLabel = box:AddLabel("Autoload: none")
        local function refreshAutoload()
            local nm = SaveManager:_autoloadName()
            if autoLabel and autoLabel.SetText then pcall(function() autoLabel:SetText("Autoload: " .. (nm or "none")) end) end
        end

        -- Resolve the chosen config name: dropdown selection first, else the typed name.
        -- Coerces the occasional table/set Value shape so Load/Delete/Autoload never silently no-op.
        local function chosenName()
            local v = Options.SM_List and Options.SM_List.Value
            if type(v) == "table" then v = v[1] or next(v) end
            if type(v) ~= "string" or v == "" then
                v = Options.SM_Name and Options.SM_Name.Value
            end
            return (type(v) == "string" and v ~= "") and v or nil
        end

        box:AddButton({ Text = "Create / Save", Func = function()
            local nm = Options.SM_Name and Options.SM_Name.Value
            if not nm or nm == "" then Library:Notify("Enter a config name first.", 3) return end
            _smEnsureFolder(self._folder)
            local ok, body = pcall(function() return HttpService:JSONEncode(_smCollect()) end)
            if ok and writefile then writefile(self._folder .. "/" .. nm .. ".json", body); refresh(); Library:Notify("Saved config '" .. nm .. "'.", 3)
            else Library:Notify("Save failed.", 3) end
        end })
        box:AddButton({ Text = "Load", Func = function()
            local nm = chosenName()
            if not nm then Library:Notify("Pick a config to load (or type its name).", 3) return end
            if not (isfile and readfile and isfile(self._folder .. "/" .. nm .. ".json")) then Library:Notify("Config '" .. nm .. "' not found.", 3) return end
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(self._folder .. "/" .. nm .. ".json")) end)
            -- Apply OFF the button thread: some toggles' OnChanged fire RemoteFunction
            -- InvokeServer (yields), which would otherwise freeze the Load button.
            if ok then task.spawn(function() SaveManager:_apply(data) end); Library:Notify("Loaded config '" .. nm .. "'.", 3) else Library:Notify("Load failed.", 3) end
        end })
        box:AddButton({ Text = "Delete", Func = function()
            local nm = chosenName()
            if nm and delfile and isfile and isfile(self._folder .. "/" .. nm .. ".json") then delfile(self._folder .. "/" .. nm .. ".json"); refresh(); Library:Notify("Deleted '" .. nm .. "'.", 3) end
        end })
        box:AddButton({ Text = "Refresh List", Func = function() refresh(); refreshAutoload() end })
        box:AddButton({ Text = "Set as Autoload", Func = function()
            local nm = chosenName()
            if nm and writefile then _smEnsureFolder(self._folder); writefile(self._folder .. "/autoload.txt", nm); refreshAutoload(); Library:Notify("Autoload set to '" .. nm .. "'.", 3)
            else Library:Notify("Pick or type a config first.", 3) end
        end })
        box:AddButton({ Text = "Clear Autoload", Func = function()
            if delfile and isfile and isfile(self._folder .. "/autoload.txt") then pcall(delfile, self._folder .. "/autoload.txt") end
            refreshAutoload(); Library:Notify("Autoload cleared.", 3)
        end })

        box:AddInput("SM_Search", { Text = "Search options", Placeholder = "filter elements..." })
        if Options.SM_Search then
            Options.SM_Search:OnChanged(function(q)
                q = string.lower(tostring(q or ""))
                for _, e in ipairs(_searchReg) do
                    if e.el and e.el.SetVisibility then
                        pcall(function() e.el:SetVisibility(q == "" or string.find(string.lower(e.name), q, 1, true) ~= nil) end)
                    end
                end
            end)
        end

        -- Guarantee the config list + autoload label are current once the UI has settled
        -- (build-time _list() can run before the folder is populated on some executors).
        refreshAutoload()
        task.defer(refresh)
    end
    function SaveManager:LoadAutoloadConfig()
        if not (isfile and readfile and isfile(self._folder .. "/autoload.txt")) then return end
        local nm = self:_autoloadName()
        if nm and nm ~= "" and isfile(self._folder .. "/" .. nm .. ".json") then
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(self._folder .. "/" .. nm .. ".json")) end)
            if ok then task.delay(1, function() SaveManager:_apply(data) end); Library:Notify("Autoloaded config '" .. nm .. "'.", 3) end
        end
    end

    return Library, Toggles, Options, ThemeManager, SaveManager
end

return Shim
