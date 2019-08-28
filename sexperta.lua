-- license:BSD-3-Clause
-- copyright-holders:Sandro Ronco

interface = {}

interface.level = "b8"
interface.cur_level = nil

function interface.go_back(stop) -- function is required to move back, "stop" = end of backmove. 
if stop~=1 then                     
    send_input(":IN.0", 0x02, 0.5)		--Analyze Games / Tack Back
  end
end

function interface.player_vs_player_mode() -- function is required to move forward. 
	send_input(":IN.7", 0x02, 0.5)		--  Player-Player / Gambit Book / King
  send_input(":IN.7", 0x02, 0.5)	  --  Player-Player / Gambit Book / King
end

function interface.player_vs_player_off() --function some engine needed for 'end of move forward'.
  -- nothing to do            
end

function interface.stop_play() -- function is required for time control if 'stop play not the same like 'start ply'.
  send_input(":IN.0", 0x01,1) -- play
end

function interface.Start_Roll_Info() -- function is required, if the engine does not automatically display the score
 
end

function interface.show_info() -- function is required to show score depth and pv. Added by Vegetatio
  send_input(":IN.2", 0x01, 0.3)
  local ddram = emu.item(machine.devices[':hd44780'].items['0/m_ddram']):read_block(0x00, 0x80)
  local pv = " pv " .. ddram.sub(ddram,3,6):gsub(" ","") .. " " .. (ddram.sub(ddram,8,8) .. ddram.sub(ddram,65,67)):gsub(" ","")
  send_input(":IN.2", 0x01, 0.3)
  ddram = emu.item(machine.devices[':hd44780'].items['0/m_ddram']):read_block(0x00, 0x80)
  pv = pv .. " " ..ddram.sub(ddram,3,6) .. " " .. ddram.sub(ddram,8,8).. ddram.sub(ddram,65,67)
  send_input(":IN.1", 0x02, 0.3)
  send_input(":IN.1", 0x02, 0.3) 
	ddram = emu.item(machine.devices[':hd44780'].items['0/m_ddram']):read_block(0x00, 0x80)
	local info = tostring(ddram.sub(ddram,7,8) .. ddram.sub(ddram,63,70))
  info = info:gsub(" ","")
  info = "info score cp " .. info:gsub("%.","") --score
  info = info .." currmove " .. ddram.sub(ddram,2,5)
	send_input(":IN.1", 0x02, 0.3) 
	ddram = emu.item(machine.devices[':hd44780'].items['0/m_ddram']):read_block(0x00, 0x80)
  info = info .. " depth " .. ddram.sub(ddram,3,4) .. " currmovenumber " .. ddram.sub(ddram,6,7) .. pv
  send_input(":IN.1", 0x02, 0.3) 
	send_input(":IN.1", 0x02, 0.3)
  send_input(":IN.1", 0x02, 0.3)
	return (info) -- info = score, currmove currmonenumber, pv, depth (seldepth if the engine show it)
end

function interface.setlevel()
	if (interface.cur_level == nil or interface.cur_level == interface.level) then
		return
	end
	interface.cur_level = interface.level
	local cols_idx = { a=1, b=2, c=3, d=4, e=5, f=6, g=7, h=8 }
	local x = cols_idx[interface.level:sub(1, 1)]
	local y = tostring(tonumber(interface.level:sub(2, 2)))
	send_input(":IN.1", 0x01, 1) -- Set Level
	sb_press_square(":board", 1, x, y)
	send_input(":IN.0", 0x01, 1) -- Go
end

function interface.setup_machine()
	sb_reset_board(":board")
	emu.wait(2)
	send_input(":IN.7", 0x01, 1) -- New Game
	emu.wait(3)
	interface.cur_level = ""
	interface.setlevel()
end

function interface.start_play(init)
	send_input(":IN.0", 0x01, 1) -- Go
	emu.wait(1)
end

function interface.is_selected(x, y)
	return machine:outputs():get_indexed_value(tostring(y - 1) .. ".", 8 - x) ~= 0
end

function interface.select_piece(x, y, event)
	sb_select_piece(":board", 1, x, y, event)
end

function interface.get_options()
	return { { "string", "Level", "a1"}, }
end

function interface.set_option(name, value)
	if (name == "level" and value ~= "") then
		interface.level = value
		interface.setlevel()
	end
end

function interface.get_promotion(x, y)
	-- HD44780 Display Data RAM
	local ddram = emu.item(machine.devices[':hd44780'].items['0/m_ddram']):read_block(0x00, 0x80)
	local ch9 = ddram:sub(0x42,0x42)

	if     (ch9 == '\x02' or ch9 == '\x0a') then	return 'q'
	elseif (ch9 == '\x03' or ch9 == '\x0b') then	return 'r'
	elseif (ch9 == '\x04' or ch9 == '\x0c') then	return 'b'
	elseif (ch9 == '\x05' or ch9 == '\x0d') then	return 'n'
	end
	return nil
end

function interface.promote(x, y, piece)
	sb_promote(":board", x, y, piece)
	emu.wait(1.0)
	if     (piece == "q") then	send_input(":IN.6", 0x02, 1)
	elseif (piece == "r") then	send_input(":IN.3", 0x02, 1)
	elseif (piece == "b") then	send_input(":IN.5", 0x02, 1)
	elseif (piece == "n") then	send_input(":IN.4", 0x02, 1)
	end
end

return interface
