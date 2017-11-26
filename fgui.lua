local utf8 = require "utf8"

local Object = require "lib.classic"

-- Don't really like having this here
local function col_from_hex(s, offset)
	local offset = offset or 0
	local c = {}
	for i=2,8,2 do
		c[i/2] = tonumber(s:sub(i,i+1),16) or 255
	end
	for i=2,6,2 do
		c[i/2] = math.min(255, math.max(0, c[i/2]+offset))
	end
	return c
end

-- The following function is from the penlight text module
function text_wrap (s,width)
    s = s:gsub('\n',' ')
    local i,nxt = 1
    local lines,line = {}
    while i < #s do
        nxt = i+width
        if s:find("[%w']",nxt) then -- inside a word
            nxt = s:find('%W',nxt+1) -- so find word boundary
        end
        line = s:sub(i,nxt)
        i = i + #line
        table.insert(lines,strip(line))
    end
    return makelist(lines)
end

local function in_table(v, t)
	for i,x in pairs(t) do
		if x == v then return true end
	end
end

local function split(s, del)
	t = {}
	local ts = s
	while ts:find(del) do
		local pos = ts:find(del)
		table.insert(t, ts:sub(1,pos))
		ts = ts:sub(pos+1)
	end
	table.insert(t, ts)
	return t
end

local GUI = {}

GUI.items = {}

GUI.Object = Object:extend()
GUI.Object.Top_level_draw = {}
GUI.Object.Lock_click = nil

function GUI.Object:new(options, children)
	self.x = self.x or 0
	self.y = self.y or 0
	self.xoff = self.xoff or 0
	self.yoff = self.yoff or 0
	self.w = self.w or love.graphics.getWidth()
	self.h = self.h or love.graphics.getHeight()
	self.hovered = false
	self.clicked = false
	self.scroll_x = nil
	self.scroll_y = nil

	default_options = {
		align_x = "left",
		align_y = "top",
		padding_x = 0,
		padding_y = 0,
		background_color = "#00000000",
		hover_color = "#00000000",
		click_color = "#00000000",
		border_color = "#00000000",
		border_radius = 0,
		overflow_x = "auto", -- hidden, auto, scroll, resize
		overflow_y = "auto",
		can_hover = false,
		can_click = false
	}

	if self.options then
		for i,v in pairs(self.options) do
			default_options[i] = v
		end
	end
	self.options = default_options

	if options then
		for i,o in pairs(options) do
			self.options[i] = o
		end
	end

	-- This is a stupid, completely absolutely unnecessary statement
	self.parent = self.parent or nil
	if self.children and children then
		for i,v in pairs(children) do
			table.insert(self.children, v)
		end
	else
		self.children = self.children or children or {}
	end
	if children then
		self:updateDimensions()
	end

	for i,v in pairs(self.children) do
		v.parent = self
	end
end

function GUI.Object:getOuterSize()
	return self.w + 2*self.options.padding_x, self.h + 2*self.options.padding_y
end

function GUI.Object:getInnerSize()
	return self.w, self.h
end

function GUI.Object:getClippedSize()
	if self.parent then
		return self.parent:getInnerSize()
	end
	return love.graphics.getDimensions()
end

function GUI.Object:getOuterCoordinates()
	local inner_par_x, inner_par_y
	local inner_par_w, inner_par_h
	if self.parent then
		inner_par_x, inner_par_y = self.super.getInnerCoordinates(self.parent)
		inner_par_w, inner_par_h = self.super.getInnerSize(self.parent)
	else
		inner_par_x, inner_par_y = 0, 0
		inner_par_w, inner_par_h = love.graphics.getDimensions()
	end

	local ret_x, ret_y = inner_par_x + self.x, inner_par_y + self.y

	local outer_w, outer_h = self:getOuterSize()
	if self.options.align_x == "right" then
		ret_x = inner_par_x + inner_par_w - outer_w - self.x
	end
	if self.options.align_y == "bottom" then
		ret_y = inner_par_y + inner_par_h - outer_h - self.y
	end

	return ret_x + self.xoff, ret_y + self.yoff
end

function GUI.Object:getInnerCoordinates()
	local outer_x, outer_y = self:getOuterCoordinates()
	return outer_x + self.options.padding_x, outer_y + self.options.padding_y
end

function GUI.Object:updateDimensions()
	if self.options.overflow_x == "hidden" and self.options.overflow_y == "hidden" then
		return
	end
	-- This is in case there are more subchildren
	for i,v in pairs(self.children) do
		self.updateDimensions(v)
	end

	local inner_x, inner_y = self:getInnerCoordinates()
	local inner_w, inner_h = self:getInnerSize()
	local max_x, max_y = inner_x + inner_w, inner_y + inner_h

	for i,v in pairs(self.children) do
		local c_x, c_y = self.getOuterCoordinates(v)
		local c_w, c_h = self.getOuterSize(v)

		if max_x < c_x + c_w then
			max_x = c_x + c_w
		end
		if max_y < c_y + c_h then
			max_y = c_y + c_h
		end
	end

	if self.options.overflow_x == "resize" then
		self.w = self.w + (max_x - self.w)
	end
	if self.options.overflow_y == "resize" then
		self.h = self.h + (max_y - self.h)
	end
	if self.options.overflow_x == "auto" then
		if max_x ~= inner_x + inner_w then
			self.scroll_x = GUI.Scrollbar("bottom", self, (inner_w)/(max_x-inner_x))
		end
	end
	if self.options.overflow_y == "auto" then
		if max_y ~= inner_y + inner_h then
			self.scroll_y = GUI.Scrollbar("right", self, (inner_h)/(max_y-inner_y))
		end
	end
	if self.scroll_x and self.scroll_y then
		self.scroll_x.fraction = (inner_w-7)/(max_x-inner_x)
		self.scroll_y.fraction = (inner_h-7)/(max_y-inner_y)
	end
