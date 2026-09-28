.import "Sprites.js" as Sprites

// The runner itself: pure state + step functions, no QML. The panel owns one
// state object, feeds it input and frame time, and paints whatever it holds.
//
// Tuning follows Chrome's offline T-rex game at 1x: a 600x150 world, speed 6
// accelerating to 13, gravity 0.6, a jump that can be cut short by letting go,
// fast-fall on Down, pterodactyls only once the pace picks up, and the night
// flip every 700 points. Everything is expressed per 60 Hz frame; `dt` is the
// elapsed time in those frames, so a 144 Hz display plays at the same pace.

var WIDTH = 600
var HEIGHT = 150
var GROUND_Y = 140          // bottom edge of anything standing on the ground
var DINO_X = 50

var START_SPEED = 6
var MAX_SPEED = 13
var ACCELERATION = 0.001
var GRAVITY = 0.6
var JUMP_VELOCITY = -10
var DROP_VELOCITY = -5
var MIN_JUMP_HEIGHT = 30
var MAX_JUMP_TOP = 30
var SPEED_DROP_COEFFICIENT = 3
var CLEAR_FRAMES = 180       // no obstacles for the first three seconds
var GAP_COEFFICIENT = 0.6
var MAX_GAP_COEFFICIENT = 1.5
var MAX_DUPLICATION = 2
var SCORE_COEFFICIENT = 0.025
var ACHIEVEMENT_DISTANCE = 100
var INVERT_DISTANCE = 700
var INVERT_FRAMES = 720      // twelve seconds of night
var RESTART_DELAY_FRAMES = 30

var OBSTACLE_TYPES = [
  { type: "cactusSmall", minGap: 120, multipleSpeed: 4, minSpeed: 0 },
  { type: "cactusLarge", minGap: 120, multipleSpeed: 7, minSpeed: 0 },
  { type: "ptero", minGap: 150, multipleSpeed: 999, minSpeed: 8.5 }
]

// Bottom edge of a pterodactyl at each of its three heights: along the ground
// (jump it), head height (duck under it), and overhead (keep running).
var PTERO_BOTTOMS = [GROUND_Y, 113, 88]

function rand(min, max) {
  return min + Math.random() * (max - min)
}

function randInt(min, max) {
  return Math.floor(rand(min, max + 1))
}

function create() {
  var state = {
    phase: "idle",          // idle | playing | paused | over
    frames: 0,
    speed: START_SPEED,
    distance: 0,
    score: 0,
    highScore: 0,
    newHighScore: false,
    dino: { y: GROUND_Y, vy: 0, jumping: false, ducking: false, speedDrop: false, reachedMin: false },
    input: { jump: false, duck: false },
    obstacles: [],
    history: [],
    clouds: [],
    pebbles: [],
    groundOffset: 0,
    flash: 0,               // frames left of the every-100-points score blink
    night: 0,               // 0 day .. 1 night, eased
    nightFrames: 0,
    lastInvertAt: 0,
    overFrames: 0,
    blinkIn: randInt(120, 300)
  }
  seedScenery(state)
  return state
}

function seedScenery(state) {
  state.clouds = []
  for (var i = 0; i < 3; i++)
    state.clouds.push({ x: rand(40, WIDTH - 40), y: rand(20, 70) })
  state.pebbles = []
  for (var p = 0; p < 26; p++)
    state.pebbles.push({ x: rand(0, WIDTH), y: GROUND_Y + randInt(1, 4) * 2, w: randInt(1, 2) * 2, bump: Math.random() < 0.15 })
}

function reset(state) {
  var high = state.highScore
  var fresh = create()
  fresh.highScore = high
  for (var key in fresh) state[key] = fresh[key]
}

function start(state) {
  reset(state)
  state.phase = "playing"
  jump(state)
}

// ---- input --------------------------------------------------------------

function jump(state) {
  var d = state.dino
  if (d.jumping || d.ducking) return
  d.jumping = true
  d.reachedMin = false
  d.speedDrop = false
  d.vy = JUMP_VELOCITY - state.speed / 10
}

// Letting go early turns a full jump into a hop, once it has cleared the
// minimum height.
function endJump(state) {
  var d = state.dino
  if (d.reachedMin && d.vy < DROP_VELOCITY) d.vy = DROP_VELOCITY
}

