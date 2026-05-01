{ ... }: {
  home.file.".hammerspoon/init.lua".text = ''
    -- Menu bar toggle for `pmset disablesleep` — keeps the Mac awake (including
    -- with the lid closed) for long Nix builds. Requires the matching sudoers
    -- drop-in installed by the Darwin host config (security.sudo.extraConfig).

    local pmset = "/usr/bin/pmset"
    local sudo  = "/usr/bin/sudo"

    local function readDisableSleep()
      local out = hs.execute(pmset .. " -g | /usr/bin/awk '/SleepDisabled/{print $2}'")
      return (out or ""):match("1") ~= nil
    end

    local function render(menu, disabled)
      if disabled then
        menu:setTitle("☕")
        menu:setTooltip("Sleep disabled — lid-close will NOT sleep.\nClick to restore normal sleep.")
      else
        menu:setTitle("💤")
        menu:setTooltip("Normal sleep behaviour.\nClick to disable sleep (stays awake lid-closed).")
      end
    end

    sleepToggle = { state = readDisableSleep() }
    sleepToggle.menu = hs.menubar.new()
    if sleepToggle.menu then
      render(sleepToggle.menu, sleepToggle.state)
      sleepToggle.menu:setClickCallback(function()
        local newval = sleepToggle.state and "0" or "1"
        local _, ok = hs.execute(sudo .. " -n " .. pmset .. " -a disablesleep " .. newval)
        if ok then
          sleepToggle.state = not sleepToggle.state
          render(sleepToggle.menu, sleepToggle.state)
        else
          hs.alert.show("pmset toggle failed — sudoers rule missing?")
        end
      end)
    end
  '';
}
