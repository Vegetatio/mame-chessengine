-- license:BSD-3-Clause
-- copyright-holders:Sandro Ronco

interface = {}
interface.cur_level = "010"
interface.level = "900"


function interface.get_options()
	return { { "spin", "Level", "10", "0", "999"}, }
end

function interface.set_option(name, value)
	if (name == "level") then
		local level = tonumber(value)
		if (level < 0 or level > 999) then
			return
		end
    if level <= 9 then
      interface.level = "00" .. tostring(level)
    elseif level <= 99 then
      interface.level = "0" .. tostring(level)
     else
      interface.level = tostring(level)
    end
		interface.setlevel()
	end
end

function interface.setlevel()
	if (interface.cur_level == interface.level) then
		return
	end
	interface.cur_level = interface.level
	send_input(":IN.2", 0x20, 0.2) -- Menu
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.3", 0x40, 0.2) -- down
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.2", 0x40, 0.2) -- up
  send_input(":IN.3", 0x20, 0.2) -- Enter
  interface.cur_level=interface.read_display(642,644)
  while interface.cur_level:sub(1,1) ~= interface.level:sub(1,1)
    do
      send_input(":IN.2", 0x40, 0.2) -- up
      interface.cur_level=interface.read_display(642,644)
    end
     send_input(":IN.1", 0x40, 0.2) -- right
     while interface.cur_level:sub(2,2) ~= interface.level:sub(2,2)
    do
      send_input(":IN.2", 0x40, 0.2) -- up
      interface.cur_level=interface.read_display(642,644)
    end
    send_input(":IN.1", 0x40, 0.2) -- right
     while interface.cur_level:sub(3,3) ~= interface.level:sub(3,3)
    do
      send_input(":IN.2", 0x40, 0.2) -- up
      interface.cur_level=interface.read_display(642,644)
    end
    send_input(":IN.3", 0x20, 0.2) -- Enter
    send_input(":IN.2", 0x20, 0.2) -- Menu
end


function interface.set_notation()
  send_input(":IN.2", 0x20, 0.2) -- Menu
  send_input(":IN.3", 0x40, 0.2) -- down
  send_input(":IN.3", 0x40, 0.2) -- down
  send_input(":IN.3", 0x40, 0.2) -- down
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.3", 0x40, 0.2) -- down
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.2", 0x40, 0.2) -- up
  send_input(":IN.3", 0x20, 0.2) -- Enter
  send_input(":IN.0", 0x40, 0.2) -- Left
  send_input(":IN.2", 0x40, 0.2) -- up
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.3", 0x20, 0.2) -- Enter
  send_input(":IN.2", 0x20, 0.2) -- Menu
end

function interface.go_back()

end

function interface.player_vs_player_mode()
  send_input(":IN.2", 0x20, 0.2) -- Menu
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.1", 0x40, 0.2) -- right
  send_input(":IN.3", 0x20, 0.2) -- Enter
  send_input(":IN.2", 0x20, 0.2) -- Menu
end

function interface.player_vs_player_off()
 send_input(":IN.2", 0x20, 0.2) -- Menu
  send_input(":IN.1", 0x40, 0.1) -- right
  send_input(":IN.1", 0x40, 0.1) -- right
   send_input(":IN.3", 0x40, 0.2) -- down
  send_input(":IN.3", 0x20, 0.2) -- Enter
  send_input(":IN.2", 0x20, 0.2) -- Menu
end

function interface.show_info()
  local info = interface.read_display(19,22)
  while info ~= "best"
  do
    send_input(":IN.3", 0x40, 0.2) -- down
    info = interface.read_display(19,22)
  end
 
 info ="info score cp " .. (interface.read_display(97,102):gsub("%.","")):gsub(" ","")
  info = info .. " depth " .. interface.read_display(258,259) .. " seldepth " .. interface.read_display(261,262)
  info = info .. " currmove " .. interface.read_display(385,390)  .. " currmovenumber " .. interface.read_display(549,550)
  info = info .. " pv " .. interface.read_display(385,390)
   send_input(":IN.3", 0x40, 0.2) -- down
  info = info .. " ".. interface.read_display(96,101):gsub("-","") .. " " .. interface.read_display(147,152):gsub("-","") .. " " .. interface.read_display(255,261):gsub("-","") .. " " .. interface.read_display(306,312):gsub("-","") .. " " .. interface.read_display(319,325):gsub("-","") .. " " .. interface.read_display(370,376):gsub("-","")
