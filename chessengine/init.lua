-- license:BSD-3-Clause
-- copyright-holders:Sandro Ronco

local exports = {}
exports.name = "chessengine"
exports.version = "0.0.1"
exports.description = "Chess UCI/XBoard Interface plugin"
exports.license = "The BSD 3-Clause License"
exports.author = { name = "Sandro Ronco" }


-- Time Conrol.
local Zeit=nil
local ZeitDiff=10
local SendStop = false

-- Info Control.
local SendInfo =os.clock() 
local StartRollInfo=false
local EmuspeedFaktor

local Emuspeed=true -- false = unlimited speed


-- Move Info, needed for move back
local Move_Nr=0
local Move_attr={}
local All_Moves=""
local last_move=""
local sensorboard = ""

local Akt_Move="" -- needed for go. (not 'position startpos ..' send sen move to the device. 'go movetime ...' send themoveto the device

local plugin_path = ""
local protocol = ""
local co = nil
local conth = nil
local interface = nil
local board = nil
local game_started = false
local sel_started = false
local piece_get = false
local my_color = "B"
local ply = "W"
local piece_from = nil
local piece_to = nil
local scr = [[
	while true do
		_G.status = io.stdin:read("*line")
		yield()
	end
]]

local function describe_system()
	return manager:machine():system().description --.. " (" .. emu.app_name() .. " " .. emu.app_version() .. ")"
end

local function board_reset()
	game_started = false
	piece_get = false
	sel_started = false
	my_color = "B"
	ply = "W"
	piece_from = nil
	piece_to = nil
  
  -- TimeConrol
  Zeit=nil
  ZeitDiff=10
  SendStop = false

-- Move Info, need it for move back
  Move_Nr=0
  Move_attr={}
  All_Moves=""
  last_move=""
  Akt_Move=""
  
	board = {{ 3, 5, 4, 2, 1, 4, 5, 3 },
		{  6, 6, 6, 6, 6, 6, 6, 6 },
		{  0, 0, 0, 0, 0, 0, 0, 0 },
		{  0, 0, 0, 0, 0, 0, 0, 0 },
		{  0, 0, 0, 0, 0, 0, 0, 0 },
		{  0, 0, 0, 0, 0, 0, 0, 0 },
		{ -6,-6,-6,-6,-6,-6,-6,-6 },
		{ -3,-5,-4,-2,-1,-4,-5,-3 }}

end

local function move_to_pos(move)
	local rows_idx = { a=1, b=2, c=3, d=4, e=5, f=6, g=7, h=8 }
	local x = rows_idx[move:sub(1, 1)]
	local y = tonumber(move:sub(2, 2))
	return {x = x, y = y}
end

local function promote_pawn(pos, piece, promotion)
	local sign = 1
	if board[pos.y][pos.x] < 0 then
		sign = -1
	end

	if     (piece == "q") then	board[pos.y][pos.x] = board[pos.y][pos.x] - (4 * sign)
	elseif (piece == "r") then	board[pos.y][pos.x] = board[pos.y][pos.x] - (3 * sign)
	elseif (piece == "b") then	board[pos.y][pos.x] = board[pos.y][pos.x] - (2 * sign)
	elseif (piece == "n") then	board[pos.y][pos.x] = board[pos.y][pos.x] - (1 * sign)
	end

	if interface.promote then
		emu.wait(0.5)
		if promotion then
			interface.promote(pos.x, pos.y, string.lower(piece))
		else
			interface.promote(pos.x, pos.y, string.upper(piece))
		end
	end
end

local function send_input(tag, mask, seconds,tag1,mask1) -- tag1,mask1 required to push down to keys 
	manager:machine():ioport().ports[tag]:field(mask):set_value(1)
  if tag1 ~=nil then
    manager:machine():ioport().ports[tag1]:field(mask1):set_value(1)
  end
	emu.wait(seconds * 2 / 3)
	manager:machine():ioport().ports[tag]:field(mask):set_value(0)
  if tag1 ~= nil then
    manager:machine():ioport().ports[tag1]:field(mask1):set_value(0)
  end
	emu.wait(seconds * 1 / 3)
end

local function sb_set_ui(tag, mask, state)
	local field = manager:machine():ioport().ports[tag .. ":UI"]:field(mask)
	if (field ~= nil) then
		field:set_value(state)
		emu.wait(0.5)
	end
end

local function sb_press_square(tag, seconds, x, y)
	sb_set_ui(tag, 0x0001, 1)
	send_input(tag .. ":RANK." .. tostring(y), 1 << (x - 1), seconds)
	sb_set_ui(tag, 0x0001, 0)
end

local function sb_promote(tag, x, y, piece)
	local mask = 0
	if     (string.lower(piece) == 'q') then	mask = 0x10
	elseif (string.lower(piece) == 'r') then	mask = 0x08
	elseif (string.lower(piece) == 'b') then	mask = 0x04
	elseif (string.lower(piece) == 'n') then	mask = 0x02
	end

	if board[y][x] < 0 or (board[y][x] == 0 and y == 8) then
		mask = mask << 6
	end

	send_input(tag .. ":SPAWN", mask, 0.5)
	if (manager:machine():outputs():get_value("piece_ui0") ~= 0) then
		sb_set_ui(tag, 0x0002, 1)
		send_input(tag .. ":RANK." .. tostring(y), 1 << (x - 1), 0.5)
		sb_set_ui(tag, 0x0002, 0)
	end
end

local function sb_remove_piece(tag, x, y)
	sb_set_ui(tag, 0x0002, 1)
	send_input(tag .. ":RANK." .. tostring(y), 1 << (x - 1), 0.09)
	sb_set_ui(tag, 0x0002, 0)
	send_input(tag .. ":UI", 0x0008, 0.09)	-- SensorBoard REMOVE
end

local function piece_in_hand(piece)
      if (piece == 2) then send_input(sensorboard .. ":SPAWN", 0x0010,1) --queen
      elseif (piece == 4) then send_input(sensorboard .. ":SPAWN", 0x0004,1) -- bishop
      elseif(piece == 3) then send_input(sensorboard .. ":SPAWN", 0x0008,1) --rook
      elseif (piece == 5)then send_input(sensorboard .. ":SPAWN", 0x0002,1) --knight
      elseif (piece == -2) then send_input(sensorboard .. ":SPAWN", 0x0400,1) --queen
      elseif  (piece == -4) then send_input(sensorboard .. ":SPAWN", 0x0100,1) --bishop
      elseif (piece == -3) then send_input(sensorboard .. ":SPAWN", 0x0200,1) --rook
      elseif (piece == -5) then send_input(sensorboard .. ":SPAWN", 0x0080,1) --knight
      elseif (piece == 6) then send_input(sensorboard .. ":SPAWN", 0x0001,1) --pawn
      elseif (piece == -6) then send_input(sensorboard .. ":SPAWN", 0x0040,1) --pawn
      end
end

local function sb_select_piece(tag, seconds, x, y, event)
	if (event ~= "capture") then
		send_input(tag .. ":RANK." .. tostring(y), 1 << (x - 1), seconds)
	end
	if (event == "en_passant") then
		send_input(tag .. ":UI", 0x0008, seconds)	-- SensorBoard REMOVE
	end
end

local function sb_move_piece(tag, x, y)
	sb_set_ui(tag, 0x0002, 1)
	sb_select_piece(tag, 0.09, x, y, "")
	sb_set_ui(tag, 0x0002, 0)
end

local function sb_reset_board(tag)
  sensorboard=tag
	send_input(tag .. ":UI", 0x0200, 0.09)	-- SensorBoard RESET
end

local function sb_rotate_board(tag)
	sb_set_ui(tag, 0x0002, 1)
	send_input(tag .. ":UI", 0x0200, 0.09)	-- SensorBoard RESET
	sb_set_ui(tag, 0x0002, 0)
end

local function get_piece_id(x, y)
	if (board ~= nil) then
		return board[y][x]
	end
	return 0
end

local function get_move_type(fx, fy, tx, ty)
	if (fy == 1 and fx == 5 and ty == 1 and (tx == 3 or tx == 7) and get_piece_id(fx, fy) == 1) or
	   (fy == 8 and fx == 5 and ty == 8 and (tx == 3 or tx == 7) and get_piece_id(fx, fy) == -1) then
		return "castling"

	elseif (fx ~= tx and fy == 5 and ty == 6 and get_piece_id(fx, fy) == 6 and get_piece_id(tx, ty) == 0) or
	       (fx ~= tx and fy == 4 and ty == 3 and get_piece_id(fx, fy) == -6 and get_piece_id(tx, ty) == 0) then
		return "en_passant"

	elseif (get_piece_id(fx, fy) == 6 and ty == 8) or (get_piece_id(fx, fy) == -6 and ty == 1) then
		if (get_piece_id(tx, ty) ~= 0) then
			return "capture_promotion"
		else
			return "promotion"
		end

	elseif (get_piece_id(tx, ty) ~= 0) then
		return "capture"
	end

	return nil
end

local function recv_cmd()
	if conth.yield then
		return conth.result
	end
	return nil
end

local function send_cmd(cmd)
  if cmd ~= "" then
    io.stdout:write(cmd .. "\n")
    io.stdout:flush()
  end
end

local function round(num)
  local numDecimalPlaces=1
  local mult = 10^(numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function send_move(move)
  manager:machine():video().throttled = false -- speed up the move transfer
  All_Moves=(All_Moves .. " " .. move)
	if (protocol == "xboard") then
		send_cmd("move " .. move)
	elseif (protocol == "uci") then
		send_cmd("bestmove " .. move)
	end
  Zeit=os.clock()
  SendStop=false
  StartRollInfo=false
  manager:machine():video().throttled = Emuspeed
end

local function make_move(move, reason, promotion)
  manager:machine():video().throttled = false
	local from = move_to_pos(move:sub(1, 2))
	local to = move_to_pos(move:sub(3, 4))
  Move_attr[Move_Nr]=board[to.y][to.x]
  Zeit=os.clock()
	if interface.select_piece then
		if not piece_get then
			interface.select_piece(from.x, from.y, "get" .. reason)
			emu.wait(0.5)
		end
    if (move:len() >= 5) then
      if ply~=my_color and interface.promote_special then 
        interface.promote_special(move:sub(move:len())) -- some engine need at promotion the piece between from and to
      end 
    end
		if board[to.y][to.x] ~= 0 then
			interface.select_piece(to.x, to.y, "capture")
		end
		interface.select_piece(to.x, to.y, "put" .. reason)
	end
	piece_get = false
	sel_started = false
	-- castling
	if (board[from.y][from.x] ==  1 and move == "e1g1") then 
    make_move("h1f1", "_castling", false)
    Move_attr[Move_Nr]=11
  elseif (board[from.y][from.x] ==  1 and move == "e1c1") then 
    make_move("a1d1", "_castling", false)
    Move_attr[Move_Nr]=11
  elseif (board[from.y][from.x] == -1 and move == "e8g8") then 
    make_move("h8f8", "_castling", false)
    Move_attr[Move_Nr]=20
  elseif (board[from.y][from.x] == -1 and move == "e8c8") then
    make_move("a8d8", "_castling", false)
    Move_attr[Move_Nr]=21
	else
    	-- next ply
		if (ply == "W") then
			ply = "B"
		else
			ply = "W"
		end
  end

	-- en passant
	if board[to.y][to.x] == 0 and board[from.y][from.x] == -6 and from.y == 4 and to.y == 3 and from.x ~= to.x and board[to.y + 1][to.x] == 6 then
		if interface.select_piece  then
			interface.select_piece(to.x, to.y + 1, "en_passant")
			emu.wait(0.5)
		end
		board[to.y + 1][to.x] = 0
    Move_attr[Move_Nr]=25
	elseif board[to.y][to.x] == 0 and board[from.y][from.x] == 6  and from.y == 5 and to.y == 6 and from.x ~= to.x and board[to.y - 1][to.x] == -6 then
		if interface.select_piece then
			interface.select_piece(to.x, to.y - 1, "en_passant")
			emu.wait(0.5)
		end
		board[to.y - 1][to.x] = 0
    Move_attr[Move_Nr]=26
	end

	board[to.y][to.x] = board[from.y][from.x]
	board[from.y][from.x] = 0

	-- promotion
  
	if (move:len() >= 5) then
    if ply==my_color then promotion=true end
    promote_pawn(to, move:sub(move:len()), promotion)
	end
  
   Zeit=os.clock()
   SendInfo=os.clock()
  manager:machine():video().throttled = Emuspeed
end

local function move_back(move)
  last_move=move
  if interface.go_back then
    interface.go_back()
		local from = move_to_pos(last_move:sub(3, 4))
		local to = move_to_pos(last_move:sub(1, 2))
		local cap =tonumber(last_move:sub(5,6)) 
    interface.select_piece(from.x, from.y, "get")
    emu.wait(0.5)
    interface.select_piece(to.x, to.y, "put")
     board[to.y][to.x] = board[from.y][from.x]
     board[from.y][from.x]=0
     if cap ~= 0 then
       if cap < 10 then
         piece_in_hand(Move_attr[Move_Nr])
        interface.select_piece(from.x, from.y, "put")-- capture move	
         board[from.y][from.x] = cap
       elseif cap == 10 then
         last_move=("f1h1")							
         from = move_to_pos(last_move:sub(1,2))
         to = move_to_pos(last_move:sub(3,4))
        interface.select_piece(from.x, from.y, "get")
        interface.select_piece(to.x, to.y, "put")
         board[to.y][to.x] = board[from.y][from.x]
         board[from.y][from.x]=0
       elseif cap ==11 then						
         last_move=("d1a1")						
         from = move_to_pos(last_move:sub(1,2))
         to = move_to_pos(last_move:sub(3,4))
           interface.select_piece(from.x, from.y, "get")
        interface.select_piece(to.x, to.y, "put")
        board[to.y][to.x] = board[from.y][from.x]
         board[from.y][from.x]=0
       elseif cap ==20 then					
         last_move=("f8h8")						
         from = move_to_pos(last_move:sub(1,2))
         to = move_to_pos(last_move:sub(3,4))
           interface.select_piece(from.x, from.y, "get")
        interface.select_piece(to.x, to.y, "put")
         board[to.y][to.x] = board[from.y][from.x]
         board[from.y][from.x]=0
       elseif cap ==11 then						
         last_move=("d8a8")						
         from = move_to_pos(last_move:sub(1,2))
         to = move_to_pos(last_move:sub(3,4))
          interface.select_piece(from.x, from.y, "get")
        interface.select_piece(to.x, to.y, "put")
         board[to.y][to.x] = board[from.y][from.x]
         board[from.y][from.x]=0
       elseif cap ==26 then								--en passant -6
         piece_in_hand(-6)
       interface.select_piece(from.x, from.y-1, "put")
         board[to.y-1][to.x] = -6
       elseif cap ==25 then								--en passant 6
         piece_in_hand(6)
         interface.select_piece(from.x, from.y+1, "put")
         board[to.y+1][to.x] = 6
       elseif cap ==50 then	-- white promotion
        piece_in_hand(6)
           interface.select_piece(to.x, to.y, "put")
        board[to.y][to.x] =6
       elseif cap ==70 then								-- black promotion
        piece_in_hand(-6)
         interface.select_piece(to.x, to.y, "put")
        board[to.y][to.x] =-6
       elseif cap >50 then
         if cap<65 then							-- white promotion with capture
           piece_in_hand(6)
              interface.select_piece(to.x, to.y, "put")
           piece_in_hand(cap-50)
            interface.select_piece(to.x, to.y, "put")
           board[from.y][from.x]=cap-50
           board[to.y][to.x]=6
         else									-- black promotion with capture
           piece_in_hand(-6)
          interface.select_piece(to.x, to.y, "put")
           piece_in_hand(cap-70)
            interface.select_piece(to.x, to.y, "put")
           board[from.y][from.x]=cap-70
          board[from.y][from.x]=-6
         end
       end
     else
       board[from.y][from.x] = 0
     end
     if (ply == "W") then
       ply = "B"
       my_color="W"
     else
       ply = "W"
       my_color="B"
     end
     last_move=""
     piece_from = nil
     piece_to = nil
     interface.go_back(1) -- required if after move back need the device a key
    end
  end
  
local function search_selected_piece()
  if my_color==ply then
    local active_fpos = 0
    local active_tpos = 0
    local board_sel = {}
    if (interface.is_selected) then
      for y=1,8 do
        for x=1,8 do
          board_sel[y*8 + x] = interface.is_selected(x, y)
          if board_sel[y*8 + x] and ((board[y][x] < 0 and ply == "B") or (board[y][x] > 0 and ply == "W")) then
            piece_from = {x = x, y = y}
            active_fpos = active_fpos + 1
          end
        end
      end
      if (piece_from ~= nil) then
        for y=1,8 do
          for x=1,8 do
            if board_sel[y*8 + x] and (board[y][x] == 0 or (board[y][x] < 0 and ply == "W") or (board[y][x] > 0 and ply == "B")) then
              piece_to = {x = x, y = y}
              active_tpos = active_tpos + 1
            end
          end
        end
      end
    end
	-- If there are more than 2 selections, something is wrong
    if active_tpos > 1 or active_fpos > 1 or (piece_from ~= nil and piece_to ~= nil and piece_from.x == piece_to.x and piece_from.y == piece_to.y) then
      piece_from = nil
      piece_to = nil
    end

	-- in some systems LEDs flash for a bit after the search is completed, wait for 1 second should allow thing to stabilize
    if (not sel_started and (piece_from or piece_to)) then
      sel_started = true
      emu.wait(1)
      piece_from = nil
      piece_to = nil
    end
    if not piece_get and piece_from ~= nil and piece_to == nil then
      SendStop=true
      piece_get = true
      if interface.select_piece then
        interface.select_piece(piece_from.x, piece_from.y, "get")
        emu.wait(0.5)
      end
    end
  end
  if piece_to ~= nil and piece_from ~= nil then
    manager:machine():video().throttled = false
    SendStop=true
    if interface.show_after_move then
      send_cmd("info score bk " .. interface.show_after_move())
    end
    local rows = { "a", "b", "c", "d", "e", "f", "g", "h" }
    local move = rows[piece_from.x] .. tostring(piece_from.y)
    move = move .. rows[piece_to.x] .. tostring(piece_to.y)
    local need_promotion = (piece_to.y == 8 and board[piece_from.y][piece_from.x] == 6) or (piece_to.y == 1 and board[piece_from.y][piece_from.x] == -6)
   
   
  -- promotion
    if (need_promotion) then
      local new_type = "q"	-- default to Queen
      if interface.get_promotion then
        new_type = interface.get_promotion(piece_to.x, piece_to.y)
      end
      if (new_type ~= nil) then
        move = move .. new_type
        need_promotion = false
        send_move(move)
      end
    else
      send_move(move)
    end
    Move_Nr=Move_Nr+1
    make_move(move, "", false)
    -- some machines show the promotion only after the pawn has been moved
    if (need_promotion) then
      local new_type = nil
      if interface.get_promotion then
        new_type = interface.get_promotion(piece_to.x, piece_to.y)
      end
      if (new_type == nil) then
        manager:machine():logerror(manager:machine():system().name .. " Unable to determine the promotion")
        new_type = "q"	-- default to Queen
      end
      promote_pawn(piece_to, new_type, false)
      move = move .. new_type
      send_move(move)
    end
     manager:machine():video().throttled = Emuspeed
  else
    EmuspeedFaktor= (round(tonumber(manager:machine():video():speed_percent()) )) -- read the speed and send it as hashfull
    if Zeit ~= nil and ZeitDiff ~=nil and SendStop == false and ply == my_color then
      local Aktuelle_Zeit = os.clock()
      if (Aktuelle_Zeit - Zeit)>=ZeitDiff then
        if interface.stop_play then
          SendStop=true
          interface.stop_play()
          -- send_cmd("stopped by time control") -- for tests
        elseif interface.start_play then
          SendStop=true
          interface.start_play()
          -- send_cmd("stopped by time control")
        end
      elseif (Aktuelle_Zeit - Zeit) >= 2 and (Aktuelle_Zeit - Zeit) <= (ZeitDiff-2) and piece_to == nil and piece_from == nil and (Aktuelle_Zeit - SendInfo) >=0.75/EmuspeedFaktor then
        if StartRollInfo==false and interface.Start_Roll_Info then --if the device has a rolling info display
          StartRollInfo=true
          interface.Start_Roll_Info()
        end
        if interface.show_info then
          local info=interface.show_info(ply) -- to show the score depth and pv
          if info~="" then
            send_cmd(info .. " hashfull " ..(tostring(EmuspeedFaktor*100)):gsub("%.",""))
          end
       else
         send_cmd("info score cp 000 depth 1 currmovenumber 1 hashfull " .. (tostring(EmuspeedFaktor*100)):gsub("%.",""))
        end
        SendInfo=os.clock()
      end
    end
  end
end
 
local function send_options()
	local tag_default = ""
	local tag_min = " "
	local tag_max = " "

	if (protocol == "uci") then
		tag_default = "default "
		tag_min = " min "
		tag_max = " max "
	end

	for idx,opt in ipairs(interface.get_options()) do
		local opt_data = nil
		if     (#opt == 3 and opt[1] == "string") then    opt_data = tag_default .. tostring(opt[3])
		elseif (#opt == 2 and opt[1] == "button") then    opt_data = ''
		elseif (#opt == 5 and opt[1] == "spin")   then    opt_data = tag_default .. tostring(opt[3]) .. tag_min .. tostring(opt[4]) .. tag_max .. tostring(opt[5])
		elseif (#opt == 3 and opt[1] == "check")  then
			if protocol == "uci" then
				opt_data = tag_default .. tostring(opt[3]:gsub("1", "true"):gsub("0", "false"))
			elseif protocol == "xboard" then
				opt_data = tag_default .. tostring(opt[3])
			end
		elseif (#opt == 4 and opt[1] == "combo")  then
			if protocol == "uci" then
				opt_data = tag_default .. tostring(opt[3]) .. " var " .. tostring(opt[4]):gsub("\t", " var ")
			elseif protocol == "xboard" then
				opt_data = tostring(opt[4]):gsub("%f[%w_]" .. tostring(opt[3]) .. "%f[^%w_]", "*" .. tostring(opt[3])):gsub("\t", " /// ")
			end
		end
		if (opt_data ~= nil) then
			if protocol == "uci" then
				send_cmd('option name ' .. tostring(opt[2])  .. ' type ' .. tostring(opt[1]) .. ' ' .. opt_data)
			elseif protocol == "xboard" then
				send_cmd('feature option="' .. tostring(opt[2])  .. ' -' .. tostring(opt[1]) .. ' ' .. opt_data .. '"')
			end
		else
			manager:machine():logerror("Invalid interface options '" .. tostring(opt[1]) .. " " .. tostring(opt[2]) .. "'")
		end
	end
end

local function set_option(name, value)
	if (name == nil or value == nil) then
		return
	end

	if (string.lower(name) == "speed") then
		if (tonumber(value) == 0) then	-- 0 = unlimited
			manager:machine():video().throttled = false
      manager:machine():video().frameskip=10 -- max. spped
      Emuspeed = false
		else
			manager:machine():video().throttled = true
			manager:machine():video().throttle_rate = tonumber(value) / 100.0
      manager:machine():video().frameskip=9 -- some engine ignore throttle if frameskip =10
      Emuspeed = true
		end
	elseif (interface.set_option) then
		interface.set_option(string.lower(name), value)
	end
end

local function execute_uci_command(cmd)
	if cmd == "uci" then
    send_cmd("\n" .. "id name " .. describe_system())
    math.randomseed(os.time()) 
		protocol = cmd
    local Speed=Emuspeed
    Emuspeed=false
    manager:machine():video().throttle_rate =1
    manager:machine():video().frameskip=10
    manager:machine():video().throttled = false -- quickly setup
    if interface.setup_machine then
      interface.setup_machine()
    end
    	 if interface.get_options then
    		 send_options()
		   end
    board_reset()
		send_cmd("option name Speed type spin default 100 min 0 max 10000")
    manager:machine():video().throttled = Speed
    if Speed==true then manager:machine():video().frameskip=9 end
		send_cmd("uciok")
    Emuspeed=Speed
	elseif cmd == "isready" then
		send_cmd("readyok")
	elseif cmd == "ucinewgame" then
    game_started = false
    manager:machine():video().throttled = false -- quickly setup
    if interface.setup_machine then
      interface.setup_machine()
    end
		board_reset()
    emu.wait(math.random(2,20)/10) -- because some engine plays always the same in Arena Tournament.
    manager:machine():video().throttled = Emuspeed
  elseif cmd == "quit" then
		manager:machine():exit()
	elseif cmd:match("^go") ~= nil then
		if board == nil then
			board_reset()
		end
    if my_color ~= ply then
      if Akt_Move ~="" then
        make_move(Akt_Move, "", true) -- send the move to the device
        Akt_Move=""
        piece_from = nil
        piece_to = nil
        piece_get=nil
        sel_started = false
      else
        Akt_Move=""
        if interface.start_play then
          interface.start_play(not game_started)
        end
        game_started = true
        my_color = ply
      end
    end
    if cmd:match("^go movetime") then -- time per move
      local Diff
      for i in string.gmatch(cmd, "%S+") do
        Diff=i
      end
      ZeitDiff=tonumber(Diff)
      ZeitDiff=ZeitDiff/1000
    elseif cmd:match("go wtime") then -- without movestoge = time for the game 
      local ZeitW=5
      local ZeitS=5
      local Farbe
      local Zugkontrolle=nil
      local BBonus=0
      local WBonus=0
      for i in string.gmatch(cmd, "%S+") do
        if i == "wtime" then 
          Farbe="W"
        elseif i == "movestogo" then -- tournament level
          Farbe = "M"
        elseif i == "btime" then
          Farbe="S"
        elseif i == "winc" then -- bonus time
          Farbe="WINC"
        elseif i == "binc" then 
          Farbe="BINC"
        elseif Farbe == "W" then
          ZeitW=tonumber(i)
          ZeitW=ZeitW/1000
          Farbe=""
        elseif Farbe == "S" then
          ZeitS=tonumber(i)
          ZeitS=ZeitS/1000
          Farbe=""
        elseif Farbe == "WINC" then
          WBonus=tonumber(i)
          WBonus=WBonus/1000
          Farbe=""
        elseif Farbe == "BINC" then
          BBonus=tonumber(i)
          BBonus=BBonus/1000
          Farbe=""
        elseif Farbe == "M" then
          Zugkontrolle=tonumber(i)
          Farbe=""
        
        end
      end
      if my_color=="W" then
        ZeitDiff=ZeitW
      else
        ZeitDiff=ZeitS
      end
    
      if Zugkontrolle~=nil then
        ZeitDiff=ZeitDiff/Zugkontrolle
      else
        if Move_Nr>=140 then
           ZeitDiff=ZeitDiff/(280-Move_Nr)
        else
          ZeitDiff=ZeitDiff/(140-Move_Nr)
        end
      end
        if my_color=="W" then
        ZeitDiff=ZeitDiff+WBonus
      else
        ZeitDiff=ZeitDiff+BBonus
      end
    end
    if ZeitDiff<=4 then ZeitDiff=4 end
     Zeit=os.clock()
    manager:machine():video().throttled = Emuspeed
	elseif cmd:match("^setoption name ") ~= nil then
		local opt_name, opt_val = string.match(cmd:sub(16), '(.+) value (.+)')
		if     (string.lower(opt_val) == "true" ) then opt_val = "1"
		elseif (string.lower(opt_val) == "false") then opt_val = "0"
		end
		set_option(opt_name, opt_val)
	elseif cmd:match("^position startpos moves") ~= nil then
    manager:machine():video().throttled = false
    Akt_Move=""
		game_started = true
    cmd=cmd.gsub(cmd,"position startpos moves","")
    if All_Moves~=cmd then 
      while (string.len(cmd) <= string.len(All_Moves)) -- move back ?
      do
        for i in string.gmatch(All_Moves, "%S+") do
          last_move = i
        end
        All_Moves=All_Moves:sub(1,string.len(All_Moves)-string.len(last_move))
        if All_Moves:sub(string.len(All_Moves),string.len(All_Moves)) ==" " then
          All_Moves=All_Moves:sub(1,string.len(All_Moves)-1)
        end
        if All_Moves=="position startpos moves" then
          All_Moves=""
        end
        last_move=last_move .. Move_attr[Move_Nr]
        move_back(last_move)
        Move_Nr=Move_Nr-1
      end
    
    local ZNR =0
		for i in string.gmatch(cmd, "%S+") do
			last_move = i
      ZNR = ZNR+1
		end
    if (All_Moves == "") and (ZNR >= 2) then -- for move forward
			if interface.player_vs_player_mode then 
				interface.player_vs_player_mode()
        emu.wait(0,5)
				ply="W"
				ZNR=0
				for i in string.gmatch(cmd, "%S+") do
					last_move = i
					ZNR = ZNR + 1
          Move_Nr=Move_Nr+1
          make_move(last_move, "", false)
				end
        if ply=="W" then
          my_color="B"
        else
          my_color="W"
        end
				if interface.player_vs_player_off then
				  interface.player_vs_player_off()
				else
				  interface.player_vs_player_mode()
			  end
				game_started = true 
				piece_from = nil
				piece_to = nil
        All_Moves=cmd
      end
  elseif  (All_Moves) ~= cmd  then
      Move_Nr=Move_Nr+1
      Akt_Move=last_move
       All_Moves=cmd
		end
  end
  manager:machine():video().throttled = Emuspeed
	elseif cmd == "stop" then
		if game_started == true then
			if interface.stop_play then
				interface.stop_play()
			elseif interface.start_play then
				interface.start_play(not game_started)
			end
		end
    elseif cmd:match("^info") ~= nil then -- only for tests
         if interface.show_info then
            send_cmd("white:" .. "\n" .. interface.show_info("W"))
             send_cmd("black:" .. "\n" .. interface.show_info("B"))
          end
	else
		manager:machine():logerror("Unhandled UCI command '" .. cmd .. "'")
	end
end

local function execute_xboard_command(cmd)
	if cmd == "xboard" then
		protocol = cmd
	elseif cmd:match("^protover") then
		send_cmd("feature done=0")
		send_cmd("feature myname=\"" .. describe_system() .. "\" colors=0 usermove=1 sigint=0 sigterm=0")
		send_cmd('feature option="Speed -spin 100 0 10000"')
		if interface.get_options then
			send_options()
		end
		send_cmd("feature done=1")
	elseif cmd == "new" then
		if game_started == true then
			game_started = false
			manager:machine():soft_reset()
		end
		board_reset()
	elseif cmd == "go" then
		if (board == nil) then
			board_reset()
		end
		sel_started = false
		if my_color ~= ply then
      if interface.start_play then
				interface.start_play(not game_started)
      end
			game_started = true
			my_color = ply
		end
	elseif (cmd == "stop") then
		if interface.stop_play and my_color==ply then
			interface.stop_play()
		end
	elseif cmd == "quit" then
		manager:machine():exit()
	elseif cmd:match("^option ") ~= nil then
		local opt_name, opt_val = string.match(cmd:sub(8), '([^=]+)=([^=]+)')
		set_option(opt_name, opt_val)
	elseif cmd:match("^usermove ") ~= nil then
		if board == nil then
			board_reset()
		end
		game_started = true
		make_move(cmd:sub(10), "", true)
		piece_from = nil
		piece_to = nil
		sel_started = false
	else
		manager:machine():logerror("Unhandled xboard command '" .. cmd .. "'")
	end
end

local function update()
	repeat
		local command = recv_cmd()
		if (command ~= nil) then
			if (command == "uci" or command == "xboard") then
				protocol = command
			end

			if protocol == "uci" then
				execute_uci_command(command)
			elseif protocol == "xboard" then
				execute_xboard_command(command)
			end

			conth:continue(conth.result)
			emu.wait(0.1)
		end
	until command == nil

	-- search for a new move
	if ply == my_color then
		search_selected_piece()
	end
end

local function load_interface(name)
	local env = { machine = manager:machine(), send_input = send_input, get_piece_id = get_piece_id, get_move_type = get_move_type, load_interface = load_interface, emu = emu,
			sb_select_piece = sb_select_piece, sb_move_piece = sb_move_piece, sb_press_square = sb_press_square, sb_promote = sb_promote,
			sb_remove_piece = sb_remove_piece, sb_reset_board = sb_reset_board, sb_rotate_board = sb_rotate_board, sb_set_ui = sb_set_ui,
			pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, string = string, math = math, print = _G.print }

	local func = loadfile(plugin_path .. "/interfaces/" .. name .. ".lua", "t", env)
	if func then
		return func()
	end
	return nil
end

function exports.set_folder(path)
	plugin_path = path
end

function exports.startplugin()
	conth = emu.thread()
	conth:start(scr)

	emu.register_periodic(
	function()
		if ((co == nil or coroutine.status(co) == "dead") and not manager:machine().paused) then
			co = coroutine.create(update)
			coroutine.resume(co)
		end
	end)

	emu.register_start(
	function()
		local system = manager:machine():system().name
		if interface == nil then
			interface = load_interface(system)
		end
		if interface == nil and manager:machine():system().parent ~= nil then
			interface = load_interface(manager:machine():system().parent)
		end

		if interface == nil then
			interface = {}
			emu.print_error("Error: missing interface for " .. system)
		end
	end)

	emu.register_stop(
	function()

	end)
end

return exports
