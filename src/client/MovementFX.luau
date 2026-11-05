--!strict
-- Sprint 42 movement effects (design-vault/Mechanics/Movement Tech.md, "Effects and feel").
-- Camera (local player only): FOV widens with horizontal speed plus a +6 kick on a dash, a slight roll while
-- sliding, a dip on landing scaled to the fall, and speed lines at the screen edges above 24 studs/s.
-- Sounds (local only): dash whoosh, slide scrape, landing thud (splash in water), a wind loop at speed.
-- Particles (everyone): dash puff, slide dust/spray trail, wall jump dust, double jump air ring. The local player's
-- come from Movement.onAction; other players' from the MoveAction/MoveActionAt attributes the server sets.
-- Particles use one shared emitter per kind (moved, then :Emit), so they're pooled, and nothing past CULL_DISTANCE.
-- Built-in content only (rbxasset://).
-- FOV and camera offsets are applied as tracked deltas, the same way Dread.luau does it: last frame's delta is taken
-- off and the new one added, so Dread's FOV drop and this FOV boost simply add up.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Movement = require(script.Parent.Movement)

-- FOV: +0 at walk speed, +FOV_SPEED_MAX at MOMENTUM_CAP (70 -> 82 on the default camera)
local WALK_SPEED = 10
local MOMENTUM_CAP = 32
local FOV_SPEED_MAX = 12
local FOV_RATE = 6
local DASH_KICK = 6
local KICK_DECAY = 5
-- Slide camera roll
local SLIDE_TILT = math.rad(4)
local TILT_RATE = 10
local SLIDE_FALLBACK = 1.5 -- seconds; a slide that never reports SlideEnd stops counting after this
-- Landing dip: a critically damped spring kicked by the fall speed
local DIP_STIFFNESS = 120
local DIP_DAMPING = 2 * math.sqrt(DIP_STIFFNESS)
local DIP_PER_SPEED = 0.3
local DIP_KICK_MAX = 24
local LAND_MIN_SPEED = 12 -- falls slower than this get no dip or thud
-- Speed lines
local LINES_FROM = 24
local LINES_FULL = 32
local LINE_COUNT = 18
local LINE_LIFE = 0.28
local LINE_RATE = 45 -- lines per second at full intensity
-- Particles
local CULL_DISTANCE = 150
local TRAIL_DUST_RATE = 40
local TRAIL_SPRAY_RATE = 70
local REMOTE_SLIDE_TIME = 1 -- other players: a Slide counts as sliding for this long while they still move fast
local REMOTE_SLIDE_MIN_SPEED = 12

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TEX_DROP = "rbxasset://textures/particles/SquareParticle.png"
local SND_WIND = "rbxasset://sounds/action_falling.ogg"
local SND_LAND = "rbxasset://sounds/action_jump_land.mp3"
local SND_SPLASH = "rbxasset://sounds/impact_water.mp3"
local SND_SCRAPE = "rbxasset://sounds/action_footsteps_plastic.mp3"

local RENDER_UNDO = "HushMoveFXUndo"
local RENDER_APPLY = "HushMoveFXApply"

local MovementFX = {}

local started = false

type Emitters = {
	dust: ParticleEmitter,
	puff: ParticleEmitter,
	spray: ParticleEmitter,
	ring: ParticleEmitter,
}

type Line = {
	frame: Frame,
	age: number,
	angle: number,
	radius: number,
	length: number,
}

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

local function emitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LockedToPart = false
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function buildEmitters(): (Emitters, { [ParticleEmitter]: Attachment })
	local anchor = Instance.new("Part")
	anchor.Name = "MovementFX"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(0, -500, 0)
	local holders: { [ParticleEmitter]: Attachment } = {}
	local function holder(name: string): Attachment
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = anchor
		return a
	end
	local dustA, puffA, sprayA, ringA = holder("Dust"), holder("Puff"), holder("Spray"), holder("Ring")
	local dust = emitter(dustA, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(150, 140, 125)),
		Size = seq(0.6, 2.4),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 3,
		Acceleration = Vector3.new(0, 1.5, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
	})
	local puff = emitter(puffA, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(225, 228, 235)),
		Size = seq(1, 3.6),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.3, 0.45),
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 6,
		Rotation = NumberRange.new(0, 360),
	})
	local spray = emitter(sprayA, {
		Texture = TEX_DROP,
		Color = ColorSequence.new(Color3.fromRGB(170, 205, 225)),
		Size = seq(0.18, 0.08),
		Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(7, 12),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -45, 0),
		LightEmission = 0.2,
	})
	local ring = emitter(ringA, {
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromRGB(220, 235, 255)),
		Size = seq(1, 9),
		Transparency = seq(0.25, 1),
		Lifetime = NumberRange.new(0.35, 0.35),
		Speed = NumberRange.new(0.05, 0.05),
		SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Top,
		-- Faces along its (upward) velocity, so the ring lies flat under the feet
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		LightEmission = 0.6,
	})
	anchor.Parent = workspace
	holders[dust] = dustA
	holders[puff] = puffA
	holders[spray] = sprayA
	holders[ring] = ringA
	return { dust = dust, puff = puff, spray = spray, ring = ring }, holders
