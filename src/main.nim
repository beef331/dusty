import nico
import nico/vec
import std/[random, times, os]
{.experimental: "views".}
const 
  ScreenSize = 1024
  ChunkSize = 128
  ThreadCount = ScreenSize.div(ChunkSize) * ScreenSize.div(ChunkSize)
  DrawRange = 10..200
  ScrollSpeed = 10
type
  ParticleKind = enum
    air, sand, water, steel, salt, gas
  Particle = object
    dirty: bool
    kind: ParticleKind
  MoveShape = enum
    msU, msTri
  Properties = object
    density: float
    velocity: float
    moveShape: MoveShape
    upsideDown: bool
  Direction = enum
    vertical, left, right, invert
  Level = array[ScreenSize * ScreenSize, Particle]
  ThreadData = object
    level: ptr Level
    index: int
const 
  ParticleProp = [
    air: Properties(density: 0, velocity: 10, moveShape: msTri, upsideDown: true),
    sand: Properties(density: 1, velocity: 1, moveShape: msTri, upsideDown: false),
    water: Properties(density: 0.5, velocity: 1, moveShape: msU, upsideDown: false),
    steel: Properties(density: 100, velocity: 0, moveShape: msU, upsideDown: false),
    salt: Properties(density: 2, velocity: 2, moveShape: msTri, upsideDown: false),
    gas: Properties(density: 0.0001, velocity: 1, moveShape: msTri, upsideDown: true)]
  Colors = [
    air: 0,
    sand: 9,
    water: 12,
    steel: 5,
    salt: 7,
    gas: 1,
  ]
  UpdateMask = {sand, water, salt, gas}

var
  drawSize = 100
  level: Level
  tick = 0
proc moveTowards(start: int, level: ptr Level, direction: set[Direction]): (int, int) {.inline.} = 
  let 
    yOffset = 
      if invert in direction:
        -ScreenSize
      else:
        ScreenSize
    xOffset = 
      if right in direction:
        1
      else:
        -1
    velocity = ParticleProp[level[start].kind].velocity
    direction = direction - {invert}

  if direction == {vertical}:
    result[1] = start
    while result[1] < (ScreenSize - 1) * ScreenSize and result[1] >= 0 and result[0] < velocity:
      result[1] += yOffset
      inc result[0]
  
  elif direction == {left} or direction == {right}:
    result[1] = start
    while result[1].mod(ScreenSize) < (ScreenSize - 1) and result[1].mod(ScreenSize) > 0 and result[0] < velocity:
      result[1] += xOffset
      inc result[0]

  elif {right, vertical} <= direction:
    result[1] = start
    while result[1].mod(ScreenSize) < (ScreenSize - 1) and  result[1] < (ScreenSize - 1) * ScreenSize and  result[1] > 0 and result[0] < velocity:
      result[1] += xOffset + yOffset
      inc result[0]

  elif {left, vertical} <= direction:
    result[1] = start
    while result[1].mod(ScreenSize) > 0 and result[1] > 0 and result[1] < level[].len - ScreenSize and result[0] < velocity:
      result[1] += xOffset + yOffset
      inc result[0]

  if result[1] notin 0..level[].len:
    result[1] = start

proc swap(level: ptr Level, a, b: int) {.inline.} =
  let currentKind = level[b].kind
  if currentKind != level[a].kind:
    level[b] = level[a]
    level[b].dirty = true
    level[a].kind = currentKind
    level[a].dirty = true

proc update(data: ThreadData) {.thread.} =
  var
    level = data.level
    offset = data.index * (ChunkSize * ChunkSize)
    lastTick = 0
  while true:
    var i = 0
    if tick != lastTick:
      while i < ChunkSize * ChunkSize:
        let kind = level[i + offset].kind
        if kind in UpdateMask and not level[i + offset].dirty:
          let
            pos = i + offset
            props = ParticleProp[kind]
            invertSet = if props.upsideDown: {invert} else: {}
            (vertSteps, vertPos) =  pos.moveTowards(level, {vertical} + invertSet)
          if vertSteps > 0 and ParticleProp[level[vertPos].kind].density < props.density:
            level.swap(pos, vertPos)
            continue
          if rand(0..1) == 1:
            let (leftVertSteps, leftVertPos) =  pos.moveTowards(level, {vertical, left} + invertSet)
            if leftVertSteps > 0 and ParticleProp[level[leftVertPos].kind].density < props.density:
              level.swap(pos, leftVertPos)
              continue
          else:
            let (rightVertSteps, rightVertPos) =  pos.moveTowards(level, {vertical, right} + invertSet)
            if rightVertSteps > 0 and ParticleProp[level[rightVertPos].kind].density < props.density:
              level.swap(pos, rightVertPos)
              continue
          if props.moveShape == msU:
            if rand(0..1) == 1:
              let (leftSteps, leftPos) =  pos.moveTowards(level, {left} + invertSet)
              if leftSteps > 0 and ParticleProp[level[leftPos].kind].density < props.density:
                level.swap(pos, leftPos)
                continue
            else:
              let (rightSteps, rightPos) =  pos.moveTowards(level, {right} + invertSet)
              if rightSteps > 0 and ParticleProp[level[rightPos].kind].density < props.density:
                level.swap(pos, rightPos)
                continue
        inc i
      lastTick = tick
    sleep(1)
proc gameInit() =
  loadFont(0, "font.png")

proc drawParticle(level: var Level, kind: ParticleKind) =
  let 
    (x, y) = mouse()
    halfDraw = drawSize.div(2)
  for xPos in -halfDraw..halfDraw:
    for yPos in -halfDraw..halfDraw:
      if vec2f(xPos, yPos).length <= halfDraw:
        let ind = (x + xPos) + (y + yPos) * ScreenSize
        if ind in 0 ..< ScreenSize * ScreenSize and level[ind].kind == air:
          level[ind].kind = kind
          level[ind].dirty = true

var updateThreads: array[ThreadCount, Thread[ThreadData]]
for x in 0..<ThreadCount:
  updateThreads[x].createThread(update, ThreadData(level: level.addr, index: x))

proc gameUpdate(dt: float32) =
  if mousebtn(0):
    level.drawParticle(sand)
  if mousebtn(2):
    level.drawParticle(water)
  if mousebtn(1):
    level.drawParticle(steel)
  if btn(pcA):
    level.drawParticle(salt)
  if btn(pcB):
    level.drawParticle(gas)
  if btn(pcStart):
    for x in level.mitems:
      x.kind = air
  drawSize = clamp(drawSize + mousewheel() * ScrollSpeed, DrawRange.a, DrawRange.b)
  inc tick

fps(300)
var lastDraw = cpuTime()
proc gameDraw() =
  cls()
  let fps = 1.0 / (cpuTime() - lastDraw)
  for i, tile in level:
    if tile.kind != air:
      let
        x = i.mod(ScreenSize)
        y = i.div(ScreenSize)
      psetraw(x, y, Colors[tile.kind])
      level[i].dirty = false
  setColor(15)
  let (x,y) = mouse()
  circ(x,y, drawSize.div(2))
  printc($fps, ScreenSize.div(2), 0, 10)
  lastDraw = cpuTime()


nico.init("myOrg", "myApp")
nico.createWindow("myApp", ScreenSize, ScreenSize, 1, false)
nico.run(gameInit, gameUpdate, gameDraw)