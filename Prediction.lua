
--[[

	Author: Ark223
	Prediction library powered by BruhWalker
	________________________________________

	prediction_input:
	> source - the unit that the skillshot will be launched from [game_object/Vec3]
	> hitbox - indicates if the unit bounding radius should be included in calculations [boolean]
	> speed - the skillshot speed in units per second [number]
	> range - the skillshot range in units [number]
	> delay - the skillshot initial delay before release [number]
	> radius - the skillshot radius (for non-conic skillshots) [number]
	> angle - the skillshot angle (for conic skillshots) [number]
	> collision - determines the collision flags for the skillshot [table]:
	   ({"minion", "ally_hero", "enemy_hero", "wind_wall", "terrain_wall"})
	> type - the skillshot type: ({"linear", "circular", "conic"})[x]

	prediction_output:
	> cast_pos - the skillshot cast position [Vec3]
	> pred_pos - the predicted unit position [Vec3]
	> hit_chance - the calculated skillshot hit chance [number]
	> hit_count - the area of effect hit count [number]

	hit_chance:
	> -2 - impossible prediction, the unit is unpredictable
	> -1 - the skillshot is colliding other units on the path
	> 0 - the predicted position is out of the skillshot range
	> (0.01 - 0.99) - the solution has been found for given range
	> 1 - the unit is immobile or skillshot will land for sure
	> 2 - the unit is dashing or blinking

	API:
	> calc_aa_damage_to_minion(game_object source, game_object minion) [number]
	> get_aoe_prediction(prediction_input input, game_object unit) [prediction_output]
	> get_aoe_position(prediction_input input, table<game_object/Vec3> points, game_object/Vec3 star*) [{position, hit_count}]
	> get_collision(prediction_input input, Vec3 end_pos, game_object exclude) [table<game_object/Vec3>]
	> get_position_after(game_object unit, number delta, boolean skip_latency*) [Vec3]
	> get_health_prediction(game_object unit, number delta) [number]
	> get_lane_clear_health_prediction(game_object unit, number delta) [number]
	> get_prediction(prediction_input input, game_object unit) [prediction_output]
	> get_immobile_duration(game_object unit) [number]
	> get_invulnerable_duration(game_object unit) [number]
	> get_invisible_duration(game_object unit) [number]
	> get_movement_speed(game_object unit) [number]
	> get_waypoints(game_object unit) [table<Vec3>]
	> is_loaded() [boolean]
	> set_collision_buffer(number buffer)
	> set_internal_delay(number delay)

--]]

local Class = function(...)
	local cls = {}; cls.__index = cls
	cls.__call = function(_, ...) return cls:New(...) end
	function cls:New(...)
		local instance = setmetatable({}, cls)
		cls.__init(instance, ...)
		return instance
	end
	return setmetatable(cls, {__call = cls.__call})
end

----------------
-- Local data --

local myHero = game.local_player

local Blinks = {
	["Ezreal"] = {
		["EzrealE"] = {name = "Arcane Shift", range = 475, windup = 0.25}
	},
	["FiddleSticks"] = {
		["FiddleSticksR"] = {name = "Crowstorm", range = 800, windup = 1.5}
	},
	["Kassadin"] = {
		["Riftwalk"] = {name = "Riftwalk", range = 500, windup = 0.25}
	},
	["Katarina"] = {
		["KatarinaEWrapper"] = {name = "Shunpo", range = 725, windup = 0.125}
	},
	["Pyke"] = {
		["PykeR"] = {name = "Death from Below", range = 750, windup = 0.5}
	},
	["Shaco"] = {
		["Deceive"] = {name = "Deceive", range = 400, windup = 0.25}
	},
	["Viego"] = {
		["ViegoR"] = {name = "Heartbreaker", range = 500, windup = 0.5}
	},
	["Zoe"] = {
		["ZoeR"] = {name = "Portal Jump", range = 575, windup = 0.25}
	}
}

local ChanneledSpells = {
	["Caitlyn"] = {id = "caitlynheadshot", name = "Ace in the Hole", buff = true},
	["FiddleSticks"] = {id = "Crowstorm", name = "Crowstorm", buff = true},
	["Janna"] = {id = "ReapTheWhirlwind", name = "Monsoon", buff = true},
	["Jhin"] = {id = "JhinRShot", name = "Curtain Call", buff = false},
	["Karthus"] = {id = "karthusfallenonecastsound", name = "Requiem", buff = true},
	["Katarina"] = {id = "katarinarsound", name = "Death Lotus", buff = true},
	["Lucian"] = {id = "LucianR", name = "The Culling", buff = true},
	["Malzahar"] = {id = "alzaharnethergraspsound", name = "Nether Grasp", buff = true},
	["MissFortune"] = {id = "missfortunebulletsound", name = "Bullet Time", buff = true},
	["Nunu"] = {id = "NunuR_Recast", name = "Absolute Zero", buff = false},
	["TwistedFate"] = {id = "Gate", name = "Gate", buff = true},
	["Velkoz"] = {id = "VelkozR", name = "Life Form Disintegration Ray", buff = true},
	["Warwick"] = {id = "infiniteduresssound", name = "Infinite Duress", buff = true},
	["Xerath"] = {id = "XerathLocusOfPower2", name = "Rite of the Arcane", buff = true}
}

local BuffType = {
	Internal = 0, Aura = 1, CombatEnchancer = 2, CombatDehancer = 3, SpellShield = 4,
	Stun = 5, Invisibility = 6, Silence = 7, Taunt = 8, Berserk = 9, Polymorph = 10,
	Slow = 11, Snare = 12, Damage = 13, Heal = 14, Haste = 15, SpellImmunity = 16,
	PhysicalImmunity = 17, Invulnerability = 18, AttackSpeedSlow = 19, NearSight = 20,
	Currency = 21, Fear = 22, Charm = 23, Poison = 24, Suppression = 25, Blind = 26,
	Counter = 27, Shred = 28, Flee = 29, Knockup = 30, Knockback = 31, Disarm = 32,
	Grounded = 33, Drowsy = 34, Asleep = 35, Obscured = 36, Clickproof = 37, UnKillable = 38
}

