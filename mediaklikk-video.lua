local dkjson = require('dkjson')
local log = {}
local openGraph = {}
local streams = {}
local tables = {}

local urlPatterns = {
  'hirado%.hu',
  'm4sport%.hu',
  'mediaklikk%.hu'
}

function probe()
  return vlc.access:match('https?')
    and tables.find(urlPatterns, function(pattern)
      return vlc.path:match(pattern)
    end)
    and not vlc.path:match('player%.mediaklikk%.hu')
end

function parse()
  local pageSource = streams.readAll(vlc)
  local playerSetupJsons = tables.collect(pageSource:gmatch('mtva_player_manager%.player%(document%.getElementById%("player_%d+_%d+"%), (%b{})%);'));

  log.dbg('Number of players:', #playerSetupJsons)

  return tables.map(playerSetupJsons, function(playerSetupJson)
    local playerSetup = dkjson.decode(playerSetupJson)
    local video = playerSetup.streamId or playerSetup.token

    if not video then
      log.warn('Cannot find either streamId or token in player setup json:', playerSetupJson)
      return nil
    end

    local playerUrl = vlc.access .. '://player.mediaklikk.hu/playernew/player.php?video=' .. video

    log.dbg('Loading player:', playerUrl)

    local playerSource = streams.readAll(vlc.stream(playerUrl))
    local playerOptionsJson = playerSource:match('pl.setup%( (%b{}) %);')
    local playerOptions = dkjson.decode(playerOptionsJson)
    local playlistItem = tables.find(playerOptions.playlist, function(playlistItem)
      return playlistItem.type == 'hls'
    end)

    if not playlistItem then
      log.warn('Cannot find playlist item of type hls in player options json:', playerOptionsJson)
      return nil
    end

    return {
      path = vlc.access .. ':' .. playlistItem.file,
      title = playerSetup.title or openGraph.property(pageSource, 'title'),
      description = openGraph.property(pageSource, 'description'),
      arturl = (playerSetup.bgImage and vlc.access .. ':' .. playerSetup.bgImage) or openGraph.property(pageSource, 'image')
    }
  end)
end

local function logger(vlcLog)
  return function(...)
    vlcLog(table.concat({'mediaklikk-video:', ...}, ' '))
  end
end

log.dbg = logger(vlc.msg.dbg)
log.warn = logger(vlc.msg.warn)
log.err = logger(vlc.msg.err)
log.info = logger(vlc.msg.info)

function openGraph.property(source, property)
  return source:match('<meta property="og:' .. property .. '" content="(.-)"/>')
end

function streams.readAll(s)
  local function iterator(size)
    if s == vlc then
      return s.read(size)
    else
      return s:read(size)
    end
  end

  return table.concat(tables.collect(iterator, 1024, nil));
end

function tables.find(values, predicate)
  for key, value in pairs(values) do
    if predicate(value, key, values) then
      return value, key
    end
  end
end

function tables.collect(iterator, state, initialValue)
  local result = {}
  for value in iterator, state, initialValue do
    table.insert(result, value)
  end
  return result
end

function tables.map(values, transform)
  local result = {}
  for key, value in pairs(values) do
    result[key] = transform(value, key, values)
  end
  return result
end
