--[[ 
    This script merges every opened tab into 1 sprite. 
    Useful becase aseprite only groups 1 level, so if you have images like:
      Monster_walk_east_0
      Monster_walk_east_1

      Monster_attack_east_0
      Monster_attack_east_1
    
    it will create 2 tabs when really you want these combined together into 1 sprite because they're animations relating to an entire unit
    
    script by jest(https://github.com/jestarray) - for aseprite versions > 1.2.10
    
    Public domain, do whatever you want
 ]]

if #app.sprites < 1 then
  return app.alert "You should have at least one sprite opened"
end

local bounds = Rectangle()
for i,sprite in ipairs(app.sprites) do
  bounds = bounds:union(sprite.bounds)
end

local function getTitle(filename)
  return filename:match("^.+/(.+)$")
end

local newSprite = Sprite(bounds.width, bounds.height)
local active = 1;
for i,sprite in ipairs(app.sprites) do
  if sprite ~= newSprite then
    for h,layer in ipairs(newSprite.layers) do
      for j,frame in ipairs(sprite.frames) do
      
      -- print(j)
      local cel = newSprite:newCel(layer, active, frame)
      cel.image:drawSprite(sprite, j)
      newSprite:newEmptyFrame()
      active = active + 1
      end
    end
  end
end
app.activeFrame = 1
