local Player      = require "object/Player"
local Actor       = require "actions/Executor"
local MessageBox  = require "actions/MessageBox"
local Menu        = require "actions/Menu"
local Animate     = require "actions/Animate"
local BattleMenu  = require "object/BattleMenu"
local SpriteNode  = require "object/SpriteNode"
local TextNode    = require "object/TextNode"
local BattleActor = require "object/BattleActor"
local PartyMember = require "object/PartyMember"
local OpposingPartyMember = require "object/OpposingPartyMember"
local Parallax    = require "object/Parallax"
local Arrow       = require "object/Arrow"

local Rect       = unpack(require "util/Shapes")
local Animation  = require "util/AnAL"
local Transform  = require "util/Transform"
local Gradient   = require "util/Gradient"
local Audio      = require "util/Audio"

local Action    = require "actions/Action"
local Executor  = require "actions/Executor"
local Serial    = require "actions/Serial"
local Ease      = require "actions/Ease"
local Parallel  = require "actions/Parallel"
local Do        = require "actions/Do"
local Wait      = require "actions/Wait"
local TypeText  = require "actions/TypeText"
local PlayAudio = require "actions/PlayAudio"
local AudioFade = require "actions/AudioFade"

local Scene = require "scene/Scene"

local BattleScene = class(Scene)

BattleScene.STATE_PLAYERTURN           = "playerstart"
BattleScene.STATE_PLAYERTURN_PENDING   = "playerpending"
BattleScene.STATE_PLAYERTURN_COMPLETE  = "playerdone"
BattleScene.STATE_MONSTERTURN          = "monsterstart"
BattleScene.STATE_MONSTERPENDING       = "monsterpending"
BattleScene.STATE_MONSTERTURN_COMPLETE = "monsterdone"

BattleScene.STATE_PLAYERWIN            = "playerwin"
BattleScene.STATE_MONSTERWIN           = "monsterwin"

function BattleScene:onEnter(args)
	self:pushLayer("tiles")
	self:pushLayer("sprites")
	self:pushLayer("ui")

	self.images = args.images
	self.animations = args.animations
	self.audio = args.audio
	self.bgimg = args.background
	self.nextMusic = args.nextMusic or "battle"
	self.prevMusic = args.prevMusic
	self.blur = args.blur
	self.bossBattle = args.bossBattle
	self.initiative = args.initiative

	self.mboxGradient = self.images["mboxgradient"]

	self.bgColor = {0,0,0,255}
	
	self.playerSlots = {
		Transform(580,150,2,2),
		Transform(640,210,2,2),
		Transform(580,270,2,2),
		Transform(640,340,2,2)
	}
	self.opponentSlots = {
		Transform(60,270,2,2),
		Transform(220,150,2,2),
		Transform(220,270,2,2),
		Transform(60,150,2,2),
		Transform(140,210,2,2),
	}
	
	self.cachedMonsters = {}
	self.opponents = {}
	for k,v in pairs(args.opponents) do
		self:addMonster(v)
	end
	
	self.partyByName = {}
	self.party = {}
	
	local slotsByPartySize = {{2}, {2,3}, {1,2,3}, {1,2,3,4}}
	local partySize = table.count(GameState.party)
	local slotIndex = slotsByPartySize[partySize]
	
	local index = 1
	for _,v in pairs(GameState.party) do
		local mem = table.clone(v)
		mem.sprite = SpriteNode(
			self,
			self.playerSlots[slotIndex[index]],
			{255,255,255,255},
			v.battlesprite
		)
		mem.sprite.transform.ox = mem.sprite.w/2
		mem.sprite.transform.oy = mem.sprite.h/2
		mem.sprite.transform.x = mem.sprite.transform.x + mem.sprite.w
		mem.sprite.transform.y = mem.sprite.transform.y + mem.sprite.h
		mem.playerSlot = index
		
		local partyMember = PartyMember(self, mem)
		partyMember:setShadow()
		table.insert(self.party, partyMember)
		self.partyByName[v.id] = partyMember
		
		index = index + 1
	end
	
	self.xpGain = 0
	self.rewards = {}
	
	self.menu = BattleMenu(
		self,
		self.mboxGradient,
		Transform(5, love.graphics.getHeight() - 154),
		self.party,
		self.opponents
	)
	
	self.currentPlayer = 1
	local member = self.party[self.currentPlayer]
	member.turns = member.turns + 1
	
	self.currentOpponent = 1
	self.initialized = false
	self.state = BattleScene.STATE_PLAYERTURN
	self.playerTurns = #self.party
	self.maxOpponentTurns = #self.opponents
	self.opponentTurns = self.maxOpponentTurns
	
	local initiativeAction = Action()

	-- Player has initiative by encountering enemy from behind
	if self.initiative == "player" then
		for _, opponent in pairs(self.opponents) do
			opponent.sprite:setAnimation("backward")
		end
		self.playerTurns = #self.party * 2

		if #self.opponents == 1 then
			initiativeAction = MessageBox {
				message=self.opponents[1].name.." was caught off guard!",
				rect=MessageBox.HEADLINER_RECT
			}
		else
			initiativeAction = MessageBox {
				message="Bots were caught off guard!",
				rect=MessageBox.HEADLINER_RECT
			}
		end
	-- Opponent has initiative by running toward player
	elseif self.initiative == "opponent" then
		for _, player in pairs(self.party) do
			if player.state ~= BattleActor.STATE_DEAD then
				player.sprite:setAnimation("backward")
			end
		end
		self.state = BattleScene.STATE_MONSTERTURN

		initiativeAction = MessageBox {
			message="You were caught off guard!",
			rect=MessageBox.HEADLINER_RECT
		}		
	end
	
	self.musicVolume = 1.0
	return Serial {
		PlayAudio("music", self.nextMusic, self.musicVolume, true, true),
		Parallel {
			-- Unblur + fade in
			Ease(self.blur, "radius_h", 0, 2),
			Ease(self.bgColor, 1, 255, 1, "linear"),
			Ease(self.bgColor, 2, 255, 1, "linear"),
			Ease(self.bgColor, 3, 255, 1, "linear"),
			Do(function() ScreenShader:sendColor("multColor", self.bgColor) end)
		},
		initiativeAction
	}
