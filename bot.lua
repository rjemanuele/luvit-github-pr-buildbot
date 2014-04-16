#!/usr/bin/env luvit

local http = require("http")
local https = require("https")
local io = require("io")
local JSON = require('json')
local parse = require('querystring').parse
local string = require('string')
local url = require('url')
local base64 = require('./base64')
local fmt = require('string').format
local spawn = require('childprocess').spawn

local server

--Configure
local argv = require('luvit-options')
  .usage("Usage: ./bot.lua ....")
  .describe("c", "config file location")
  .alias({["c"]="config"})
  .demand({'c'})
  .argv("c:")

if not argv.args.c then
  process.exit(1)
end

local config = {}
local f = io.open(argv.args.c, "r")
if f ~= nil then
  local content = f:read("*all")
  f:close()
  config = JSON.parse(content)
end


--Hook Handler
local function webhook_handler(request, response)
  local postBuffer = ''
  request:on('data', function(chunk)
    postBuffer = postBuffer .. chunk
  end)
  request:on('end', function()
    response:write("Hello")
    response:finish()
    local t = ''
    p("request", request)
    p("postBuffer", postBuffer)
    local ret, error = pcall(function()
      t = JSON.parse(postBuffer)
      --p("final", t)
      --p(t.comment.body)
      local found = string.find(t.comment.body, "[Pp][Rr][Bb][Uu][Ii][Ll][Dd]")
      if found ~= nil then
        --Post to buildbot
        p(t)
        get_pr_data(t.issue.pull_request.url, function(err, data)
          p(err, data)
          if err == nil then
            local ret
            ret, err = pcall(function()
              local pr_data = JSON.parse(data)
              p(pr_data)
              spawn("buildbot",
                {'sendchange',
                 '-W', t.sender.login,
                 '-m', config.buildbot.master,
                 '-C', config.buildbot.category,
                 '-b', pr_data.head.ref,
                 '-R', t.repository.html_url,
                 'Dummy Force'})
            end)
          end

          if err ~= nil then
            p('ERROR', err)
          end
        end)
      end
    end)
  end)
end


--Go
server = http.createServer(webhook_handler)
server:listen(config.http.port, config.http.addr)

print(string.format("Server listening at http://%s:%d/", config.http.addr, config.http.port))


function get_pr_data(pr_url, callback)
  local purl = url.parse(pr_url)

  if purl.protocol ~= 'https' then
    callback('HTTPS supported only')
    return
  end

  local options = {
    host = purl.hostname,
    path = purl.pathname,
    headers = {}
  }

  options.headers['User-Agent'] = config.github.agent or 'Luvit Github PR Buildbot Trigger'

  if purl.port then
    options.port = purl.port
  end

  if config.github.token then
    options.headers['Authorization'] = 'token ' .. config.github.token
  end

  local data = ''

  p("Making request", options)

  local req = https.request(options, function(res)
    res:on('data', function (chunk)
      data = data .. chunk
    end)
  end)

  --req:on('error', callback)

  req:on('end', function()
    callback(nil, data)
  end)

  req:done()
end