end

function GUI.Object:updateChildren(fun)
	-- Update all children and subchildren
	for i,v in pairs(self.children) do
		fun(v)
	end
end

function GUI.Object:getMouseInteraction(condition, mouseDownEvent, hoverEvent, noInteractionEvent)
	if GUI.Object.Lock_click ~= nil and GUI.Object.Lock_click ~= self then
		return
	end

	if not mouseDownEvent then
		mouseDownEvent = function()
			if self.options.can_click then self.clicked = true end
			if self.options.can_hover then self.hovered = false end
		end
	end
	if not hoverEvent then
		hoverEvent = function()
			if self.options.can_hover then self.hovered = true end
			if self.options.can_click then self.clicked = false end
		end
	end
	if not noInteractionEvent then
		noInteractionEvent = function()
			if self.options.can_hover then self.hovered = false end
		end
	end

	if self.options.can_hover or self.options.can_click then
		if condition == nil then
			local mx, my = love.mouse.getPosition()
			local outer_x, outer_y = self:getOuterCoordinates()
			local outer_w, outer_h = self:getOuterSize()
			local clip_w, clip_h = self:getClippedSize()
			condition = (mx > outer_x and mx < outer_x + outer_w and
			my > outer_y and my < outer_y + outer_h and
			mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff)
		end
		if condition then
			if love.mouse.isDown(1) then
				mouseDownEvent()
			else
				hoverEvent()
			end
		else
			noInteractionEvent()
		end
	end
end

function GUI.Object:update(dt)
	for _,v in pairs(self.children) do
		v:update(dt)
	end

	if self.scroll_x then
		self.scroll_x.update(self.scroll_x, dt)
	end
	if self.scroll_y then
		self.scroll_y.update(self.scroll_y, dt)
	end
end

function GUI.Object:draw_background()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local r = self.options.border_radius
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	if self.hovered then
		color_bg = col_from_hex(self.options.hover_color)
	elseif self.clicked then
		color_bg = col_from_hex(self.options.click_color)
	end
	love.graphics.setColor(color_bg)
	love.graphics.rectangle("fill", outer_x, outer_y, outer_w, outer_h, r, r)

	local lw = love.graphics.getLineWidth()
	local color_border = col_from_hex(self.options.border_color)
	love.graphics.setColor(color_border)
	love.graphics.rectangle("line", outer_x+lw, outer_y+lw, outer_w-lw, outer_h-lw, r, r)

	love.graphics.setColor(previous_color)
end

function GUI.Object:set_scissor()
	local inner_x, inner_y = self:getInnerCoordinates()
	local inner_w, inner_h = self:getInnerSize()
	local cur_scissor = {love.graphics.getScissor()}
	local new_scissor = {cur_scissor[1], cur_scissor[2], cur_scissor[3], cur_scissor[4]}
	if in_table(self.options.overflow_x, {"hidden", "auto", "scroll"}) then
		if #cur_scissor > 0 then
			new_scissor[1] = math.min(cur_scissor[1] + cur_scissor[3], math.max(cur_scissor[1], inner_x))
			new_scissor[3] = math.min(cur_scissor[1] + cur_scissor[3], math.max(cur_scissor[1], inner_x + inner_w))
			if new_scissor[3] == inner_x+inner_w then new_scissor[3] = inner_w end
		else
			new_scissor[1] = inner_x
			new_scissor[3] = inner_w
		end
	end

	if in_table(self.options.overflow_y, {"hidden", "auto", "scroll"}) then
		if #cur_scissor > 0 then
			new_scissor[2] = math.min(cur_scissor[2] + cur_scissor[4], math.max(cur_scissor[2], inner_y))
			new_scissor[4] = math.min(cur_scissor[2] + cur_scissor[4], math.max(cur_scissor[2], inner_y + inner_h))
			if new_scissor[4] == inner_y+inner_h then new_scissor[4] = inner_h end
		else
			new_scissor[2] = inner_y
			new_scissor[4] = inner_h
		end
	end

	love.graphics.setScissor(new_scissor[1], new_scissor[2], new_scissor[3], new_scissor[4])

	for _,v in pairs(self.children) do
		v:draw()
	end
	if self.scroll_x then
		self.scroll_x.draw(self.scroll_x)
	end
	if self.scroll_y then
		self.scroll_y.draw(self.scroll_y)
	end

	return cur_scissor
end

function GUI.Object:clear_scissor(prev_scissor)
	love.graphics.setScissor(prev_scissor[1], prev_scissor[2], prev_scissor[3], prev_scissor[4])
end

function GUI.Object:draw()
	self:draw_background()
	local prev_scissor = self:set_scissor()
	self:clear_scissor(prev_scissor)
end

function GUI.Object:mousereleased(x,y,button, f_custom)
	if self.options.can_click then self.clicked = false end
	if self.options.can_hover then self.hovered = false end

	for i,v in pairs(self.children) do
		v:mousereleased(x,y,button)
	end
	if self.scroll_x then
		self.scroll_x.mousereleased(self.scroll_x, x,y,button)
	end
	if self.scroll_y then
		self.scroll_y.mousereleased(self.scroll_y, x,y,button)
	end

	if GUI.Object.Lock_click and GUI.Object.Lock_click == self then
		if f_custom then f_custom(self) end
	end
end