function press(state, action) {
  if (action === "jump") {
    state.input.jump = true
    if (state.phase === "idle") { start(state); return "started" }
    if (state.phase === "paused") { state.phase = "playing"; return "resumed" }
    if (state.phase === "over") {
      if (state.overFrames < RESTART_DELAY_FRAMES) return ""
      start(state)
      return "restarted"
    }
    jump(state)
  } else if (action === "duck") {
    state.input.duck = true
    if (state.phase !== "playing") return ""
    var d = state.dino
    if (d.jumping) {
      d.speedDrop = true
      d.vy = 1
    } else {
      d.ducking = true
    }
  }
  return ""
}

function release(state, action) {
  if (action === "jump") {
    state.input.jump = false
    if (state.phase === "playing") endJump(state)
  } else if (action === "duck") {
    state.input.duck = false
    state.dino.ducking = false
    state.dino.speedDrop = false
  }
}

function pause(state) {
  if (state.phase === "playing") state.phase = "paused"
}

// ---- simulation ---------------------------------------------------------

function dinoSprite(state) {
  var s = Sprites.sprites
  var d = state.dino
  if (state.phase === "over") return s.dinoDead
  if (state.phase === "idle")
    return state.blinkIn <= 0 ? s.dinoBlink : s.dinoStand
  if (d.jumping) return s.dinoStand
  var alt = Math.floor(state.frames / 6) % 2 === 0
  if (d.ducking) return alt ? s.dinoDuckA : s.dinoDuckB
  return alt ? s.dinoRunA : s.dinoRunB
}

function obstacleSprite(ob, frames) {
  var s = Sprites.sprites
  if (ob.type === "ptero") return Math.floor(frames / 10) % 2 === 0 ? s.pteroUp : s.pteroDown
  return s[ob.type]
}

function obstacleWidth(ob) {
  var sprite = obstacleSprite(ob, 0)
  return ob.size * sprite.width + (ob.size - 1) * Sprites.PIXEL
}

function tooManyRepeats(state, type) {
  var run = 0
  for (var i = 0; i < state.history.length; i++) {
    if (state.history[i] !== type) break
    run++
  }
  return run >= MAX_DUPLICATION
}

function spawnObstacle(state) {
  var choices = []
  for (var i = 0; i < OBSTACLE_TYPES.length; i++) {
    var t = OBSTACLE_TYPES[i]
    if (state.speed >= t.minSpeed && !tooManyRepeats(state, t.type)) choices.push(t)
  }
  if (choices.length === 0) choices.push(OBSTACLE_TYPES[0])
  var kind = choices[randInt(0, choices.length - 1)]

  var size = state.speed > kind.multipleSpeed ? randInt(1, 3) : 1
  var ob = { type: kind.type, size: size, x: WIDTH, bottom: GROUND_Y, speedOffset: 0, gap: 0 }
  if (kind.type === "ptero") {
    ob.bottom = PTERO_BOTTOMS[randInt(0, PTERO_BOTTOMS.length - 1)]
    ob.speedOffset = Math.random() < 0.5 ? -0.8 : 0.8
  }

  var width = obstacleWidth(ob)
  var minGap = Math.round(width * state.speed + kind.minGap * GAP_COEFFICIENT)
  ob.gap = randInt(minGap, Math.round(minGap * MAX_GAP_COEFFICIENT))

  state.obstacles.push(ob)
  state.history.unshift(kind.type)
  if (state.history.length > MAX_DUPLICATION) state.history.length = MAX_DUPLICATION
}

function updateDino(state, dt) {
  var d = state.dino
  if (!d.jumping) {
    d.ducking = state.input.duck
    return
  }
  d.y += d.vy * dt * (d.speedDrop ? SPEED_DROP_COEFFICIENT : 1)
  d.vy += GRAVITY * dt
  var top = d.y - Sprites.sprites.dinoStand.height
  if (GROUND_Y - d.y > MIN_JUMP_HEIGHT) d.reachedMin = true
  if (top < MAX_JUMP_TOP || d.speedDrop) endJump(state)
  if (d.reachedMin && !state.input.jump) endJump(state)
  if (d.y >= GROUND_Y) {
    d.y = GROUND_Y
    d.vy = 0
    d.jumping = false
    d.speedDrop = false
    d.ducking = state.input.duck
  }
}