send_input(":IN.2", 0x40, 0.2) -- up
return info
end


function interface.read_display(st,en)
  alpha = {"!","'","#","$" ,"%","&","'","(",")","*","+",",","-",".","/","0","1","2","3","4","5","6","7","8","9",":",";","<","=",">","?","@","A","B","C","D","D","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","[","/",")","^","_","`", "a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z" }
  
  local info=""
  local byte=0
  local dram = machine.devices[':lcd:lcdc'].spaces['display']
    for i= st ,en do
      byte=0
      byte=tonumber(dram:read_u8(num2hex(i)))
      if (byte >= 1) and (byte <= 90) then
        info =  info .. alpha[byte]
      elseif (byte == 0) or (byte == 128) then
        info = info .. " "
      elseif (byte >= 129) then
        byte = byte - 128
        if byte <= 90 then
          info =  info .. alpha[byte]
        else
          info=info .. "@->" .. alpha[byte]
        end
      end
    end
  return (info)
end

function num2hex(num)
    local hexstr = '0123456789abcdef'
    local s = ''
    while num > 0 do
        local mod = math.fmod(num, 16)
        s = string.sub(hexstr, mod+1, mod+1) .. s
        num = math.floor(num / 16)
    end
    if s == '' then s = '0' end
    return s
end
 --local byte = dram:read_u8(0x000b)    -- offset from 0x0000 to 0x1fff


function interface.setup_machine()
	sb_reset_board(":smartboard:board")
	emu.wait(2)
  interface.set_notation() -- set long notation anf figures in alphabet
  interface.setlevel()
end

function interface.stop_play()
  send_input(":IN.0", 0x20, 1)
  
end
function interface.analyze()
  send_input(":IN.2", 0x20,0.1) -- Menu 
  send_input(":IN.1", 0x40,0.1) -- Right
  send_input(":IN.3", 0x40,0.1) -- Down
  send_input(":IN.1", 0x40,0.1) -- Right
   send_input(":IN.2", 0x40,0.1) -- up
    send_input(":IN.3", 0x20,0.1) -- Enter
  send_input(":IN.3", 0x40,0.1) -- Down
--  send_input(":IN.3", 0x40,0.1) -- Down
--  send_input(":IN.3", 0x40,0.1) -- Down
--  send_input(":IN.3", 0x40,0.1) -- Down
  send_input(":IN.3", 0x20,0.1) -- Enter
  send_input(":IN.2", 0x20,0.1) -- Menu
end
function interface.start_play(init)
	send_input(":IN.0", 0x20, 0.5)	-- PLAY
end

function interface.is_selected(x, y)
	local led0 = machine:outputs():get_value("led_" .. tostring(8 - y) .. tostring(8 - x)) == 1
	local led1 = machine:outputs():get_value("led_" .. tostring(8 - y) .. tostring(9 - x)) == 1
	local led2 = machine:outputs():get_value("led_" .. tostring(9 - y) .. tostring(8 - x)) == 1
	local led3 = machine:outputs():get_value("led_" .. tostring(9 - y) .. tostring(9 - x)) == 1
	return led0 and led1 and led2 and led3
end

function interface.select_piece(x, y, event)
	sb_select_piece(":smartboard:board", 1, x, y, event)
end

function interface.get_promotion(x, y)
  return string.lower(interface.read_display(772,772))
end

function interface.promote(x, y, piece)
	sb_promote(":smartboard:board", x, y, piece)
	local right = -1
	if     (piece == "q") then	right = 0
	elseif (piece == "r") then	right = 1
	elseif (piece == "b") then	right = 2
	elseif (piece == "n") then	right = 3
	end

	if (right ~= -1) then
		for i=1,right do
			send_input(":IN.1", 0x40, 0.5)	-- RIGHT
		end

		send_input(":IN.3", 0x20, 0.5)	-- ENTER
	end
end

return interface