function GUI.Object:mousepressed(x,y,button, f_custom)
	local outer_x, outer_y = self:getOuterCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local clip_w, clip_h = self:getClippedSize()
	if x > outer_x and x < outer_x + outer_w and
		y > outer_y and y < outer_y + outer_h and
		x < outer_x + clip_w - self.xoff and y < outer_y + clip_h - self.yoff then
		GUI.Object.Lock_click = self
	end

	for i,v in pairs(self.children) do
		v:mousepressed(x,y,button)
	end
	if self.scroll_x then
		self.scroll_x.mousepressed(self.scroll_x, x,y,button)
	end
	if self.scroll_y then
		self.scroll_y.mousepressed(self.scroll_y, x,y,button)
	end

	if f_custom then f_custom(self) end
end

function GUI.Object:textinput(t)
	for i,v in pairs(self.children) do
		v:textinput(t)
	end
end

function GUI.Object:keypressed(key)
	for i,v in pairs(self.children) do
		v:keypressed(key)
	end
end

--###############################
--# GUIDILNE TO MAKING AN ELEMENT
--###############################
--
--In the new function, second to last parameter has to be options
--and last parameter children. In the last line, call self.super.new(self,options.children)
--Implement update and draw methods and
--call their respective super methods in the first line,


--###############################
--# SCROLLBAR BEGIN #############
--###############################

GUI.Scrollbar = GUI.Object:extend()

