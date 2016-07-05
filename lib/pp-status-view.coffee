{View,SelectListView} = require 'atom-space-pen-views'
$ = require 'jquery'
_ = require 'lodash'

class PPStatusView extends View
  @content: ->
    @div class:'pp-status inline-block', =>
      @span "Live",class:"live off ",outlet:"live", click:'toggleLive'
      @span class:"compileTo",outlet:"compileTo", click:'compile'
      @span "▼", class:"enums",outlet:"enums", click:'previewList'

  initialize: (@model,@editor)->
    @statusBarTile = @model.statusBar.addRightTile {item:@, priority:9999}
    @clicks = 0

  setLive: (live)->
    edStatus = @model.editors[@editor.id][@_id]
    if edStatus.live?.disposalAction
      @live.removeClass('off').removeClass('hyper').addClass('on')
    else if edStatus.hyperLive?.disposalAction
      @live.removeClass('off').removeClass('on').addClass('hyper')
    else
      @live.removeClass('on').removeClass('hyper').addClass('off')

  showStatusBar: (@editor,fresh)->
    return unless @editor
    @hide()
    delete @_id if fresh
    try
      status = @model.getStatus(@editor)
      @_id = status._id
      if status.vw
        # preview = _.find @model.previews,(preview)->
        #               preview._id is status._id
        # preview.statusView = status.vw.clone(true) unless preview.statusView
        @compileTo.empty().append status.vw
      else
        @compileTo.empty().text status.name

      @show()
      @setLive()
      if status.enum
        @enums.show()
      else
        @enums.hide()
    catch e
      # console.log 'Not a Preview-Plus Editor',e.message,e.stack

  compile: ->
    @model.compile(@editor,@_id)

  setToggleLive: (click)->
    @model.setLiveListener(@editor,@_id,click)
    @setLive()

  toggleLive: (evt)->
    edStatus = @model.editors[@editor.id][@_id]
    preview = _.find @model.previews, (preview)->
      preview._id is edStatus._id
    if @model.processes[edStatus._id]?[@_id]
      @model.processes[edStatus._id][@_id]?.kill()
      @compileTo.replace('(kill)','')
      return true
    @clicks++
    if @clicks is 1
      @timer = setTimeout =>
        @clicks = 0
        @setToggleLive(1)
      ,300
    else
      @clicks = 0
      if ( typeof preview.hyperLive is 'boolean' and preview.hyperLive ) or (typeof preview.hyperLive is 'function' and preview.hyperLive())
        @setToggleLive(2)
      else
        atom.notifications.addInfo('HyperLive Not available')

      clearTimeout @timer

  previewList: ->
    previews = @model.getPreviews(@editor)
    defaults = @model.getDefaultStatus(@editor)
    if defaults
      for preview in previews
        if preview._id is defaults._id
          preview.default = true
        else
          preview.default = false
    else
      previews[0].default = true

    new CompilerView previews,@

  updateStatusBar: (item)->
    status = @model.getStatus(@editor,item._id)
    if status.vw
      # item.statusView = item.vw.clone(true) unless item.statusView
      @compileTo.empty().append status.vw
    else
      @compileTo.empty().text status.name
    @_id = item._id
    @setLive()
    @model.compile(@editor,item._id)

  show: ->
    super

  hide: ->
    super
  destroy: ->

class CompilerView extends SelectListView
  initialize: (items,@statusView)->
    super
    @addClass 'overlay from-top'
    @setItems items
    atom.workspace.addModalPanel item:@
    @focusFilterEditor()
    # if @statusView.compileTo.children()?.length > 0
    #   @selectItemView @list.find("li").has('span')
    # else
    #   compileTo = @statusView.compileTo.text()
    #   @selectItemView @list.find("li:contains('#{compileTo}')")

  viewForItem: (item)->
    if item.viewClass
      li = $("<li><span class='pp-space'></span></li>")
      unless item.vw
        if item.viewArgs
          item.vw = new item.viewClass(item.viewArgs)
        else
          item.vw = new item.viewClass
      li.append item.vw
      item.vw.selectList = @
    else
      li = $("<li>#{item.fname}<span class='pp-space'></span></li>")
    # li = $("<li>#{item.fname}</li>")
    if item.default
      radio = $("<span class='pp-default mega-octicon octicon-star on'></span>")
    else
      radio = $("<span class='pp-default mega-octicon octicon-star'></span>")
    fn = (e)=>
      $(`this `).closest('ol').find('span').removeClass('on')
      $(`this `).addClass('on')
      model = _this.statusView.model
      ext = model.getExt(_this.statusView.editor)
      item.enum = true
      model.defaults[ext] = item
      item.default = true
      e.stopPropagation()
      return false
    radio.on 'mouseover', fn
    li.append(radio)
    return li
    # "<li>#{item.fname} <\li>"
    # if typeof item is 'string'
    #   "<li>#{item}</li>"
    # else
    #   $li = $('<li></li>').append item.element
    #   $li.data('selectList',@)
      # item
  confirmed: (item)->
    @statusView.updateStatusBar(item)
    # if item.vw
    #   for i in [1..10000]
    #     console.log i
    # else
    @cancel()

  cancelled: ->
    @parent().remove()

module.exports = { PPStatusView, CompilerView }
