local GUI = require "fgui"

function love.load()
	local files = love.filesystem.getDirectoryItems("img/")
	for i,v in pairs(files) do
		files[i] = "img/" .. files[i]
	end

	local left_gui = GUI.build(
		GUI.Box(100,100,200,400, {background_color = "#abc123", padding_x = 10, padding_y = 10, overflow_x = "auto"}, {
			GUI.Dropdown("Select item...",0,0,{"a","b","c"},function(i,v) print(i,v) end,{}),
			GUI.Button("generic button",0,40,function() print("ok") end),
			GUI.Checkbox(0,80,false,function(b) print(b) end),
			GUI.VSlider(0,110,10,100,30,90,30,function(v) print(v) end),
			GUI.HSlider(50,150,100,10,30,90,30,function(v) print(v) end),
			GUI.Input("Name", 0, 230, 200, 100, function(t) print(t) end),
			GUI.Radiobutton(50, 350, {"Puppies", "Crocodiles", "Kitten"}, 3, function(i,v) print(i,v) end),
		}),
		GUI.Box(350, 100, 400, 400, {background_color = "#558855", padding_x = 10, padding_y = 10, overflow_x = "auto"}, {
			GUI.Imagelist(0,0,400,50,files, function(i,v,img) print(i,v,img) end)
		})
	)

end

function love.update(dt)
	GUI.update(dt)
end

function love.draw()
	GUI.draw()
end

function love.textinput(t)

end

function love.keypressed(key)

end

function love.mousereleased(x,y,button)
	GUI.mousereleased(x,y,button)
end

function love.mousepressed(x,y,button)
	GUI.mousepressed(x,y,button)
end

function love.textinput(t)
	GUI.textinput(t)
end

function love.keypressed(key)
	GUI.keypressed(key)
end