end

local function sound(name: string, id: string, volume: number, speed: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = `HushMoveFX_{name}`
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.Looped = looped
	s.Parent = SoundService
	return s
end

local function playOnce(s: Sound, volume: number?)
	if volume then
		s.Volume = volume
	end
	s.TimePosition = 0
	s:Play()
end

-- Top of Workspace.Water above pos, if pos is inside its footprint and the water has any depth
local function waterTop(pos: Vector3): number?
	local w = workspace:FindFirstChild("Water")
	if not (w and w:IsA("BasePart")) or w.Size.Y < 0.2 then
		return nil
	end
	local p = w.CFrame:PointToObjectSpace(pos)
	if math.abs(p.X) > w.Size.X / 2 or math.abs(p.Z) > w.Size.Z / 2 then
		return nil
	end
	return w.Position.Y + w.Size.Y / 2
end

local function feetOf(root: BasePart, humanoid: Humanoid?): Vector3
	local drop = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2)
	return root.Position - Vector3.new(0, drop, 0)
end

local function inWater(feet: Vector3): boolean
	local top = waterTop(feet)
	return top ~= nil and feet.Y < top
end

local function horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function buildLines(gui: ScreenGui): { Line }
	local holder = Instance.new("Frame")
	holder.Name = "SpeedLines"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local lines: { Line } = {}
	for i = 1, LINE_COUNT do
		local f = Instance.new("Frame")
		f.Name = `Line{i}`
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = Color3.fromRGB(235, 240, 255)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		f.Visible = false
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = holder
		table.insert(lines, { frame = f, age = LINE_LIFE, angle = 0, radius = 0, length = 0 })
	end
	return lines
end

