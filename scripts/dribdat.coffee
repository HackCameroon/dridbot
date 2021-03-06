# Description:
#   A module for Happy Healthy Hackathons
#
# Dependencies:
#   "lodash.js"
#   "moment.js"
#
# Commands:
#   hubot ready - Get ready to run the hackathon
#   hubot info - Get info about your event
#   hubot call - Start an open source call with your team
#   hubot set [name|location|host|website|community|call|start|finish]
#   hubot quiet - Stop receiving hourly updates
#   hubot time - Keep track of the time remaining till start/finish
#   hubot all - List all documented projects at the current hackathon.
#   hubot find <query> - Search among all hackathon projects.
#   hubot start - Start your project with a Q&A session
#   hubot recruit <role> - Find a collaborator for your team
#   hubot level [up|down] <status> - Share the progress of your team
#   hubot whoami - See public info on me and my team
#   hubot update - Publish project documentation
#   hubot fix <something> - Notify the organizers of a problem
#
# Author:
#   sodacpr <ol@utou.ch>

crypto = require 'crypto'
moment = require 'moment'
_ = require 'lodash'
fs = require 'fs'

logdev = require('tracer').colorConsole()
logger = require('tracer').dailyfile(
  root: '.'
  maxLogFiles: 5)

DATE_FORMAT = "ddd, D MMM YYYY hh:mm:ss"
DRIBDAT_URL = process.env.DRIBDAT_HOST or ''
DRIBDAT_APIKEY = process.env.DRIBDAT_APIKEY or ''
DEFAULT_SRC = ""

scrunchName = (nm) ->
  return nm.toLowerCase().replace(/[^A-z0-9]/g, "-")

timeUntil = (event) ->
  sta_at = moment(event.starts_at, DATE_FORMAT)
  end_at = moment(event.ends_at, DATE_FORMAT)
  has_started = sta_at < moment()
  if moment() > end_at then return false
  dt = if has_started then end_at else sta_at
  cc = if has_started then 'will finish' else 'will start'
  suffix = ''
  if has_started and moment(end_at - moment()).hours() in [1, 2]
    suffix = ' - time to get your presentation together!'
  return cc + ' ' + moment(dt, DATE_FORMAT).fromNow() + suffix