end

function BattleScene:endCondition()
	return self.partyHp == 0 or self.monsterHp == 0
end

function BattleScene:onPostEnter()
	self.initialized = true
end

function BattleScene:update(dt)
	Scene.update(self, dt)

	if not self.initialized then
		return
	end
	
	if self.state == BattleScene.STATE_PLAYERTURN then
		-- Resolve against dead players
		local deadPlayerCount = 0
		for index, mem in pairs(self.party) do
			if mem.state == BattleActor.STATE_DEAD then
				deadPlayerCount = deadPlayerCount + 1
				self.playerTurns = self.playerTurns - 1
			end
			if deadPlayerCount == #self.party then
				self.state = BattleScene.STATE_MONSTERWIN
				return
			end
		end
		-- Cycle through party till we hit someone who's alive
		while self.party[self.currentPlayer].state == BattleActor.STATE_DEAD do
			self.currentPlayer = (self.currentPlayer % #self.party) + 1
		end
		-- Player begin turn
		self.party[self.currentPlayer]:beginTurn()

		local sprite = self.party[self.currentPlayer].sprite
		local playerId = self.party[self.currentPlayer].id
		self.topSprite = sprite

		if playerId == "rotor" then
			self.arrow = Arrow(self, Transform.relative(sprite.transform, Transform(0, -sprite.h * 1.3)))
		else
			self.arrow = Arrow(self, Transform.relative(sprite.transform, Transform(0, -sprite.h)))
		end
		self.state = BattleScene.STATE_PLAYERTURN_PENDING
	elseif self.state == BattleScene.STATE_PLAYERTURN_PENDING then
		local member = self.party[self.currentPlayer]
		if member:isTurnOver() then
			self.arrow:remove()
			member.turns = member.turns - 1
			if member.turns <= 0 then
				self.currentPlayer = (self.currentPlayer % #self.party) + 1

				print("turn over for "..member.id.." "..tostring(self.currentPlayer).." "..tostring(#self.party))
				
				member = self.party[self.currentPlayer]
				member.turns = member.turns + 1
				
				print("turn starting for "..member.id.." "..tostring(self.currentPlayer).." "..tostring(#self.party))

				self.state = BattleScene.STATE_PLAYERTURN_COMPLETE
			else
				print("extra turn for "..member.id)
				self.state = BattleScene.STATE_PLAYERTURN
			end
		end
	elseif self.state == BattleScene.STATE_PLAYERTURN_COMPLETE then
		if self:cleanMonsters() then
			if (self.currentOpponent > #self.opponents) then
				self.currentOpponent = 1
			end
			
			self.playerTurns = self.playerTurns - 1
			if self.playerTurns <= 0 then
				self.playerTurns = #self.party
				self.state = BattleScene.STATE_MONSTERTURN
			else
				self.state = BattleScene.STATE_PLAYERTURN
			end
		end
		
	elseif self.state == BattleScene.STATE_MONSTERTURN then
		self.opponents[self.currentOpponent]:beginTurn()
		self.topSprite = self.opponents[self.currentOpponent].sprite
		self.state = BattleScene.STATE_MONSTERTURN_PENDING

	elseif self.state == STATE_MONSTERTURN_PENDING then
		if self.opponents[self.currentOpponent]:isTurnOver() then
			self.state = BattleScene.STATE_MONSTERTURN_COMPLETE
		end

	elseif self.state == BattleScene.STATE_MONSTERTURN_COMPLETE then
		if self:cleanMonsters() then
			self.currentOpponent = self.nextOpponentOverride or ((self.currentOpponent % #self.opponents) + 1)
			
			self.opponentTurns = self.opponentTurns - 1
			if self.opponentTurns <= 0 then
				self.opponentTurns = math.min(#self.opponents, self.maxOpponentTurns)
				self.state = BattleScene.STATE_PLAYERTURN
			else
				self.state = BattleScene.STATE_MONSTERTURN
			end
		end
		
	elseif self.state == BattleScene.STATE_PLAYERWIN then
		-- Add up spoils of war from each opponent
		local spoilsActions = {}
		for _,reward in pairs(self.rewards) do
			GameState:grantItem(reward.item, reward.count)
			table.insert(
				spoilsActions,
				MessageBox {
					message="Found "..tostring(reward.count).." "..tostring(reward.item.name)..
					(reward.count > 1 and "s" or "").."!",
					rect=MessageBox.HEADLINER_RECT
				}
			)
		end
		table.insert(
			spoilsActions,
			MessageBox {
				message="Gained "..tostring(self.xpGain).." experience!",
				rect=MessageBox.HEADLINER_RECT
			}
		)
		
		-- Update hp + sp + xp on all players
		local victoryAnimActions = {}
		for _,mem in ipairs(self.party) do
			local partyMember = GameState.party[mem.id]
			partyMember.hp = mem.hp
			partyMember.sp = mem.sp
			
			-- Only living players get xp and to do their cool pose at end of battle
			if mem.state ~= BattleActor.STATE_DEAD then
				partyMember.xp = partyMember.xp + self.xpGain
				
				if partyMember.xp >= GameState:calcNextXp(mem.id, partyMember.level) then
					table.insert(
						spoilsActions,
						MessageBox {
							message=mem.name .. " gained a level!",
							rect=MessageBox.HEADLINER_RECT,
							sfx="levelup"
						}
					)
					local messages = GameState:levelup(mem.id)
					
					-- If we learned anything this level, show message for that
					for _, message in pairs(messages) do
						table.insert(
							spoilsActions,
							MessageBox {
								message=message,
								rect=MessageBox.HEADLINER_RECT,
								sfx="levelup"
							}
						)
					end
				end
				table.insert(victoryAnimActions, Animate(mem.sprite, "victory"))
			end
		end
		
		local victoryAction
		table.insert(
			spoilsActions,
			Do(function() self.sceneMgr:popScene{} end)
		)
		victoryAction = Parallel {
			PlayAudio("music", "victory", 1.0),
			Parallel(victoryAnimActions),
			Serial(spoilsActions)
		}
		
		self.bgColor = {255,255,255,255}
		self:run {
			-- Fade out current music
			AudioFade("music", self.audio:getMusicVolume(), 0, 2),
			
			-- Play victory
			victoryAction
		}
		self.state = "playerwinpending"
	elseif self.state == BattleScene.STATE_MONSTERWIN then
		-- Game over
		self.musicVolume = self.audio:getMusicVolume()
		self.bgColor = {255,255,255,255}
		self.sceneMgr:backToTitle()
		self.state = "monsterwinpending"
	end
end

function BattleScene:earlyExit()
	-- Make sure party hp is reflected back into GameState if you run away...
	for _,mem in ipairs(self.party) do
		local partyMember = GameState.party[mem.id]
		partyMember.hp = mem.hp
		partyMember.sp = mem.sp
	end

	return Serial {
		-- Fade out current music
		AudioFade("music", self.audio:getMusicVolume(), 0, 2),
		Do(function() self.sceneMgr:popScene{} end)
	}
end

function BattleScene:onExit(args)
	if args.toTitle then
		return Serial {
			AudioFade("music", self.audio:getMusicVolume(), 0, 2),
			MessageBox {
				message="The Freedom Fighters are no more...",
				rect=MessageBox.HEADLINER_RECT
			},
		
			-- Motion blur + fade to black + fade music
			Parallel {
				Ease(self.blur, "radius_h", 150, 2),
				Ease(self.bgColor, 1, 0, 1, "linear"),
				Ease(self.bgColor, 2, 0, 1, "linear"),
				Ease(self.bgColor, 3, 0, 1, "linear"),
				Do(function()
					ScreenShader:sendColor("multColor", self.bgColor)
				end)
			}
		}
	else
		return Serial {
			-- Motion blur + fade to black + fade music
			Parallel {
				Ease(self.blur, "radius_h", 150, 2),
				Ease(self.bgColor, 1, 0, 1, "linear"),
				Ease(self.bgColor, 2, 0, 1, "linear"),
				Ease(self.bgColor, 3, 0, 1, "linear"),
				Do(function()
					ScreenShader:sendColor("multColor", self.bgColor)
				end),
				
				AudioFade("music", self.audio:getMusicVolume(), 0, 1)
			},
			
			PlayAudio("music", self.prevMusic, 1, true)
		}
	end
end

function BattleScene:addMonster(monster)
	-- Ran out of space on game board
	if next(self.opponentSlots) == nil then
		return
	end

	if not self.cachedMonsters[monster] then
		self.cachedMonsters[monster] = love.filesystem.load("data/monsters/"..monster..".lua")()
	end
	local monster = self.cachedMonsters[monster]
	local mem = table.clone(monster)

	local slot = table.remove(self.opponentSlots)
	mem.sprite = SpriteNode(self, Transform.from(slot), {255,255,255,255}, monster.sprite)
	mem.sprite.transform.ox = mem.sprite.w/2
	mem.sprite.transform.oy = mem.sprite.h/2
	mem.sprite.transform.x = mem.sprite.transform.x + mem.sprite.w
	mem.sprite.transform.y = mem.sprite.transform.y + mem.sprite.h
	
	local origPosX = mem.sprite.transform.x
	mem.sprite.transform.x = -mem.sprite.w*2
	
	local oppo = OpposingPartyMember(self, mem)
	oppo.slot = slot
	
	-- Monster add animation
	Executor(self):act(Serial {
		Ease(mem.sprite.transform, "sx", (origPosX + mem.sprite.w*4)/mem.sprite.w, 7, "log"),
		Parallel {
			Ease(mem.sprite.transform, "sx", 2, 7, "quad"),
			Ease(mem.sprite.transform, "x", origPosX, 7, "quad"),
		},
		Do(function()
			oppo:setShadow(mem.hasDropShadow)
		end)
	})
	
	table.insert(self.opponents, oppo)
	oppo.index = #self.opponents
end

function BattleScene:cleanMonsters()
	-- Check if all monsters dead (This can happen due to counter attack or reflection)
	for index,oppo in pairs(self.opponents) do
		if oppo.state == BattleActor.STATE_DEAD then
			self.xpGain = self.xpGain + oppo.stats.xp				
			for _,drop in pairs(oppo.drops) do
				if math.random() < drop.chance then
					table.insert(self.rewards, drop)
				end
			end
			table.remove(self.opponents, index)
			table.insert(self.opponentSlots, oppo.slot)
			self.opponentTurns = self.opponentTurns - 1
		end
	end
	if next(self.opponents) == nil then
		self.state = BattleScene.STATE_PLAYERWIN
		return false -- Return whether battle should continue
	else
		return true
	end
end

function BattleScene:keytriggered(key)
    -- Exit game
    if key == "escape" then
        --love.event.quit()
    end
end

function BattleScene:draw()
	if self.blur then
		self.blur(function()
			love.graphics.setDefaultFilter("nearest", "nearest")
			
			love.graphics.setColor(255,255,255,255)
			love.graphics.draw(self.bgimg, 0, 0)
		
			self:sortedDraw("sprites")
			Scene.draw(self, "ui")
		end)
	else
		love.graphics.setDefaultFilter("nearest", "nearest")
		
		love.graphics.setColor(255,255,255,255)
		love.graphics.draw(self.bgimg, 0, 0)
		
		self:sortedDraw("sprites")
		Scene.draw(self, "ui")
	end
end


return BattleScene