// Pixel-art sprites for the dino runner, as character grids.
//
// Each "#" is one art pixel, drawn at PIXEL world units, so the grids come out
// at the same world size as the Chrome sprites (a 22-wide T-rex is 44 units).
// Grids are turned into row runs once at load time, so the canvas paints one
// fillRect per horizontal run instead of one per pixel, and collision checks
// can test solid pixels straight off the parsed mask.

var PIXEL = 2

var HEAD = [
  "............########.",
  "...........##.#######",
  "...........##########",
  "...........##########",
  "...........##########",
  "...........#####.....",
  "...........########..",
  "#.........#####......",
  "#........######......",
  "##......#######......",
  "###....##########....",
  "############.##.#....",
  "#############........",
  ".###########.........",
  "..#########..........",
  "...#######..........."
]

var DEAD_HEAD = [
  "............########.",
  "...........#...######",
  "...........#.#.######",
  "...........#...######",
  "...........##########",
  "...........#####.....",
  "...........########..",
  "#.........#####......",
  "#........######......",
  "##......#######......",
  "###....##########....",
  "############.##.#....",
  "#############........",
  ".###########.........",
  "..#########..........",
  "...#######..........."
]

var LEGS_STAND = [
  "....###.##...........",
  "....##...#...........",
  "....#....#...........",
  "....##...##.........."
]

var LEGS_RUN_A = [
  "....###.##...........",
  "....##...#...........",
  ".........#...........",
  ".........##.........."
]

var LEGS_RUN_B = [
  "....###.##...........",
  "....##...............",
  "....#................",
  "....##..............."
]

var DUCK_BODY = [
  "#.............................",
  "##.......#######..########....",
  "###...##################.#####",
  ".#############################",
  "..############################",
  "...############.########......",
  "....############..............",
  ".....#########................"
]

var DUCK_LEGS_A = [
  ".....###.##...................",
  ".....##...#...................",
  "..........##.................."
]

var DUCK_LEGS_B = [
  ".....###.##...................",
  ".....##.......................",
  ".....##......................."
]

var CACTUS_SMALL = [
  "...##...",
  "..####..",
  "..####..",
  "#.####..",
  "#.####.#",
  "#.####.#",
  "#.####.#",
  "#.####.#",
  "######.#",
  ".#######",
  "..####..",
  "..####..",
  "..####..",
  "..####..",
  "..####..",
  "..####..",
  "..####.."
]

var CACTUS_LARGE = [
  ".....##.....",
  "....####....",
  "....####....",
  "....####..#.",
  ".#..####.###",
  "###.####.###",
  "###.####.###",
  "###.####.###",
  "###.####.###",
  "###.####.###",
  "###.#######.",
  "###.######..",
  "###.####....",
  ".#######....",
  "..######....",
  "....####....",
  "....####....",
  "....####....",
  "....####....",
  "....####....",
  "....####....",
  "....####....",
  "....####....",
  "....####...."
]

var PTERO_UP = [
  "......#...............",
  "......##..............",
  "......###.............",
  "......####............",
  "..#...#####...........",
  ".##...######..........",
  "####################..",
  ".....###############..",
  "......############....",
  "..........######......"
]

var PTERO_DOWN = [
  "..#...................",
  ".##...................",
  "####################..",
  ".....###############..",
  "......############....",
  "......######..........",
  "......#####...........",
  "......####............",
  "......###.............",
  "......##.............."
]

var CLOUD = [
  "..........######.......",
  "........###....###.....",
  "....#####........##....",
  "..###.............###..",
  ".##.................##.",
  "#######################"
]

function parse(rows) {
  var width = 0
  var runs = []
  var mask = []
  for (var y = 0; y < rows.length; y++) {
    var row = rows[y]
    width = Math.max(width, row.length)
    var solid = []
    var start = -1
    for (var x = 0; x <= row.length; x++) {
      var on = x < row.length && row.charAt(x) === "#"
      solid.push(on)
      if (on && start < 0) start = x
      if (!on && start >= 0) {
        runs.push({ x: start, y: y, w: x - start })
        start = -1
      }
    }
    mask.push(solid)
  }
  return {
    cols: width,
    rows: rows.length,
    width: width * PIXEL,
    height: rows.length * PIXEL,
    runs: runs,
    mask: mask
  }
}

function solidAt(sprite, col, row) {
  if (row < 0 || row >= sprite.rows) return false
  var line = sprite.mask[row]
  return col >= 0 && col < line.length && line[col] === true
}

var sprites = {
  dinoStand: parse(HEAD.concat(LEGS_STAND)),
  dinoRunA: parse(HEAD.concat(LEGS_RUN_A)),
  dinoRunB: parse(HEAD.concat(LEGS_RUN_B)),
  dinoDead: parse(DEAD_HEAD.concat(LEGS_STAND)),
  dinoDuckA: parse(DUCK_BODY.concat(DUCK_LEGS_A)),
  dinoDuckB: parse(DUCK_BODY.concat(DUCK_LEGS_B)),
  cactusSmall: parse(CACTUS_SMALL),
  cactusLarge: parse(CACTUS_LARGE),
  pteroUp: parse(PTERO_UP),
  pteroDown: parse(PTERO_DOWN),
  cloud: parse(CLOUD)
}

// The standing dino with its eye shut, for the idle blink.
sprites.dinoBlink = parse(HEAD.map(function(row, i) {
  return i === 1 ? row.substring(0, 13) + "#" + row.substring(14) : row
}).concat(LEGS_STAND))

// A coarser T-rex for the bar icon, so it stays crisp at icon size.
sprites.icon = parse([
  ".......######",
  "......##.####",
  "......#######",
  "......####...",
  "#....######..",
  "##..#######..",
  "##########.#.",
  ".#########...",
  "..#######....",
  "...#####.....",
  "...##.##.....",
  "...#...##...."
])