module.exports = (robot) ->
  # Globals
  eventInfo = null
  hackyQuotes = []

  # Load the quote file
  hackyQuotes = require process.cwd() + '/hacky-quotes.json'
  hackyQuotes = _.shuffle hackyQuotes.all

  # A per-channel brain
  getChannel = (id) ->
    return robot.brain.get("room-#{id}") or {
        id: id,
        hasIntroduced: false,
        hasExplained: false,
        hasPicked: false,
        roomTopic: null,
        remindAt: 0,
        remindInterval: null,
      }
  saveChannel = (dt) ->
    id = dt.id
    robot.brain.set "room-#{id}", dt
  helloChannel = (id) ->
    chdata = getChannel id
    chdata.hasIntroduced = true
    saveChannel chdata
    return chdata
  initEvent = (info) ->
    # validation would be nice
    eventInfo = info
    if not eventInfo.team_call
      hashmeet = crypto.randomBytes(10).toString('hex')
      eventInfo.team_call = "https://meet.jit.si/#{hashmeet}"
    robot.brain.set 'eventInfo', eventInfo
    timeuntil = timeUntil eventInfo
    logdev.info "#{eventInfo.name} #{timeuntil}"
  getRoomName = (robot, res) ->
    if not robot.adapter.client
      return res.message.room
    return robot.adapter.client.rtm.dataStore.getChannelGroupOrDMById(res.message.room).name

  # Get and cache current event data
  if DRIBDAT_URL
    robot.http(DRIBDAT_URL + "/api/event/current/info.json")
      .header('Accept', 'application/json')
      .get() (err, response, body) ->
        # error checking code here
        if err or _.isEmpty(body)
          logdev.debug err
          return logdev.warn "Could not connect to server #{DRIBDAT_URL}"
        jsondata = JSON.parse body
        ei = if jsondata then jsondata.event else robot.brain.get('eventInfo')
        initEvent(ei)
  else
    ei = robot.brain.get('eventInfo')
    if not ei
      ei = {
            name: "a Hackathon",
            location: "Whole Earth",
            hostname: "the Internet",
            webpage_url: "https://hackcodeofconduct.org/",
            community_url: "https://forum.opendata.ch/c/events/hackathons",
            starts_at: moment().format(DATE_FORMAT),
            ends_at: moment().add(1, 'days').format(DATE_FORMAT),
            id: 1
           }
    initEvent(ei)

  # Log all interactions
  robot.hear /(.*)/, (res) ->
    chdata = getChannel res.message.room
    query = res.message.text
    logger.trace "#{query} [##{res.message.room}]"

    if not chdata.remindInterval and not chdata.hasIntroduced
      setTimeout () ->
        chdata = getChannel res.message.room
        return if chdata.remindInterval or chdata.hasIntroduced
        chdata.hasIntroduced = true
        saveChannel chdata
        res.send "Hi there! I am here to help you with your project. " +
          "Say `@#{robot.name} ready` to get general advice, " +
          "`@#{robot.name} update` to get your documentation set up, " +
          "or `@#{robot.name} help` for other options."
      , 1000 * 60 * 5

  # Notify the developer of something
  robot.respond /fix (.*)/, (res) ->
    query = res.match[0]
    logdev.warn query + ' #' + res.message.room
    res.send "Thanks for letting us know. If you do not get a response from us soon, post to the wall of shame (or fork the code and send in a Pull Request!) at https://github.com/hackathons-ftw/dridbot/issues"

  robot.respond /(issue|bug|problem|who are you|what are you).*/i, (res) ->
    res.send "I am an alpha personal algoristant powered by a Hubot 2 engine - delighted to be with you today. :simple_smile: Did you find a bug or have an improvement to suggest? Write a note to my developers by saying `#{robot.name} fix <something>`"

  robot.respond /.*(stupid|idiot|blöd).*/i, (res) ->
    res.send "I heard that! :slightly_frowning_face:"

  # Show basic event information
  robot.respond /info/i, (res) ->
    eventInfo = robot.brain.get('eventInfo')
    timeuntil = timeUntil eventInfo
    if timeuntil
      res.send "You are taking part in #{eventInfo.name} on #{eventInfo.location}, hosted by #{eventInfo.hostname}. Visit the website #{eventInfo.webpage_url} or join the community #{eventInfo.community_url} to get started. The event #{timeuntil}."
    else
      res.send "It seems like #{eventInfo.name} is over :( Let's do a hackathon again soon!"

  # Show event videocall information
  robot.respond /call/i, (res) ->
    eventInfo = robot.brain.get('eventInfo')
    timeuntil = timeUntil eventInfo
    if timeuntil
      res.send "#{eventInfo.name} is still on and #{timeuntil}."
    else
      res.send "Let's meet to plan the next hackathon!"
    res.send "Join the call and share your screen at #{eventInfo.team_call} :information_desk_person:"

  # Change event information
  robot.respond /set (name|location|host|website|community|call|start|finish) (.*)/i, (res) ->
    eventInfo = robot.brain.get('eventInfo')
    query = res.match[1].trim()
    text = res.match[res.match.length-1].trim()
    if not _.isEmpty(query) and not _.isEmpty(text)
      if query == 'name'
        eventInfo.name = text
      if query == 'location'
        eventInfo.location = text
      if query == 'host'
        eventInfo.hostname = text
      if query == 'website'
        eventInfo.webpage_url = text
      if query == 'community'
        eventInfo.community_url = text
      if query == 'call'
        eventInfo.team_call = text
      if query == 'start'
        eventInfo.starts_at = moment(text).format(DATE_FORMAT)
      if query == 'finish'
        eventInfo.ends_at = moment(text).format(DATE_FORMAT)
      robot.brain.set 'eventInfo', eventInfo
      res.send "OK!"

  # List all projects in Dribdat by activity order
  robot.respond /all( projects)?/i, (res) ->
    chdata = helloChannel res.message.room
    robot.http(DRIBDAT_URL + "/api/event/current/projects.json")
    .header('Accept', 'application/json')
    .get() (err, response, body) ->
      # error checking code here
      data = JSON.parse body
      if data.projects.length == 0
        res.send "No projects to speak of. Have we even started yet? :stuck_out_tongue_closed_eyes:"
      else
        pcount = data.projects.length
        prlist = ""
        for project, ix in data.projects
          roomname = scrunchName project.name
          prlist += ":star: ##{roomname} "
        res.send "#{prlist}:star:\nTo see all #{pcount} projects, visit #{DRIBDAT_URL}"

  # Search for projects in Dribdat
  robot.respond /find( a)?( project)?(.*)/i, (res) ->
    chdata = helloChannel res.message.room
    query = res.match[res.match.length-1].trim()
    if query is ""
      res.send "Looking for something to work on..? :stuck_out_tongue_closed_eyes:"
      return
    robot.http(DRIBDAT_URL + "/api/project/search.json?q=" + query)
    .header('Accept', 'application/json')
    .get() (err, response, body) ->
      # error checking code here
      data = JSON.parse body
      if data.projects.length == 0
        res.send ":wind_blowing_face: Nothing found. Why not make your own #{query}?"
      else
        if data.projects.length > 5
          res.send "First #{data.projects.length} matching "#{query}":"
        for project in data.projects[..5]
          res.send "*#{project.name}*: #{project.summary} #{DRIBDAT_URL}/project/#{project.id}"

  # Help with picking a name for the project
  robot.respond /start( project)?(.*)/i, (res) ->
    chdata = helloChannel res.message.room
    query = res.match[res.match.length-1].trim()
    if _.isEmpty(query)
      roomname = getRoomName robot, res
      res.send "You need a name for your team. Say `start` again followed by a name, like this: `start #{roomname}`"
      setTimeout () ->
          chdata = helloChannel res.message.room
          return if chdata.hasPicked
          res.send ":8ball: Looking for a name? Try http://www.dotomator.com/web20.html"
          setTimeout () ->
              chdata = helloChannel res.message.room
              return if chdata.hasPicked
              res.send ":8ball: No luck yet? Try this too: https://crestonbunch.github.io/neural-namer-demo/#/"
            , 1000 * 60
        , 1000 * 10
      return
    chdata.hasPicked = true
    saveChannel chdata
    teamname = scrunchName query
    res.send "Great! We suggest you rename this channel to #team-#{teamname}. Time to invite your team! Say 'up' when you are ready to rock and roll."

  robot.topic (res) ->
    chdata = getChannel res.message.room
    roomTopic = res.message.text
    chdata.roomTopic = roomTopic
    saveChannel chdata
    logdev.debug "Topic changed to #{roomTopic}"

  # What is the current topic
  robot.respond /(.*)topic\??/i, (res) ->
    chdata = getChannel res.message.room
    res.send chdata.roomTopic

  # Find a collaborator for your team
  robot.respond /recruit ?(.*)?/i, (res) ->
    query = res.match[res.match.length-1]
    if query
      query = query.trim()
    else
      query = "a teammate"
    # post this in the general feed and alert organizers
    res.send ":dancers: OK, I will go look for #{query}!"

  # Share the progress of your team
  robot.respond /(level up|level down|up)(date )?(project)?(.*)/i, (res) ->
    chdata = helloChannel res.message.room
    query = res.match[res.match.length-1].trim()
    if query == 'status'
      return res.send "Change your project status by sending me `level up` or `level down` commands"
    levelup = 0
    levelupquery = res.match[1].trim().toLowerCase()
    if levelupquery == 'level up' then levelup = 1
    if levelupquery == 'level down' then levelup = -1
    if !_.startsWith(query, 'http') then query = ''
    roomname = getRoomName robot, res
    postdata = JSON.stringify({
      'autotext_url': query,
      'levelup': levelup,
      'summary': if roomTopic? then roomTopic else '',
      'hashtag': scrunchName(roomname),
      'key': DRIBDAT_APIKEY,
    })
    if not DRIBDAT_URL
      if levelup > 0
        res.send("Cool! You've levelled up. Keep going.")
      else
        res.send("Struggling a bit? Look for a mentor. Then let me know you're ready with `dridbot level up`")
      return
    # logdev.debug postdata
    robot.http(DRIBDAT_URL + "/api/project/push.json")
    .header('Content-Type', 'application/json')
    .post(postdata) (err, response, body) ->
      # logdev.debug body
      # error checking code here
      data = JSON.parse body
      if data.error?
        res.send "Sorry, something went wrong. Please check with #support"
        logdev.warn data.error
      else
        project = data.project
        if _.isEmpty(query) and levelup == 0 and project.summary == ''
          res.send "The *topic* of your channel can be used to set the project summary. Append the link to the site where you have hosted the project for a full *description*, e.g. `#{robot.name} up http:/github.com/my/project`\n"
        if !project.id?
          res.send "Sorry, your project could not be synced. Please check with #support"
          logdev.warn project
        else
          res.send "Your project is now *#{project.phase}* at #{DRIBDAT_URL}/project/#{project.id}"
          res.send "Set your team status with `level up` or `level down`." if levelup == 0
        if not chdata.hasExplained
          chdata.hasExplained = true
          saveChannel chdata
          roomname = getRoomName robot, res
          postdata = JSON.stringify({
            'longtext': query,
            'hashtag': scrunchName(roomname),
            'key': DRIBDAT_APIKEY,
          })
          # logdev.debug postdata
          robot.http(DRIBDAT_URL + "/api/project/push.json")
          .header('Content-Type', 'application/json')
          .post(postdata) (err, response, body) ->
            # logdev.debug body
            # error checking code here
            data = JSON.parse body
            if data.error?
              res.send "Sorry, something went wrong. Please check with #support"
              logdev.warn data.error
            else
              project = data.project
              if !project.id?
                res.send "Sorry, your project could not be synced. Please check with #support"
                logdev.warn project
              else
                res.send "Your project has been updated at #{DRIBDAT_URL}/project/#{project.id}"

  # How much time
  timeAndQuote = (res) ->
    eventInfo = robot.brain.get('eventInfo')
    timeuntil = timeUntil eventInfo
    if timeuntil
      if hackyQuotes
        quote = res.random hackyQuotes
        res.send "> #{quote}"
      ends = moment(eventInfo.ends_at, DATE_FORMAT).format("hh:mm")
      res.send "\n#{eventInfo.name} #{timeuntil} @ #{ends}"
    else
      res.send "#{eventInfo.name} is over. Hack again soon!"

  # Cancel reminders
  cancelReminders = (res) ->
    chdata = helloChannel res.message.room
    if chdata.remindInterval
      clearInterval(chdata.remindInterval)
      chdata.remindInterval = null
      saveChannel chdata
      return true
    return false

  # Answer if asked
  robot.respond /time( left)?\??/i, timeAndQuote
  robot.respond /.*(tired|müde|exhausted|sleepy).*/i, (res) ->
    timeAndQuote res
    res.send "Close your eyes. Breathe in slowly. Take a nap."

  # Say hello and get started
  robot.respond /(ready|lets go|hello|hey|gruezi|grüzi|welcome|why are you here)/i, (res) ->
    chdata = helloChannel res.message.room
    if chdata.remindInterval
      res.send "Okay! You will get messages every hour. If you need one now, say `time`."
      return
    res.send "Hello there! Anything i can help with? Say `help` to find out more - and you can " +
      "DM with me to avoid distracting your team. For now, i will just spam you with healthy " +
      "habit reminders every half hour.\n\n" +
      "To shush me, just tell me to be `quiet`. Happy hacking!"
    chdata.remindInterval = setInterval () ->
        chdata = getChannel res.message.room
        remindAt = chdata.remindAt
        remindAt = 0 if ++remindAt == hackyQuotes.length
        chdata.remindAt = remindAt
        if not timeAndQuote res
          cancelReminders res
        else
          saveChannel chdata
      , 1000 * 60 * 30
    saveChannel chdata

  # Be cool
  robot.respond /(be )quiet[!]*/i, (res) ->
    if cancelReminders res
      res.send "Fine, I will leave you in peace. Let me know when you are `ready` to rumble!"
    else
      res.send "Did I say something? Did you say something?"

  # See public info on me and my team
  robot.respond /whoami/i, (res) ->
    chdata = getChannel res.message.room
    roomname = getRoomName robot, res
    # https://api.slack.com/methods/conversations.info
    # channelcount = robot.adapter.client.rtm.dataStore.getChannelGroupOrDMById(res.message.room).num_members
    res.send "Here is what we know about your project:"
    res.send ":basketball: You are team #{chdata.roomTopic}"
    res.send ":green_apple: Level 1 status"
    res.send ":dancers: 3 team members in #{roomname}"
    res.send ":bookmark_tabs: 0 lines of documentation"
    res.send ":eyes: 13 code commits on GitHub"
    res.send(
      attachments: [
        {
          text: "#_Say `@dri recruit` for help finding the 4th team member, or `@dri level up` when ready!_"
          fallback: "Let me know if you need help with @dri help"
          mrkdwn_in: ['text']
        }
      ]
    )
    timeAndQuote res
