local Menu = require "actions/Menu"
local BouncyText = require "actions/BouncyText"
local Rect = unpack(require "util/Shapes")
local Transform = require "util/Transform"
local Serial = require "actions/Serial"
local Parallel = require "actions/Parallel"
local Wait = require "actions/Wait"
local Shake = require "actions/Shake"
local PlayAudio = require "actions/PlayAudio"
local Ease = require "actions/Ease"
local Animate = require "actions/Animate"
local Executor = require "actions/Executor"
local Repeat = require "actions/Repeat"
local Action = require "actions/Action"
local Do = require "actions/Do"
local Lazy = require "util/Lazy"
local MessageBox = require "actions/MessageBox"
local SpriteNode = require "object/SpriteNode"

local TargetType = require "util/TargetType"

local Telegraph = require "data/monsters/actions/Telegraph"

local BattleActor = require "object/BattleActor"

local OpposingPartyMember = class(BattleActor)

function OpposingPartyMember:construct(scene, data)
	self.scene = scene
	self.transform = transform
	self.playerSlot = data.playerSlot
	self.sprite = data.sprite
	self.turns = 0
	self.lostTurns = 0
	self.malfunctioningTurns = 0
	self.state = BattleActor.STATE_IDLE

	self.name = data.altName or ""
	self.stats = data.stats
	self.flying = data.flying
	self.run_chance = data.run_chance or 1.0
	self.drops = data.drops
	self.hp = data.stats.maxhp
	self.maxhp = data.stats.maxhp
	self.scan = data.scan
	self.hurtSfx = "smack"
	self.behavior = data.behavior or function() end
	self.onDead = data.onDead or function() return Action() end
	self.onAttack = data.onAttack
	self.textOffset = data.textOffset or Transform(0, self.sprite.h/2 - 15)
	self.color = data.color or {255,255,255,255}
	
	self.sprite.color = self.color
	
	self.side = TargetType.Opponent
end

function OpposingPartyMember:setShadow(visible)
	self.dropShadow = SpriteNode(
		self.scene,
		Transform(self.sprite.transform.x - self.sprite.w + 18, self.sprite.transform.y + self.sprite.h - 14, 2, 2),
		nil,
		"dropshadow"
	)
	self.dropShadow.sortOrderY = -1
	self.dropShadow.visible = visible
end