function updateObstacles(state, dt) {
  var obs = state.obstacles
  for (var i = 0; i < obs.length; i++) obs[i].x -= (state.speed + obs[i].speedOffset) * dt
  while (obs.length > 0 && obs[0].x + obstacleWidth(obs[0]) < 0) obs.shift()

  if (state.frames < CLEAR_FRAMES) return
  var last = obs.length > 0 ? obs[obs.length - 1] : null
  if (!last || last.x + obstacleWidth(last) + last.gap < WIDTH) spawnObstacle(state)
}

function updateScenery(state, dt) {
  var clouds = state.clouds
  for (var i = 0; i < clouds.length; i++) {
    clouds[i].x -= state.speed * 0.2 * dt
    if (clouds[i].x < -Sprites.sprites.cloud.width) {
      clouds[i].x = WIDTH + rand(0, 200)
      clouds[i].y = rand(20, 70)
    }
  }
  var pebbles = state.pebbles
  for (var p = 0; p < pebbles.length; p++) {
    pebbles[p].x -= state.speed * dt
    if (pebbles[p].x < -8) {
      pebbles[p].x = WIDTH + rand(0, 40)
      pebbles[p].bump = Math.random() < 0.15
    }
  }
}

function updateScore(state, dt) {
  var before = state.score
  state.distance += state.speed * dt
  state.score = Math.floor(state.distance * SCORE_COEFFICIENT)
  if (Math.floor(state.score / ACHIEVEMENT_DISTANCE) > Math.floor(before / ACHIEVEMENT_DISTANCE))
    state.flash = 60
  if (Math.floor(state.score / INVERT_DISTANCE) > state.lastInvertAt) {
    state.lastInvertAt = Math.floor(state.score / INVERT_DISTANCE)
    state.nightFrames = INVERT_FRAMES
  }
}

function updateNight(state, dt) {
  if (state.nightFrames > 0) state.nightFrames = Math.max(0, state.nightFrames - dt)
  var target = state.nightFrames > 0 ? 1 : 0
  var step = dt / 45
  if (state.night < target) state.night = Math.min(target, state.night + step)
  else if (state.night > target) state.night = Math.max(target, state.night - step)
}

// Pixel-exact collision: bounding boxes first, then the overlapping art
// pixels of both sprites. Anything the eye would call a near miss is one.
function spritesHit(a, ax, ay, b, bx, by) {
  var P = Sprites.PIXEL
  var left = Math.max(ax, bx), right = Math.min(ax + a.width, bx + b.width)
  var top = Math.max(ay, by), bottom = Math.min(ay + a.height, by + b.height)
  if (left >= right || top >= bottom) return false
  for (var y = top; y < bottom; y += P / 2) {
    for (var x = left; x < right; x += P / 2) {
      if (Sprites.solidAt(a, Math.floor((x - ax) / P), Math.floor((y - ay) / P))
          && Sprites.solidAt(b, Math.floor((x - bx) / P), Math.floor((y - by) / P)))
        return true
    }
  }
  return false
}

function collides(state) {
  var dino = dinoSprite(state)
  var dx = DINO_X, dy = state.dino.y - dino.height
  for (var i = 0; i < state.obstacles.length; i++) {
    var ob = state.obstacles[i]
    if (ob.x > dx + dino.width) break
    var sprite = obstacleSprite(ob, state.frames)
    for (var n = 0; n < ob.size; n++) {
      var ox = ob.x + n * (sprite.width + Sprites.PIXEL)
      if (spritesHit(dino, dx, dy, sprite, ox, ob.bottom - sprite.height)) return true
    }
  }
  return false
}

// Advance by `dt` 60 Hz frames. Returns "crashed" on the frame the run ends.
function step(state, dt) {
  dt = Math.max(0, Math.min(dt, 3))
  if (state.phase === "idle") {
    state.blinkIn -= dt
    if (state.blinkIn < -8) state.blinkIn = randInt(120, 300)
    return ""
  }
  if (state.phase === "over") {
    state.overFrames += dt
    return ""
  }
  if (state.phase !== "playing") return ""

  state.frames += dt
  if (state.flash > 0) state.flash = Math.max(0, state.flash - dt)
  updateDino(state, dt)
  updateObstacles(state, dt)
  updateScenery(state, dt)
  updateScore(state, dt)
  updateNight(state, dt)

  if (collides(state)) {
    state.phase = "over"
    state.overFrames = 0
    state.newHighScore = state.score > state.highScore
    if (state.newHighScore) state.highScore = state.score
    return "crashed"
  }

  if (state.speed < MAX_SPEED) state.speed = Math.min(MAX_SPEED, state.speed + ACCELERATION * dt)
  return ""
}
