EVENT_REMOVE_BUTTON = '<div class="event-ctrls"><span class="remove-event"><i class="fa fa-minus"></i></span></div>'

Meteor.Spinner.options =
  width: 5
  radius: 3
  color: '#666'
  top: '10px'
  left: '0px'
  lines: 15
  length: 5
  width: 1
  speed: 3

Template.scheduler.onCreated ->
  @calendars = new ReactiveVar()
  calendarsCount = GCCalendars.find().count()
  @showSpinner = new ReactiveVar not calendarsCount
  self = @

Template.scheduler.onRendered ->
  hr = $ '<hr>'
  container = $ 'td.fc-today'

  unit = container.height() / (24 * 60) #pixel per minute
  curTime = new Date()
  minutesAfterMidnight = curTime.getHours() * 60 + curTime.getMinutes()

  hr.css 'top', minutesAfterMidnight * unit + 'px'
  hr.css 'width', container.width()
  container.append hr

  Meteor.setInterval ->
    hr.css 'top', hr.height + unit + 'px'
    console.log hr
  , 60000
#$('.fc-view-container > div > table > tbody').height()

Template.scheduler.helpers
  boards: () ->
    return Boards.find { ownerId: Meteor.userId(), isBacklog: {$exists: false}}, sort: order: 1
  backlogBoard: () ->
    return Boards.findOne {isBacklog: true}
  calendarOptions: ->
    {
    eventRender: (event, element) ->
      if not event.isGoogle
        element.append EVENT_REMOVE_BUTTON
      if event.isGoogle
        element.addClass "gc-event"
      if event.tasks?
        element.append "<div class=\"event-tasks\">#{event.tasks?.join ", "}"
    events: (start, end, timezone, callback) ->
      allEvents = Chips.find().map (el) ->
        board = Boards.findOne el.boardId
        if el.taskIds?
          el.tasks = []
          for taskId in el.taskIds
            try
              el.tasks.push Tasks.findOne(_id: taskId).text
            catch e
              #task is removed
        el.title = board.title
        el.color = COLORS[board.config.bgColor]
        el
      googleEvents = GCEvents.find().fetch()
      if googleEvents
        allEvents = allEvents.concat googleEvents
      callback allEvents
    defaultView: 'agendaWeek'
    allDaySlot: false
    editable: true
    overlap: true
    height: "auto"
    id: 'calendar'
    header: {
      left: 'title',
      center: '',
      right: 'month,agendaWeek,agendaDay today prev,next'
    }
    timezone: 'local'
    selectable: true
    select: (start, end, jsEvent, template) ->
      Modal.show 'newChipModal',
        start: start
        end: end
    eventDrop: (event, delta, revertFunc, jsEvent, ui, view) ->
      updateChip event
    eventResize: (event, jsEvent, ui, view) ->
      updateChip event
    eventClick: (event, jsEvent, view) ->
      if not event.isGoogle
        className = jsEvent.target.className
        if className is 'remove-event' or className is 'fa fa-minus'
          Chips.remove {_id: event._id}, (err, res) ->
            console.log err or res
        else
          Router.go 'boards', {},
            hash: event.boardId
    #console.log 'go to board ', event.boardId
    }
  calendars: ->
    return GCCalendars.find()
  showSpinner: ->
    return Template.instance().showSpinner.get()

Template.scheduler.onRendered ->
  fetchGCCalendars()
  Meteor.setTimeout ->
    refetchEvents()
  , 100
  Chips.after.insert refetchEvents
  Chips.after.remove refetchEvents
  Chips.after.update refetchEvents
  @.$('.dropdown-toggle').dropdown()


Template.scheduler.events
  'click .choosable-calendar-item': (e, t)->
    calendar = Blaze.getData e.target
    events = GCEvents.find(calendarId: calendar.id)
    if events.count() < 1
      fetchGCEvents calendar.id
    else
      removeGCEventsByCalendarId calendar.id
    GCCalendars.update {_id: calendar._id}, {$set: {active: not calendar.active}}

refetchEvents = () ->
  $('#calendar').fullCalendar 'refetchEvents'

updateChip = (event) ->
  Chips.update {_id: event._id}, {$set: {start: event.start.format(), end: event.end.format()}}, (err, res) ->
    console.log err or res

createChip = (start, end, boardId) ->
  Chips.insert {start: start, end: end, boardId: boardId}, (err, res) ->
    console.log err or res

fetchGCEvents = (calendarId) ->
  Meteor.call 'gcalendar/fetchEvents', calendarId, (err, res) ->
    console.log err or res
    if res and res.result
      res.result.items.forEach (el)->
        if el.start and el.start.dateTime and el.end and el.end.dateTime
          GCEvents.insert
            start: el.start.dateTime#new Date el.start.dateTime
            end: el.end.dateTime#new Date el.end.dateTime
            title: el.summary
            isGoogle: true
            color: 'rgba(69, 158, 203, 0.55)'
            calendarId: calendarId
      refetchEvents()

fetchGCCalendars = () ->
  instance = Template.instance()
  if GCCalendars.find().count() < 1
    Meteor.call 'gcalendar/fetchCalendars', (err, res) ->
      if res and res.result
        res.result.items.forEach (el)->
          el.active = false
          GCCalendars.insert el
        instance.showSpinner.set false

removeGCEventsByCalendarId = (calendarId) ->
  GCEvents.remove calendarId: calendarId, (err, res) ->
    console.log err or res
    refetchEvents()