function OpposingPartyMember:beginTurn()
	-- Choose a target
	self.selectedTarget = math.random(#self.scene.party)
	
	-- If current target is dead, choose another
	local iterations = 1
	while self.scene.party[self.selectedTarget].state == BattleActor.STATE_DEAD do
		self.selectedTarget = (self.selectedTarget % #self.scene.party) + 1
		iterations = iterations + 1
		if iterations > #self.scene.party then
			print "this be broken"
			return
		end
	end
	
	local additionalActions = {}
	
	-- Choose action based on current state
	if self.immobilized then
		-- Shake left and right
		local shake = Repeat(Serial {
			Do(function()
				self.scene.audio:playSfx("bang")
			end),

			Ease(
				self.sprite.transform,
				"x",
				self.sprite.transform.x + 7,
				10
			),
			Ease(
				self.sprite.transform,
				"x",
				self.sprite.transform.x - 7,
				10
			),
			Ease(
				self.sprite.transform,
				"x",
				self.sprite.transform.x + 3,
				10
			),
			Ease(
				self.sprite.transform,
				"x",
				self.sprite.transform.x - 3,
				10
			),
			Ease(
				self.sprite.transform,
				"x",
				self.sprite.transform.x,
				10
			),
			
			Wait(0.5)
		}, 2)
		
		if not self.chanceToEscape then
			self.chanceToEscape = 0.4
		else
			self.chanceToEscape = self.chanceToEscape * 2
		end
		
		if math.random() > self.chanceToEscape then
			self.action = Serial {
				shake,
				Telegraph(self, self.name.." is immobilized!", {self.color[1],self.color[2],self.color[3],50}),
			}
		else
			-- Retract bunny ext arm and linkages and go back to idle anim
			self.action = Serial {
				shake,
				
				Do(function()
					if self.prevAnim == "backward" then
						self.prevAnim = "idle"
					end
					self.sprite:setAnimation(self.prevAnim)
					self.immobilized = false
					self.chanceToEscape = nil
				end),
				
				self.scene.partyByName["bunny"].reverseAnimation,
				
				Telegraph(self, self.name.." broke free!", {self.color[1],self.color[2],self.color[3],50}),
			}
		end
	elseif self.confused then
		self.selectedTarget = math.random(#self.scene.opponents)
		self.action = Serial {
			Telegraph(self, self.name.." is confused!", {self.color[1],self.color[2],self.color[3],50}),
			self.behavior(self, self.scene.opponents[self.selectedTarget]) or Action()
		}
		self.confused = false
	elseif self.lostTurns > 1 then
		self.action = Telegraph(self, self.name.." is still bored!", {self.color[1],self.color[2],self.color[3],50})
		self.lostTurns = self.lostTurns - 1
	elseif self.lostTurns > 0 then
		self.action = Telegraph(self, self.name.."'s boredom has subsided.", {self.color[1],self.color[2],self.color[3],50})
		self.lostTurns = self.lostTurns - 1
		self.sprite:setAnimation("idle")
	else
		-- Choose action based on behavior
		self.action = self.behavior(self, self.scene.party[self.selectedTarget]) or Action()
	end
	
	if self.malfunctioningTurns > 1 then
		table.insert(
			additionalActions,
			Serial {
				Telegraph(self, self.name.." is still malfunctioning!", {self.color[1],self.color[2],self.color[3],50}),
				Parallel {
					Animate(function()
						local xform = Transform(
							self.sprite.transform.x - 50,
							self.sprite.transform.y - 50,
							2,
							2
						)
						return SpriteNode(self.scene, xform, nil, "lightning", nil, nil, "ui"), true
					end, "idle"),
					
					Serial {
						Wait(0.2),
						PlayAudio("sfx", "shocked", 0.5, true),
					}
				},
				self:takeDamage({attack = 10, speed = 0, luck = 0})
			}
		)
		self.malfunctioningTurns = self.malfunctioningTurns - 1
	elseif self.malfunctioningTurns > 0 then
		table.insert(
			additionalActions,
			Telegraph(self, self.name.." is no longer malfunctioning.", {self.color[1],self.color[2],self.color[3],50})
		)
		self.malfunctioningTurns = self.malfunctioningTurns - 1
	end
	
	self.scene:run {
		Serial(additionalActions),
		self.action
	}
end

function OpposingPartyMember:isTurnOver()
	return not self.action or self.action:isDone()
end

function OpposingPartyMember:die()
	-- Don't do counter attack
	self.onAttack = nil
	
	local extraAnim = Action()
	if self.immobilized then
		extraAnim = self.scene.partyByName["bunny"].reverseAnimation
	end
	
	if self.scene.bossBattle then
		return Serial {
			Parallel {
				extraAnim,
				Ease(self.sprite.color, 1, 800, 5),
				
				Repeat(Serial {
					Do(function()
						self.scene.audio:playSfx("bossdie")
					end),

					Ease(
						self.sprite.transform,
						"x",
						self.sprite.transform.x + 7,
						10
					),
					Ease(
						self.sprite.transform,
						"x",
						self.sprite.transform.x - 7,
						10
					),
					Ease(
						self.sprite.transform,
						"x",
						self.sprite.transform.x + 3,
						10
					),
					Ease(
						self.sprite.transform,
						"x",
						self.sprite.transform.x - 3,
						10
					),
					Ease(
						self.sprite.transform,
						"x",
						self.sprite.transform.x,
						10
					),
				}, 10)
			},
			Do(function()
				self.scene.audio:playSfx("oppdeath")
				self.dropShadow:remove()
			end),
			Ease(self.sprite.color, 4, 0, 2),
			
			Do(function()
				self.hp = 0
				self.state = BattleActor.STATE_DEAD
				self.sprite:remove()
			end),
			
			self.onDead(self),
			
			Do(function()
				self.action = nil
			end)
		}
	else
		return Serial {
			Do(function()
				self.scene.audio:playSfx("oppdeath")
				self.dropShadow:remove()
			end),
			
			-- Fade out with red and play sound
			Parallel {
				extraAnim,
				Ease(self.sprite.color, 1, 800, 5),
				Ease(self.sprite.color, 4, 0, 2)
			},
			
			Do(function()
				self.hp = 0
				self.state = BattleActor.STATE_DEAD
				self.sprite:remove()
			end),
			
			self.onDead(self),
			
			Do(function()
				self.action = nil
			end)
		}
	end
end


return OpposingPartyMember
