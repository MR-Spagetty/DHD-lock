-- require('process').info().data.signal = function()end -- Blocking Ctrl+Alt+C
local comp = require('component')
local event = require('event')
local term = require('term')
local sg = comp.stargate
Pass_code = {"Leo","Pegasus"}
Current_Guess = {}
MainLoop = true

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
        term.write('ACCESS GRANTED\n')
        MainLoop = false
    else
        term.write('ACCESS DENIED')
        os.sleep(3)
        term.clear()
        term.write('Terminal Locked\n')
    end
    Current_Guess = {}
end

sg.disengageGate()

eventStargateOpen = event.listen('stargate_open', Check_code)
eventStargateFailed = event.listen('stargate_failed', Check_code)
eventDHDChevronEngaged = event.listen("stargate_dhd_chevron_engaged", Add_to_guess)

term.clear()
term.write('Terminal Locked')
while MainLoop do
    os.sleep()
end

event.cancel(eventStargateOpen)
event.cancel(eventStargateFailed)
event.cancel(eventDHDChevronEngaged)