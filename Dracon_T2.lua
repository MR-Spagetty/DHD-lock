local component = require("component")
local event = require("event")
local term = require("term")
local gpu = component.gpu
local screen = component.screen

 -- DynamicRes

local ratioX, ratioY = screen.getAspectRatio()
local maxX, maxY = gpu.maxResolution() 
gpu.setResolution(math.min(ratioX*55, maxX), math.min(ratioY*25,maxY))

 -- Safety Checks

if not component.isAvailable("draconic_reactor") then
  print("Reactor not connected. Please connect computer to reactor with an Adapter block.")
  os.exit()
end
reactor = component.draconic_reactor
local flux_gates = {}
for x,y in pairs(component.list("flux_gate")) do
  flux_gates[#flux_gates+1] = x
end
if #flux_gates < 2 then
  print("Not enough flux gates connected; please connect inflow and outflow flux gates with Adapter blocks.")
  os.exit()
end
flux_in = component.proxy(flux_gates[1])
flux_out = component.proxy(flux_gates[2])
if not flux_in or not flux_out then
  print("Not enough flux gates connected; please connect inflow and outflow flux gates with Adapter blocks.")
  os.exit()
end

 -- Functions

function exit_msg(msg)
  term.clear()
  print(msg)
  os.exit()
end

 -- Buttons

local adj_button_width = 19
local temp_adjust_x_offset = 68
local temp_adjust_y_offset = 2
local field_adjust_x_offset = temp_adjust_x_offset + adj_button_width + 2
local field_adjust_y_offset = 2
local status = "PeFi"
local lowest_field = 100
local lowest_fuel = 100
local highest_temp = 0
local highest_sat = 0
local highest_outflow = 0
local cutoff_field = 0.75

      -- Inflow PID
local proportional_field_error = 0
local inflow_I_sum = 0
local integral_field_error = 0
local derivative_field_error = 0
local inflow_D_last = 0
local inflow_correction = 0

    -- Outflow PID
local proportional_temp_error = 0
local outflow_I_sum = 0
local integral_temp_error = 0
local derivative_temp_error = 0
local outflow_D_last = 0
local outflow_correction = 0

local buttons = {
  start={
    x=1,
    y=1,
    width=3,
    height=1,
    text="STR",
    action=function() 
      if safe then
        state = "Charging"
        reactor.chargeReactor()
      elseif shutting_down then
        state = "Active"
        reactor.activateReactor()
      end
    end,
  },
  shutdown={
    x=1,
    y=2,
    width=3,
    height=1,
    text="SHD",
    action=function()
    cutoff_temp = 8001
    ideal_temp = 8000
    ideal_strength = 75
    cutoff_field = 0.75
      state = "Manual Shutdown"
      reactor.stopReactor()
    end,
  },
      chaosmode={
    x=1,
    y=3,
    width=3,
    height=1,
    text=" CHM",
    action=function()
      cutoff_temp = 19750 
      cutoff_field = 12.5
      ideal_strength = 75
      ideal_temp = 50000
      chaosmode = 1
    end,
  },

    switch_gates={
    x=1,
    y=4,
    width=3,
    height=1,
    text="SWG",
    action=function()
      cutoff_temp = 10500
      local old_addr = flux_in.address
      flux_in = component.proxy(flux_out.address)
      flux_out = component.proxy(old_addr)
    end,
  },
    exit={
    x=1,
    y=5,
    width=3,
    height=1,
    text="EXT",
    action=function()
      reactor.stopReactor()
      gpu.setResolution(gpu.maxResolution())
      event_loop = false
    end,
  },
    self_destruct={
    x=0,
    y=0,
    width=3,
    height=4,
    text="DST",
    action=function()
      local sg = component.stargate
      Pass_code = {"Leo","Pegasus"}
      Current_Guess = {}
      destructLoop = true

      function Add_to_guess(evname, address, caller, num, lock, glyph)
          table.insert(Current_Guess, glyph)
      end

      function Check_code()
          local passes = true
          if #Pass_code == #Current_Guess then
              for i,v in ipairs(Current_Guess) do
                  if Pass_code[i] ~= v then
                    passes = false
                  end
              end
          else
              passes = false
          end
          term.clear()
          if passes then
              term.write('Code accepted\nSelf destruct iniated')
              ideal_strength = 0
              destructLoop = false
          else
              term.write('Code invalid\nAborting Self destruct')
              os.sleep(3)
              term.clear()
              destructLoop = false
          end
          Current_Guess = {}
      end

      sg.disengageGate()

      eventStargateOpen = event.listen('stargate_open', Check_code)
      eventStargateFailed = event.listen('stargate_failed', Check_code)
      eventDHDChevronEngaged = event.listen("stargate_dhd_chevron_engaged", Add_to_guess)

      term.clear()
      term.write('Terminal Locked')
      while destructLoop do
          os.sleep()
      end

      event.cancel(eventStargateOpen)
      event.cancel(eventStargateFailed)
      event.cancel(eventDHDChevronEngaged)
    end
    }
}

 -- main code

flux_in.setFlowOverride(0)
flux_out.setFlowOverride(0)
flux_in.setOverrideEnabled(true)
flux_out.setOverrideEnabled(true)

local condition = reactor.getReactorInfo()
if not condition then
  print("Reactor not initialized, please ensure the stabilizers are properly laid out.")
  os.exit()
end

ideal_strength = 15

ideal_temp = 8000
cutoff_temp = 8001

 -- tweakable pid gains

inflow_P_gain = 1
inflow_I_gain = 0.04
inflow_D_gain = 0.05

outflow_P_gain = 500
outflow_I_gain = 0.10
outflow_II_gain = 0.0000003
outflow_D_gain = 30000

 -- initialize main loop

inflow_I_sum = 0
inflow_D_last = 0

outflow_I_sum = 0
outflow_II_sum = 0
outflow_D_last = 0

state = "Standby"
shutting_down = false

if condition.temperature > 25 then
  state = "Cooling"
end
if condition.temperature > 2000 then
  state = "Active"
end

 -- Possible states:
  --Standby
  --Charging
  --Active
  --Manual Shutdown
  --Emergency Shutdown
  --Cooling

event_loop = true
while event_loop do

  if not component.isAvailable("draconic_reactor") then
    exit_msg("Reactor disconnected, exiting")
  end

  if not component.isAvailable("flux_gate") then
    exit_msg("Flux gates disconnected, exiting")
  end

    local info = reactor.getReactorInfo()
 
 -- Highest Heat Value 
 
if info.temperature > highest_temp then
  highest_temp = info.temperature
end

 -- Highest Sat Value 
 
if ((info.energySaturation / info.maxEnergySaturation) * 100) > highest_sat then
  highest_sat = ((info.energySaturation / info.maxEnergySaturation) * 100)
end
 
 -- Lowest Field Value ((1 - info.fuelConversion / info.maxFuelConversion) * 100)
 
if ((info.fieldStrength / info.maxFieldStrength) * 100) < lowest_field then
  lowest_field = ((info.fieldStrength / info.maxFieldStrength) * 100)
end

 -- Lowest Field Value
 
if ((1 - info.fuelConversion / info.maxFuelConversion) * 100) < lowest_fuel then
  lowest_fuel = ((1 - info.fuelConversion / info.maxFuelConversion) * 100)
end

  local inflow = 0
  local outflow = 0

  shutting_down = state == "Manual Shutdown" or state == "Emergency Shutdown"
  running = state == "Charging" or state == "Active"
  safe = state == "Standby" or state == "Cooling"

  if state == "Charging" then
    inflow = 5000000

    if info.temperature > 2000 then
      reactor.activateReactor()
      state = "Active"
    end
  elseif state == "Cooling" then
    if info.temperature < 25 then
      state = "Standby"
    end
    inflow = 10
    outflow = 20
  elseif state == "Standby" then
    inflow = 10
    outflow = 20
  else
    -- adjust inflow rate based on field strength
   
    field_error = (info.maxFieldStrength * (ideal_strength / 100)) - info.fieldStrength
    proportional_field_error = field_error * inflow_P_gain
    inflow_I_sum = inflow_I_sum + field_error
    integral_field_error = inflow_I_sum * inflow_I_gain
    derivative_field_error = (field_error - inflow_D_last) * inflow_D_gain
    inflow_D_last = field_error
    inflow_correction = proportional_field_error + integral_field_error + derivative_field_error
    if inflow_correction < 0 then
      inflow_I_sum = inflow_I_sum - field_error
    end
    inflow = inflow_correction

    if not shutting_down then

      -- adjust outflow rate based on core temperature

      temp_error = ideal_temp - info.temperature
      proportional_temp_error = temp_error * outflow_P_gain
      outflow_I_sum = outflow_I_sum + temp_error
      integral_temp_error = outflow_I_sum * outflow_I_gain
      if math.abs(temp_error) < 100 then
        outflow_II_sum = outflow_II_sum + integral_temp_error
      else
        outflow_II_sum = 0
      end
      second_integral_temp_error = outflow_II_sum * outflow_II_gain
      derivative_temp_error = (temp_error - outflow_D_last) * outflow_D_gain
      outflow_D_last = temp_error
      outflow_correction = proportional_temp_error + integral_temp_error + second_integral_temp_error + derivative_temp_error
      if outflow_correction < 0 then
        outflow_I_sum = outflow_I_sum - temp_error
      end
      outflow = outflow_correction

      -- cut off reactor in case of emergency

      if info.temperature > cutoff_temp then
        print("Reactor Too Hot, shutting down")
        state = "Emergency Shutdown"
        status = "HiTe"
        reactor.stopReactor()
      end
      if ((info.fieldStrength / info.maxFieldStrength) * 100) < cutoff_field then
        print("Reactor Field Has Failed, Failsafe Activated, Shutting Down")
        state = "Emergency Shutdown"
        status = "LoFi"
        reactor.stopReactor()
      end
      if ((1 - info.fuelConversion / info.maxFuelConversion) * 100) < 1.25 then
        print("Reactor Fuel Low, Shutting Down")
      state = "Emergency Shutdown"
      status = "LoFu"
      reactor.stopReactor()
      end
    else
      if info.temperature < 2000 then
        state = "Cooling"
      end
    end
  end

  if state ~= "Active" and not shutting_down then
    inflow_I_sum = 0
    inflow_D_last = 0
    outflow_I_sum = 0
    outflow_II_sum = 0
    outflow_D_last = 0
  end

  if inflow < 0 then
    inflow = 0
  end
  if outflow < 0 then
    outflow = 0
  end

  inflow = math.floor(inflow)
  outflow = math.floor(outflow)

  flux_in.setFlowOverride(inflow)
  flux_out.setFlowOverride(outflow)

  -- Draw screen

  if term.isAvailable() then

    -- Draw Values

function modify_eff(offset)
  local eff = ((outflow / inflow) * 100)
  if eff > 100000 then
    eff = 1
  end
end

    local secondsToExpire = (info.maxFuelConversion - info.fuelConversion) / math.max(info.fuelConversionRate*0.00002, 0.00001)

    local left_margin = 2
    local spacing = 1
    local values = {
    	"",
    	"",
    	"",
    	"",
    	"",
string.format("ETA %2dd, %2dh, %2dm, %2ds", secondsToExpire/86400, secondsToExpire/3600 % 24, secondsToExpire/60 % 60, secondsToExpire % 60),
string.format("FLD %7.1f%%", ((info.fieldStrength / info.maxFieldStrength) * 100)),
string.format("FUL %5.1f%%", ((1 - info.fuelConversion / info.maxFuelConversion) * 100)),
string.format("TMP %7.1f°c", info.temperature),
string.format("ENG %12.1fRF/t", outflow),
              "STS " .. state .. "",
}


    term.clear()
    
    for i, v in ipairs(values) do
      term.setCursor(left_margin, i * spacing)
      term.write(v)
    end

    -- Draw button values

    term.setCursor(temp_adjust_x_offset, temp_adjust_y_offset+10)
    term.write(" ")
    term.setCursor(field_adjust_x_offset+1, field_adjust_y_offset+10)
    term.write(" ")

    -- Draw Buttons

    gpu.setForeground(0x000000)

    for bname, button in pairs(buttons) do
      if button.depressed then

        button.depressed = button.depressed - 1
        if button.depressed == 0 then
          button.depressed = nil
        end
      end
      if button.condition == nil or button.condition() then
        local center_color = 0xAAAAAA
        local highlight_color = 0xCCCCCC
        local lowlight_color = 0x808080
        if button.depressed then
          center_color = 0x999999
          highlight_color = 0x707070
          lowlight_color = 0xBBBBBB
        end
        gpu.setBackground(center_color)
        gpu.fill(button.x, button.y, button.width, button.height, " ")
        if button.width > 1 and button.height > 1 then
          gpu.setBackground(lowlight_color)
          gpu.fill(button.x+1, button.y+button.height-1, button.width-1, 1, " ")
          gpu.fill(button.x+button.width-1, button.y, 1, button.height, " ")
          gpu.setBackground(highlight_color)
          gpu.fill(button.x, button.y, 1, button.height, " ")
          gpu.fill(button.x, button.y, button.width, 1, " ")
        end
        gpu.setBackground(center_color)
        term.setCursor(button.x + math.floor(button.width / 2 - #button.text / 2), button.y + math.floor(button.height / 2))
        term.write(button.text)
      end
    end

    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
  end  

  -- Wait for next tick, or manual shutdown

  local event, id, op1, op2 = event.pull(0.05)
  if event == "interrupted" then
    if safe then
      break
    end
  elseif event == "touch" then
    
    -- Handle Button Presses

    local x = op1
    local y = op2

    for bname, button in pairs(buttons) do
      if (button.condition == nil or button.condition()) and x >= button.x and x <= button.x + button.width and y >= button.y and y <= button.y + button.height then
        button.action()
        button.depressed = 3
      end
    end
  end
end

term.clear()