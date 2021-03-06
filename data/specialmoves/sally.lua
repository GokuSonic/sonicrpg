local Serial = require "actions/Serial"
local Do = require "actions/Do"
local Wait = require "actions/Wait"
local While = require "actions/While"
local Action = require "actions/Action"
local PlayAudio = require "actions/PlayAudio"

local Transform = require "util/Transform"
local Player = require "object/Player"
local SpriteNode = require "object/SpriteNode"
local NPC = require "object/NPC"

return function(player)
	-- Pause controls
	local origUpdate = player.basicUpdate
	
	player.state = Player.ToIdle[player.state]
	if player.state == Player.STATE_IDLEUP then
		player.sprite:setAnimation("nicholeup")
	elseif player.state == Player.STATE_IDLEDOWN then
		player.sprite:setAnimation("nicholedown")
	elseif player.state == Player.STATE_IDLELEFT then
		player.sprite:setAnimation("nicholeleft")
	elseif player.state == Player.STATE_IDLERIGHT then
		player.sprite:setAnimation("nicholeright")
	end
	
	player.scene.audio:playSfx("nichole", 1.0)
		
	player.scan = function(self, target)
		if self.scanning then
			return
		end
		
		self:removeKeyHint()

		self.cinematic = true
		self.scanning = true
		self.scene:run {
			PlayAudio("sfx", "nicholescan", 1.0, true),

			Do(function()
				target.sprite:setParallax(4)
			end),
			
			Wait(0.7),
			
			Do(function()
				target.sprite:removeParallax()
			end),
			
			target.onScan and target:onScan() or Action(),
			
			Do(function()
				self.scanning = false
				self.cinematic = false
				self.basicUpdate = origUpdate
				
				-- Refresh keyhint
				self:showKeyHint(
					target.isInteractable,
					target.specialHintPlayer
				)
				self.keyHintObj = tostring(target)
			end)
		}
	end
	
	player.basicUpdate = function(self, dt)
		if not love.keyboard.isDown("lshift") and not self.scanning then
			self.cinematic = false
			self.basicUpdate = origUpdate
		end
	end
end