function GUI.Scrollbar:new(position,parent,fraction,options,children)
	self.parent = parent
	local inner_par_x, inner_par_y = self.parent.getInnerCoordinates(self.parent)
	local inner_par_w, inner_par_h = self.parent.getInnerSize(self.parent)
	if position == "bottom" then
		self.x = 0
		self.y = inner_par_h - 7
		self.w = inner_par_w
		self.h = 7
		self.scroll_pos_x = 0
		self.scroll_pos_y = 0
		self.orientation = "horizontal"
	elseif position == "right" then
		self.x = inner_par_w - 7
		self.y = 0
		self.w = 7
		self.h = inner_par_h
		self.orientation = "vertical"
		self.scroll_pos_x = 0
		self.scroll_pos_y = 0
	end
	self.fraction = fraction
	self.clicked_pos_x = -1
	self.clicked_pos_y = -1
	self.previous_pos_x = -1
	self.previous_pos_y = -1

	self.options = {}
	self.options.background_color = "#000000"
	self.options.hover_color = "#3AB0B1"
	self.options.click_color = "#010101"
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.Scrollbar:update(dt)
	-- So annoying, I have to rewrite so many functions :(
	if self.options.can_hover or self.options.can_click then
		local posx, posy, w, h
		local outer_x, outer_y = self.super.getOuterCoordinates(self)
		local mx, my = love.mouse.getPosition()
		local clip_w, clip_h = self:getClippedSize()
		if self.orientation == "horizontal" then
			posx = outer_x + self.scroll_pos_x
			posy = outer_y
			w = self.w * self.fraction
			h = self.h
		elseif self.orientation == "vertical" then
			posx = outer_x
			posy = outer_y + self.scroll_pos_y
			w = self.w
			h = self.h * self.fraction
		end

		local condition = (mx > posx and mx < posx + w and
			my > posy and my < posy + h and
			mx < posx + clip_w and my < posy + clip_h)
		self.super.getMouseInteraction(self,condition)

		if self.clicked then
			if self.orientation == "horizontal" then
				self.scroll_pos_x = math.min(self.w-w,math.max(0, self.previous_pos_x + mx - self.clicked_pos_x))
				self.parent.updateChildren(self.parent, function(v)
					v.xoff = -self.scroll_pos_x/self.fraction
				end)
			elseif self.orientation == "vertical" then
				self.scroll_pos_y = math.min(self.h-h,math.max(0, self.previous_pos_y + my - self.clicked_pos_y))
				self.parent.updateChildren(self.parent, function(v)
					v.yoff = -self.scroll_pos_y/self.fraction
				end)
			end
		end
	end
end

function GUI.Scrollbar:draw()
	-- In this case, don't draw a background box
	--self.super.draw(self)

	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local r = self.options.border_radius
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	if self.hovered then
		color_bg = col_from_hex(self.options.hover_color)
	elseif self.clicked then
		color_bg = col_from_hex(self.options.click_color)
	end
	love.graphics.setColor(color_bg)
	local posx, posy, w, h
	if self.orientation == "horizontal" then
		posx = outer_x + self.scroll_pos_x
		posy = outer_y
		w = self.w * self.fraction
		h = self.h
	elseif self.orientation == "vertical" then
		posx = outer_x
		posy = outer_y + self.scroll_pos_y
		w = self.w
		h = self.h * self.fraction
	end
	love.graphics.rectangle("fill", posx, posy, w, h)

	love.graphics.setColor(previous_color)
end

function GUI.Scrollbar:mousepressed(x,y,button)
	self.super.mousepressed(self,x,y,button,
	function(self)
		if button == 1 then
			local posx, posy, w, h
			local outer_x, outer_y = self.super.getOuterCoordinates(self)
			if self.orientation == "horizontal" then
				posx = outer_x + self.scroll_pos_x
				posy = outer_y
				w = self.w * self.fraction
				h = self.h
			elseif self.orientation == "vertical" then
				posx = outer_x
				posy = outer_y + self.scroll_pos_y
				w = self.w
				h = self.h * self.fraction
			end

			if x > posx and x < posx + w and
				y > posy and y < posy + h then
				self.clicked_pos_x = x
				self.clicked_pos_y = y

				self.previous_pos_x = self.scroll_pos_x
				self.previous_pos_y = self.scroll_pos_y
			end
		end
	end)
end
--###############################
--# SCROLLBAR END ###############
--###############################

--###############################
--# BOX BEGIN ###################
--###############################

GUI.Box = GUI.Object:extend()

function GUI.Box:new(x,y,w,h,options,children)
	self.x = x
	self.y = y
	self.w = w
	self.h = h

	self.super.new(self,options,children)
end

function GUI.Box:update(dt)
	self.super.update(self,dt)
	self.super.getMouseInteraction(self)
end

function GUI.Box:draw()
	self.super.draw(self)
end
--###############################
--# BOX END #####################
--###############################

--###############################
--# LABEL BEGIN #################
--###############################

GUI.Label = GUI.Object:extend()

function GUI.Label:new(t,x,y,options,children)
	self.t = t
	self.x = x
	self.y = y

	font = love.graphics.getFont()
	self.w = font:getWidth(t)
	self.h = font:getHeight(t)

	self.wrapx = 1000000000

	self.super.new(self,options,children)
end

function GUI.Label:update(dt)
	self.super.update(self,dt)
	self.super.getMouseInteraction(self)
	local font = love.graphics.getFont()
	if self.wrapx > 0 then
		local width, wrapped_text = font:getWrap(self.t, self.wrapx)
		self.w = width
		self.h = font:getHeight() * #wrapped_text
	else
		self.w = font:getWidth(self.t)
		self.h = font:getHeight(self.t)
	end
end

function GUI.Label:draw()
	self.super.draw(self)
	local xoff, yoff = self.super.getInnerCoordinates(self)

	love.graphics.printf(self.t, xoff, yoff, self.wrapx)
end


--###############################
--# LABEL END ###################
--###############################

--###############################
--# INPUT BEGIN #################
--###############################

GUI.Input = GUI.Object:extend()

function GUI.Input:new(t,x,y,w,h,cb,options,children)
	self.t = t
	self.cb = cb
	self.x = x
	self.y = y

	self.w = w
	self.h = h

	children = children or {}
	table.insert(children, 1, GUI.Label(self.t,0,0))
	children[1].wrapx = self.w

	-- Just some defaults for the button
	self.options = {}
	self.options.padding_x = 5
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true
	self.options.overflow_x = "auto"
	self.options.overflow_y = "auto"

	self.super.new(self,options,children)
end

function GUI.Input:update(dt)
	self.super.update(self,dt)
	self.super.getMouseInteraction(self)
end

function GUI.Input:draw()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local inner_w, inner_h = self:getInnerSize()
	local r = self.options.border_radius
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	love.graphics.setColor(color_bg)
	love.graphics.rectangle("fill", outer_x, outer_y, outer_w, outer_h, r, r)

	local lw = love.graphics.getLineWidth()
	local color_border = col_from_hex(self.options.border_color)
	love.graphics.setColor(color_border)
	love.graphics.rectangle("line", outer_x+lw, outer_y+lw, outer_w-lw, outer_h-lw, r, r)

	if self.hovered then
		color_bg = col_from_hex(self.options.hover_color)
	elseif self.clicked then
		color_bg = col_from_hex(self.options.click_color)
	end
	love.graphics.setColor(color_bg)

	love.graphics.rectangle("fill", inner_x, inner_y, inner_w, inner_h, r, r)
	love.graphics.setColor(255,255,255,255)

	local prev_scissor = self.super.set_scissor(self)
	local label = self.children[1]
	local font = love.graphics.getFont()
	local width, wrappedtext = font:getWrap(label.t, inner_w)

	if self.active then
		local cursor_x, cursor_y = inner_x+1, inner_y
		local last_line_len = font:getWidth(wrappedtext[#wrappedtext])
		local num_breaks = #wrappedtext-1
		local line_height = font:getHeight()
		if label.t:sub(-1) == "\n" then
			last_line_len = 0
			num_breaks = num_breaks + 1
		end

		love.graphics.line(cursor_x + last_line_len, cursor_y + line_height * num_breaks, cursor_x + last_line_len, cursor_y + line_height * (num_breaks+1))
	end

	love.graphics.setColor(previous_color)
	self.super.clear_scissor(self, prev_scissor)
end

function GUI.Input:mousereleased(x,y,button)
	self.super.mousereleased(self,x,y,button,
	function(self)
		self.active = false

		if button == 1 then
			local mx, my = love.mouse.getPosition()
			local outer_x, outer_y = self:getOuterCoordinates()
			local outer_w, outer_h = self:getOuterSize()
			local clip_w, clip_h = self:getClippedSize()
			if mx > outer_x and mx < outer_x + outer_w and
				my > outer_y and my < outer_y + outer_h and
				mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff then
				self.active = true
			end
			self.clicked = false
			self.hovered = false
		end

		if self.active then
			love.keyboard.setKeyRepeat(true)
		else
			love.keyboard.setKeyRepeat(false)
		end
	end)
end

function GUI.Input:textinput(t)
	self.super.textinput(self,t)
	local label = self.children[1]
	if self.active then
		label.t = label.t .. t
		self.super.updateDimensions(self)
		self.cb(label.t)
	end
end

function GUI.Input:keypressed(key)
	self.super.keypressed(self,key)
	local label = self.children[1]

	if self.active then
		if key == "backspace" then
			local byteoffset = utf8.offset(label.t, -1)
			if byteoffset then
				label.t = label.t:sub(1, byteoffset - 1)
				self.super.updateDimensions(self)
				self.cb(label.t)
			end
		end
		if key == "return" then
			label.t = label.t .. "\n"
			self.super.updateDimensions(self)
			self.cb(label.t)
		end
	end
end

--###############################
--# INPUT END ###################
--###############################

--###############################
--# BUTTON BEGIN ################
--###############################

GUI.Button = GUI.Object:extend()

function GUI.Button:new(t,x,y,cb,options,children)
	self.t = t
	self.cb = cb
	self.x = x
	self.y = y

	font = love.graphics.getFont()
	self.w = font:getWidth(t)
	self.h = font:getHeight(t)

	-- Just some defaults for the button
	self.options = {}
	self.options.padding_x = 10
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.Button:update(dt)
	self.super.update(self,dt)
	self.super.getMouseInteraction(self)
end

function GUI.Button:draw()
	self.super.draw(self)
	local xoff, yoff = self.super.getInnerCoordinates(self)

	love.graphics.print(self.t, xoff, yoff)
end

function GUI.Button:mousereleased(x,y,button)
	self.super.mousereleased(self,x,y,button,
	function(self)
		if button == 1 then
			local mx, my = love.mouse.getPosition()
			local outer_x, outer_y = self:getOuterCoordinates()
			local outer_w, outer_h = self:getOuterSize()
			local clip_w, clip_h = self:getClippedSize()
			if mx > outer_x and mx < outer_x + outer_w and
				my > outer_y and my < outer_y + outer_h and
				mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff then
				self.cb()
			end
			self.clicked = false
			self.hovered = false
		end
	end)
end

--###############################
--# BUTTON END ##################
--###############################

--###############################
--# CHECKBOX BEGIN ##############
--###############################

GUI.Checkbox = GUI.Object:extend()

function GUI.Checkbox:new(x,y,active,cb,options,children)
	self.cb = cb
	self.x = x
	self.y = y
	self.active = active

	self.w = 10
	self.h = 10

	-- Just some defaults for the checkbox
	self.options = {}
	self.options.padding_x = 5
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.Checkbox:update(dt)
	self.super.update(self,dt)
	self.super.getMouseInteraction(self)
end

function GUI.Checkbox:draw()
	self.super.draw(self)

	-- Draw the cross
	if self.active then
		local inner_x, inner_y = self:getInnerCoordinates()
		local inner_w, inner_h = self:getInnerSize()

		local cur_color = {love.graphics.getColor()}
		love.graphics.setColor(255,255,255,255)
		love.graphics.line(inner_x, inner_y, inner_x+inner_w, inner_y+inner_h)
		love.graphics.line(inner_x, inner_y+inner_h, inner_x+inner_w, inner_y)
		love.graphics.setColor(cur_color)
	end
end

function GUI.Checkbox:mousereleased(x,y,button)
	self.super.mousereleased(self,x,y,button,
	function(self)
		if button == 1 then
			local mx, my = love.mouse.getPosition()
			local outer_x, outer_y = self:getOuterCoordinates()
			local outer_w, outer_h = self:getOuterSize()
			local clip_w, clip_h = self:getClippedSize()
			if mx > outer_x and mx < outer_x + outer_w and
				my > outer_y and my < outer_y + outer_h and
				mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff then
				self.active = not self.active
				self.cb(self.active)
			end
			self.clicked = false
			self.hovered = false
		end
	end)
end

--###############################
--# CHECKBOX END ################
--###############################

--###############################
--# Radiobutton BEGIN ###########
--###############################

GUI.Radiobutton = GUI.Object:extend()

function GUI.Radiobutton:new(x,y,items,active_item,cb,options,children)
	self.cb = cb
	self.x = x
	self.y = y
	self.items = items
	self.active_item = active_item
	self.hovered_item = -1
	self.clicked_item = -1

	local max_w = 0
	local font = love.graphics.getFont()
	for i,v in pairs(items) do
		local w = font:getWidth(v)
		if w > max_w then max_w = w end
	end
	self.w = 10 + max_w
	self.h = 20*#items-6 -- 6 is 20-7*2 (7 is the radius) (we have to subtract the spacing from the last element)

	-- Just some defaults for the checkbox
	self.options = {}
	self.options.padding_x = 5
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.Radiobutton:update(dt)
	local mx, my = love.mouse.getPosition()
	local inner_x, inner_y = self:getOuterCoordinates()
	local inner_w, inner_h = self:getOuterSize()

	self.super.getMouseInteraction(self, nil,
	function()
		for i,v in pairs(self.items) do
			if mx > inner_x and mx < inner_x + inner_w and
				my > inner_y + 20*(i-1) and my < inner_y + 20*i then
				self.clicked_item = i
				self.hovered = false
				self.hovered_item = -1
			end
		end
	end,
	function()
		for i,v in pairs(self.items) do
			if mx > inner_x and mx < inner_x + inner_w and
				my > inner_y + 20*(i-1) and my < inner_y + 20*i then
				self.hovered_item = i
				self.clicked = false
				self.clicked_item = -1
			end
		end
	end,
	function()
		self.hovered = false
		self.hovered_item = -1
	end)
end

function GUI.Radiobutton:draw()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	local color_hover = col_from_hex(self.options.hover_color)
	local color_active = col_from_hex(self.options.hover_color, -80)
	local color_click = col_from_hex(self.options.click_color)

	love.graphics.setColor(color_bg)
	local r = 7
	for i,v in pairs(self.items) do
		love.graphics.print(v, inner_x + 20, inner_y + 20*(i-1))
		if self.hovered_item == i then
			love.graphics.setColor(color_hover)
		elseif self.clicked_item == i then
			love.graphics.setColor(color_click)
		end
		love.graphics.circle("fill", inner_x + r, inner_y + r + 20*(i-1), r)
		if i == self.active_item then
			love.graphics.setColor(color_active)
			love.graphics.circle("fill", inner_x + r, inner_y + r + 20*(i-1), 4)
		end
		love.graphics.setColor(color_bg)
	end

	love.graphics.setColor(previous_color)
end

function GUI.Radiobutton:mousereleased(x,y,button)
	self.super.mousereleased(self,x,y,button,
	function(self)
		if button == 1 then
			local mx, my = love.mouse.getPosition()
			local outer_x, outer_y = self:getOuterCoordinates()
			local inner_x, inner_y = self:getOuterCoordinates()
			local outer_w, outer_h = self:getOuterSize()
			local inner_w, inner_h = self:getOuterSize()
			local clip_w, clip_h = self:getClippedSize()
			if mx > outer_x and mx < outer_x + outer_w and
				my > outer_y and my < outer_y + outer_h and
				mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff then

				for i,v in pairs(self.items) do
					if mx > inner_x and mx < inner_x + inner_w and
						my > inner_y + 20*(i-1) and my < inner_y + 20*i then
						self.active_item = i
						self.cb(i,v)
					end
				end
			end
			self.hovered = false
			self.hovered_item = -1
			self.clicked = false
			self.clicked_item = -1
		end
	end)
end

--###############################
--# Radiobutton END #############
--###############################

--###############################
--# Imagelist BEGIN #############
--###############################

GUI.Imagelist = GUI.Object:extend()

function GUI.Imagelist:new(x,y,w,h,items,cb,options,children)
	self.cb = cb
	self.x = x
	self.y = y
	self.items = items
	self.image_items = {}
	self.active_item = active_item
	self.hovered_item = -1
	self.clicked_item = -1

	for i,v in pairs(items) do
		self.image_items[i] = love.graphics.newImage(v)
	end
	self.w = w
	self.h = h*#items

	-- Just some defaults for the Imagelist
	self.options = {}
	self.options.padding_x = 5
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.Imagelist:update(dt)
	local mx, my = love.mouse.getPosition()
	local inner_x, inner_y = self:getOuterCoordinates()
	local inner_w, inner_h = self:getOuterSize()
	local outer_w, outer_h = self:getOuterSize()

	local item_height = outer_h/#self.items

	self.super.getMouseInteraction(self, nil,
	function()
		for i,v in pairs(self.items) do
			if mx > inner_x and mx < inner_x + inner_w and
				my > inner_y + item_height*(i-1) and my < inner_y + item_height*i then
				self.clicked_item = i
				self.hovered = false
				self.hovered_item = -1
			end
		end
	end,
	function()
		for i,v in pairs(self.items) do
			if mx > inner_x and mx < inner_x + inner_w and
				my > inner_y + item_height*(i-1) and my < inner_y + item_height*i then
				self.hovered_item = i
				self.clicked = false
				self.clicked_item = -1
			end
		end
	end,
	function()
		self.hovered = false
		self.hovered_item = -1
	end)
end

function GUI.Imagelist:draw()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local inner_w, inner_h = self:getInnerSize()
	local outer_w, outer_h = self:getOuterSize()
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	local color_bg_darker = col_from_hex(self.options.background_color,-40)
	local color_hover = col_from_hex(self.options.hover_color)
	local color_active = col_from_hex(self.options.hover_color, -80)
	local color_click = col_from_hex(self.options.click_color)

	local item_height = inner_h/#self.items

	love.graphics.setColor(color_bg)
	for i,v in pairs(self.items) do
		if self.hovered_item == i then
			love.graphics.setColor(color_hover)
		elseif self.clicked_item == i then
			love.graphics.setColor(color_click)
		end
		love.graphics.rectangle("fill", inner_x, inner_y + item_height*(i-1), inner_w, inner_h)
		if i == self.active_item then
			love.graphics.setColor(color_active)
			love.graphics.rectangle("fill", inner_x, inner_y + item_height*(i-1), inner_w, inner_h)
		end
		love.graphics.setColor(color_bg_darker)
		love.graphics.line(inner_x+1, inner_y+item_height*i, inner_x+inner_w, inner_y+item_height*i)

		love.graphics.setColor(255,255,255,255)
		local imx, imy = self.image_items[i]:getWidth(), self.image_items[i]:getHeight()
		local scale_factor
		-- scale images according to padding
		local imsize = (inner_h/#self.items - 2*self.options.padding_y)
		local yoff = 0
		if imx >= imy then
			scale_factor = imsize/imx
			yoff = imsize - imy*scale_factor
		else
			scale_factor = imsize/imy
		end
		love.graphics.draw(self.image_items[i],inner_x,inner_y+yoff/2+item_height*(i-1),0,scale_factor,scale_factor)

		local nameheight = love.graphics.getFont():getHeight(v)
		local name = v:sub(v:len() - (v:reverse():find("/") or v:len() + 2) + 2, -1)
		love.graphics.print(name, inner_x+imsize+10, inner_y + item_height*(i-1)+imsize/2-nameheight/2)

		love.graphics.setColor(color_bg)
	end

	love.graphics.setColor(previous_color)
end

function GUI.Imagelist:mousereleased(x,y,button)
	self.super.mousereleased(self,x,y,button,
	function(self)
		if button == 1 then
			local mx, my = love.mouse.getPosition()
			local outer_x, outer_y = self:getOuterCoordinates()
			local inner_x, inner_y = self:getOuterCoordinates()
			local outer_w, outer_h = self:getOuterSize()
			local inner_w, inner_h = self:getOuterSize()
			local clip_w, clip_h = self:getClippedSize()

			local item_height = outer_h/#self.items

			if mx > outer_x and mx < outer_x + outer_w and
				my > outer_y and my < outer_y + outer_h and
				mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff then

				for i,v in pairs(self.items) do
					if mx > inner_x and mx < inner_x + inner_w and
						my > inner_y + item_height*(i-1) and my < inner_y + item_height*i then
						self.active_item = i
						self.cb(i,v,self.image_items[i])
					end
				end
			end
			self.hovered = false
			self.hovered_item = -1
			self.clicked = false
			self.clicked_item = -1
		end
	end)
end

--###############################
--# Imagelist END ###############
--###############################

--###############################
--# VSlider BEGIN ###############
--###############################

GUI.VSlider = GUI.Object:extend()

function GUI.VSlider:new(x,y,w,h,min,max,value,cb,options,children)
	self.cb = cb
	-- Call the callback once in the beginning! (So if you set a value to the sliders value, it gets set right off the bat!)
	self.cb(value)
	self.x = x
	self.y = y
	self.w = w
	self.h = h
	self.min = min
	self.max = max
	self.value = math.min(max, math.max(min, value))

	self.clicked_pos_x = -1
	self.clicked_pos_y = -1

	-- Just some defaults for the slider
	self.options = {}
	self.options.padding_x = 5
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.VSlider:update(dt)
	local mx, my = love.mouse.getPosition()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local inner_w, inner_h = self:getInnerSize()
	local clip_w, clip_h = self:getClippedSize()

	local offset = (self.max-self.value)/(self.max-self.min)*inner_h

	local condition = (mx > outer_x and mx < outer_x + outer_w and
		my > inner_y+offset-3 and my < inner_y+offset+3 and
		mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff)
	self.super.getMouseInteraction(self, condition)

	if self.clicked then
		-- See equation above for offset. We solve this for self.value, and get the value depending on the offset
		local offset = my - inner_y
		self.value = -offset/inner_h*(self.max-self.min)+self.max
		self.value = math.min(self.max, math.max(self.min, self.value))

		self.cb(self.value)
	end
end

function GUI.VSlider:draw()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local inner_w, inner_h = self:getInnerSize()
	local r = self.options.border_radius
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	local color_back_rectangle = col_from_hex(self.options.background_color, -20)
	-- Draw a rectangle according to inner size
	love.graphics.setColor(color_back_rectangle)
	love.graphics.rectangle("fill", inner_x, inner_y, inner_w, inner_h, r ,r)

	love.graphics.setColor(0,0,0,255)
	local font = love.graphics.getFont()
	-- Getting all the numbers, just to get the general height
	local yoff = font:getHeight("1234567890")
	love.graphics.print(""..self.max, inner_x + inner_w + 8, inner_y-yoff/2)
	love.graphics.print(""..self.min, inner_x + inner_w + 8, inner_y + inner_h-yoff/2)

	-- Draw the rectangle that indicates the current position
	if self.hovered then
		color_bg = col_from_hex(self.options.hover_color)
	elseif self.clicked then
		color_bg = col_from_hex(self.options.click_color)
	end
	love.graphics.setColor(color_bg)
	local offset = (self.max-self.value)/(self.max-self.min)*inner_h
	love.graphics.rectangle("fill", outer_x, inner_y+offset -3, outer_w, 6, r, r)

	love.graphics.setColor(previous_color)
end

--###############################
--# VSlider END #################
--###############################

--###############################
--# HSlider BEGIN ###############
--###############################

GUI.HSlider = GUI.Object:extend()

function GUI.HSlider:new(x,y,w,h,min,max,value,cb,options,children)
	self.cb = cb
	-- Call the callback once in the beginning! (So if you set a value to the sliders value, it gets set right off the bat!)
	self.cb(value)
	self.x = x
	self.y = y
	self.w = w
	self.h = h
	self.min = min
	self.max = max
	self.value = math.min(max, math.max(min, value))

	self.clicked_pos_x = -1
	self.clicked_pos_y = -1

	-- Just some defaults for the slider
	self.options = {}
	self.options.padding_x = 5
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.HSlider:update(dt)
	local mx, my = love.mouse.getPosition()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local inner_w, inner_h = self:getInnerSize()
	local clip_w, clip_h = self:getClippedSize()

	local offset = (self.max-self.value)/(self.max-self.min)*inner_w
	-- This does the mouse interaction and is the way it should be implemented everywhere!
	local condition = (mx > inner_x+offset-3 and mx < inner_x+offset+3 and
		my > outer_y and my < outer_y + outer_h and
		mx < outer_x + clip_w - self.xoff and my < outer_y + clip_h - self.yoff)
	self.super.getMouseInteraction(self, condition)

	if self.clicked then
		-- See equation above for offset. We solve this for self.value, and get the value depending on the offset
		local offset = mx - inner_x
		self.value = -offset/inner_w*(self.max-self.min)+self.max
		self.value = math.min(self.max, math.max(self.min, self.value))

		self.cb(self.value)
	end
end

function GUI.HSlider:draw()
	local outer_x, outer_y = self:getOuterCoordinates()
	local inner_x, inner_y = self:getInnerCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local inner_w, inner_h = self:getInnerSize()
	local r = self.options.border_radius
	local previous_color = {love.graphics.getColor()}

	local color_bg = col_from_hex(self.options.background_color)
	local color_back_rectangle = col_from_hex(self.options.background_color, -20)
	-- Draw a rectangle according to inner size
	love.graphics.setColor(color_back_rectangle)
	love.graphics.rectangle("fill", inner_x, inner_y, inner_w, inner_h, r ,r)

	love.graphics.setColor(0,0,0,255)
	local font = love.graphics.getFont()
	-- Getting all the numbers, just to get the general height
	local xoff_min = font:getWidth(self.min)
	local xoff_max = font:getWidth(self.max)
	love.graphics.print(""..self.min, inner_x - xoff_min/2, inner_y-20)
	love.graphics.print(""..self.min, inner_x + inner_w - xoff_min/2, inner_y-20)

	-- Draw the rectangle that indicates the current position
	if self.hovered then
		color_bg = col_from_hex(self.options.hover_color)
	elseif self.clicked then
		color_bg = col_from_hex(self.options.click_color)
	end
	love.graphics.setColor(color_bg)
	local offset = (self.max-self.value)/(self.max-self.min)*inner_w
	love.graphics.rectangle("fill", inner_x+offset-3, outer_y, 6, outer_h, r, r)

	love.graphics.setColor(previous_color)
end

--###############################
--# HSlider END #################
--###############################

--###############################
--# DROPDOWN BEGIN ##############
--###############################

GUI.Dropdown = GUI.Object:extend()

function GUI.Dropdown:new(t,x,y,items,cb,options,children)
	self.t = t
	self.x = x
	self.y = y
	self.items = items
	self.selected = nil
	self.state = 0 -- if the menu items are visible or not
	self.cb = cb -- The callback is called, when an item is clicked ("switched"). The parameters of the callback are index and value of the item (according to the listing in items)

	font = love.graphics.getFont()
	self.w = font:getWidth(t) + 30
	self.h = font:getHeight(t)

	-- Just some defaults for the dropdown
	self.options = {}
	self.options.padding_x = 10
	self.options.padding_y = 5
	self.options.background_color = "#252525"
	self.options.hover_color = "#8CD0D3"
	self.options.click_color = "#131313"
	self.options.border_radius = 2
	self.options.can_hover = true
	self.options.can_click = true

	self.super.new(self,options,children)
end

function GUI.Dropdown:update(dt)
	self.super.update(self,dt)
	self.super.getMouseInteraction(self)
end

function GUI.Dropdown:draw()
	self.super.draw(self)
	local xoff, yoff = self.super.getInnerCoordinates(self)
	local outer_x, outer_y = self.super.getOuterCoordinates(self)

	local text = self.selected or self.t
	love.graphics.print(text, xoff, yoff)
	local c = {love.graphics.getColor()}
	local lw = love.graphics.getLineWidth()
	local inner_w, inner_h = self.super.getInnerSize(self)
	local outer_w, outer_h = self.super.getOuterSize(self)

	love.graphics.setColor(255,255,255,30)
	love.graphics.setLineWidth(1)
	love.graphics.line(xoff + inner_w - 20, yoff, xoff + inner_w - 20, yoff + inner_h)
	love.graphics.polygon("fill", xoff+inner_w - 12, yoff+1, xoff+inner_w, yoff+1, xoff+inner_w-6, yoff+inner_h-1)

	function dropdown_menu()
		if self.state == 1 then
			local color_bg = col_from_hex(self.options.background_color)
			love.graphics.setColor(color_bg)
			love.graphics.rectangle("fill", outer_x, outer_y + outer_h, outer_w, #self.items*20)
			for i,v in pairs(self.items) do
				local mx, my = love.mouse.getPosition()
				local x1,y1 = outer_x, outer_y + outer_h + 20*(i-1)
				local x2,y2 = x1 + outer_w, y1 + 20
				local clip_w, clip_h = self:getClippedSize()
				if mx > x1 and mx < x2 and
					my > y1 and my < y2 and
					mx < x1 + clip_w and my < y1 + clip_h then
					local color_hover = col_from_hex(self.options.hover_color)
					love.graphics.setColor(color_hover)
					love.graphics.rectangle("fill", x1,y1,x2-x1,y2-y1)
				end

				local font = love.graphics.getFont()
				local w,h = font:getWidth(v), font:getHeight(v)
				love.graphics.setColor(255,255,255,255)
				love.graphics.print(v,x1+10,y1+10 - h/2)
			end
		end
	end

	table.insert(GUI.Object.Top_level_draw, dropdown_menu)


	love.graphics.setColor(c)
	love.graphics.setLineWidth(lw)
end

function GUI.Dropdown:toggle(state)
	if not state then state = (self.state+1)%2 end
	self.state = state
end

function GUI.Dropdown:mousereleased(x,y,button)
	local outer_x, outer_y = self:getOuterCoordinates()
	local outer_w, outer_h = self:getOuterSize()
	local clip_w, clip_h = self:getClippedSize()

	self.super.mousereleased(self,x,y,button,
	function(self)
		if x > outer_x and x < outer_x + outer_w and
			y > outer_y and y < outer_y + outer_h and
			x < outer_x + clip_w - self.xoff and y < outer_y + clip_h - self.yoff then
			self:toggle()
		else
			self:toggle(0)
		end

		self.clicked = false
		self.hovered = false
	end)

	if button == 1 then
		-- Get the clicked item
		if self.state == 1 then
			for i,v in pairs(self.items) do
				local x1,y1 = outer_x, outer_y + outer_h + 20*(i-1)
				local x2,y2 = x1 + outer_w, y1 + 20
				local clip_w, clip_h = self:getClippedSize()
				if x > x1 and x < x2 and
					y > y1 and y < y2 and
					x < x1 + clip_w and y < y1 + clip_h then
					self.selected = v
					self.cb(i,v)
					self:toggle(0)
				end
			end
		end
	end
end

--###############################
--# DROPDOWN END ################
--###############################


function GUI.build(...)
	local item = GUI.Object({}, {...})
	table.insert(GUI.items, item)
end


function GUI.update(dt)
	-- The user can define multiple GUI "views" (a group of elements, that the user can hide and show at will)
	for _,gui_table in pairs(GUI.items) do
		gui_table:update(dt)
	end
end

function GUI.draw()
	for _,gui_table in pairs(GUI.items) do
		gui_table:draw()
	end
	for _,draw_f in pairs(GUI.Object.Top_level_draw) do
		draw_f()
	end
	GUI.Object.Top_level_draw = {}
end

function GUI.mousereleased(x,y,button)
	for _,gui_table in pairs(GUI.items) do
		gui_table:mousereleased(x,y,button)
	end

	GUI.Object.Lock_click = nil
end

function GUI.mousepressed(x,y,button)
	for _,gui_table in pairs(GUI.items) do
		gui_table:mousepressed(x,y,button)
	end
end

function GUI.textinput(t)
	for _,gui_table in pairs(GUI.items) do
		gui_table:textinput(t)
	end
end

function GUI.keypressed(key)
	for _,gui_table in pairs(GUI.items) do
		gui_table:keypressed(key)
	end
end

return GUI