function MovementFX.start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer

	local fx, holders = buildEmitters()
	local function emitAt(e: ParticleEmitter, at: CFrame, count: number)
		local cam = workspace.CurrentCamera
		if cam and (cam.CFrame.Position - at.Position).Magnitude > CULL_DISTANCE then
			return
		end
		holders[e].WorldCFrame = at
		e:Emit(count)
	end

	local whoosh = sound("Whoosh", SND_WIND, 0.7, 1.9, false)
	local wind = sound("Wind", SND_WIND, 0, 1.2, true)
	local scrape = sound("Scrape", SND_SCRAPE, 0, 1.9, true)
	local thud = sound("Thud", SND_LAND, 0.5, 0.85, false)
	local splash = sound("Splash", SND_SPLASH, 0.6, 1.1, false)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MovementFX"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Under Dread's vignette (50), over the world
	gui.DisplayOrder = 40
	local lines = buildLines(gui)
	gui.Parent = player:WaitForChild("PlayerGui")

	local humanoid: Humanoid? = nil
	local root: BasePart? = nil
	local slideUntil = 0
	local kick = 0
	local fovBoost = 0
	local tilt = 0
	local dip, dipVel = 0, 0
	local fallSpeed = 0
	local lineCarry = 0
	-- Weak keys: old characters drop out on their own
	local trailCarry: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

	-- Camera bookkeeping, undone exactly like Dread's
	local fovCamera: Camera? = nil
	local appliedFov = 0
	local offsetCamera: Camera? = nil
	local appliedOffset = CFrame.identity

	local function setFov(cam: Camera, boost: number)
		if fovCamera ~= cam then
			local old = fovCamera
			if old then
				old.FieldOfView -= appliedFov
			end
			fovCamera = cam
			appliedFov = 0
		end
		cam.FieldOfView = cam.FieldOfView - appliedFov + boost
		appliedFov = boost
	end

	local function undoOffset()
		local cam = offsetCamera
		if cam then
			cam.CFrame = cam.CFrame * appliedOffset:Inverse()
		end
		offsetCamera = nil
		appliedOffset = CFrame.identity
	end

	local function sliding(): boolean
		return os.clock() < slideUntil
	end

	-- One-shot particles shared by the local player and remote players
	local function burst(action: string, r: BasePart, hum: Humanoid?, direction: Vector3?)
		local feet = feetOf(r, hum)
		if action == "Dash" or action == "DashJump" then
			local dir = direction or horizontal(r.AssemblyLinearVelocity)
			if dir.Magnitude < 0.1 then
				dir = r.CFrame.LookVector
			end
			-- Front = LookVector, so look backwards to blow the puff out behind
			local at = r.Position - dir.Unit * 1.5
			emitAt(fx.puff, CFrame.lookAt(at, at - dir.Unit), 14)
		elseif action == "DoubleJump" then
			emitAt(fx.ring, CFrame.new(feet), 1)
			emitAt(fx.puff, CFrame.lookAt(feet, feet - Vector3.yAxis), 6)
		elseif action == "WallJump" then
			-- direction is the wall normal for the local player; others: the wall is behind their new velocity
			local normal = direction or -horizontal(r.AssemblyLinearVelocity)
			local at = r.Position
			if direction == nil and normal.Magnitude > 0.1 then
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = { r.Parent :: Instance }
				params.FilterType = Enum.RaycastFilterType.Exclude
				local hit = workspace:Raycast(r.Position, normal.Unit * 4, params)
				if hit then
					at, normal = hit.Position, hit.Normal
				end
			elseif normal.Magnitude > 0.1 then
				at = r.Position - normal.Unit * 1.4
			end
			emitAt(fx.dust, CFrame.new(at), 12)
		end
	end

	-- Local player's moves
	Movement.onAction(function(action: string, direction: Vector3?)
		local r = root
		if not r then
			return
		end
		if action == "Dash" or action == "DashJump" then
			kick += DASH_KICK
			kick = math.min(kick, DASH_KICK * 1.5)
			playOnce(whoosh)
		elseif action == "Slide" then
			slideUntil = os.clock() + SLIDE_FALLBACK
		elseif action == "SlideEnd" or action == "SlideHop" then
			slideUntil = 0
		elseif action == "DoubleJump" or action == "WallJump" then
			whoosh.PlaybackSpeed = 2.4
			playOnce(whoosh, 0.35)
			task.delay(0.4, function()
				whoosh.PlaybackSpeed = 1.9
				whoosh.Volume = 0.7
			end)
		end
		burst(action, r, humanoid, direction)
	end)

	-- Other players' moves, from the server attributes
	local function watchCharacter(other: Player, character: Model)
		character:GetAttributeChangedSignal("MoveActionAt"):Connect(function()
			if other.Character ~= character then
				return
			end
			local action = character:GetAttribute("MoveAction")
			local r = character:FindFirstChild("HumanoidRootPart")
			if typeof(action) ~= "string" or not (r and r:IsA("BasePart")) then
				return
			end
			burst(action, r, character:FindFirstChildOfClass("Humanoid"), nil)
		end)
	end
	local function watchPlayer(other: Player)
		if other == player then
			return
		end
		other.CharacterAdded:Connect(function(c)
			watchCharacter(other, c)
		end)
		if other.Character then
			watchCharacter(other, other.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end

	local function landed(speed: number)
		local r = root
		if speed < LAND_MIN_SPEED or not r then
			return
		end
		dipVel -= math.min(speed * DIP_PER_SPEED, DIP_KICK_MAX)
		local loud = math.clamp((speed - LAND_MIN_SPEED) / 50, 0, 1)
		playOnce(thud, 0.25 + 0.45 * loud)
		local feet = feetOf(r, humanoid)
		if inWater(feet + Vector3.new(0, 0.5, 0)) then
			playOnce(splash, 0.3 + 0.5 * loud)
			emitAt(fx.spray, CFrame.new(feet), math.floor(10 + 20 * loud))
		else
			emitAt(fx.dust, CFrame.new(feet), math.floor(3 + 8 * loud))
		end
	end

	local function onCharacter(character: Model)
		humanoid, root = nil, nil
		slideUntil, dip, dipVel, fallSpeed = 0, 0, 0, 0
		local hum = character:WaitForChild("Humanoid", 10)
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		if player.Character ~= character or not (hum and hum:IsA("Humanoid")) then
			return
		end
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end
		humanoid, root = hum, hrp
		hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed and humanoid == hum then
				landed(fallSpeed)
				fallSpeed = 0
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- Slide trail for anyone sliding nearby: the local player from onAction, others from the attributes
	local function trail(character: Model, r: BasePart, hum: Humanoid?, dt: number)
		local feet = feetOf(r, hum)
		local wet = inWater(feet + Vector3.new(0, 0.5, 0))
		local rate = if wet then TRAIL_SPRAY_RATE else TRAIL_DUST_RATE
		local carry = (trailCarry[character] or 0) + rate * dt
		local n = math.floor(carry)
		trailCarry[character] = carry - n
		if n > 0 then
			local back = horizontal(r.AssemblyLinearVelocity)
			local at = CFrame.new(feet)
			if back.Magnitude > 0.1 then
				-- Kick the spray up and back from the feet
				at = CFrame.lookAt(feet, feet - back.Unit) * CFrame.Angles(math.rad(-50), 0, 0)
			end
			emitAt(if wet then fx.spray else fx.dust, at, n)
		end
	end

	RunService:BindToRenderStep(RENDER_UNDO, Enum.RenderPriority.Camera.Value - 2, undoOffset)

	RunService:BindToRenderStep(RENDER_APPLY, Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local cam = workspace.CurrentCamera
		local hum, r = humanoid, root
		local alive = hum ~= nil and r ~= nil and r.Parent ~= nil and hum.Health > 0
		local speed = if alive and r then horizontal(r.AssemblyLinearVelocity).Magnitude else 0
		local isSliding = alive and sliding()

		-- Track the fall speed while airborne, for the landing dip
		if alive and r and hum and hum.FloorMaterial == Enum.Material.Air then
			fallSpeed = math.max(fallSpeed, -r.AssemblyLinearVelocity.Y)
		end

		-- FOV
		local target = FOV_SPEED_MAX * math.clamp((speed - WALK_SPEED) / (MOMENTUM_CAP - WALK_SPEED), 0, 1)
		fovBoost += (target - fovBoost) * (1 - math.exp(-FOV_RATE * dt))
		kick *= math.exp(-KICK_DECAY * dt)
		if kick < 0.01 then
			kick = 0
		end
		if cam then
			setFov(cam, fovBoost + kick)
		end

		-- Roll and landing dip
		local tiltTarget = if isSliding then SLIDE_TILT else 0
		tilt += (tiltTarget - tilt) * (1 - math.exp(-TILT_RATE * dt))
		local step = math.min(dt, 1 / 30)
		dipVel += (-DIP_STIFFNESS * dip - DIP_DAMPING * dipVel) * step
		dip += dipVel * step
		if math.abs(dip) < 0.001 and math.abs(dipVel) < 0.01 then
			dip, dipVel = 0, 0
		end
		if cam and (math.abs(tilt) > 0.0005 or dip ~= 0) then
			appliedOffset = CFrame.new(0, dip, 0) * CFrame.Angles(0, 0, tilt)
			offsetCamera = cam
			cam.CFrame = cam.CFrame * appliedOffset
		end

		-- Sounds
		local fast = math.clamp((speed - LINES_FROM) / (LINES_FULL - LINES_FROM), 0, 1)
		wind.Volume = 0.35 * fast
		if fast > 0 and not wind.IsPlaying then
			wind:Play()
		elseif fast == 0 and wind.IsPlaying then
			wind:Stop()
		end
		local onGround = hum ~= nil and hum.FloorMaterial ~= Enum.Material.Air
		local scraping = isSliding and onGround
		scrape.Volume = if scraping then 0.35 else 0
		if scraping and not scrape.IsPlaying then
			scrape:Play()
		elseif not scraping and scrape.IsPlaying then
			scrape:Stop()
		end

		-- Speed lines
		local viewport = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		lineCarry += LINE_RATE * fast * dt
		for _, line in lines do
			if line.age >= LINE_LIFE and lineCarry >= 1 then
				lineCarry -= 1
				line.age = 0
				line.angle = math.random() * math.pi * 2
				line.radius = 0.42 + math.random() * 0.12
				line.length = 0.08 + math.random() * 0.1
			end
			if line.age < LINE_LIFE then
				line.age += dt
				local t = math.clamp(line.age / LINE_LIFE, 0, 1)
				local half = viewport / 2
				local radius = (line.radius + 0.12 * t) * math.max(half.X, half.Y) * 1.1
				local dir = Vector2.new(math.cos(line.angle), math.sin(line.angle))
				local pos = half + Vector2.new(dir.X * radius, dir.Y * radius * (half.Y / half.X) * 1.4)
				local f = line.frame
				f.Visible = true
				f.Position = UDim2.fromOffset(pos.X, pos.Y)
				f.Size = UDim2.fromOffset(line.length * viewport.Y, 2)
				f.Rotation = math.deg(line.angle)
				f.BackgroundTransparency = 1 - 0.55 * math.sin(t * math.pi) * math.max(fast, 0.3)
			else
				line.frame.Visible = false
			end
		end
		lineCarry = math.min(lineCarry, 2)

		-- Slide trails
		if isSliding and onGround and r and hum then
			trail(r.Parent :: Model, r, hum, dt)
		end
		local now = workspace:GetServerTimeNow()
		for _, other in Players:GetPlayers() do
			local c = other.Character
			if other ~= player and c then
				local at = c:GetAttribute("MoveActionAt")
				local otherRoot = c:FindFirstChild("HumanoidRootPart")
				if
					c:GetAttribute("MoveAction") == "Slide"
					and typeof(at) == "number"
					and now - at < REMOTE_SLIDE_TIME
					and otherRoot
					and otherRoot:IsA("BasePart")
					and horizontal(otherRoot.AssemblyLinearVelocity).Magnitude > REMOTE_SLIDE_MIN_SPEED
				then
					trail(c, otherRoot, c:FindFirstChildOfClass("Humanoid"), dt)
				else
					trailCarry[c] = nil
				end
			end
		end
	end)

	-- Studio-only hooks for checks
	if RunService:IsStudio() then
		(MovementFX :: any)._test = {
			state = function()
				return {
					fovBoost = fovBoost,
					kick = kick,
					tilt = math.deg(tilt),
					dip = dip,
					sliding = sliding(),
				}
			end,
			landed = landed,
		}
	end
end

return MovementFX
