-- main.lua
-- Wordle clone in Love2D

local WORD_LENGTH = 5
local MAX_GUESSES = 6

-- Word lists
local answers, guessesList, guessSet = {}, {}, {}

local function loadWordList(filename, intoList, intoSet)
  if love.filesystem.getInfo(filename) then
    local contents = love.filesystem.read(filename)
    for word in contents:gmatch("[^\r\n]+") do
      word = word:lower():match("^%s*(.-)%s*$") -- trim whitespace
      if #word == WORD_LENGTH then
        table.insert(intoList, word)
        if intoSet then
          intoSet[word] = true
        end
      end
    end
  else
    print("Missing word list: " .. filename)
  end
end

local secret = "apple"
local guesses, feedback, currentGuess = {}, {}, ""
local state, gameMessage = "menu", nil

-- Animations
local anims = {}  -- tile flip animations
local shakes = {} -- row shake animations

-- Colors
local colors = {
  bg     = {0.1, 0.1, 0.1},
  text   = {1, 1, 1},
  green  = {0.2, 0.6, 0.2},
  yellow = {0.8, 0.7, 0.2},
  gray   = {0.3, 0.3, 0.3},
  empty  = {0.2, 0.2, 0.2},
  keybg  = {0.2, 0.2, 0.2}
}

-- Keyboard layout
local keyboardRows = {
  "qwertyuiop",
  "asdfghjkl",
  "zxcvbnm"
}
local keyboard = {}

-- Score guess vs secret
local function scoreGuess(secret, guess)
  local result, counts = {}, {}
  for i = 1, #secret do
    local ch = secret:sub(i,i)
    counts[ch] = (counts[ch] or 0) + 1
  end
  for i = 1, WORD_LENGTH do
    local g, s = guess:sub(i,i), secret:sub(i,i)
    if g == s then
      result[i] = {letter = g, status = "green"}
      counts[g] = counts[g] - 1
    end
  end
  for i = 1, WORD_LENGTH do
    if not result[i] then
      local g = guess:sub(i,i)
      if counts[g] and counts[g] > 0 then
        result[i] = {letter = g, status = "yellow"}
        counts[g] = counts[g] - 1
      else
        result[i] = {letter = g, status = "gray"}
      end
    end
  end
  return result
end

-- Update keyboard coloring
local function updateKeyboard(scored)
  for _, t in ipairs(scored) do
    local k = keyboard[t.letter]
    if k then
      local prev = k.status
      if t.status == "green" then
        k.status = "green"
      elseif t.status == "yellow" and prev ~= "green" then
        k.status = "yellow"
      elseif t.status == "gray" and not prev then
        k.status = "gray"
      end
    end
  end
end

