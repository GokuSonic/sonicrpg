local Serial = require "actions/Serial"
local Parallel = require "actions/Parallel"
local Wait = require "actions/Wait"
local Ease = require "actions/Ease"
local Animate = require "actions/Animate"
local PlayAudio = require "actions/PlayAudio"
local WaitForFrame = require "actions/WaitForFrame"
local MessageBox = require "actions/MessageBox"
local Do = require "actions/Do"
local Executor = require "actions/Executor"
local Repeat = require "actions/Repeat"
local Spawn = require "actions/Spawn"
local Action = require "actions/Action"

local PressX = require "data/battle/actions/PressX"
local OnHitEvent = require "data/battle/actions/OnHitEvent"

local SpriteNode = require "object/SpriteNode"
local Transform = require "util/Transform"

local LeapBackward = function(self, target)
	return Serial {
		-- Bounce off target
		Parallel {
			Ease(self.sprite.transform, "y", target.sprite.transform.y - self.sprite.h*2.5, 4, "linear"),
			Ease(self.sprite.transform, "x", target.sprite.transform.x + self.sprite.w*2, 4, "linear"),
		},
		Parallel {
			Ease(self.sprite.transform, "y", target.sprite.transform.y + target.sprite.h - self.sprite.h, 4, "linear"),
			Ease(self.sprite.transform, "x", target.sprite.transform.x + self.sprite.w*3, 4, "linear")
		},
		
		-- Land on ground
		Animate(self.sprite, "crouch"),
		Wait(0.1),
		Animate(self.sprite, "idle"),
		Wait(0.2),
		
		-- Leap backward
		Animate(self.sprite, "crouch"),
		Wait(0.1),
		Animate(self.sprite, "leap"),
		Parallel {
			Ease(self.sprite.transform, "x", self.sprite.transform.x, 3),
			Serial {
				Ease(self.sprite.transform, "y", self.sprite.transform.y - math.abs(target.sprite.transform.y - self.sprite.transform.y) - self.sprite.h, 4),
				Ease(self.sprite.transform, "y", self.sprite.transform.y, 6)
			}
		},
		
		Animate(self.sprite, "crouch"),
		Wait(0.1),
		Animate(self.sprite, "idle"),
	}
end

local ChargeSpin = function(self, key)
	if key == "x" then
		self.spinCharge = self.spinCharge + 1
		self.scene.audio:stopSfx()
		self.scene.audio:playSfx("spincharge")
		self.sprite:setAnimation("spincharge")
		Executor(self.scene):act(
			Animate(function()
				local xform = Transform.from(self.sprite.transform)
				xform.y = xform.y + self.sprite.h
				local sprite = SpriteNode(self.scene, xform, nil, "spindust", nil, nil, "ui")
				sprite.transform.y = sprite.transform.y - sprite.h*2
				return sprite, true
			end, "idle")
		)
	end
end

local SawSpark = function(self, angle, xOffset, yOffset)
	return Animate(function()
		local xform = Transform.from(self.sprite.transform)
		xform.angle = angle
		xform.ox = 8
		xform.oy = 0
		xform.x = xform.x + xOffset
		xform.y = xform.y + yOffset
		return SpriteNode(self.scene, xform, nil, "spark", nil, nil, "ui"), true
	end, "idle")
end

return function(self, target)
	local ringbeamActions = {}
	for index=1,12 do
		local sprite = SpriteNode(self.scene, Transform.from(self.sprite.transform), nil, "ringbeam", nil, nil, "ui")
		sprite.transform.angle = index * math.pi/6
		sprite.transform.x = sprite.transform.x - 28
		sprite.transform.y = sprite.transform.y - 12
		sprite.transform.sy = 0
		sprite.transform.ox = -5
		sprite.transform.oy = 32
		sprite.color[4] = 0
		table.insert(
			ringbeamActions,
			Serial {
				Wait((index % 3) / 2),
				
				Parallel {
					Ease(sprite.transform, "sy", (index % 3 == 0) and 3 or 1, 2),
					
					Repeat(Serial {
						Ease(sprite.color, 4, 125, 20),
						Ease(sprite.color, 4, 100, 20)
					}, 20 - 5 * (index % 3))
				},
				Ease(sprite.color, 4, 255, 3),
				Ease(sprite.color, 4, 0, 3),
				Do(function()
					sprite:remove()
				end)
			}
		)
	end

	return Serial {
		Animate(self.sprite, "fish_backpack"),
		Spawn(PlayAudio("music", "sonicring", 1.0)),
		Animate(self.sprite, "foundring_backpack"),
		Do(function() self.sprite:setGlow({255,255,0,255},2) end),
		Parallel {
			Serial {
				Animate(self.sprite, "liftring_idle", true),
				Wait(0.5),
				Parallel(ringbeamActions)
			},
			Ease(self.sprite, "glowSize", 6, 2),
			Ease(self.sprite.color, 1, 500, 2),
			Ease(self.sprite.color, 2, 500, 2),
		},
		Parallel {
			Ease(self.sprite.glowColor, 4, 0, 5, "quad"),
			Ease(self.sprite, "glowSize", 2, 5, "quad"),
			Ease(self.sprite.color, 1, 255, 5, "quad"),
			Ease(self.sprite.color, 2, 255, 5, "quad"),
		},
		Do(function() self.sprite:removeGlow() end),
		Animate(self.sprite, "liftring"),
		Wait(2)
	}
end