local CrowdControls = {
	[BuffType.Charm] = true, [BuffType.Fear] = true,
	[BuffType.Flee] = true, [BuffType.Knockup] = true,
	[BuffType.Snare] = true, [BuffType.Stun] = true,
	[BuffType.Suppression] = true, [BuffType.Taunt] = true
}

local MinionFilter = {
	["HA_ChaosMinionMelee"] = math.huge, ["HA_ChaosMinionRanged"] = 650, ["HA_ChaosMinionSiege"] = 1200,
	["HA_ChaosMinionSuper"] = math.huge, ["HA_OrderMinionMelee"] = math.huge, ["HA_OrderMinionRanged"] = 650,
	["HA_OrderMinionSiege"] = 1200, ["HA_OrderMinionSuper"] = math.huge, ["SRU_Baron"] = 0, ["SRU_Blue"] = 0,
	["Sru_Crab"] = 0, ["SRU_Dragon_Air"] = 0, ["SRU_Dragon_Earth"] = 0, ["SRU_Dragon_Elder"] = 0,
	["SRU_Dragon_Fire"] = 0, ["SRU_Dragon_Water"] = 0, ["SRU_ChaosMinionMelee"] = math.huge,
	["SRU_ChaosMinionRanged"] = 650, ["SRU_ChaosMinionSiege"] = 1200, ["SRU_ChaosMinionSuper"] = math.huge,
	["SRU_Gromp"] = 0, ["SRU_Murkwolf"] = 0, ["SRU_MurkwolfMini"] = 0, ["SRU_OrderMinionMelee"] = math.huge,
	["SRU_OrderMinionRanged"] = 650, ["SRU_OrderMinionSiege"] = 1200, ["SRU_OrderMinionSuper"] = math.huge,
	["SRU_Razorbeak"] = 0, ["SRU_RazorbeakMini"] = 0, ["SRU_Red"] = 0, ["SRU_RiftHerald"] = 0,
	["AnnieTibbers"] = 0, ["IvernMinion"] = 0, ["YorickWGhoul"] = 0, ["YorickGhoulMelee"] = 0,
	["YorickBigGhoul"] = 0, ["HeimerTYellow"] = 0, ["HeimerTBlue"] = 0, ["ZyraThornPlant"] = 0,
	["ZyraGraspingPlant"] = 0, ["ShacoBox"] = 0, ["MalzaharVoidling"] = 0, ["KalistaSpawn"] = 0,
	["EliseSpiderling"] = 0
}

-- --------------------------------
-- Language INtegrated Query (LINQ)

