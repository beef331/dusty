import nico
import nico/vec
import std/[random, times, math, cpuinfo]

const 
  ScreenSize = 1024
  DrawRange = 10..200
  ScrollSpeed = 10
  CheckerRange = 0..<4

let 
  (ChunkSize, ThreadWidth, ThreadCount, ThreadRange) = block:
    let
      baseFourThreads = 4f.pow(countProcessors().float.log(4f).floor)
      size = min(ScreenSize.div(baseFourThreads), 512)
      width = ScreenSize.div(size)
      count = width.div(2).float.pow(2).int # Should be half area squared
      rng = 0..<count
    (size, width, count, rng)
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
    water: Properties(density: 0.5, velocity: 2, moveShape: msU, upsideDown: false),
    steel: Properties(density: 100, velocity: 0, moveShape: msU, upsideDown: false),
    salt: Properties(density: 2, velocity: 3, moveShape: msTri, upsideDown: false),
    gas: Properties(density: 0.0001, velocity: 5, moveShape: msTri, upsideDown: true)]
  Colors = [
    air: 0,
    sand: 9,
    water: 12,
    steel: 5,
    salt: 7,
    gas: 1,
  ]
  UpdateMask = {sand, water, salt, gas}
echo ThreadCount
var
  drawSize = 100
  level: Level
  tick = 0
  updateThreads = newSeq[Thread[ThreadData]](ThreadCount)
  threadChannels = newSeq[Channel[int]](ThreadCount)
  mainChannels = newSeq[Channel[int]](ThreadCount)
for x in 0..<threadChannels.len:
  threadChannels[x].open()
  mainChannels[x].open()
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

proc draw(data: ThreadData, chunkIndex: int) {.thread, inline.} =
  var level = data.level
  let offset = chunkIndex * (ChunkSize * ChunkSize)
  for i in 0..<ChunkSize * ChunkSize:
    let
      pos = i + offset
      x = pos.mod(ScreenSize)
      y = pos.div(ScreenSize)
    {.cast(gcsafe).}:
      psetraw(x, y, Colors[level[pos].kind])
    level[pos].dirty = false

proc update(data: ThreadData, chunkIndex: int) {.thread, inline.} =
  var
    level = data.level
    offset = chunkIndex * (ChunkSize * ChunkSize)
  for i in 0 ..< ChunkSize * ChunkSize:
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

proc threadWait(data: ThreadData) {.thread.} =
  while true:
    {.cast(gcSafe).}:
      let id = threadChannels[data.index].recv()
      update(data, id)
      draw(data, id)
      mainChannels[data.index].send(0)

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
        if ind in 0 ..< ScreenSize * ScreenSize and (level[ind].kind == air or kind == air):
          level[ind].kind = kind
          level[ind].dirty = true

for x in ThreadRange:
  updateThreads[x].createThread(threadWait, ThreadData(level: level.addr, index: x))

proc update(l: var Level) =
  for step in CheckerRange:     
    var ind = 
      case step:
        of 0: 0
        of 1: 1
        of 2: ThreadWidth
        of 3: ThreadWidth + 1
        else: 0
    for i in ThreadRange:
      threadChannels[i].send(ind)
      if ind.div(ThreadWidth) < (ind + 2).div(ThreadWidth):
        ind += ThreadWidth
      ind += 2
    for i in ThreadRange:
      discard mainChannels[i].recv # "Freeze"

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
  if btn(pcY):
    level.drawParticle(air)
  if btn(pcStart):
    for x in level.mitems:
      x.kind = air
  drawSize = clamp(drawSize + mousewheel() * ScrollSpeed, DrawRange.a, DrawRange.b)
  level.update()
  inc tick

fps(300)
var 
  lastDraw = cpuTime()
  sixtyAvg = newSeq[int](60)
  pos = 0
proc gameDraw() =
  let fps = (1 / (cpuTime() - lastDraw)).int
  sixtyAvg[pos] = fps
  pos = (pos + 1).mod(sixtyAvg.len)
  setColor(15)
  let 
    (x,y) = mouse()
    avg = block:
      var res = 0
      for x in sixtyAvg:
        res += x
      res.div sixtyAvg.len
  circ(x,y, drawSize.div(2))
  printc($avg, ScreenSize.div(2), 0, 10)
  lastDraw = cpuTime()

nico.init("myOrg", "myApp")
nico.createWindow("myApp", ScreenSize, ScreenSize, 1, false)
nico.run(gameInit, gameUpdate, gameDraw)