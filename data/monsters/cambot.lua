local Serial = require "actions/Serial"
local Do = require "actions/Do"
local MessageBox = require "actions/MessageBox"
local Wait = require "actions/Wait"
local Action = require "actions/Action"

local Heal = require "data/items/actions/Heal"
local Telegraph = require "data/monsters/actions/Telegraph"
local Smack = require "data/monsters/actions/Smack"

return {
	name = "Cambot",
	altName = "Cambot",
	sprite = "sprites/cambot",

	stats = {
		xp    = 5,
		maxhp = 50,
		attack = 15,
		defense = 15,
		speed = 2,
		focus = 1,
		luck = 1,
	},

	run_chance = 0.7,

	coin = 0,

	drops = {
		{item = require "data/items/GreenLeaf", count = 1, chance = 0.2},
	},

	behavior = function (self, target)
		if not self.firstTurnOver then
			self.firstTurnOver = true
			self.scene.audio:playSfx("cambotpic", 1.0)
			return Telegraph(self, "Cambot is focusing its lens...", {255,255,255,50})
		end
	
		-- If there's less than 3 opponents (cambot + 2 swatbots), spawn another swatbot
		if #self.scene.opponents < 3 then
			self.scene.nextOpponentOverride = self.index
			self.scene.opponentTurns = 0
			self.scene.maxOpponentTurns = 1

			return Serial {
				Telegraph(self, "Intruder alert!", {255,255,255,50}),
				Do(function()
					self.scene:addMonster("swatbot")
				end)
			}
		-- Issue commands to swatbots
		else
			-- Find weakest party member, suggest focus damage
			local weakest = nil
			for _, mem in pairs(self.scene.party) do
				if not weakest or mem.hp < weakest.hp and mem.hp > 0 then
					weakest = mem
				end
			end
		
			local actions = {}
			for index, oppo in pairs(self.scene.opponents) do
				if index ~= self.index then
					table.insert(actions, oppo:behavior(weakest))
				end
			end
			
			-- End turns of other monsters
			self.scene.currentOpponent = self.index
			
			self.controlLinkEstablished = true
			
			local monicker = {
				sonic = "hedgehog",
				sally = "squirrel",
				antoine = "fox"
			}
			return Serial {
				Telegraph(self, "Cambot is scanning{p50}.{p50}.{p50}.", {255,255,255,50}),
				Telegraph(self, "Cambot has assumed command over Swatbots.", {255,255,255,50}),
				Telegraph(self, "Focusing damage on "..monicker[weakest.id]..".", {255,255,255,50}),
				Serial(actions)
			}
		end
	end,
	
	onDead = function(self)
		self.scene.nextOpponentOverride = nil
		self.scene.currentOpponent = 1
		self.scene.maxOpponentTurns = #self.scene.opponents -- Minus one because cambot is dead
		self.scene.opponentTurns = self.scene.maxOpponentTurns
		if self.controlLinkEstablished then
			return MessageBox {message="Cambot control link broken!", rect=MessageBox.HEADLINER_RECT, closeAction=Wait(1), blocking=true}
		else
			return Action()
		end
	end
}