local function ParsePredicate(func)
	if func == nil then return function(x) return x end end
	if type(func) == "function" then return func end
	local index = string.find(func, "=>")
	local arg = string.sub(func, 1, index - 1)
	local func = string.sub(func, index + 2, #func)
	return loadstring(string.format("return function"
		.. " %s return %s end", arg, func))()
end
----------------------------------------------------------------------------------------

local function Linq(tab)
	return setmetatable(tab or {}, {__index = table})
end
----------------------------------------------------------------------------------------

function table.Aggregate(source, func, accumulator)
	local accumulator = accumulator or 0
	local func = ParsePredicate(func)
	for index, value in ipairs(source) do
		accumulator = func(accumulator, value)
	end
	return accumulator
end
----------------------------------------------------------------------------------------

function table.All(source, func)
	local func = ParsePredicate(func)
	for index, value in ipairs(source) do
		if not func(value, index) then
			return false
		end
	end
	return true
end
----------------------------------------------------------------------------------------

function table.Any(source, func)
	local func = ParsePredicate(func)
	for index, value in ipairs(source) do
		if func(value, index) then
			return true
		end
	end
	return false
end
----------------------------------------------------------------------------------------

function table.Append(first, second)
	local index = #first + 1
	for _, value in ipairs(second) do
		first[index] = value
		index = index + 1
	end
end
----------------------------------------------------------------------------------------

function table.Average(source, func)
	local result, count = 0, 0
	local func = ParsePredicate(func)
	for _, value in ipairs(source) do
		local temp = func(value)
		if type(temp) == "number" then
			result = result + temp
			count = count + 1
		end
	end
	return count == 0 and 0 or result / count
end
----------------------------------------------------------------------------------------

function table.Clear(source)
	local size = #source
	for i = 1, size do
		source[i] = nil
	end
end
----------------------------------------------------------------------------------------

function table.Concat(first, second)
	local result, index = Linq(), 1
	for _, value in ipairs(first) do
		result[index] = value
		index = index + 1
	end
	for _, value in ipairs(second) do
		result[index] = value
		index = index + 1
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Contains(source, item)
	for _, value in ipairs(source) do
		if item == value then
			return true
		end
	end
	return false
end
----------------------------------------------------------------------------------------

function table.Copy(source)
	local result = Linq()
	for index, value in ipairs(source) do
		result[index] = value
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Distinct(source)
	local result, hash = Linq(), {}
	for _, value in ipairs(source) do
		if hash[value] == nil then
			hash[value] = true
			result:insert(value)
		end
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Except(first, second)
	return first:Where(function(x)
		return not second:Contains(x) end)
end
----------------------------------------------------------------------------------------

function table.ForEach(source, func)
	for index, value in pairs(source) do
		func(value, index)
	end
end
----------------------------------------------------------------------------------------

function table.GroupBy(source, func1, func2)
	local result = Linq()
	local keySelect = ParsePredicate(func1)
	local elemSelect = ParsePredicate(func2)
	for index, value in ipairs(source) do
		local key = keySelect(value, index)
		local element = elemSelect(value, index)
		result[key] = result[key] or Linq()
		result[key]:insert(element)
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Intersect(first, second)
	return first:Where(function(x)
		return second:Contains(x) end)
end
----------------------------------------------------------------------------------------

function table.Join(first, second, func)
	local result = Linq()
	local func = ParsePredicate(func)
	for _, v1 in ipairs(first) do
		for _, v2 in ipairs(second) do
			result:insert(func(v1, v2))
		end
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Max(source, func)
	local result = -math.huge
	local func = ParsePredicate(func)
	for _, value in ipairs(source) do
		local temp = func(value)
		if type(temp) == "number" and temp >
			result then result = temp end
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Min(source, func)
	local result = math.huge
	local func = ParsePredicate(func)
	for _, value in ipairs(source) do
		local temp = func(value)
		if type(temp) == "number" and temp <
			result then result = temp end
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Print(source, depth)
	local depth = depth or 0
	for key, value in pairs(source) do
		str = string.rep("  ", depth) .. key .. ": "
		if type(value) == "table" then console:log(str)
			Linq(value):Print(depth + 1)
		elseif type(value) == "boolean" then
			console:log(str .. tostring(value))
		else console:log(str .. value) end
	end
end
----------------------------------------------------------------------------------------

function table.Range(start, count)
	local result, index = Linq(), 1
	for value = start, start + count - 1 do
		result[index] = value
		index = index + 1
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Remove(source, element)
	local func = ParsePredicate(func)
	for index, value in ipairs(source) do
		if element and element == value then
			source:remove(index)
			return true
		end
	end
	return false
end
----------------------------------------------------------------------------------------

function table.RemoveWhere(source, func)
	local size = #source
	local func = ParsePredicate(func)
	for index = size, 1, -1 do
		local value = source[index]
		if func(value, index) then
			source:remove(index)
		end
	end
	return size ~= #source
end
----------------------------------------------------------------------------------------

function table.Reverse(source)
	local result, position = Linq(), 1
	for index = #source, 1, -1 do
		result[position] = source[index]
		position = position + 1
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Select(source, func)
	local result = Linq()
	local func = ParsePredicate(func)
	for index, value in ipairs(source) do
		result[index] = func(value, index)
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Sum(source, func)
	local result = 0
	local func = ParsePredicate(func)
	for _, value in ipairs(source) do
		local temp = func(value)
		if type(temp) == "number" then
			result = result + temp
		end
	end
	return result
end
----------------------------------------------------------------------------------------

function table.Union(first, second)
	return first:Concat(second):Distinct()
end
----------------------------------------------------------------------------------------

function table.Where(source, func)
	local result, position = Linq(), 1
	local func = ParsePredicate(func)
	for index, value in ipairs(source) do
		if func(value, index) then
			result[position] = value
			position = position + 1
		end
	end
	return result
end

-----------------
-- Point class --

local function IsPoint(p)
	return p and p.x and type(p.x) == "number"
			and p.y and type(p.y) == "number"
			and p.type and p.type == "Point"
end
-----------------------------------------------------------------------------------------------

local function IsUnit(p)
	return p and type(p) == "userdata" and
		(p.path and p.path.server_pos or p.origin)
end
-----------------------------------------------------------------------------------------------

local function IsVector(v)
	return v and v.x and type(v.x) == "number"
			and v.y and type(v.y) == "number"
			and v.z and type(v.z) == "number"
end
----------------------------------------------------------------------------------------

local function Round(v)
	return floor(v + 0.5) -- always positive number
end
-----------------------------------------------------------------------------------------------

local Point = Class()

function Point:__init(x, y)
	self.type = "Point"
	if x and IsUnit(x) then
		local p = x.path ~= nil and
			x.path.server_pos or x.origin
		self.x, self.y = p.x, p.z or p.y
	elseif x and y then
		self.x, self.y = x, y
	elseif x and not y then
		self.x, self.y = x.x, x.z or x.y
	else
		self.x, self.y = 0, 0
	end
end
-----------------------------------------------------------------------------------------------

function Point:__tostring()
	return string.format("%d %d", self.x, self.y)
end
----------------------------------------------------------------------------------------

function Point:__eq(p)
	return math.abs(self.x - p.x) < 1
		and math.abs(self.y - p.y) < 1
end
-----------------------------------------------------------------------------------------------

function Point:__add(p)
	return Point:New(self.x + p.x, self.y + p.y)
end
-----------------------------------------------------------------------------------------------

function Point:__sub(p)
	return Point:New(self.x - p.x, self.y - p.y)
end
-----------------------------------------------------------------------------------------------

function Point.__mul(a, b)
	if type(a) == "number" and IsPoint(b) then
		return Point:New(b.x * a, b.y * a)
	elseif type(b) == "number" and IsPoint(a) then
		return Point:New(a.x * b, a.y * b)
	end
	error("Multiplication error!")
end
-----------------------------------------------------------------------------------------------

function Point.__div(a, b)
	if type(a) == "number" and IsPoint(b) then
		return Point:New(a / b.x, a / b.y)
	elseif type(b) == "number" and IsPoint(a) then
		return Point:New(a.x / b, a.y / b)
	end
	error("Division error!")
end
-----------------------------------------------------------------------------------------------

function Point:__tostring()
	return string.format("(%d, %d)", self.x, self.y)
end
-----------------------------------------------------------------------------------------------

function Point:AngleBetween(p1, p2)
	local angle = math.deg(
		math.atan2(p2.y - self.y, p2.x - self.x) -
		math.atan2(p1.y - self.y, p1.x - self.x))
	if angle < 0 then angle = angle + 360 end
	return angle > 180 and 360 - angle or angle
end
-----------------------------------------------------------------------------------------------

function Point:Append(p, dist)
	if dist == 0 then return p:Clone() end
	return p + (p - self):Normalize() * dist
end
-----------------------------------------------------------------------------------------------

function Point:Clone()
	return Point:New(self.x, self.y)
end
-----------------------------------------------------------------------------------------------

function Point:ClosestOnSegment(s1, s2)
	local ap, ab = self - s1, s2 - s1
	local t = ap:DotProduct(ab) / ab:LengthSquared()
	return t < 0 and s1 or t > 1 and s2 or (s1 + ab * t)
end
-----------------------------------------------------------------------------------------------

function Point:CrossProduct(p)
	return self.x * p.y - self.y * p.x
end
-----------------------------------------------------------------------------------------------

function Point:DistanceSquared(p)
	local dx, dy = p.x - self.x, p.y - self.y
	return dx * dx + dy * dy
end
-----------------------------------------------------------------------------------------------

function Point:Distance(p)
	return math.sqrt(self:DistanceSquared(p))
end
-----------------------------------------------------------------------------------------------

function Point:DotProduct(p)
	return self.x * p.x + self.y * p.y
end
-----------------------------------------------------------------------------------------------

function Point:Extend(p, dist)
	if dist == 0 then return self:Clone() end
	return self + (p - self):Normalize() * dist
end
-----------------------------------------------------------------------------------------------

function Point:Intersection(s2, c1, c2)
	local a, b = s2 - self, c2 - c1
	local axb = a:CrossProduct(b)
	if axb == 0 then return nil end
	local c = c1 - self
	local t1 = c:CrossProduct(b) / axb
	local t2 = c:CrossProduct(a) / axb
	if t1 >= 0 and t1 <= 1 and t2 >= 0 and
		t2 <= 1 then return self + a * t1 end
	return nil
end
-----------------------------------------------------------------------------------------------

function Point:IsZero()
	return self.x == 0 and self.y == 0
end
-----------------------------------------------------------------------------------------------

function Point:LengthSquared(p)
	local p = p and p:Clone() or self
	return p.x * p.x + p.y * p.y
end
-----------------------------------------------------------------------------------------------

function Point:Length(p)
	return math.sqrt(self:LengthSquared(p))
end
-----------------------------------------------------------------------------------------------

function Point:Negate()
	return Point:New(-self.x, -self.y)
end
-----------------------------------------------------------------------------------------------

function Point:Normalize()
	local len = self:Length()
	if len == 0 then return Point:New() end
	return Point:New(self.x / len, self.y / len)
end
-----------------------------------------------------------------------------------------------

function Point:Perpendicular()
	return Point:New(-self.y, self.x)
end
-----------------------------------------------------------------------------------------------

function Point:Perpendicular2()
	return Point:New(self.y, -self.x)
end
-----------------------------------------------------------------------------------------------

function Point:Rotate(phi, p)
	local c = math.cos(phi)
	local s = math.sin(phi)
	local p = p or Point:New()
	local d = Point:New(self - p)
	return Point:New(c * d.x - s * d.y +
		p.x, s * d.x + c * d.y + p.y)
end
-----------------------------------------------------------------------------------------------

function Point:To3D(y)
	local pos = vec3.new(self.x, 0, self.y)
	pos.y = y or myHero.path.server_pos.y
	return pos
end

--------------------------------
-- Prediction input structure --

local PredictionInput = Class()

function PredictionInput:__init(data)
	self.source = data.source or nil
	self.speed = data.speed or math.huge
	self.range = data.range or 25000
	self.delay = data.delay or 0.25
	self.radius = data.radius or 1
	self.angle = data.angle or 0
	self.hitbox = data.hitbox or false
	self.collision = data.collision or {}
	self.type = data.type or "linear"
end

---------------------------------
-- Prediction output structure --

local PredictionOutput = Class()

function PredictionOutput:__init()
	self.cast_pos = nil
	self.pred_pos = nil
	self.hit_chance = -2
	self.hit_count = 0
	self.time_to_hit = 0
end

-------------------
-- Prediction class

local Pred = Class()

function Pred:__init(delay, buffer)
	self.attacks = Linq()
	self.data = Linq()
	self.windwalls = Linq()
	self.internalDelay = delay or 0.034
	self.collisionBuffer = buffer or 30
	self.units = Linq(game.players):Where(
		function(u) return u.object_id ~= myHero.object_id end)
	self.enemies = self.units:Where(function(u) return u.is_enemy end)
	for _, unit in ipairs(self.units) do self:ResetData(unit) end
	client:set_event_callback("on_tick", function(...) self:OnTick(...) end)
	client:set_event_callback("on_new_path", function(...) self:OnNewPath(...) end)
	--client:set_event_callback("on_process_spell", function(...) self:OnProcessSpell(...) end)
	client:set_event_callback("on_stop_cast", function(...) self:OnStopCast(...) end)
	self.loaded = true
end
-----------------------------------------------------------------------------------------------

function Pred:CalcPhysicalDamage(source, unit, amount)
	-- needs extra API
	return amount
end
-----------------------------------------------------------------------------------------------

function Pred:CutPath(path, distance)
	if distance < 0 then return path end
	local count, result = #path, {}
	local distance = distance
	for i = 1, count - 1 do
		local dist = path[i]:Distance(path[i + 1])
		if dist > distance then
			result[#result + 1] = path[i]
				:Extend(path[i + 1], distance)
			for j = i + 1, count do
				result[#result + 1] = path[j]
			end break
		end
		distance = distance - dist
	end
	return #result > 0 and result or {path[count]}
end
-----------------------------------------------------------------------------------------------

function Pred:CalcAutoAttackDamage(source, unit)
	if not unit.is_minion then return 0 end
	if source.is_turret then
		if unit.champ_name:find("MinionSiege") then
			if source.champ_name:find("1") then
				return unit.max_health * 0.14
			end
			if source.champ_name:find("2") then
				return unit.max_health * 0.11
			end
			if source.champ_name:find("3") or source.champ_name:find("4") then
				return unit.max_health * 0.08
			end
		end
		if unit.champ_name:find("MinionSuper") then
			return unit.max_health * 0.05
		end
		if unit.champ_name:find("MinionRanged") then
			return unit.max_health * 0.6788079470198675
		end
		if unit.champ_name:find("MinionMelee") then
			return unit.max_health * 0.45
		end
	end
	local damage = source.total_attack_damage
	-- needs percent_damage_to_barracks_minion_mod for total damage
	if source.champ_name == "Kalista" then
		damage = damage * 0.9
	elseif source.champ_name == "Graves" then
		damage = damage * (0.68235 + source.level * 0.01765)
	end
	return self:CalcPhysicalDamage(source, unit, damage)
end
-----------------------------------------------------------------------------------------------

function Pred:GetMovementSpeed(unit)
	local path = unit.path
	return path and path.is_dashing and
		path.dash_speed or unit.move_speed
end
-----------------------------------------------------------------------------------------------

function Pred:GetPathIndex(path, pos)
	if #path <= 2 then return 2 end
	local result = {distance = math.huge,
		index = 0, point = Point:New()}
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local pt = pos:ClosestOnSegment(a, b)
		local dist = pos:DistanceSquared(pt)
		if dist < result.distance then
			result = {distance = dist,
				index = i + 1, point = pt}
		end
	end
	pos = result.point
	return result.index
end
-----------------------------------------------------------------------------------------------

function Pred:GetWaypoints(unit)
	local result = Linq()
	result[1] = Point:New(unit.path.server_pos)
	local path = Linq(unit.path.waypoints):Select(
		function(w) return Point:New(w.x, w.z) end)
	local index = self:GetPathIndex(path, result[1])
	for i = index, #path do result[#result + 1] = path[i] end
	return result
end
-----------------------------------------------------------------------------------------------

function Pred:Interception(startPos, endPos, source, speed, mspeed, delay)
	-- dynamic circle-circle collision:
	-- https://stackoverflow.com/questions/2248876/2d-game-fire-at-a-
	-- moving-target-by-predicting-intersection-of-projectile-and-u
	local dir = endPos - startPos
	local magn = dir:Length()
	local vel = dir * speed / magn
	dir = startPos - source
	local a = vel:LengthSquared() - mspeed * mspeed
	local b = 2 * vel:DotProduct(dir)
	local c = dir:LengthSquared()
	local delta = b * b - 4 * a * c
	if delta >= 0 then
		local delta, t = math.sqrt(delta), 0
		local t1 = (-b + delta) / (2 * a)
		local t2 = (-b - delta) / (2 * a)
		if t2 >= delay then
			t = t1 >= delay and math.min(
				t1, t2) or math.max(t1, t2)
		end
		return t, startPos + vel * t
	end
	return 0, nil
end
----------------------------------------------------------------------------------------

function Pred:IsInserted(unit)
	return self.attacks:Any(function(a)
		return unit.object_id == a.networkId and
			game.game_time - a.timer < a.windupTime
	end)
end
----------------------------------------------------------------------------------------

function Pred:Latency()
	return game.ping * 0.001
end
----------------------------------------------------------------------------------------

function Pred:ResetData(unit)
	self.data[unit.object_id] = {
		blink = {}, -- the stored data about unit's blink
		dashing = false, -- indicates if the unit is dashing
		dashSpeed = 0, -- the unit last dashing speed
		castEndTimer = 0, -- the last AA or spell cast timer
		miaTimer = -1, -- the last invisibility timer
		pathTimer = 0, -- the last path change timer
		waypoints = Linq() -- the unit waypoints
	}
end

------------
-- Events --

function Pred:OnTick()
	for _, unit in ipairs(self.units) do
		local data = self.data[unit.object_id]
		if unit.is_valid and unit.is_visible then
			data.waypoints = self:GetWaypoints(unit)
			data.miaTimer = 0
		elseif data.miaTimer == 0 then
			data.miaTimer = game.game_time + 0.0167
		end
	end
	self.attacks:ForEach(function(a)
		if a.processed == true then return end
		local target = Point:New(a.target.origin)
		local dist = a.source:Distance(target)
		if not a.target.is_valid or not a.target.is_alive
			or a.timer + dist / a.speed + a.windupTime <=
			game.game_time then a.processed = true end
	end)
	self.attacks:RemoveWhere(function(a)
		return a.processed == true and
		game.game_time - a.timer > 3 end)
	self.windwalls:ForEach(function(w)
		return game.game_time - w.timer > 4 end)
end
----------------------------------------------------------------------------------------

function Pred:OnNewPath(unit)
	if unit.team == myHero.team or not
		unit.is_hero then return end
	local data = self.data[unit.object_id]
	data.dashing = unit.path.is_dashing
	data.dashSpeed = unit.path.dash_speed
	data.pathTimer = game.game_time
end
----------------------------------------------------------------------------------------

function Pred:OnProcessSpell(unit, args)
	if not unit.is_valid or not unit.is_alive then return end
	local charName, name = unit.champ_name, args.spell_name
	if unit.is_hero and self.data[unit.object_id]
		and unit.object_id ~= myHero.object_id then
		local data = self.data[unit.object_id]
		if args.cast_delay > 0 then data.castEndTimer =
			args.cast_time + args.cast_delay end
		if Blinks[charName] and Blinks[charName][name] then
			local blink = Blinks[charName][name]
			local startPos = Point:New(args.start_pos)
			local endPos = Point:New(args.end_pos)
			endPos = startPos:Extend(endPos, math.min(
				blink.range, startPos:Distance(endPos)))
			data.blink = {pos = endPos, endTime =
				args.cast_time + blink.windup}
		elseif name == "YasuoW" then
			local startPos = Point:New(args.start_pos)
			local endPos = Point:New(args.end_pos)
			local dir = (endPos - startPos):Normalize()
			local pos = startPos + dir * 350
			local perp = dir:Perpendicular()
			local lvl = unit:get_spell_slot(1).level
			local width = 300 + lvl * 50
			self.windwalls[#self.windwalls + 1] = {
				cornerA = pos - perp * width,
				cornerB = pos + perp * width,
				timer = args.cast_time
			}
		end
	elseif args.is_autoattack and args.target
		and args.target.is_valid and args.target.is_minion and
		unit.team == myHero.team and not self:IsInserted(unit) then
		local target = args.target
		local data = MinionFilter[target.champ_name]
		if not data or data == 0 then return end
		local heroPos = Point:New(myHero.origin)
		local targetPos = Point:New(target.origin)
		if heroPos:Distance(targetPos) > 2500 then return end
		local speed = unit:get_basic_attack_data().missile_speed
		self.attacks[#self.attacks + 1] = {
			processed = false,
			target = target,
			source = Point:New(unit.origin),
			timer = args.cast_time,
			networkId = unit.object_id,
			windupTime = unit.attack_cast_delay,
			animationTime = unit.attack_delay -
				(unit.is_turret and 0.067 or 0),
			speed = MinionFilter[charName] ~= nil
				and MinionFilter[charName] ~= 0
				and (MinionFilter[charName]) or
				(not unit.is_melee and speed ~= nil
				and speed > 0 and speed or math.huge),
			damage = self:CalcAutoAttackDamage(unit, target)
		}
	end
end
----------------------------------------------------------------------------------------

function Pred:OnStopCast(unit, args)
	local heroPos = Point:New(myHero.origin)
	local source = Point:New(unit.origin)
	if unit.team ~= myHero.team or
		source:Distance(heroPos) > 2500 or
		not args.stop_animation then return end
	self.attacks:RemoveWhere(function(a)
		return unit.object_id == a.networkId and
			game.game_time - a.timer < a.windupTime
	end)
end

------------------------
-- Prediction methods --

function Pred:GetAOEPosition(input, points, star)
	-- extract points and hitboxes from input table
	local size, hitbox = #units, {}
	if size > 0 and IsUnit(points[1]) then
		points = Linq(points):Select(function(p) return Point:New(p) end)
		hitbox = Linq(points):Select("(p) => p.bounding_radius")
	end
	if star and IsUnit(star) then star = Point:New(star) end

	-- return results if size of table is <= 1
	if size == 0 then return {position = nil, hit_count = 0} end
	if size == 1 then return {position = points[1]:To3D(), hit_count = 1} end
	local source, count, distance, index = Point:New(input.source), 0, 0, 0

	-- calculate the average position from given points
	local ax = points:Average("(u) => u.x")
	local ay = points:Average("(u) => u.y")
	local pos = Point:New(ax, ay)

	-- calculate hit count, remove the farthest point and try again...
	for i, point in ipairs(points) do
		local hitbox = (input.radius or 0)
			+ (input.hitbox and hitbox[i] or 0)
		local dist, dsrc, angle = 0, 0, 180
		if input.type == "linear" then
			local endPos = source:Extend(pos, input.range)
			local closest = point:ClosestOnSegment(source, endPos)
			dist = pos:DistanceSquared(closest)
		elseif input.type == "conic" then
			angle = source:AngleBetween(pos, point)
			dsrc = source:DistanceSquared(point)
		end
		if dist == 0 then dist = pos:DistanceSquared(point) end
		if input.type == "conic" and angle <= input.angle * 0.5 and
			dsrc <= input.range * input.range or input.type ~= "conic"
			and dist <= hitbox * hitbox then count = count + 1
		elseif star and point == star then goto continue end
		if dist > distance then distance, index = dist, i end
		::continue::
	end

	-- return results or continue...
	if count ~= size and index ~= 0 then
		table.remove(points, index)
		return self:GetAOEPosition(input, points, star)
	end
	return {position = pos:To3D(), hit_count = count}
end
----------------------------------------------------------------------------------------

function Pred:GetCollision(input, endPos, exclude)
	local source = Point:New(input.source)
	local endPos, result = Point:New(endPos), {}
	for _, flag in ipairs(input.collision) do
		if flag == "minion" or flag:find("hero") then
			-- gather valid collision candidates
			local units = Linq(flag == "minion"
				and game.minions or game.players):Where(
				function(u) local pos = Point:New(u.origin)
				return u.is_valid and myHero.object_id ~= u.object_id and
					u.is_alive and u.is_visible and u.max_health > 5 and
					(exclude and exclude.object_id ~= u.object_id or not exclude) and
					source:DistanceSquared(pos) <= math.pow(input.range + 1000, 2)
			end)
			if flag == "minion" then
				units = units:Where(function(u) return u.is_enemy
					and MinionFilter[u.champ_name] ~= nil end)
			elseif flag == "enemy_hero" then
				units = units:Where(function(u) return u.is_enemy end)
			elseif flag == "ally_hero" then
				units = units:Where(function(u) return not u.is_enemy end)
			end
			for _, unit in ipairs(units) do
				local output = self:PredictOnPath(input, unit)
				local pos = Point:New(output.pred_pos) or nil
				if not pos or pos:IsZero() then goto continue end
				local hitbox = (input.radius or 0) + unit.bounding_radius
				local closest = pos:ClosestOnSegment(source, endPos)
				if pos:DistanceSquared(closest) <= math.pow(self.collisionBuffer
					+ hitbox, 2) then result[#result + 1] = unit end
				::continue::
			end
		elseif flag == "wind_wall" then
			for _, data in ipairs(self.windwalls) do
				local pos = source:Intersection(
					endPos, data.cornerA, data.cornerB)
				if pos and IsPoint(pos) then
					local dist = source:Distance(pos)
					local t = input.delay + dist / input.speed
					if game.game_time + t <= unit.timer + 4.1 then
						result[#result + 1] = pos:To3D() end
				end
			end
		elseif flag == "terrain_wall" then
			local dir = (endPos - source):Normalize()
			local dist, step = source:Distance(endPos), 0
			while step <= dist do
				local pos = (source + dir * step):To3D()
				if nav_mesh:is_wall(pos) then return pos end
				step = step + math.min(dist - step, 35)
			end
		end
	end
	return result
end
----------------------------------------------------------------------------------------

function Pred:GetHitChance(input, output, unit)
	-- no solution found
	if output.cast_pos == nil then return -2 end

	-- position is valid and unit is dashing or blinking
	local data = self.data[unit.object_id]
	if #data.blink > 0 or data.dashing then return 2 end

	-- the cast position is out of range
	local source = Point:New(input.source)
	local castPos = Point:New(output.cast_pos)
	local predPos = Point:New(output.pred_pos)
	local distance = source:Distance(input.type
		== "circular" and castPos or predPos)
	if distance > input.range then return 0 end

	-- the skillshot is a missile and collides the units
	if input.collision and #self:GetCollision(
		input, castPos, unit) > 0 then return -1 end

	-- calculate the skillshot arrival time
	local distance = source:Distance(castPos)
	local timeToHit = distance / input.speed +
		input.delay + self.internalDelay + self:Latency()

	-- the unit is invulnerable for this time, he won't get hit
	local invulnerability = self:GetInvulnerableDuration(unit)
	if invulnerability > timeToHit then return -2 end

	-- we haven't seen the unit any single time
	local invTime = self:GetInvisibleDuration(unit)
	if invTime == math.huge then return -2 end

	-- the unit has been standing for too long
	if invTime <= 0 and #data.waypoints <= 1
		and game.game_time - data.pathTimer >
		timeToHit + 1.5 then return 1 end

	-- gather remaining dependencies
	local hitbox = (input.type ~= "conic" and
		input.radius or math.min(input.range - distance,
		distance, distance * (input.angle or 50) / 90))
		+ (input.hitbox and unit.bounding_radius or 0)
	local moveSpeed = self:GetMovementSpeed(unit)
	local reactionTime = self:GetReactionTime(unit)
	local immobility = self:GetImmobileDuration(unit)

	-- calculate hitchance
	return math.min(1, hitbox / moveSpeed / math.max(0,
		timeToHit - reactionTime + invTime - immobility))
end
----------------------------------------------------------------------------------------

function Pred:GetImmobileDuration(unit)
	local duration = Linq(unit.buffs)
		:Where(function(b)
			return b.is_valid and b.duration > 0 and
			b.count > 0 and CrowdControls[b.type] end)
		:Aggregate(function(current, b)
			local remaining = b.end_time - game.game_time
			return math.max(0, current, remaining) end)
	local castEndTime = self.data[unit.object_id].castEndTimer
	return math.max(castEndTime - game.game_time, duration)
end
----------------------------------------------------------------------------------------

function Pred:GetInvisibleDuration(unit)
	local data = self.data[unit.object_id]
	if not data then return math.huge end
	local timer = data.miaTimer
	return timer == 0 and 0 or timer < 0 and
		math.huge or (game.game_time - timer)
end
----------------------------------------------------------------------------------------

function Pred:GetInvulnerableDuration(unit)
	for _, buff in ipairs(unit.buffs) do
		if buff and buff.duration > 0 and buff.count > 0 
			and buff.type == BuffType.Invulnerability then
			return math.max(0, buff.end_time - game.game_time)
		end
	end
	return 0
end
----------------------------------------------------------------------------------------

function Pred:GetReactionTime(unit)
	local data = self.data[unit.object_id]
	if not data then return 0.0 end
	local heroPos = Point:New(myHero.path.server_pos)
	local unitPos = Point:New(unit.path.server_pos)
	local dir = unitPos + Point:New(unit.direction) * 100
	local angle = math.rad(heroPos:AngleBetween(unitPos, dir))
	local reaction = math.abs(math.cos(angle)) * 0.215
	return math.max(game.game_time - data.pathTimer <=
		self.internalDelay and 0.125 or 0.0, reaction)
end
----------------------------------------------------------------------------------------

function Pred:GetAOEPrediction(input, unit)
	-- invalid unit, input or source
	if not unit or not input or not input.source
		then return PredictionOutput:New() end

	-- save the unit as the star target
	local candidates = {}
	local op = self:GetPrediction(input, unit)
	if op.hit_chance <= 0 then return op end
	units[#units + 1] = {origin = op.pred_pos,
		bounding_radius = unit.bounding_radius}

	-- add valid candidates
	for _, enemy in pairs(self.enemies) do
		if enemy.object_id ~= unit.object_id and enemy.is_valid
			and enemy.is_visible and enemy.is_alive then
			local o = self:GetPrediction(input, enemy)
			if o.hit_chance > 0 then units[#units + 1] = {origin =
				o.pred_pos, bounding_radius = enemy.bounding_radius} end
		end
	end

	-- calculate AoE position
	local output = PredictionOutput:New()
	local source = Point:New(input.source)
	local aoe = self:GetAOEPosition(input, units, units[1])
	output.cast_pos = aoe.hit_count > 1 and aoe.position or op.cast_pos
	output.pred_pos = aoe.hit_count > 1 and aoe.position or op.pred_pos
	output.hit_chance = self:GetHitChance(input, output, unit)
	local dist = source:Distance(Point:New(output.cast_pos))
	output.time_to_hit = dist / input.speed + input.delay
	output.hit_count = math.max(1, aoe.hit_count)
	return output
end
----------------------------------------------------------------------------------------

function Pred:GetHealthPrediction(unit, time)
	local health = unit.health
	for _, attack in ipairs(self.attacks) do
		if unit.object_id == attack.target.object_id
			and attack.processed == false then
			local target = Point:New(attack.target)
			local landTime = attack.windupTime + attack.timer
				+ target:Distance(attack.source) / attack.speed
			if game.game_time < landTime - 0.067 and
				game.game_time > landTime - time then
				health = health - attack.damage
			end
		end
	end
	return health
end
----------------------------------------------------------------------------------------

function Pred:GetLaneClearHealthPrediction(unit, time)
	local health = unit.health
	for _, attack in ipairs(self.attacks) do
		if game.game_time - 0.1 <= attack.timer + attack.animationTime
			and unit.object_id == attack.target.object_id then
			local from, to = attack.timer, game.game_time + time
			local target = Point:New(attack.target)
			local landTime = attack.windupTime + target
				:Distance(attack.source) / attack.speed
			while from < to do
				if from >= game.game_time
					and from + landTime < to then
					health = health - attack.damage
				end
				from = from + attack.animationTime
			end
		end
	end
	return health
end
----------------------------------------------------------------------------------------

function Pred:GetPositionAfter(unit, delta, skipLatency)
	if not unit or not unit.is_alive then return nil end
	local data = self.data[unit.object_id]
	local waypoints = data ~= nil and
		data.waypoints or self:GetWaypoints(unit)
	if #waypoints == 0 then return unit.path.server_pos end
	local invTime = data ~= nil and data.miaTimer > 0
		and (game.game_time - data.miaTimer) or 0
	local delay = delta + (skipLatency and 0 or
		self.internalDelay + self:Latency())
	local speed = self:GetMovementSpeed(unit)
	local distance = speed * delay
	local y = unit.path.server_pos.y
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		local dist = a:Distance(b)
		if dist >= distance then return
			a:Extend(b, distance):To3D(y) end
		distance = distance - dist
	end
	return waypoints[#waypoints]:To3D(y)
end
----------------------------------------------------------------------------------------

function Pred:GetPrediction(input, unit)
	-- validate input, unit and source
	local output = PredictionOutput:New()
	if not unit or not input or not unit.is_alive
		or not input.source then return output end

	local data = self.data[unit.object_id]
	if not data then return output end
	local hitbox = (input.radius or 0) +
		(input.hitbox and unit.boundingRadius or 0)
	local unitPos = Point:New(unit.path.server_pos)
	local source = Point:New(input.source)

	-- handle extra cases like dashes and blinks
	if #data.blink > 0 then
		local y = unit.path.server_pos.y
		local speed = unit.move_speed or 315
		local t1 = source:Distance(unitPos) / input.speed + input.delay
		local t2 = source:Distance(blink.pos) / input.speed + input.delay
		local remaining = math.max(0, blink.endTime - game.game_time)
		output.cast_pos = t1 < remaining and unitPos:To3D(y) or t2 <=
			remaining + hitbox / speed and blink.pos:To3D(y) or nil
		output.hit_chance = output.cast_pos ~= nil and 2 or -2
		output.pred_pos = output.cast_pos or blink.pos:To3D(y)
	else
		output = self:PredictOnPath(input, unit)
		if data.dashing == true then
			local pos = Point:New(output.cast_pos)
			local last = data.waypoints[#data.waypoints]
			if pos == last then output.cast_pos = nil
			else output.cast_pos = output.pred_pos end
		end
		output.hit_chance = self:GetHitChance(input, output, unit)
	end

	-- calculate the skillshot arrival time
	if output.hit_chance < 0 then return output end
	local castPos = Point:New(output.cast_pos)
	output.time_to_hit = source:Distance(
		castPos) / input.speed + input.delay

	return output
end
----------------------------------------------------------------------------------------

function Pred:PredictOnPath(input, unit, skipLatency)
	-- return if waypoints do not exist
	local output = PredictionOutput:New()
	local data = self.data[unit.object_id]
	local waypoints = data ~= nil and
		data.waypoints or self:GetWaypoints(unit)
	if #waypoints == 0 then return output end

	-- cut a path if unit just went in fog of war
	local speed = self:GetMovementSpeed(unit)
	if data and data.miaTimer > 0 then
		local miaDist = speed * (game.game_time - data.miaTimer)
		waypoints = self:CutPath(waypoints, miaDist)
	end

	-- the unit has no moving path
	local y = unit.path.server_pos.y
	if #waypoints == 1 then
		local pos = waypoints[1]:To3D(y)
		output.pred_pos, output.cast_pos = pos, pos
		return output
	end

	-- calc the maximum boundary offset + total skillshot delay
	local hitbox = (input.radius or 0) +
		(input.hitbox and unit.bounding_radius or 0)
	local delay = input.delay + (skipLatency and 0
		or self:Latency() + self.internalDelay)

	-- the skillshot speed is infinite
	if input.speed == 0 or input.speed >= 9999 then
		local threshold = speed * delay
		output.pred_pos = self:CutPath(waypoints, threshold)[1]:To3D(y)
		output.cast_pos = self:CutPath(waypoints, threshold - hitbox)[1]:To3D(y)
		return output
	end

	-- predict the unit path after a skillshot delay
	waypoints = self:CutPath(waypoints, speed * delay - hitbox)

	-- for each path segment calculate the interception time
	local source, totalTime = Point:New(input.source), 0
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		local reachTime = a:Distance(b) / speed
		a = a:Extend(b, -speed * totalTime)
		local t, pos = self:Interception(a, b,
			source, speed, input.speed, totalTime)

		-- the valid interception time must be positive
		if t > 0 and t >= totalTime and t <= totalTime + reachTime then
			local threshold = speed * t + hitbox
			output.pred_pos = self:CutPath(waypoints, threshold)[1]:To3D(y)
			output.cast_pos = pos:To3D(y); return output
		end

		-- check the next path segment
		totalTime = totalTime + reachTime
	end

	-- no solution found, the unit is completing his path
	local pos = waypoints[#waypoints]:To3D(y)
	output.pred_pos, output.cast_pos = pos, pos
	return output
end

--------------------
-- Prediction API --

local prediction = Pred:New(0.067, 25)

_G.Prediction = {
	calc_aa_damage_to_minion = function(self, source, minion)
		return prediction:CalcAutoAttackDamage(source, minion) end,
	get_aoe_prediction = function(self, input, unit)
		return prediction:GetAOEPrediction(input, unit) end,
	get_aoe_position = function(self, input, points, star_target)
		return prediction:GetAOEPosition(input, points, star_target) end,
	get_collision = function(self, input, end_pos, exclude)
		return prediction:GetCollision(input, end_pos, exclude) end,
	get_position_after = function(self, unit, delta, skip_latency)
		return prediction:GetPositionAfter(unit, delta, skip_latency) end,
	get_health_prediction = function(self, unit, delta)
		return prediction:GetHealthPrediction(unit, delta) end,
	get_lane_clear_health_prediction = function(self, unit, delta)
		return prediction:GetLaneClearHealthPrediction(unit, delta) end,
	get_prediction = function(self, input, unit)
		return prediction:GetPrediction(input, unit) end,
	get_immobile_duration = function(self, unit)
		return prediction:GetImmobileDuration(unit) end,
	get_invisible_duration = function(self, unit)
		return prediction:GetInvisibleDuration(unit) end,
	get_invulnerable_duration = function(self, unit)
		return prediction:GetInvulnerableDuration(unit) end,
	get_movement_speed = function(self, unit)
		return prediction:GetMovementSpeed(unit) end,
	get_waypoints = function(self, unit)
		return prediction:GetWaypoints(unit):Select(function(w)
			return w:To3D(unit.path.server_pos.y) end) end,
	is_loaded = function() return prediction.loaded end,
	set_collision_buffer = function(self, buffer)
		prediction.collisionBuffer = buffer or 30 end,
	set_internal_delay = function(self, delay)
		prediction.internalDelay = delay or 0.034 end
}