function love.load()
  love.window.setMode(500, 800)
  love.window.setTitle("Wordle (Lua/Love2D)")
  love.graphics.setFont(love.graphics.newFont(32))

  -- Load word lists
  answers, guessesList, guessSet = {}, {}, {}
  loadWordList("answers.txt", answers)
  loadWordList("guesses.txt", guessesList, guessSet)

  if #answers > 0 then
    math.randomseed(os.time())
    secret = answers[math.random(#answers)]
  end

  -- Build clickable keyboard
  local keyW, keyH, startY = 40, 60, 600
  for rowIdx, row in ipairs(keyboardRows) do
    local rowLen, totalW = #row, #row * (keyW+5)
    local offsetX = (500 - totalW) / 2
    for i = 1, rowLen do
      local ch = row:sub(i,i)
      local x = offsetX + (i-1)*(keyW+5)
      local y = startY + (rowIdx-1)*(keyH+10)
      keyboard[ch] = {x=x, y=y, w=keyW, h=keyH, status=nil}
    end
  end
end

-- Draw menu
local function drawMenu()
  love.graphics.clear(colors.bg)
  love.graphics.setColor(colors.text)
  love.graphics.printf("WORDLE CLONE", 0, 200, 500, "center")
  love.graphics.printf("Press Enter to Start", 0, 300, 500, "center")
end

-- Draw a cell (with animations)
local function drawCell(x, y, size, letter, status, anim)
  local boxColor = colors.empty
  if status then boxColor = colors[status] end

  local scaleY = 1
  if anim then
    local t, duration = anim.time, 0.3
    if t < duration then
      scaleY = 1 - (t/duration)
    elseif t < duration*2 then
      if not anim.revealed then
        status = anim.targetStatus
        anim.revealed = true
      end
      boxColor = colors[anim.targetStatus]
      scaleY = (t-duration)/duration
    else
      scaleY = 1
      anim.done = true
    end
  end

  love.graphics.setColor(boxColor)
  love.graphics.push()
  love.graphics.translate(x + size/2, y + size/2)
  love.graphics.scale(1, scaleY)
  love.graphics.rectangle("fill", -size/2, -size/2, size, size, 8, 8)
  love.graphics.setColor(colors.text)
  if letter ~= "" and scaleY > 0.05 then
    love.graphics.printf(letter, -size/2, -size/2+15, size, "center")
  end
  love.graphics.pop()
end

-- Draw game
local function drawGame()
  local cellSize, offsetX, offsetY, spacing = 70, 50, 50, 10
  for row = 1, MAX_GUESSES do
    local guess, rowFeedback = guesses[row], feedback[row]
    local rowShake = shakes[row]
    local shakeOffset = 0
    if rowShake and rowShake.active then
      shakeOffset = math.sin(rowShake.time * 40) * 8
    end

    for col = 1, WORD_LENGTH do
      local x = offsetX + (col-1)*(cellSize+spacing) + shakeOffset
      local y = offsetY + (row-1)*(cellSize+spacing)
      local letter, status = "", nil
      local anim = anims[row] and anims[row][col] or nil

      if guess then
        letter = guess:sub(col,col):upper()
        if rowFeedback and rowFeedback[col] then
          status = rowFeedback[col].status
        else
          status = "gray"
        end
      elseif row == #guesses+1 then
        letter = currentGuess:sub(col,col):upper()
      end

      drawCell(x, y, cellSize, letter, status, anim)
    end
  end

  -- Draw keyboard
  for ch, k in pairs(keyboard) do
    local c = colors.keybg
    if k.status then c = colors[k.status] end
    love.graphics.setColor(c)
    love.graphics.rectangle("fill", k.x, k.y, k.w, k.h, 5, 5)
    love.graphics.setColor(colors.text)
    love.graphics.printf(ch:upper(), k.x, k.y+15, k.w, "center")
  end

  if gameMessage then
    love.graphics.setColor(colors.text)
    love.graphics.printf(gameMessage, 0, 500, 500, "center")
    love.graphics.printf("Press Enter to Restart", 0, 540, 500, "center")
  end
end

function love.draw()
  if state == "menu" then
    drawMenu()
  else
    love.graphics.clear(colors.bg)
    drawGame()
  end
end

function love.update(dt)
  if state ~= "game" and state ~= "gameover" then return end
  for _, row in pairs(anims) do
    for _, a in pairs(row) do
      if not a.done then
        a.time = a.time + dt
      end
    end
  end
  for _, s in pairs(shakes) do
    if s.active then
      s.time = s.time + dt
      if s.time > 0.5 then
        s.active = false
      end
    end
  end
end

-- Input
function love.textinput(t)
  if state ~= "game" or gameMessage then return end
  if #currentGuess < WORD_LENGTH and t:match("%a") then
    currentGuess = currentGuess .. t:lower()
  end
end

function love.keypressed(key)
  if state == "menu" then
    if key == "return" then
      state = "game"
      if #answers > 0 then
        secret = answers[math.random(#answers)]
      else
        secret = "apple"
      end
      guesses, feedback, currentGuess, gameMessage, anims, shakes = {}, {}, "", nil, {}, {}
      for _, k in pairs(keyboard) do k.status = nil end
    end

  elseif state == "game" then
    if key == "backspace" then
      currentGuess = currentGuess:sub(1, -2)
    elseif key == "return" and not gameMessage then
      if #currentGuess == WORD_LENGTH then
        if not guessSet[currentGuess] then
          local row = #guesses + 1
          shakes[row] = {time = 0, active = true}
        else
          table.insert(guesses, currentGuess)
          local row = #guesses
          local scored = scoreGuess(secret, currentGuess)
          table.insert(feedback, scored)
          updateKeyboard(scored)

          anims[row] = {}
          for col = 1, WORD_LENGTH do
            anims[row][col] = {
              time = -(col-1)*0.2,
              revealed = false,
              targetStatus = scored[col].status,
              done = false
            }
          end

          if currentGuess == secret then
            gameMessage = "You Win! Word: " .. secret:upper()
            state = "gameover"
          elseif #guesses == MAX_GUESSES then
            gameMessage = "Out of guesses! Word: " .. secret:upper()
            state = "gameover"
          end
          currentGuess = ""
        end
      else
        local row = #guesses + 1
        shakes[row] = {time = 0, active = true}
      end
    end

  elseif state == "gameover" then
    if key == "return" then
      state = "menu"
    end
  end
end

-- Mouse clicks
function love.mousepressed(mx, my, button)
  if state ~= "game" or gameMessage then return end
  if button ~= 1 then return end
  for ch, k in pairs(keyboard) do
    if mx >= k.x and mx <= k.x+k.w and my >= k.y and my <= k.y+k.h then
      if #currentGuess < WORD_LENGTH then
        currentGuess = currentGuess .. ch
      end
    end
  end
end