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
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m1%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m2%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m4%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/m5%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/duna%-elo'},
  LiveStreamParser:new{urlPattern = 'mediaklikk%.hu/duna%-world%-elo'},
  VideoParser:new{urlPattern = 'hirado%.hu'},
  VideoParser:new{urlPattern = 'm4sport%.hu'},
  VideoParser:new{urlPattern = 'mediaklikk%.hu'}
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

  log.dbg('Extracting Player URLs...')

  local playerUrls = self:playerUrls(pageSource)
  if #playerUrls == 0 then
    return noPlaylist('could not find any Player URL')
  end

  log.dbg('Player URLs:', unpack(playerUrls))
  log.dbg('Extracting Paths...')

  local function findPath(playerUrl)
    local path = self:path(playerUrl)
    if not path then
      log.warn('could not extract Path from', playerUrl)
    end

    return path
  end

  local paths = tables.map(findPath, playerUrls)
  if #paths == 0 then
    return noPlaylist('could not find any Path')
  end

  log.dbg('Paths:', unpack(paths))

  local function playListItem(path)
    return self:playListItem(path, pageSource)
  end

  return tables.map(playListItem, paths)
end

function Parser:path(playerUrl)
  local playerPageSource = streams.readAll(vlc.stream(playerUrl))
  local path = playerPageSource:match('"file":%s*"(.-)"')
  if path then
    return urls.normalize(path)
  end
end

function VideoParser:playerUrls(pageSource)
  local function playerUrl(token)
    return protocol .. 'player.mediaklikk.hu/player/player-external-vod-full.php?hls=1&token=' .. token
  end

  local tokens = tables.collect(pageSource:gmatch('"token":%s*"(.-)"'))
  return tables.map(playerUrl, tokens)
end

function VideoParser:playListItem(path, pageSource)
  local function findProperty(property)
    return pageSource:match('<meta%s+property=["\']og:' .. property .. '["\']%s+content=["\'](.-)["\']%s*/?>')
  end

  return {
    path = path,
    title = findProperty('title'),
    description = findProperty('description'),
    arturl = urls.normalize(findProperty('image'))
  }
end

function LiveStreamParser:playerUrls(pageSource)
  local streamId = pageSource:match('"streamId":%s*"(.-)"')
  if not streamId then
    return {}
  end

  return {protocol .. 'player.mediaklikk.hu/playernew/player.php?noflash=yes&video=' .. streamId}
end

function LiveStreamParser:playListItem(path, pageSource)
  return {
    path = path,
    title = pageSource:match('<title>(.-)</title>')
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
  end,

  map = function(transform, values)
    local result = {}
    for key, value in ipairs(values) do
      result[key] = transform(value, i, values)
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
