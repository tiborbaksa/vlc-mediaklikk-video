local tables
local streams
local urls
local log

local function noPlaylist(reason)
  log.err('Failed to create playlist:', reason)
  return {}
end

local Object = {}

function Object:new(overrides)
  return setmetatable(overrides or {}, {__index = self})
end

local Parser = Object:new()
local VideoParser = Parser:new()
local LiveStreamParser = Parser:new()

local parsers = {
  VideoParser:new{urlPattern = 'hirado%.hu/videok/'},
  VideoParser:new{urlPattern = 'm4sport%.hu/videok/'},
  VideoParser:new{urlPattern = 'mediaklikk%.hu/video/'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m1%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m2%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m4%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m5%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/duna%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/duna%-world%-elo'}
}

function probe()
  return tables.some(Parser.probe, parsers)
end

function parse()
  local parser = tables.find(Parser.probe, parsers)
  if not parser then
    return noPlaylist('could not find Parser')
  end

  return parser:parse()
end

local protocol = vlc.access .. '://'

function Parser:probe()
  return vlc.access:match('https?') and vlc.path:match(self.urlPattern)
end

function Parser:parse()
  local pageSource = streams.readAll(vlc)

  log.dbg('Extracting Player URL...')

  local playerUrl = self:playerUrl(pageSource)
  if not playerUrl then
    return noPlaylist('could not find Player URL')
  end

  log.dbg('Player URL:', playerUrl)
  log.dbg('Extracting Path...')

  local path = self:path(playerUrl)
  if not path then
    return noPlaylist('could not find Path')
  end

  log.dbg('Path:', path)
  
  return {self:playListItem(path, pageSource)}
end

function Parser:path(playerUrl)
  local playerPageSource = streams.readAll(vlc.stream(playerUrl))
  local path = playerPageSource:match('"file": *"([^"]+)"')
  if path then
    return urls.normalize(path)
  end
end

function VideoParser:playerUrl(pageSource)
  local token = pageSource:match('"token":"([^"]+)"')
  if token then
    return protocol .. 'player.mediaklikk.hu/player/player-external-vod-full.php?hls=1&token=' .. token
  end
end

function VideoParser:playListItem(path, pageSource)
  local function findProperty(property)
    return pageSource:match('<meta property="og:' .. property .. '" content="([^"]+)"/>')
  end

  return {
    path = path,
    title = findProperty('title'),
    description = findProperty('description'),
    arturl = findProperty('image'),
    url = findProperty('url')
  }
end

function LiveStreamParser:playerUrl(pageSource)
  local streamId = pageSource:match('"streamId":"([^"]+)"')
  if streamId then
    return protocol .. 'player.mediaklikk.hu/playernew/player.php?noflash=yes&video=' .. streamId
  end
end

function LiveStreamParser:playListItem(path, pageSource)
  return {
    path = path,
    title = pageSource:match('<title>(.+)</title>'),
    url = protocol .. vlc.path
  }
end

tables = {
  find = function(predicate, values)
    for key, value in ipairs(values) do
      if predicate(value, key, values) then
        return value, key
      end
    end
  end,

  some = function(predicate, values)
    local value, key = tables.find(predicate, values)
    return key
  end,

  collect = function(iterator, state, initialValue)
    local result = {}
    for value in iterator, state, initialValue do
      table.insert(result, value)
    end
    return result
  end
}

streams = {
  lines = function(s)
    return s.readline, s, nil
  end,

  readAll = function(s)
    return table.concat(tables.collect(streams.lines(s)), '\n')
  end
}

urls = {
  normalizations = {
    {pattern = '\\(.)', replacement = '%1'},
    {pattern = '^//', replacement = protocol}
  },

  normalize = function(url)
    for i, normalization in ipairs(urls.normalizations) do
      url = url:gsub(normalization.pattern, normalization.replacement)
    end
    return url
  end
}

local function logger(vlcLog)
  return function(...)
    vlcLog(table.concat({'mediaklikk-video:', ...}, ' '))
  end
end

log = {
  dbg = logger(vlc.msg.dbg),
  warn = logger(vlc.msg.warn),
  err = logger(vlc.msg.err),
  info = logger(vlc.msg.info)
}
