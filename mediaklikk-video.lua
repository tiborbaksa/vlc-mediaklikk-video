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
  return vlc.access:match('https?') and tables.find(urlPatterns, function(pattern)
    return vlc.path:match(pattern)
  end)
end

function parse()
  local pageSource = streams.readAll(vlc)

  local playerOptionsJson = pageSource:match('pl.setup%( (%b{}) %);')
  if playerOptionsJson then
    log.dbg('Found player options json, finding playlist item of type hls')

    local playerOptions = dkjson.decode(playerOptionsJson)
    local playlistItem = tables.find(playerOptions.playlist, function(playlistItem)
      return playlistItem.type == 'hls'
    end)

    if not playlistItem then
      log.warn('Cannot find playlist item of type hls in player options json:', playerOptionsJson)
      return nil
    end

    local params = tables.map(tables.toMap(vlc.path:gmatch('[?&]([^=]+)=([^&]*)')), function(param)
      return vlc.strings.decode_uri(param)
    end)

    return {
      {
        path = vlc.access .. ':' .. playlistItem.file,
        title = params.title,
        arturl = params.bgimage
      }
    }
  end

  log.dbg('Cannot find player options json, finding embedded players');

  local playerSetupJsons = tables.toArray(pageSource:gmatch('mtva_player_manager%.player%(document%.getElementById%("player_%d+_%d+"%), (%b{})%);'));

  log.dbg('Number of players:', #playerSetupJsons)

  return tables.map(playerSetupJsons, function(playerSetupJson)
    local playerSetup = dkjson.decode(playerSetupJson)
    local video = playerSetup.streamId or playerSetup.token

    if not video then
      log.warn('Cannot find either streamId or token in player setup json:', playerSetupJson)
      return nil
    end

    local title = playerSetup.title or openGraph.property(pageSource, 'title')
    local arturl = (playerSetup.bgImage and vlc.access .. ':' .. playerSetup.bgImage) or openGraph.property(pageSource, 'image')
    local playerUrl = vlc.access .. '://player.mediaklikk.hu/playernew/player.php?video=' .. video ..
      ((title and '&title=' .. vlc.strings.encode_uri_component(title)) or '') ..
      ((arturl and '&bgimage=' .. vlc.strings.encode_uri_component(arturl)) or '')

    log.dbg('Loading player:', playerUrl)

    return {
      path = playerUrl,
      title = title,
      arturl = arturl,
      options = {
        'http-referrer=' .. vlc.access .. '://' .. vlc.path
      }
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

  return table.concat(tables.toArray(iterator, 1024, nil));
end

function tables.find(values, predicate)
  for key, value in pairs(values) do
    if predicate(value, key, values) then
      return value, key
    end
  end
end

function tables.toArray(iterator, state, initialValue)
  local result = {}
  for value in iterator, state, initialValue do
    table.insert(result, value)
  end
  return result
end

function tables.toMap(iterator, state, initialValue)
  local result = {}
  for key, value in iterator, state, initialValue do
    result[key] = value
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
